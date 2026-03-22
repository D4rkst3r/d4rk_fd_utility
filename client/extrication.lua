---------------------------------------------------
--  d4rk_fd_utility – Modul: Extrication
--  Türen / Reifen / Dach / Airbag / Stabilisierung
---------------------------------------------------
if not FD.ModuleEnabled('Extrication') then return end

-- ─────────────────────────────────────────────
--  Schema registrieren
--  Core registriert automatisch alle StateBag
--  Handler und ruft onApply bei Änderung auf
-- ─────────────────────────────────────────────

FD.RegisterStateSchema('extrication', {
    door = {
        type    = 'bool',
        indexed = true,
        count   = 6,
        onApply = function(vehicle, index, value)
            if value then SetVehicleDoorBroken(vehicle, index, true) end
        end,
        onClear = function(vehicle, index)
            SetVehicleDoorBreakout(vehicle, index, false)
        end,
    },
    tire = {
        type    = 'bool',
        indexed = true,
        count   = 6,
        onApply = function(vehicle, index, value)
            if value then
                SetVehicleTyreBurst(vehicle, index, true, 1000.0)
                SetVehicleWheelHealth(vehicle, index, 0.0)
            end
        end,
    },
    roof = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            if value then
                if GetIsDoorValid(vehicle, 4) then SetVehicleDoorBroken(vehicle, 4, true) end
                if GetIsDoorValid(vehicle, 5) then SetVehicleDoorBroken(vehicle, 5, true) end
                SetVehicleRoofLivery(vehicle, -1)
            end
        end,
    },
    airbag = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            if value then SetVehicleCanBeVisiblyDamaged(vehicle, false) end
        end,
    },
    stabilized = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            FreezeEntityPosition(vehicle, value == true)
        end,
    },
})

-- ─────────────────────────────────────────────
--  Reset Handler (alle States gelöscht)
-- ─────────────────────────────────────────────

-- fd_cleared → kompletter Reset
AddStateBagChangeHandler('fd_cleared', nil, function(bagName, _, value)
    if not value then return end
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    FreezeEntityPosition(vehicle, false)
    FD.Debug('Fahrzeug %d komplett zurückgesetzt', vehicle)
end)

-- fd_module_cleared → nur Extrication zurücksetzen
AddStateBagChangeHandler('fd_module_cleared', nil, function(bagName, _, value)
    if value ~= 'extrication' then return end
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    FreezeEntityPosition(vehicle, false)
end)

-- ─────────────────────────────────────────────
--  Lokaler Status (nicht persistiert)
-- ─────────────────────────────────────────────

local activeTargets       = {}
local stabilizedVehicles  = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function IsVehicleWrecked(vehicle)
    return GetVehicleEngineHealth(vehicle) < 0.0
        or IsVehicleDriveable(vehicle, false) == false
end

local function CanInteract(action, vehicle)
    if not FD.HasJob()   then FD.Notify(T('no_job'), 'error')   return false end
    if not FD.HasGrade('extrication') then FD.Notify(T('no_job'), 'error') return false end
    if not FD.CheckCooldown(('extr_%s_%d'):format(action, vehicle)) then
        FD.Notify(T('cooldown'), 'warning') return false
    end
    return true
end

local function SetCD(action, vehicle)
    FD.SetCooldown(('extr_%s_%d'):format(action, vehicle), action)
end

-- ─────────────────────────────────────────────
--  Türen entfernen
-- ─────────────────────────────────────────────

local doorLabels = {
    [0]='Fahrertür', [1]='Beifahrertür',
    [2]='Hinten Links', [3]='Hinten Rechts',
    [4]='Motorhaube', [5]='Kofferraum',
}

local function RemoveDoor(vehicle)
    if not CanInteract('doorRemove', vehicle) then return end

    local item = FD.HasItem('hydraulicSpreader') and 'hydraulicSpreader'
              or FD.HasItem('rescueSaw')         and 'rescueSaw'
              or nil
    if not item then FD.Notify(T('no_item'), 'error') return end

    -- Vorhandene & noch nicht entfernte Türen listen
    local options = {}
    for i = 0, 5 do
        if GetIsDoorValid(vehicle, i)
        and not FD.State.Get(vehicle, 'extrication', 'door', i) then
            local label = doorLabels[i] or ('Tür %d'):format(i)
            options[#options + 1] = {
                title    = label,
                icon     = 'fas fa-door-open',
                onSelect = function()
                    local done = FD.Progress(
                        ('%s – %s'):format(T('door_remove'), label),
                        item == 'hydraulicSpreader' and 'spreizer' or 'saw',
                        Config.Items[item].useTime
                    )
                    if not done then return end
                    FD.State.Set(vehicle, 'extrication', 'door', i, true)
                    SetCD('doorRemove', vehicle)
                    FD.RemoveItem(item, 1)
                    FD.Notify(T('door_removed'), 'success')
                end,
            }
        end
    end

    if #options == 0 then FD.Notify('Keine Türen mehr vorhanden.', 'error') return end

    lib.registerContext({ id = 'fd_door_select', title = 'Tür auswählen', options = options })
    lib.showContext('fd_door_select')
end

-- ─────────────────────────────────────────────
--  Reifen entfernen
-- ─────────────────────────────────────────────

local tireLabels = {
    [0]='Vorne Links', [1]='Vorne Rechts',
    [2]='Hinten Links', [3]='Hinten Rechts',
    [4]='Mitte Links',  [5]='Mitte Rechts',
}

local function RemoveTire(vehicle)
    if not CanInteract('tireRemove', vehicle) then return end
    if not FD.HasItem('tireCutter') then FD.Notify(T('no_item'), 'error') return end

    local options = {}
    for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        if not FD.State.Get(vehicle, 'extrication', 'tire', i) then
            local label = tireLabels[i] or ('Reifen %d'):format(i)
            options[#options + 1] = {
                title    = label,
                icon     = 'fas fa-circle',
                onSelect = function()
                    local done = FD.Progress(
                        ('%s – %s'):format(T('tire_remove'), label),
                        'saw',
                        Config.Items.tireCutter.useTime
                    )
                    if not done then return end
                    FD.State.Set(vehicle, 'extrication', 'tire', i, true)
                    SetCD('tireRemove', vehicle)
                    FD.RemoveItem('tireCutter', 1)
                    FD.Notify(T('tire_removed'), 'success')
                end,
            }
        end
    end

    if #options == 0 then FD.Notify('Alle Reifen bereits entfernt.', 'error') return end

    lib.registerContext({ id = 'fd_tire_select', title = 'Reifen auswählen', options = options })
    lib.showContext('fd_tire_select')
end

-- ─────────────────────────────────────────────
--  Dach aufschneiden
-- ─────────────────────────────────────────────

local function RemoveRoof(vehicle)
    if not CanInteract('doorRemove', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'roof') then
        FD.Notify('Dach wurde bereits aufgeschnitten.', 'warning') return
    end
    if not FD.HasItem('rescueSaw') then FD.Notify(T('no_item'), 'error') return end

    local done = FD.Progress('Dach aufschneiden', 'saw', Config.Items.rescueSaw.useTime + 2000)
    if not done then return end

    FD.State.Set(vehicle, 'extrication', 'roof', nil, true)
    SetCD('doorRemove', vehicle)
    FD.RemoveItem('rescueSaw', 1)
    FD.Notify('Dach aufgeschnitten.', 'success')
end

-- ─────────────────────────────────────────────
--  Airbag deaktivieren
-- ─────────────────────────────────────────────

local function DeactivateAirbag(vehicle)
    if not CanInteract('airbag', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'airbag') then
        FD.Notify('Airbag bereits deaktiviert.', 'warning') return
    end

    local done = FD.Progress(T('airbag_deactivate'), 'kneel', Config.Cooldowns.airbag)
    if not done then return end

    FD.State.Set(vehicle, 'extrication', 'airbag', nil, true)
    SetCD('airbag', vehicle)
    FD.Notify(T('airbag_done'), 'success')
end

-- ─────────────────────────────────────────────
--  Fahrzeug stabilisieren
-- ─────────────────────────────────────────────

local function StabilizeVehicle(vehicle)
    if not CanInteract('doorRemove', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'stabilized') then
        FD.Notify('Bereits stabilisiert.', 'warning') return
    end

    local done = FD.Progress('Fahrzeug stabilisieren', 'place', 4000)
    if not done then return end

    -- Keil-Props platzieren
    local heading = GetEntityHeading(vehicle)
    for _, offset in ipairs({{-1.2,1.5},{1.2,1.5},{-1.2,-1.5},{1.2,-1.5}}) do
        local wx, wy, wz = table.unpack(GetOffsetFromEntityInWorldCoords(vehicle, offset[1], offset[2], -0.3))
        FD.SpawnProp('prop_rub_brokentire', vector3(wx, wy, wz), heading, 'cones')
    end

    FD.State.Set(vehicle, 'extrication', 'stabilized', nil, true)
    stabilizedVehicles[vehicle] = true
    FD.Notify('Fahrzeug stabilisiert.', 'success')
end

local function DestabilizeVehicle(vehicle)
    if not FD.State.Get(vehicle, 'extrication', 'stabilized') then return end
    FD.State.Set(vehicle, 'extrication', 'stabilized', nil, false)
    stabilizedVehicles[vehicle] = nil
    FD.Notify('Stabilisierung aufgehoben.', 'inform')
end

-- ─────────────────────────────────────────────
--  ox_target Options
-- ─────────────────────────────────────────────

local function BuildTargetOptions(vehicle)
    return {
        {
            name        = 'fd_door_remove',
            icon        = 'fas fa-door-open',
            label       = T('door_remove'),
            distance    = Config.Target.distance,
            onSelect    = function() RemoveDoor(vehicle) end,
            canInteract = function() return FD.HasJob() end,
        },
        {
            name        = 'fd_tire_remove',
            icon        = 'fas fa-circle-notch',
            label       = T('tire_remove'),
            distance    = Config.Target.distance,
            onSelect    = function() RemoveTire(vehicle) end,
            canInteract = function() return FD.HasJob() end,
        },
        {
            name        = 'fd_roof_remove',
            icon        = 'fas fa-cut',
            label       = 'Dach aufschneiden',
            distance    = Config.Target.distance,
            onSelect    = function() RemoveRoof(vehicle) end,
            canInteract = function() return FD.HasJob() end,
        },
        {
            name        = 'fd_airbag',
            icon        = 'fas fa-wind',
            label       = T('airbag_deactivate'),
            distance    = Config.Target.distance,
            onSelect    = function() DeactivateAirbag(vehicle) end,
            canInteract = function() return FD.HasJob() end,
        },
        {
            name        = 'fd_stabilize',
            icon        = 'fas fa-car-crash',
            label       = 'Fahrzeug stabilisieren',
            distance    = Config.Target.distance,
            onSelect    = function() StabilizeVehicle(vehicle) end,
            canInteract = function()
                return FD.HasJob() and not FD.State.Get(vehicle, 'extrication', 'stabilized')
            end,
        },
        {
            name        = 'fd_destabilize',
            icon        = 'fas fa-unlock',
            label       = 'Stabilisierung lösen',
            distance    = Config.Target.distance,
            onSelect    = function() DestabilizeVehicle(vehicle) end,
            canInteract = function()
                return FD.HasJob() and FD.State.Get(vehicle, 'extrication', 'stabilized') == true
            end,
        },
    }
end

-- ─────────────────────────────────────────────
--  Scan Thread – optimiert
-- ─────────────────────────────────────────────

CreateThread(function()
    Config.Extrication  = Config.Extrication  or { onlyWrecked = false }
    Config.PlayerVehicles = Config.PlayerVehicles or { enabled = true }
    Wait(500)

    while FD.ModuleEnabled('Extrication') do

        -- Kein FD-Job → langsam scannen, Targets räumen
        if not FD.HasJob() then
            if next(activeTargets) then
                for vehicle in pairs(activeTargets) do
                    if DoesEntityExist(vehicle) then
                        exports.ox_target:removeLocalEntity(vehicle)
                    end
                    activeTargets[vehicle]      = nil
                    stabilizedVehicles[vehicle] = nil
                end
            end
            Wait(5000)
            goto continue
        end

        do
            local pCoords = GetEntityCoords(PlayerPedId())

            -- Hilfsfunktion: Fahrzeug registrieren wenn alle Checks bestehen
            local function TryRegisterVehicle(vehicle)
                if activeTargets[vehicle] then return end
                if not DoesEntityExist(vehicle) then return end
                if #(GetEntityCoords(vehicle) - pCoords) > 30.0 then return end
                if Config.Extrication.onlyWrecked and not IsVehicleWrecked(vehicle) then return end

                if Config.PlayerVehicles.enabled then
                    -- Synchroner Check: Cache-Treffer oder nil (noch unbekannt)
                    local known = FD.IsPlayerVehicle(vehicle)

                    if known == false then return end   -- sicher kein Spieler-Fahrzeug

                    if known == nil then
                        -- Cache noch leer → async nachladen, diesmal überspringen
                        FD.PrefetchVehicle(vehicle, function(isPlayer)
                            if isPlayer and not activeTargets[vehicle] and DoesEntityExist(vehicle) then
                                exports.ox_target:addLocalEntity(vehicle, BuildTargetOptions(vehicle))
                                activeTargets[vehicle] = true
                                FD.Debug('Target nachregistriert (async): Fahrzeug %d', vehicle)
                            end
                        end)
                        return
                    end
                end

                -- Alle Checks bestanden → Target setzen
                exports.ox_target:addLocalEntity(vehicle, BuildTargetOptions(vehicle))
                activeTargets[vehicle] = true
                FD.Debug('Target gesetzt: Fahrzeug %d', vehicle)
            end

            -- Primär: GetClosestVehicle (günstig)
            local closest = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 30.0, 0, 70)
            if closest and closest ~= 0 then
                TryRegisterVehicle(closest)
            end

            -- Sekundär: GetGamePool nur wenn aktive Szene vorhanden
            if next(activeTargets) then
                local pool = GetGamePool('CVehicle')
                for i, vehicle in ipairs(pool) do
                    TryRegisterVehicle(vehicle)
                    if i % 10 == 0 then Wait(0) end
                end
            end

            -- Cleanup: weg oder zu weit
            for vehicle in pairs(activeTargets) do
                local gone = not DoesEntityExist(vehicle)
                local far  = not gone and #(pCoords - GetEntityCoords(vehicle)) > 40.0
                if gone or far then
                    if not gone then exports.ox_target:removeLocalEntity(vehicle) end
                    activeTargets[vehicle]      = nil
                    stabilizedVehicles[vehicle] = nil
                end
            end
        end

        ::continue::
        Wait(next(activeTargets) and 3000 or 5000)
    end
end)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for vehicle in pairs(activeTargets) do
        if DoesEntityExist(vehicle) then exports.ox_target:removeLocalEntity(vehicle) end
    end
    for vehicle in pairs(stabilizedVehicles) do
        if DoesEntityExist(vehicle) then FreezeEntityPosition(vehicle, false) end
    end
end)
