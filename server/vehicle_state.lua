---------------------------------------------------
--  d4rk_fd_utility – Vehicle State Backend (Server)
--  DB Persistenz + State Bag Sync
---------------------------------------------------

VehicleState = {}

local stateCache        = {}   -- { [plate] = { [fullKey] = value } }
local pvCache           = {}   -- { [plate] = { result = bool, ttl = number } }
local PV_CACHE_TTL      = 120000

-- Plates die tatsächlich States in der DB haben
-- Wird beim Start geladen und bei jedem Set/Clear aktualisiert
-- Verhindert DB-Query für jedes gespawnte NPC-Fahrzeug
local knownPlates       = {}

local function LoadKnownPlates()
    MySQL.query('SELECT DISTINCT plate FROM fd_vehicle_states', {}, function(rows)
        knownPlates = {}
        for _, row in ipairs(rows or {}) do
            knownPlates[row.plate] = true
        end
        FD.Debug('vehicle', 'Bekannte Plates geladen: %d', (function()
            local n = 0
            for _ in pairs(knownPlates) do n = n + 1 end
            return n
        end)())
    end)
end

-- ─────────────────────────────────────────────
--  Callback: Spieler-Fahrzeug Check
--  Client fragt an, Server prüft DB
-- ─────────────────────────────────────────────

lib.callback.register('d4rk_fd_utility:cb_isPlayerVehicle', function(source, plate)
    if not plate or plate == '' then return false end
    plate = string.upper(string.gsub(plate, '%s+', ''))

    if Config.Framework == 'standalone' then return true end
    if not Config.PlayerVehicles or not Config.PlayerVehicles.enabled then return true end

    local hit = pvCache[plate]
    if hit and GetGameTimer() < hit.ttl then return hit.result end

    local tbl   = Config.PlayerVehicles.dbTable  or 'player_vehicles'
    local col   = Config.PlayerVehicles.dbColumn or 'plate'
    local query = ('SELECT 1 FROM `%s` WHERE `%s` = ? LIMIT 1'):format(tbl, col)

    -- MySQL.scalar.await direkt – lib.callback läuft bereits in Coroutine
    local result   = MySQL.scalar.await(query, { plate })
    local isPlayer = result ~= nil and result ~= false

    pvCache[plate] = { result = isPlayer, ttl = GetGameTimer() + PV_CACHE_TTL }
    FD.Debug('vehicle', 'cb_isPlayerVehicle: %s → %s [%s.%s]', plate, tostring(isPlayer), tbl, col)
    return isPlayer
end)

-- Anderen Scripts erlauben den Cache zu invalidieren
-- z.B. nach Fahrzeug-Rückgabe / Verkauf
RegisterNetEvent('d4rk_fd_utility:sv_invalidateVehicleCache', function(plate)
    if plate then pvCache[string.upper(plate)] = nil
    else pvCache = {} end
end)



-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function NormalizePlate(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    return string.upper(string.gsub(GetVehicleNumberPlateText(vehicle), '%s+', ''))
end

local function ApplyStateBag(vehicle, fullKey, value)
    if not DoesEntityExist(vehicle) then return end
    Entity(vehicle).state:set('fd_' .. fullKey, value, true)
end

-- ─────────────────────────────────────────────
--  DB Operationen
-- ─────────────────────────────────────────────

function VehicleState.Set(plate, fullKey, value)
    stateCache[plate]          = stateCache[plate] or {}
    stateCache[plate][fullKey] = value
    knownPlates[plate]         = true   -- in Index eintragen

    MySQL.update(
        [[INSERT INTO fd_vehicle_states (plate, state_key, state_value)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE state_value = VALUES(state_value), updated_at = CURRENT_TIMESTAMP]],
        { plate, fullKey, json.encode(value) }
    )
end

function VehicleState.GetAll(plate, cb)
    if stateCache[plate] then cb(stateCache[plate]) return end

    MySQL.query(
        'SELECT state_key, state_value FROM fd_vehicle_states WHERE plate = ?',
        { plate },
        function(rows)
            local result = {}
            for _, row in ipairs(rows or {}) do
                local ok, val = pcall(json.decode, row.state_value)
                result[row.state_key] = ok and val or row.state_value
            end
            stateCache[plate] = result
            cb(result)
        end
    )
end

function VehicleState.Clear(plate, cb)
    stateCache[plate]  = nil
    knownPlates[plate] = nil   -- aus Index entfernen

    MySQL.update('DELETE FROM fd_vehicle_states WHERE plate = ?', { plate }, cb)
end

function VehicleState.ClearModule(plate, module, cb)
    if stateCache[plate] then
        local hasRemaining = false
        for key in pairs(stateCache[plate]) do
            if key:sub(1, #module + 1) == module .. '_' then
                stateCache[plate][key] = nil
            else
                hasRemaining = true
            end
        end
        if not hasRemaining then knownPlates[plate] = nil end
    end

    MySQL.update(
        "DELETE FROM fd_vehicle_states WHERE plate = ? AND state_key LIKE ?",
        { plate, module .. '_%' },
        cb
    )
end

-- ─────────────────────────────────────────────
--  States auf Fahrzeug anwenden (nach Spawn)
-- ─────────────────────────────────────────────

function VehicleState.Apply(vehicle, cb)
    local plate = NormalizePlate(vehicle)
    if not plate then if cb then cb(false) end return end

    -- Nicht in knownPlates → keine States vorhanden → sofort fertig
    if not knownPlates[plate] then
        if cb then cb(false) end
        return
    end

    VehicleState.GetAll(plate, function(states)
        local count = 0
        for fullKey, value in pairs(states) do
            ApplyStateBag(vehicle, fullKey, value)
            count = count + 1
        end
        if count > 0 then FD.Debug('vehicle', 'States angewendet: %s (%d Keys)', plate, count) end
        if cb then cb(true, states) end
    end)
end

-- ─────────────────────────────────────────────
--  Fahrzeug Spawn Hook
--  Nur Fahrzeuge mit bekannter Plate prüfen
-- ─────────────────────────────────────────────

AddEventHandler('entityCreated', function(entity)
    local ok, etype = pcall(GetEntityType, entity)
    if not ok or etype ~= 2 then return end

    SetTimeout(500, function()
        if not DoesEntityExist(entity) then return end
        local ok2, plate = pcall(NormalizePlate, entity)
        if not ok2 or not plate then return end
        if knownPlates[plate] then
            VehicleState.Apply(entity)
        end
    end)
end)

-- ─────────────────────────────────────────────
--  Startup: bekannte Plates laden
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetTimeout(1000, LoadKnownPlates)
end)

RegisterNetEvent('d4rk_fd_utility:sv_setState', function(netVehicle, fullKey, value)
    local vehicle = NetworkGetEntityFromNetworkId(netVehicle)
    if not DoesEntityExist(vehicle) then return end
    local plate = NormalizePlate(vehicle)
    if not plate then return end
    VehicleState.Set(plate, fullKey, value)
    ApplyStateBag(vehicle, fullKey, value)
    FD.Debug('state', 'sv_setState: %s | %s = %s (Player %d)', plate, fullKey, tostring(value), source)
end)

RegisterNetEvent('d4rk_fd_utility:sv_clearState', function(netVehicle)
    local vehicle = NetworkGetEntityFromNetworkId(netVehicle)
    if not DoesEntityExist(vehicle) then return end
    local plate = NormalizePlate(vehicle)
    if not plate then return end
    VehicleState.Clear(plate, function()
        Entity(vehicle).state:set('fd_cleared', GetGameTimer(), true)
    end)
end)

RegisterNetEvent('d4rk_fd_utility:sv_clearStateModule', function(netVehicle, module)
    local vehicle = NetworkGetEntityFromNetworkId(netVehicle)
    if not DoesEntityExist(vehicle) then return end
    local plate = NormalizePlate(vehicle)
    if not plate then return end
    VehicleState.ClearModule(plate, module, function()
        Entity(vehicle).state:set('fd_module_cleared', module, true)
    end)
end)

-- ─────────────────────────────────────────────
--  Export API
-- ─────────────────────────────────────────────

exports('GetVehicleState', function(plate, cb)
    plate = string.upper(string.gsub(plate or '', '%s+', ''))
    VehicleState.GetAll(plate, cb or function() end)
end)

exports('SetVehicleState', function(plate, key, value)
    plate = string.upper(string.gsub(plate or '', '%s+', ''))
    VehicleState.Set(plate, key, value)
end)

exports('ClearVehicleState', function(plate)
    plate = string.upper(string.gsub(plate or '', '%s+', ''))
    VehicleState.Clear(plate)
end)

exports('ApplyVehicleState', function(vehicle)
    if DoesEntityExist(vehicle) then VehicleState.Apply(vehicle) end
end)