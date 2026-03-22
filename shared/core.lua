---------------------------------------------------
--  d4rk_fd_utility – Core State Manager
--  Zentrales Schema-System für alle Module
---------------------------------------------------

FD.State    = {}
FD._schemas = {}   -- registrierte Schemas { [module] = schema }
FD._cache   = {}   -- lokaler State Cache  { [netId]  = { [fullKey] = value } }

-- ─────────────────────────────────────────────
--  Schema Registrierung
--  Jedes Modul ruft das einmal beim Start auf
-- ─────────────────────────────────────────────

--[[
    Schema-Aufbau:
    {
        key_name = {
            type    = 'bool' | 'int' | 'float' | 'string',
            indexed = true | false,   -- true = key_0, key_1, key_2 ...
            count   = 6,              -- max Indices (nur wenn indexed = true)

            -- Client-only: wird aufgerufen wenn State Bag sich ändert
            onApply = function(vehicle, index, value) ... end,

            -- Optional: wird aufgerufen wenn State gelöscht wird (reset)
            onClear = function(vehicle, index) ... end,
        }
    }
]]

---@param module string   z.B. 'extrication', 'hazmat', 'scene'
---@param schema table
function FD.RegisterStateSchema(module, schema)
    if FD._schemas[module] then
        FD.Debug('Schema überschrieben: %s', module)
    end

    FD._schemas[module] = schema
    FD.Debug('Schema registriert: %s (%d Keys)', module, (function()
        local n = 0
        for _ in pairs(schema) do n = n + 1 end
        return n
    end)())

    -- Auf Client-Seite: StateBag Handler automatisch registrieren
    if IsDuplicityVersion then return end  -- Server überspringen
    FD._RegisterStateBagHandlers(module, schema)
end

-- ─────────────────────────────────────────────
--  Key Normalisierung
--  Format: module_key  oder  module_key_index
-- ─────────────────────────────────────────────

---@param module string
---@param key    string
---@param index  number|nil
---@return string  vollständiger State-Key
function FD.State.BuildKey(module, key, index)
    if index ~= nil then
        return ('%s_%s_%d'):format(module, key, index)
    end
    return ('%s_%s'):format(module, key)
end

-- ─────────────────────────────────────────────
--  Cache
-- ─────────────────────────────────────────────

local function CacheSet(netId, fullKey, value)
    FD._cache[netId] = FD._cache[netId] or {}
    FD._cache[netId][fullKey] = value
end

local function CacheGet(netId, fullKey)
    if not FD._cache[netId] then return nil end
    return FD._cache[netId][fullKey]
end

local function CacheClearVehicle(netId)
    FD._cache[netId] = nil
end

-- ─────────────────────────────────────────────
--  State Setzen (von Client-Modulen aufgerufen)
-- ─────────────────────────────────────────────

---@param vehicle integer  Entity Handle
---@param module  string
---@param key     string
---@param index   number|nil  für indexed Keys (Türen, Reifen usw.)
---@param value   any
function FD.State.Set(vehicle, module, key, index, value)
    -- Schema validieren
    local schema = FD._schemas[module]
    if not schema or not schema[key] then
        FD.Debug('Unbekannter State Key: %s.%s', module, key)
        return
    end

    local fullKey = FD.State.BuildKey(module, key, index)
    local netId   = VehToNet(vehicle)

    -- Lokalen Cache updaten
    CacheSet(netId, fullKey, value)

    -- An Server schicken → DB + State Bags für alle
    TriggerServerEvent('d4rk_fd_utility:sv_setState', netId, fullKey, value)
    FD.Debug('State.Set: %s = %s (NetID %d)', fullKey, tostring(value), netId)
end

-- ─────────────────────────────────────────────
--  State Lesen (aus lokalem Cache)
-- ─────────────────────────────────────────────

---@param vehicle integer
---@param module  string
---@param key     string
---@param index   number|nil
---@return any
function FD.State.Get(vehicle, module, key, index)
    local netId   = VehToNet(vehicle)
    local fullKey = FD.State.BuildKey(module, key, index)
    return CacheGet(netId, fullKey)
end

-- ─────────────────────────────────────────────
--  State Löschen (ein Modul oder alles)
-- ─────────────────────────────────────────────

---@param vehicle integer
---@param module  string|nil  nil = alle Module
function FD.State.Clear(vehicle, module)
    local netId = VehToNet(vehicle)

    if module then
        -- Nur dieses Modul löschen
        if FD._cache[netId] then
            for fullKey in pairs(FD._cache[netId]) do
                if fullKey:sub(1, #module + 1) == module .. '_' then
                    FD._cache[netId][fullKey] = nil
                end
            end
        end
        TriggerServerEvent('d4rk_fd_utility:sv_clearStateModule', netId, module)
    else
        -- Alles löschen
        CacheClearVehicle(netId)
        TriggerServerEvent('d4rk_fd_utility:sv_clearState', netId)
    end
end

-- ─────────────────────────────────────────────
--  StateBag Handler (Client-only)
--  Wird automatisch für jedes Schema registriert
-- ─────────────────────────────────────────────

function FD._RegisterStateBagHandlers(module, schema)
    for key, def in pairs(schema) do
        if def.onApply then
            if def.indexed then
                -- Handler für jeden Index: module_key_0, module_key_1 ...
                for i = 0, (def.count or 6) - 1 do
                    local fullKey = FD.State.BuildKey(module, key, i)
                    local capturedIndex = i
                    local capturedDef   = def

                    AddStateBagChangeHandler('fd_' .. fullKey, nil, function(bagName, _, value)
                        local vehicle = GetEntityFromStateBagName(bagName)
                        if not vehicle or not DoesEntityExist(vehicle) then return end

                        -- Cache updaten
                        local netId = VehToNet(vehicle)
                        CacheSet(netId, fullKey, value)

                        -- Callback ausführen
                        capturedDef.onApply(vehicle, capturedIndex, value)
                        FD.Debug('StateBag → %s = %s (Fahrzeug %d)', fullKey, tostring(value), vehicle)
                    end)
                end
            else
                -- Einfacher Handler ohne Index
                local fullKey     = FD.State.BuildKey(module, key, nil)
                local capturedDef = def

                AddStateBagChangeHandler('fd_' .. fullKey, nil, function(bagName, _, value)
                    local vehicle = GetEntityFromStateBagName(bagName)
                    if not vehicle or not DoesEntityExist(vehicle) then return end

                    local netId = VehToNet(vehicle)
                    CacheSet(netId, fullKey, value)

                    capturedDef.onApply(vehicle, nil, value)
                    FD.Debug('StateBag → %s = %s (Fahrzeug %d)', fullKey, tostring(value), vehicle)
                end)
            end
        end
    end

    FD.Debug('StateBag Handler registriert für Modul: %s', module)
end

-- ─────────────────────────────────────────────
--  Cache Cleanup wenn Fahrzeug despawnt
-- ─────────────────────────────────────────────
if not IsDuplicityVersion then
    CreateThread(function()
        while true do
            Wait(30000)  -- alle 30s aufräumen
            for netId in pairs(FD._cache) do
                local vehicle = NetToVeh(netId)
                if not DoesEntityExist(vehicle) then
                    FD._cache[netId] = nil
                    FD.Debug('Cache bereinigt: NetID %d', netId)
                end
            end
        end
    end)
end
