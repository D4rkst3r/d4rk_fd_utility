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
--  Job / Permission Check (Client-seitig)
-- ─────────────────────────────────────────────

function FD.HasJob()
    if Config.Framework == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local job    = QBCore.Functions.GetPlayerData().job
        return Config.Jobs[job.name] == true
    elseif Config.Framework == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local job  = ESX.GetPlayerData().job
        return Config.Jobs[job.name] == true
    end
    return true -- standalone → immer erlaubt
end

function FD.HasGrade(action)
    local minGrade = Config.Grades[action] or 0
    if minGrade == 0 then return true end

    if Config.Framework == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local grade  = QBCore.Functions.GetPlayerData().job.grade.level or 0
        return grade >= minGrade
    elseif Config.Framework == 'esx' then
        local ESX   = exports['es_extended']:getSharedObject()
        local grade = ESX.GetPlayerData().job.grade or 0
        return grade >= minGrade
    end
    return true
end

-- ─────────────────────────────────────────────
--  ox_inventory – Item Check
-- ─────────────────────────────────────────────

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
