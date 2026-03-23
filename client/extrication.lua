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
                SetVehicleBodyHealth(vehicle, 200.0)
                SetVehicleRoofLivery(vehicle, -1)
                for i = 0, 12 do
                    if HasVehicleExtra(vehicle, i) then
                        SetVehicleExtra(vehicle, i, true)
                    end
                end
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
--  Dach aufschneiden
-- ─────────────────────────────────────────────

local function RemoveRoof(vehicle)
    if not CanInteract('doorRemove', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'roof') then
        FD.Notify('Dach wurde bereits aufgeschnitten.', 'warning') return
    end
    if not FD.HasItem('rescuesaw') then FD.Notify(T('no_item'), 'error') return end

    local done = FD.Progress('Dach aufschneiden', 'saw', Config.Items.rescuesaw.useTime + 2000)
    if not done then return end

    -- GTA hat keinen eigenen Dach-Door-Index (4=Motorhaube, 5=Kofferraum)
    -- Karosserie-Schaden simuliert aufgeschnittenes Dach visuell
    SetVehicleBodyHealth(vehicle, 200.0)
    SetVehicleRoofLivery(vehicle, -1)
    -- Extras deaktivieren (Soft-Top bei Cabrios)
    for i = 0, 12 do
        if HasVehicleExtra(vehicle, i) then
            SetVehicleExtra(vehicle, i, true)
        end
    end
    FD.State.Set(vehicle, 'extrication', 'roof', nil, true)
    SetCD('doorRemove', vehicle)
    FD.RemoveItem('rescuesaw', 1)
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

    SetVehicleCanBeVisiblyDamaged(vehicle, false)
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
        FD.SpawnProp(Config.Props.wheel, vector3(wx, wy, wz), heading, 'cones')
    end

    FreezeEntityPosition(vehicle, true)
    FD.State.Set(vehicle, 'extrication', 'stabilized', nil, true)
    stabilizedVehicles[vehicle] = true
    FD.Notify('Fahrzeug stabilisiert.', 'success')
end

local function DestabilizeVehicle(vehicle)
    if not FD.State.Get(vehicle, 'extrication', 'stabilized') then return end
    FreezeEntityPosition(vehicle, false)
    FD.ClearProps('cones')
    FD.State.Set(vehicle, 'extrication', 'stabilized', nil, false)
    stabilizedVehicles[vehicle] = nil
    FD.Notify('Stabilisierung aufgehoben.', 'inform')
end

-- ─────────────────────────────────────────────
--  Bone → Door Index Mapping
-- ─────────────────────────────────────────────

local boneToDoorIndex = {
    door_dside_f = 0,
    door_dside_r = 1,
    door_pside_f = 2,
    door_pside_r = 3,
    bonnet       = 4,
    boot         = 5,
}

local boneToDoorLabel = {
    door_dside_f = 'Fahrertür vorne',
    door_dside_r = 'Fahrertür hinten',
    door_pside_f = 'Beifahrertür vorne',
    door_pside_r = 'Beifahrertür hinten',
    bonnet       = 'Motorhaube',
    boot         = 'Kofferraum',
}

local boneToTireIndex = {
    wheel_lf = 0,
    wheel_rf = 1,
    wheel_lb = 2,
    wheel_rb = 3,
    wheel_lm = 4,
    wheel_rm = 5,
}

local boneToTireLabel = {
    wheel_lf = 'Reifen vorne links',
    wheel_rf = 'Reifen vorne rechts',
    wheel_lb = 'Reifen hinten links',
    wheel_rb = 'Reifen hinten rechts',
    wheel_lm = 'Reifen mitte links',
    wheel_rm = 'Reifen mitte rechts',
}

-- ─────────────────────────────────────────────
--  Bone-basierte Einzelaktionen
-- ─────────────────────────────────────────────

local function RemoveDoorByIndex(vehicle, doorIndex, label)
    if not CanInteract('doorRemove', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'door', doorIndex) then
        FD.Notify(label .. ' bereits entfernt.', 'warning') return
    end

    local item = FD.HasItem('hydraulicspreader') and 'hydraulicspreader'
              or FD.HasItem('rescuesaw')         and 'rescuesaw'
              or nil
    if not item then FD.Notify(T('no_item'), 'error') return end

    local done = FD.Progress(
        ('Entferne %s'):format(label),
        item == 'hydraulicspreader' and 'spreizer' or 'saw',
        Config.Items[item].useTime
    )
    if not done then return end

    SetVehicleDoorBroken(vehicle, doorIndex, true)
    FD.State.Set(vehicle, 'extrication', 'door', doorIndex, true)
    SetCD('doorRemove', vehicle)
    FD.RemoveItem(item, 1)
    FD.Notify(label .. ' entfernt.', 'success')
end

local function RemoveTireByIndex(vehicle, tireIndex, label)
    if not CanInteract('tireRemove', vehicle) then return end
    if FD.State.Get(vehicle, 'extrication', 'tire', tireIndex) then
        FD.Notify(label .. ' bereits entfernt.', 'warning') return
    end
    if not FD.HasItem('tirecutters') then FD.Notify(T('no_item'), 'error') return end

    local done = FD.Progress(
        ('Schneide %s ab'):format(label),
        'saw',
        Config.Items.tirecutters.useTime
    )
    if not done then return end

    SetVehicleTyreBurst(vehicle, tireIndex, true, 1000.0)
    SetVehicleWheelHealth(vehicle, tireIndex, 0.0)
    if tireIndex == 2 then SetVehicleTyreBurst(vehicle, 4, true, 1000.0) end
    if tireIndex == 3 then SetVehicleTyreBurst(vehicle, 5, true, 1000.0) end
    FD.State.Set(vehicle, 'extrication', 'tire', tireIndex, true)
    SetCD('tireRemove', vehicle)
    FD.RemoveItem('tirecutters', 1)
    FD.Notify(label .. ' entfernt.', 'success')
end

-- ─────────────────────────────────────────────
--  ox_target – Bone-basierte Options
-- ─────────────────────────────────────────────

local function BuildTargetOptions(vehicle)
    local options = {}
    local dist    = Config.Target.distance

    -- Türen & Motorhaube/Kofferraum – je Bone eine Option
    for bone, doorIndex in pairs(boneToDoorIndex) do
        local label = boneToDoorLabel[bone]
        local capturedBone  = bone
        local capturedIndex = doorIndex
        local capturedLabel = label

        options[#options + 1] = {
            name        = 'fd_door_' .. capturedBone,
            icon        = doorIndex <= 3 and 'fas fa-door-open' or 'fas fa-car',
            label       = capturedLabel .. ' entfernen',
            bones       = { capturedBone },
            distance    = dist,
            onSelect    = function()
                RemoveDoorByIndex(vehicle, capturedIndex, capturedLabel)
            end,
            canInteract = function()
                return FD.HasJob()
                    and not FD.State.Get(vehicle, 'extrication', 'door', capturedIndex)
                    and GetIsDoorValid(vehicle, capturedIndex)
            end,
        }
    end

    -- Reifen – je Wheel-Bone eine Option
    for bone, tireIndex in pairs(boneToTireIndex) do
        local label = boneToTireLabel[bone]
        local capturedBone  = bone
        local capturedIndex = tireIndex
        local capturedLabel = label

        options[#options + 1] = {
            name        = 'fd_tire_' .. capturedBone,
            icon        = 'fas fa-circle-notch',
            label       = capturedLabel .. ' abschneiden',
            bones       = { capturedBone },
            distance    = dist,
            onSelect    = function()
                RemoveTireByIndex(vehicle, capturedIndex, capturedLabel)
            end,
            canInteract = function()
                return FD.HasJob()
                    and not FD.State.Get(vehicle, 'extrication', 'tire', capturedIndex)
                    and tireIndex < GetVehicleNumberOfWheels(vehicle)
            end,
        }
    end

    -- Dach – auf Windschutzscheibe / Dach-Bone
    options[#options + 1] = {
        name        = 'fd_roof_remove',
        icon        = 'fas fa-cut',
        label       = 'Dach aufschneiden',
        bones       = { 'windscreen_f', 'roof_f' },
        distance    = dist,
        onSelect    = function() RemoveRoof(vehicle) end,
        canInteract = function()
            return FD.HasJob()
                and not FD.State.Get(vehicle, 'extrication', 'roof')
        end,
    }

    -- Airbag – auf Lenkrad / Fahrersitz-Bone
    options[#options + 1] = {
        name        = 'fd_airbag',
        icon        = 'fas fa-wind',
        label       = T('airbag_deactivate'),
        bones       = { 'steering_wheel', 'seat_dside_f' },
        distance    = dist,
        onSelect    = function() DeactivateAirbag(vehicle) end,
        canInteract = function()
            return FD.HasJob()
                and not FD.State.Get(vehicle, 'extrication', 'airbag')
        end,
    }

    -- Stabilisieren – auf Chassis / Unterseite
    options[#options + 1] = {
        name        = 'fd_stabilize',
        icon        = 'fas fa-car-crash',
        label       = 'Fahrzeug stabilisieren',
        bones       = { 'chassis', 'chassis_dummy' },
        distance    = dist,
        onSelect    = function() StabilizeVehicle(vehicle) end,
        canInteract = function()
            return FD.HasJob()
                and not FD.State.Get(vehicle, 'extrication', 'stabilized')
        end,
    }

    options[#options + 1] = {
        name        = 'fd_destabilize',
        icon        = 'fas fa-unlock',
        label       = 'Stabilisierung lösen',
        bones       = { 'chassis', 'chassis_dummy' },
        distance    = dist,
        onSelect    = function() DestabilizeVehicle(vehicle) end,
        canInteract = function()
            return FD.HasJob()
                and FD.State.Get(vehicle, 'extrication', 'stabilized') == true
        end,
    }

    return options
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