---------------------------------------------------
--  d4rk_fd_utility – Vehicle State Backend (Server)
--  DB Persistenz + State Bag Sync
---------------------------------------------------

VehicleState = {}

local stateCache        = {}   -- { [plate] = { [fullKey] = value } }
local pvCache           = {}   -- { [plate] = { result = bool, ttl = number } }
local PV_CACHE_TTL      = 120000

-- ─────────────────────────────────────────────
--  Callback: Spieler-Fahrzeug Check
--  Client fragt an, Server prüft DB
-- ─────────────────────────────────────────────

lib.callback.register('d4rk_fd_utility:cb_isPlayerVehicle', function(source, plate)
    if not plate or plate == '' then return false end
    plate = string.upper(string.gsub(plate, '%s+', ''))

    if Config.Framework == 'standalone' then return true end
    if not Config.PlayerVehicles or not Config.PlayerVehicles.enabled then return true end

    -- Server-Cache prüfen
    local hit = pvCache[plate]
    if hit and GetGameTimer() < hit.ttl then return hit.result end

    -- MySQL.scalar.await – gibt nur den ersten Wert zurück, günstiger als single
    local tbl   = Config.PlayerVehicles.dbTable  or 'player_vehicles'
    local col   = Config.PlayerVehicles.dbColumn or 'plate'
    local query = ('SELECT 1 FROM `%s` WHERE `%s` = ? LIMIT 1'):format(tbl, col)

    local result   = DB.ScalarSync(query, { plate })
    local isPlayer = result ~= nil and result ~= false

    pvCache[plate] = { result = isPlayer, ttl = GetGameTimer() + PV_CACHE_TTL }
    FD.Debug('cb_isPlayerVehicle: %s → %s [%s.%s]', plate, tostring(isPlayer), tbl, col)
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

    DB.Execute(
        [[INSERT INTO fd_vehicle_states (plate, state_key, state_value)
          VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE state_value = VALUES(state_value), updated_at = CURRENT_TIMESTAMP]],
        { plate, fullKey, json.encode(value) }
    )
end

function VehicleState.GetAll(plate, cb)
    if stateCache[plate] then cb(stateCache[plate]) return end

    DB.Fetch(
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
    stateCache[plate] = nil
    DB.Execute('DELETE FROM fd_vehicle_states WHERE plate = ?', { plate }, cb)
end

function VehicleState.ClearModule(plate, module, cb)
    if stateCache[plate] then
        for key in pairs(stateCache[plate]) do
            if key:sub(1, #module + 1) == module .. '_' then
                stateCache[plate][key] = nil
            end
        end
    end
    DB.Execute(
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

    VehicleState.GetAll(plate, function(states)
        local count = 0
        for fullKey, value in pairs(states) do
            ApplyStateBag(vehicle, fullKey, value)
            count = count + 1
        end
        if count > 0 then FD.Debug('States angewendet: %s (%d Keys)', plate, count) end
        if cb then cb(true, states) end
    end)
end

-- ─────────────────────────────────────────────
--  Net Events
-- ─────────────────────────────────────────────

RegisterNetEvent('d4rk_fd_utility:sv_setState', function(netVehicle, fullKey, value)
    local vehicle = NetworkGetEntityFromNetworkId(netVehicle)
    if not DoesEntityExist(vehicle) then return end
    local plate = NormalizePlate(vehicle)
    if not plate then return end
    VehicleState.Set(plate, fullKey, value)
    ApplyStateBag(vehicle, fullKey, value)
    FD.Debug('sv_setState: %s | %s = %s (Player %d)', plate, fullKey, tostring(value), source)
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
--  Fahrzeug Spawn Hook
-- ─────────────────────────────────────────────

AddEventHandler('entityCreated', function(entity)
    if GetEntityType(entity) ~= 2 then return end
    SetTimeout(1000, function()
        if DoesEntityExist(entity) then VehicleState.Apply(entity) end
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
