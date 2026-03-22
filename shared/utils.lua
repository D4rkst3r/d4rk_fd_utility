---------------------------------------------------
--  d4rk_fd_utility – Utility Funktionen
---------------------------------------------------

FD = FD or {}
FD.State    = FD.State    or {}
FD._schemas = FD._schemas or {}
FD._cache   = FD._cache   or {}

-- ─────────────────────────────────────────────
--  Debug
-- ─────────────────────────────────────────────

function FD.Debug(msg, ...)
    if not Config.Debug then return end
    print(('[^3d4rk_fd_utility^7] ' .. msg):format(...))
end

-- ─────────────────────────────────────────────
--  Framework Bridge
--  Einmal laden, intern cachen – kein GetCoreObject
--  bei jedem Aufruf
-- ─────────────────────────────────────────────

local _bridge = nil

local function GetBridge()
    if _bridge then return _bridge end

    local fw = Config.Framework

    if fw == 'qbx' then
        -- QBX-Core: direkte Exports, kein Core-Objekt nötig
        _bridge = {
            getJob = function()
                local data = exports['qbx_core']:GetPlayerData()
                return data and data.job or nil
            end,
            getGrade = function()
                local data = exports['qbx_core']:GetPlayerData()
                return data and data.job and data.job.grade and data.job.grade.level or 0
            end,
        }

    elseif fw == 'qb' then
        -- QB-Core
        local QBCore = exports['qb-core']:GetCoreObject()
        _bridge = {
            getJob = function()
                return QBCore.Functions.GetPlayerData().job
            end,
            getGrade = function()
                local grade = QBCore.Functions.GetPlayerData().job.grade
                return type(grade) == 'table' and grade.level or grade or 0
            end,
        }

    elseif fw == 'esx' then
        -- ESX
        local ESX = exports['es_extended']:getSharedObject()
        _bridge = {
            getJob = function()
                return ESX.GetPlayerData().job
            end,
            getGrade = function()
                return ESX.GetPlayerData().job.grade or 0
            end,
        }

    else
        -- Standalone – alles erlaubt
        _bridge = {
            getJob   = function() return { name = 'standalone' } end,
            getGrade = function() return 99 end,
        }
    end

    FD.Debug('Framework Bridge geladen: %s', fw)
    return _bridge
end

-- Bridge bei Playerdata-Update neu laden (QBX / QB feuern Events)
if not IsDuplicityVersion then
    -- QBX-Core
    AddEventHandler('QBX:Player:SetPlayerData', function()
        _bridge = nil
        FD.Debug('Bridge reset (QBX PlayerData Update)')
    end)
    -- QB-Core
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        _bridge = nil
        FD.Debug('Bridge reset (QB OnPlayerLoaded)')
    end)
    -- ESX
    AddEventHandler('esx:playerLoaded', function()
        _bridge = nil
        FD.Debug('Bridge reset (ESX playerLoaded)')
    end)
end

-- ─────────────────────────────────────────────
--  Job Result Cache
--  Verhindert wiederholte Export-Calls in canInteract
--  Wird bei PlayerData-Events automatisch invalidiert
-- ─────────────────────────────────────────────

local _jobCache = {
    hasJob  = nil,    -- bool
    grade   = nil,    -- number
    name    = nil,    -- string
    ttl     = 0,      -- GetGameTimer() Ablaufzeit
}
local JOB_CACHE_TTL = 5000   -- 5 Sekunden gültig

local function InvalidateJobCache()
    _jobCache.hasJob = nil
    _jobCache.grade  = nil
    _jobCache.name   = nil
    _jobCache.ttl    = 0
    FD.Debug('Job Cache invalidiert')
end

local function RefreshJobCache()
    local bridge = GetBridge()
    if not bridge then
        _jobCache.hasJob = false
        _jobCache.grade  = 0
        _jobCache.name   = nil
    else
        local job = bridge.getJob()
        _jobCache.hasJob = job and Config.Jobs[job.name] == true or false
        _jobCache.grade  = bridge.getGrade()
        _jobCache.name   = job and job.name or nil
    end
    _jobCache.ttl = GetGameTimer() + JOB_CACHE_TTL
end

local function GetJobCached()
    if GetGameTimer() > _jobCache.ttl or _jobCache.hasJob == nil then
        RefreshJobCache()
    end
    return _jobCache
end

-- Cache bei Framework-Events sofort invalidieren
if not IsDuplicityVersion then
    AddEventHandler('QBX:Player:SetPlayerData',    InvalidateJobCache)
    AddEventHandler('QBCore:Client:OnPlayerLoaded', InvalidateJobCache)
    AddEventHandler('esx:playerLoaded',             InvalidateJobCache)
    AddEventHandler('esx:setJob',                   InvalidateJobCache)
    -- QBX Job-Wechsel
    AddEventHandler('QBX:Client:OnJobUpdate',       InvalidateJobCache)
end

-- ─────────────────────────────────────────────
--  Job / Permission Check (Client-seitig)
--  Nutzt Cache – sicher für canInteract polling
-- ─────────────────────────────────────────────

function FD.HasJob()
    if Config.Framework == 'standalone' then return true end
    return GetJobCached().hasJob == true
end

function FD.HasGrade(action)
    local minGrade = Config.Grades[action] or 0
    if minGrade == 0 then return true end
    if Config.Framework == 'standalone' then return true end
    return GetJobCached().grade >= minGrade
end

function FD.GetJob()
    if Config.Framework == 'standalone' then return 'standalone' end
    return GetJobCached().name
end

-- ─────────────────────────────────────────────
--  Player Vehicle Detection
--  Zweistufig: Client Vorfilter + Server DB-Check
-- ─────────────────────────────────────────────

-- Cache: { [plate] = { isPlayer = bool, ttl = number } }
local _vehicleCache = {}
local VEHICLE_CACHE_TTL = 60000   -- 60s – Fahrzeug-Besitz ändert sich selten

-- Stufe 1: Client-seitiger Schnellfilter
-- Sortiert offensichtliche NPC Fahrzeuge aus ohne DB-Query
local function ClientVehiclePrefilter(vehicle)
    if not DoesEntityExist(vehicle) then return false end

    -- Fahrzeuge die aktuell von einem Spieler gesteuert werden
    -- oder auf einem Spieler-Ped spawned sind → immer erlaubt
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= 0 and IsPedAPlayer(driver) then return true end

    -- Fahrzeug hat keinen Netzwerk-Owner → lokales NPC Fahrzeug
    if not NetworkGetEntityIsNetworked(vehicle) then return false end

    -- Plate leer oder Standardformat "00000000" → NPC
    local plate = string.gsub(GetVehicleNumberPlateText(vehicle) or '', '%s+', '')
    if plate == '' or plate == '00000000' then return false end

    -- Plakette ist nur Zahlen → oft NPC (z.B. "12345678")
    -- Spieler-Kennzeichen haben meist Buchstaben (konfigurierbar)
    if Config.PlayerVehicles and Config.PlayerVehicles.requireLettersInPlate then
        if not plate:match('%a') then return false end
    end

    return true  -- Vorfilter bestanden → DB-Check nötig
end

-- Stufe 2: Server-seitiger DB-Check (mit Client-Cache)
-- cb(true/false) – async
local function IsPlayerVehicleAsync(vehicle, cb)
    if not DoesEntityExist(vehicle) then cb(false) return end

    -- Vorfilter zuerst
    if not ClientVehiclePrefilter(vehicle) then cb(false) return end

    local plate = string.upper(string.gsub(GetVehicleNumberPlateText(vehicle), '%s+', ''))
    if plate == '' then cb(false) return end

    -- Cache prüfen
    local cached = _vehicleCache[plate]
    if cached and GetGameTimer() < cached.ttl then
        cb(cached.isPlayer)
        return
    end

    -- Server fragen
    lib.callback('d4rk_fd_utility:cb_isPlayerVehicle', false, function(isPlayer)
        _vehicleCache[plate] = { isPlayer = isPlayer, ttl = GetGameTimer() + VEHICLE_CACHE_TTL }
        cb(isPlayer)
    end, plate)
end

-- Synchrone Version für canInteract (nutzt nur Cache + Vorfilter)
-- Gibt nil zurück wenn noch kein Ergebnis → im Zweifel zulassen
function FD.IsPlayerVehicle(vehicle)
    if not Config.PlayerVehicles or not Config.PlayerVehicles.enabled then return true end
    if not DoesEntityExist(vehicle) then return false end

    -- Vorfilter
    if not ClientVehiclePrefilter(vehicle) then return false end

    local plate = string.upper(string.gsub(GetVehicleNumberPlateText(vehicle), '%s+', ''))
    local cached = _vehicleCache[plate]

    if cached and GetGameTimer() < cached.ttl then
        return cached.isPlayer
    end

    -- Noch kein Cache-Eintrag → im Zweifel erlauben
    -- (wird beim Scan-Thread nachgeladen)
    return nil
end

-- Wird im Scan-Thread aufgerufen um Cache vorab zu befüllen
function FD.PrefetchVehicle(vehicle, cb)
    IsPlayerVehicleAsync(vehicle, cb or function() end)
end

-- Cache leeren (z.B. nach Fahrzeug-Rückgabe)
function FD.InvalidateVehicleCache(plate)
    if plate then
        _vehicleCache[string.upper(plate)] = nil
    else
        _vehicleCache = {}
    end
end

---@param itemName string  Key aus Config.Items
---@return boolean
function FD.HasItem(itemName)
    if not Config.UseInventory then return true end
    local cfg = Config.Items[itemName]
    if not cfg or not cfg.required then return true end
    return exports.ox_inventory:Search('count', itemName) > 0
end

---@param itemName string
---@param amount   number
function FD.RemoveItem(itemName, amount)
    if not Config.UseInventory then return end
    local cfg = Config.Items[itemName]
    if not cfg or not cfg.consume then return end
    TriggerServerEvent('d4rk_fd_utility:sv_removeItem', itemName, amount or 1)
end

-- ─────────────────────────────────────────────
--  Notify
-- ─────────────────────────────────────────────

---@param msg  string
---@param type string  'success' | 'error' | 'inform' | 'warning'
---@param duration number ms (optional)
function FD.Notify(msg, type, duration)
    type     = type     or 'inform'
    duration = duration or 4000
    if Config.UseNotify then
        lib.notify({ title = 'FD Utility', description = msg, type = type, duration = duration })
    else
        -- Fallback: einfaches Chat-Message
        SetNotificationTextEntry('STRING')
        AddTextComponentString(msg)
        DrawNotification(false, true)
    end
end

-- ─────────────────────────────────────────────
--  Cooldown System
-- ─────────────────────────────────────────────

local cooldowns = {}

---@param key string  Eindeutiger Cooldown-Key
---@return boolean    true = bereit, false = noch im Cooldown
function FD.CheckCooldown(key)
    local now = GetGameTimer()
    if cooldowns[key] and now < cooldowns[key] then
        return false
    end
    return true
end

---@param key string
---@param action string  Key aus Config.Cooldowns
function FD.SetCooldown(key, action)
    local ms = Config.Cooldowns[action] or 3000
    cooldowns[key] = GetGameTimer() + ms
end

-- ─────────────────────────────────────────────
--  Animationen
-- ─────────────────────────────────────────────

---@param animKey string  Key aus Config.Anims
---@param duration number ms – 0 = unbegrenzt
function FD.PlayAnim(animKey, duration)
    local anim = Config.Anims[animKey]
    if not anim then return end

    local ped = PlayerPedId()
    lib.requestAnimDict(anim.dict)
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, duration or -1, anim.flag, 0, false, false, false)
end

function FD.StopAnim()
    ClearPedTasks(PlayerPedId())
end

-- ─────────────────────────────────────────────
--  Progress Bar (ox_lib)
-- ─────────────────────────────────────────────

---@param label   string
---@param animKey string  Key aus Config.Anims (optional)
---@param duration number ms
---@return boolean  true = abgeschlossen, false = abgebrochen
function FD.Progress(label, animKey, duration)
    local anim = animKey and Config.Anims[animKey] or nil
    return lib.progressBar({
        duration  = duration,
        label     = label,
        useWhileDead  = false,
        canCancel = true,
        disable   = { move = true, car = true, combat = true },
        anim      = anim and {
            dict  = anim.dict,
            clip  = anim.clip,
            flag  = anim.flag,
        } or nil,
    })
end

-- ─────────────────────────────────────────────
--  Prop System (Spawn / Despawn mit Limit)
-- ─────────────────────────────────────────────

local spawnedProps = {}   -- { category = { { obj, coords } } }

---@param model    string
---@param coords   vector3
---@param heading  number
---@param category string  Key aus Config.Limits
---@return number|nil  Object handle
function FD.SpawnProp(model, coords, heading, category)
    local limit = Config.Limits[category] or 10
    spawnedProps[category] = spawnedProps[category] or {}

    -- Ältestes entfernen wenn Limit erreicht
    if #spawnedProps[category] >= limit then
        local oldest = table.remove(spawnedProps[category], 1)
        if DoesEntityExist(oldest.obj) then
            DeleteObject(oldest.obj)
        end
    end

    local hash = GetHashKey(model)
    lib.requestModel(hash)
    local obj = CreateObject(hash, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    table.insert(spawnedProps[category], { obj = obj, coords = coords })
    FD.Debug('Prop gespawnt: %s (Kategorie: %s, %d/%d)', model, category, #spawnedProps[category], limit)
    return obj
end

---@param category string
function FD.ClearProps(category)
    if not spawnedProps[category] then return end
    for _, entry in ipairs(spawnedProps[category]) do
        if DoesEntityExist(entry.obj) then
            DeleteObject(entry.obj)
        end
    end
    spawnedProps[category] = {}
end

function FD.ClearAllProps()
    for cat in pairs(spawnedProps) do
        FD.ClearProps(cat)
    end
end

-- ─────────────────────────────────────────────
--  Module Guard – prüft ob ein Modul aktiv ist
-- ─────────────────────────────────────────────

---@param name string  Key aus Config.Modules
---@return boolean
function FD.ModuleEnabled(name)
    return Config.Modules[name] == true
end
