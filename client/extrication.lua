---------------------------------------------------
--  d4rk_fd_utility - Modul: Extrication
--  Turen / Reifen / Dach / Airbag / Stabilisierung
---------------------------------------------------
if not FD.ModuleEnabled('Extrication') then return end

-- ─────────────────────────────────────────────
--  Schema
-- ─────────────────────────────────────────────

FD.RegisterStateSchema('extrication', {
    door = {
        type    = 'bool',
        indexed = true,
        count   = 6,
        onApply = function(vehicle, index, value)
            if value then SetVehicleDoorBroken(vehicle, index, true) end
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
    battery = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            if value then
                SetVehicleEngineOn(vehicle, false, true, true)
                SetVehicleUndriveable(vehicle, true)
                SetVehicleEngineHealth(vehicle, 0.0)
            else
                SetVehicleUndriveable(vehicle, false)
            end
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

AddStateBagChangeHandler('fd_cleared', nil, function(bagName, _, value)
    if not value then return end
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    FreezeEntityPosition(vehicle, false)
end)

AddStateBagChangeHandler('fd_module_cleared', nil, function(bagName, _, value)
    if value ~= 'extrication' then return end
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    FreezeEntityPosition(vehicle, false)
end)

-- ─────────────────────────────────────────────
--  Lokaler Status
-- ─────────────────────────────────────────────

local activeTargets      = {}
local stabilizedVehicles = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function IsVehicleWrecked(vehicle)
    return GetVehicleEngineHealth(vehicle) < 0.0
        or IsVehicleDriveable(vehicle, false) == false
end

local function CanInteract(action, vehicle)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return false end
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
--  Extrication Menü
-- ─────────────────────────────────────────────

local doorLabels = {
    [0] = 'Links Vorne (Fahrer)',
    [1] = 'Rechts Vorne (Beifahrer)',
    [2] = 'Links Hinten',
    [3] = 'Rechts Hinten',
    [4] = 'Motorhaube',
    [5] = 'Kofferraum',
}

local tireLabels = {
    [0] = 'Reifen vorne links',
    [1] = 'Reifen vorne rechts',
    [2] = 'Reifen hinten links',
    [3] = 'Reifen hinten rechts',
    [4] = 'Reifen mitte links',
    [5] = 'Reifen mitte rechts',
}

local function OpenExtricationMenu(vehicle)
    FD.Debug('extrication', 'Menü geöffnet – Fahrzeug %d | Türen: %s | Reifen: %s | Dach: %s | Airbag: %s | Stabi: %s',
        vehicle,
        tostring(FD.State.Get(vehicle, 'extrication', 'door', 0)),
        tostring(FD.State.Get(vehicle, 'extrication', 'tire', 0)),
        tostring(FD.State.Get(vehicle, 'extrication', 'roof')),
        tostring(FD.State.Get(vehicle, 'extrication', 'airbag')),
        tostring(FD.State.Get(vehicle, 'extrication', 'stabilized'))
    )
    local options = {}

    -- Türen
    for i = 0, 5 do
        if GetIsDoorValid(vehicle, i)
        and not FD.State.Get(vehicle, 'extrication', 'door', i) then
            local doorIdx = i
            local label   = doorLabels[i] or ('Tür %d'):format(i)
            options[#options + 1] = {
                title    = label .. ' entfernen',
                icon     = i <= 3 and 'fas fa-door-open' or 'fas fa-car',
                onSelect = function()
                    if not CanInteract('doorRemove', vehicle) then return end
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

                    SetVehicleDoorBroken(vehicle, doorIdx, true)
                    FD.State.Set(vehicle, 'extrication', 'door', doorIdx, true)
                    SetCD('doorRemove', vehicle)
                    FD.RemoveItem(item, 1)
                    FD.Notify(label .. ' entfernt.', 'success')
                end,
            }
        end
    end

    -- Reifen
    for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        if not FD.State.Get(vehicle, 'extrication', 'tire', i) then
            local tireIdx = i
            local label   = tireLabels[i] or ('Reifen %d'):format(i)
            options[#options + 1] = {
                title    = label .. ' abschneiden',
                icon     = 'fas fa-circle-notch',
                onSelect = function()
                    if not CanInteract('tireRemove', vehicle) then return end
                    if not FD.HasItem('tirecutters') then FD.Notify(T('no_item'), 'error') return end

                    local done = FD.Progress(
                        ('Schneide %s ab'):format(label),
                        'saw',
                        Config.Items.tirecutters.useTime
                    )
                    if not done then return end

                    SetVehicleTyreBurst(vehicle, tireIdx, true, 1000.0)
                    SetVehicleWheelHealth(vehicle, tireIdx, 0.0)
                    if tireIdx == 2 then SetVehicleTyreBurst(vehicle, 4, true, 1000.0) end
                    if tireIdx == 3 then SetVehicleTyreBurst(vehicle, 5, true, 1000.0) end
                    FD.State.Set(vehicle, 'extrication', 'tire', tireIdx, true)
                    SetCD('tireRemove', vehicle)
                    FD.RemoveItem('tirecutters', 1)
                    FD.Notify(label .. ' entfernt.', 'success')
                end,
            }
        end
    end

    -- Dach
    if not FD.State.Get(vehicle, 'extrication', 'roof') then
        options[#options + 1] = {
            title    = 'Dach aufschneiden',
            icon     = 'fas fa-cut',
            onSelect = function()
                if not CanInteract('doorRemove', vehicle) then return end
                if not FD.HasItem('rescuesaw') then FD.Notify(T('no_item'), 'error') return end

                local done = FD.Progress('Dach aufschneiden', 'saw', Config.Items.rescuesaw.useTime + 2000)
                if not done then return end

                SetVehicleBodyHealth(vehicle, 200.0)
                SetVehicleRoofLivery(vehicle, -1)
                for i = 0, 12 do
                    if HasVehicleExtra(vehicle, i) then SetVehicleExtra(vehicle, i, true) end
                end
                FD.State.Set(vehicle, 'extrication', 'roof', nil, true)
                SetCD('doorRemove', vehicle)
                FD.RemoveItem('rescuesaw', 1)
                FD.Notify('Dach aufgeschnitten.', 'success')
            end,
        }
    end

    -- Batterie
    if not FD.State.Get(vehicle, 'extrication', 'battery') then
        options[#options + 1] = {
            title    = 'Batterie entfernen',
            icon     = 'fas fa-car-battery',
            onSelect = function()
                if not CanInteract('doorRemove', vehicle) then return end

                local done = FD.Progress('Batterie entfernen', 'spreizer', 6000)
                if not done then return end

                SetVehicleEngineOn(vehicle, false, true, true)
                SetVehicleUndriveable(vehicle, true)
                SetVehicleEngineHealth(vehicle, 0.0)
                FD.State.Set(vehicle, 'extrication', 'battery', nil, true)
                SetCD('doorRemove', vehicle)
                FD.Notify('Batterie entfernt – Fahrzeug nicht mehr startbar.', 'success')
                FD.Debug('extrication', 'Batterie entfernt – Fahrzeug %d', vehicle)
            end,
        }
    end

    -- Airbag
    if not FD.State.Get(vehicle, 'extrication', 'airbag') then
        options[#options + 1] = {
            title    = T('airbag_deactivate'),
            icon     = 'fas fa-wind',
            onSelect = function()
                if not CanInteract('airbag', vehicle) then return end

                local done = FD.Progress(T('airbag_deactivate'), 'kneel', Config.Cooldowns.airbag)
                if not done then return end

                SetVehicleCanBeVisiblyDamaged(vehicle, false)
                FD.State.Set(vehicle, 'extrication', 'airbag', nil, true)
                SetCD('airbag', vehicle)
                FD.Notify(T('airbag_done'), 'success')
            end,
        }
    end

    -- Stabilisieren / Lösen
    if not FD.State.Get(vehicle, 'extrication', 'stabilized') then
        options[#options + 1] = {
            title    = 'Fahrzeug stabilisieren',
            icon     = 'fas fa-car-crash',
            onSelect = function()
                if not CanInteract('doorRemove', vehicle) then return end

                local done = FD.Progress('Fahrzeug stabilisieren', 'place', 4000)
                if not done then return end

                local heading = GetEntityHeading(vehicle)
                for _, offset in ipairs({{-1.2,1.5},{1.2,1.5},{-1.2,-1.5},{1.2,-1.5}}) do
                    local wx, wy, wz = table.unpack(GetOffsetFromEntityInWorldCoords(vehicle, offset[1], offset[2], -0.3))
                    FD.SpawnProp(Config.Props.wheel, vector3(wx, wy, wz), heading, 'cones')
                end

                FreezeEntityPosition(vehicle, true)
                FD.State.Set(vehicle, 'extrication', 'stabilized', nil, true)
                stabilizedVehicles[vehicle] = true
                FD.Debug('extrication', 'Fahrzeug %d stabilisiert', vehicle)
                FD.Notify('Fahrzeug stabilisiert.', 'success')
            end,
        }
    else
        options[#options + 1] = {
            title    = 'Stabilisierung lösen',
            icon     = 'fas fa-unlock',
            onSelect = function()
                FreezeEntityPosition(vehicle, false)
                FD.ClearProps('cones')
                FD.State.Set(vehicle, 'extrication', 'stabilized', nil, false)
                stabilizedVehicles[vehicle] = nil
                FD.Notify('Stabilisierung aufgehoben.', 'inform')
            end,
        }
    end

    if #options == 0 then
        FD.Notify('Keine Aktionen verfügbar.', 'warning')
        return
    end

    lib.registerContext({ id = 'fd_extrication_menu', title = 'Fahrzeugbefreiung', options = options })
    lib.showContext('fd_extrication_menu')
end

-- ─────────────────────────────────────────────
--  ox_target – ein einziger Target pro Fahrzeug
-- ─────────────────────────────────────────────

local function BuildTargetOptions(vehicle)
    return {
        {
            name        = 'fd_extrication',
            icon        = Config.Target.icon,
            label       = 'Fahrzeugbefreiung',
            distance    = Config.Target.distance,
            onSelect    = function() OpenExtricationMenu(vehicle) end,
            canInteract = function() return FD.HasJob() end,
        },
    }
end

-- ─────────────────────────────────────────────
--  Reparatur-Erkennung
--  Wenn Engine Health auf 1000 springt → States löschen
-- ─────────────────────────────────────────────

CreateThread(function()
    local trackedHealth = {}   -- { [vehicle] = lastEngineHealth }

    while FD.ModuleEnabled('Extrication') do
        for vehicle in pairs(activeTargets) do
            if DoesEntityExist(vehicle) then
                local health = GetVehicleEngineHealth(vehicle)
                local last   = trackedHealth[vehicle]

                -- Von beschädigt auf voll repariert
                if last and last < 950.0 and health >= 999.0 then
                    FD.Debug('extrication', 'Fahrzeug %d repariert → States löschen', vehicle)
                    -- Undriveable zurücksetzen bevor States gelöscht werden
                    SetVehicleUndriveable(vehicle, false)
                    FD.State.Clear(vehicle)
                    FD.Notify('Fahrzeugzustand zurückgesetzt.', 'inform')
                end

                trackedHealth[vehicle] = health
            else
                trackedHealth[vehicle] = nil
            end
        end
        Wait(2000)
    end
end)

-- ─────────────────────────────────────────────
--  Admin Befehl: /fdclear
--  Löscht States des nächsten Fahrzeugs
-- ─────────────────────────────────────────────

RegisterCommand('fdclear', function()
    local ped     = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 10.0, 0, 70)

    if not vehicle or vehicle == 0 then
        FD.Notify('Kein Fahrzeug in der Nähe.', 'error')
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    FD.State.Clear(vehicle)
    FD.Notify(('States gelöscht: %s'):format(plate), 'success')
    FD.Debug('extrication', '/fdclear: States gelöscht für %s', plate)
end, false)

CreateThread(function()
    Config.Extrication    = Config.Extrication    or { onlyWrecked = false }
    Config.PlayerVehicles = Config.PlayerVehicles or { enabled = true }
    Wait(500)

    while FD.ModuleEnabled('Extrication') do

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

            local function TryRegisterVehicle(vehicle)
                if activeTargets[vehicle] then return end
                if not DoesEntityExist(vehicle) then return end
                if #(GetEntityCoords(vehicle) - pCoords) > 30.0 then return end
                if Config.Extrication.onlyWrecked and not IsVehicleWrecked(vehicle) then return end

                if Config.PlayerVehicles.enabled then
                    local known = FD.IsPlayerVehicle(vehicle)
                    if known == false then return end
                    if known == nil then
                        FD.PrefetchVehicle(vehicle, function(isPlayer)
                            if isPlayer and not activeTargets[vehicle] and DoesEntityExist(vehicle) then
                                exports.ox_target:addLocalEntity(vehicle, BuildTargetOptions(vehicle))
                                activeTargets[vehicle] = true
                                FD.Debug('target', 'Target nachregistriert (async): Fahrzeug %d', vehicle)
                            end
                        end)
                        return
                    end
                end

                exports.ox_target:addLocalEntity(vehicle, BuildTargetOptions(vehicle))
                activeTargets[vehicle] = true
                FD.Debug('target', 'Target gesetzt: Fahrzeug %d', vehicle)
            end

            local closest = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 30.0, 0, 70)
            if closest and closest ~= 0 then TryRegisterVehicle(closest) end

            if next(activeTargets) then
                local pool = GetGamePool('CVehicle')
                for i, vehicle in ipairs(pool) do
                    TryRegisterVehicle(vehicle)
                    if i % 10 == 0 then Wait(0) end
                end
            end

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