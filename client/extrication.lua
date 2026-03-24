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
    wheel = {
        type    = 'bool',
        indexed = true,
        count   = 6,
        onApply = function(vehicle, index, value)
            if value then
                BreakOffVehicleWheel(vehicle, index, false, 3.0, true, false)
            end
        end,
    },
    window = {
        type    = 'bool',
        indexed = true,
        count   = 8,
        onApply = function(vehicle, index, value)
            if value then SmashVehicleWindow(vehicle, index) end
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
                SetVehicleEngineHealth(vehicle, 500.0)
            else
                SetVehicleUndriveable(vehicle, false)
                SetVehicleEngineHealth(vehicle, 1000.0)
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
    SetVehicleUndriveable(vehicle, false)
    FD.Debug('extrication', 'Fahrzeug %d komplett zurückgesetzt', vehicle)
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

-- Verbesserte Wreck-Erkennung: Engine Health, Body Health oder umgekippt
local function IsVehicleWrecked(vehicle)
    if GetVehicleEngineHealth(vehicle) < 0.0 then return true end
    if IsVehicleDriveable(vehicle, false) == false then return true end
    if GetVehicleBodyHealth(vehicle) < 500.0 then return true end
    local roll = GetEntityRoll(vehicle)
    if math.abs(roll) > 60.0 then return true end
    return false
end

local function IsVehicleRolled(vehicle)
    return math.abs(GetEntityRoll(vehicle)) > 60.0
end

local function VehicleAccessCheck(vehicle)
    if GetVehiclePedIsIn(PlayerPedId(), false) == vehicle then
        FD.Notify('Du kannst dein eigenes Fahrzeug nicht extrahieren.', 'warning')
        return false
    end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and IsPedAPlayer(ped) and ped ~= PlayerPedId() then
            local isDead          = IsPedDeadOrDying(ped, true)
            local isIncapacitated = IsPedInjured(ped) or IsEntityDead(ped)
            local isFleeing       = IsPedFleeing(ped)
            if not isDead and not isIncapacitated and not isFleeing then
                FD.Notify('Das Fahrzeug ist noch besetzt – Spieler muss raus oder bewusstlos sein.', 'warning')
                return false
            end
        end
    end

    return true
end

local function RequestControl(vehicle)
    if NetworkGetEntityOwner(vehicle) == PlayerId() then return true end
    local ok = lib.requestEntityControl(vehicle, 1000)
    if not ok then FD.Debug('extrication', 'Network Control nicht erhalten für Fahrzeug %d', vehicle) end
    return ok
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
--  Progresslog – TextUI Statusanzeige
-- ─────────────────────────────────────────────

local progresslogActive = false

local function ShowProgressLog(vehicle)
    if progresslogActive then return end
    progresslogActive = true

    CreateThread(function()
        while progresslogActive and DoesEntityExist(vehicle) do
            local pCoords = GetEntityCoords(PlayerPedId())
            local vCoords = GetEntityCoords(vehicle)
            if #(pCoords - vCoords) > Config.Target.distance + 2.0 then
                lib.hideTextUI()
                progresslogActive = false
                return
            end

            -- Status zusammenbauen
            local lines = {}

            -- Türen
            local doorsDone, doorsTotal = 0, 0
            for i = 0, 5 do
                if GetIsDoorValid(vehicle, i) then
                    doorsTotal = doorsTotal + 1
                    if FD.State.Get(vehicle, 'extrication', 'door', i) then
                        doorsDone = doorsDone + 1
                    end
                end
            end
            if doorsTotal > 0 then
                lines[#lines + 1] = ('%s Türen %d/%d'):format(
                    doorsDone == doorsTotal and '✓' or '○', doorsDone, doorsTotal
                )
            end

            -- Reifen & Felgen
            local tiresDone, tiresTotal = 0, GetVehicleNumberOfWheels(vehicle)
            local wheelsDone = 0
            for i = 0, tiresTotal - 1 do
                if FD.State.Get(vehicle, 'extrication', 'tire', i) then tiresDone = tiresDone + 1 end
                if FD.State.Get(vehicle, 'extrication', 'wheel', i) then wheelsDone = wheelsDone + 1 end
            end
            lines[#lines + 1] = ('%s Reifen %d/%d'):format(
                tiresDone == tiresTotal and '✓' or '○', tiresDone, tiresTotal
            )
            if wheelsDone > 0 then
                lines[#lines + 1] = ('%s Felgen %d/%d'):format(
                    wheelsDone == tiresTotal and '✓' or '○', wheelsDone, tiresTotal
                )
            end

            -- Einzelne States
            local function stateIcon(module, key)
                return FD.State.Get(vehicle, module, key) and '✓' or '○'
            end

            lines[#lines + 1] = stateIcon('extrication', 'roof')    .. ' Dach'
            lines[#lines + 1] = stateIcon('extrication', 'battery') .. ' Batterie'
            lines[#lines + 1] = stateIcon('extrication', 'airbag')  .. ' Airbag'
            lines[#lines + 1] = stateIcon('extrication', 'stabilized') .. ' Stabilisiert'

            -- Fahrzeugzustand Warnungen
            if GetVehicleEngineHealth(vehicle) < 200.0 then
                lines[#lines + 1] = '⚠ Kraftstoffaustritt möglich'
            end
            if IsVehicleRolled(vehicle) then
                lines[#lines + 1] = '⚠ Fahrzeug liegt auf der Seite'
            end

            lib.showTextUI(table.concat(lines, '\n'), {
                position = 'right-center',
                icon     = 'fas fa-fire-extinguisher',
                title    = 'Fahrzeugstatus',
            })

            Wait(1000)
        end

        lib.hideTextUI()
        progresslogActive = false
    end)
end

local function HideProgressLog()
    progresslogActive = false
    lib.hideTextUI()
end

-- ─────────────────────────────────────────────
--  Labels
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

local wheelLabels = {
    [0] = 'Felge vorne links',
    [1] = 'Felge vorne rechts',
    [2] = 'Felge hinten links',
    [3] = 'Felge hinten rechts',
    [4] = 'Felge mitte links',
    [5] = 'Felge mitte rechts',
}

local windowLabels = {
    [0] = 'Fenster vorne links',
    [1] = 'Fenster vorne rechts',
    [2] = 'Fenster hinten links',
    [3] = 'Fenster hinten rechts',
    [4] = 'Extra Fenster 1',
    [5] = 'Extra Fenster 2',
    [6] = 'Extra Fenster 3',
    [7] = 'Extra Fenster 4',
}

-- ─────────────────────────────────────────────
--  Extrication Menü
-- ─────────────────────────────────────────────

local function OpenExtricationMenu(vehicle)
    if not VehicleAccessCheck(vehicle) then return end

    FD.Debug('extrication', 'Menü geöffnet – Fahrzeug %d | Engine: %.0f | Body: %.0f | Roll: %.1f',
        vehicle,
        GetVehicleEngineHealth(vehicle),
        GetVehicleBodyHealth(vehicle),
        GetEntityRoll(vehicle)
    )

    -- Fuel Leak Warnung wenn Motor stark beschädigt
    if GetVehicleEngineHealth(vehicle) < 200.0 then
        FD.Notify('⚠ Schwerer Motorschaden – Kraftstoffaustritt möglich! HazMat informieren.', 'warning', 6000)
    end

    -- Umgekipptes Fahrzeug → Hinweis
    if IsVehicleRolled(vehicle) then
        FD.Notify('⚠ Fahrzeug liegt auf der Seite – zuerst stabilisieren!', 'warning', 5000)
    end

    local options = {}

    -- ── Türen ────────────────────────────────
    for i = 0, 5 do
        if GetIsDoorValid(vehicle, i) then
            local doorIdx = i
            local label   = doorLabels[i] or ('Tür %d'):format(i)
            local done    = FD.State.Get(vehicle, 'extrication', 'door', doorIdx) == true

            options[#options + 1] = {
                title       = label .. ' entfernen',
                description = done and '✓ Bereits entfernt' or nil,
                icon        = i <= 3 and 'fas fa-door-open' or 'fas fa-car',
                disabled    = done,
                onSelect    = function()
                    if not CanInteract('doorRemove', vehicle) then return end
                    local item = FD.HasItem('hydraulicspreader') and 'hydraulicspreader'
                              or FD.HasItem('rescuesaw')         and 'rescuesaw'
                              or nil
                    if not item then FD.Notify(T('no_item'), 'error') return end

                    local attachKey = item == 'hydraulicspreader' and 'spreizer' or 'saw'
                    local done2 = FD.PlayAnimWithProp(
                        ('Entferne %s'):format(label),
                        Config.Attachments[attachKey],
                        Config.Items[item].useTime
                    )
                    if not done2 then return end
                    if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

                    SetVehicleDoorBroken(vehicle, doorIdx, true)
                    FD.State.Set(vehicle, 'extrication', 'door', doorIdx, true)
                    SetCD('doorRemove', vehicle)
                    FD.RemoveItem(item, 1)
                    FD.Notify(label .. ' entfernt.', 'success')
                end,
            }
        end
    end

    -- ── Fenster ──────────────────────────────
    for i = 0, 7 do
        if IsVehicleWindowIntact(vehicle, i) then
            local winIdx = i
            local label  = windowLabels[i] or ('Fenster %d'):format(i)
            local done   = FD.State.Get(vehicle, 'extrication', 'window', winIdx) == true

            options[#options + 1] = {
                title       = label .. ' einschlagen',
                description = done and '✓ Bereits eingeschlagen' or nil,
                icon        = 'fas fa-border-none',
                disabled    = done,
                onSelect    = function()
                    if not CanInteract('doorRemove', vehicle) then return end

                    local done2 = FD.Progress(
                        ('Schlage %s ein'):format(label),
                        'spreizer',
                        2000
                    )
                    if not done2 then return end
                    if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

                    SmashVehicleWindow(vehicle, winIdx)
                    FD.State.Set(vehicle, 'extrication', 'window', winIdx, true)
                    SetCD('doorRemove', vehicle)
                    FD.Notify(label .. ' eingeschlagen.', 'success')
                end,
            }
        end
    end

    -- ── Reifen ───────────────────────────────
    for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        local tireIdx = i
        local label   = tireLabels[i] or ('Reifen %d'):format(i)
        local done    = FD.State.Get(vehicle, 'extrication', 'tire', tireIdx) == true

        options[#options + 1] = {
            title       = label .. ' abschneiden',
            description = done and '✓ Bereits entfernt' or nil,
            icon        = 'fas fa-circle-notch',
            disabled    = done,
            onSelect    = function()
                if not CanInteract('tireRemove', vehicle) then return end
                if not FD.HasItem('tirecutters') then FD.Notify(T('no_item'), 'error') return end

                local done2 = FD.PlayAnimWithProp(('Schneide %s ab'):format(label), Config.Attachments.tirecutters, Config.Items.tirecutters.useTime)
                if not done2 then return end
                if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

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

    -- ── Felgen ───────────────────────────────
    for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        local wheelIdx = i
        local label    = wheelLabels[i] or ('Felge %d'):format(i)
        local tireDone  = FD.State.Get(vehicle, 'extrication', 'tire', wheelIdx) == true
        local wheelDone = FD.State.Get(vehicle, 'extrication', 'wheel', wheelIdx) == true

        -- Felge nur anzeigen wenn Reifen bereits entfernt
        if tireDone then
            options[#options + 1] = {
                title       = label .. ' entfernen',
                description = wheelDone and '✓ Bereits entfernt' or 'Reifen wurde bereits abgeschnitten',
                icon        = 'fas fa-circle',
                disabled    = wheelDone,
                onSelect    = function()
                    if not CanInteract('tireRemove', vehicle) then return end

                    local done = FD.PlayAnimWithProp(
                        ('Entferne %s'):format(label),
                        Config.Attachments.spreizer,
                        Config.Items.hydraulicspreader.useTime
                    )
                    if not done then return end
                    if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

                    BreakOffVehicleWheel(vehicle, wheelIdx, false, 3.0, true, false)
                    FD.State.Set(vehicle, 'extrication', 'wheel', wheelIdx, true)
                    SetCD('tireRemove', vehicle)
                    FD.Notify(label .. ' entfernt.', 'success')
                    FD.Debug('extrication', 'Felge %d entfernt – Fahrzeug %d', wheelIdx, vehicle)
                end,
            }
        end
    end

    -- ── Dach ─────────────────────────────────
    local roofDone = FD.State.Get(vehicle, 'extrication', 'roof') == true
    options[#options + 1] = {
        title       = 'Dach aufschneiden',
        description = roofDone and '✓ Bereits aufgeschnitten' or nil,
        icon        = 'fas fa-cut',
        disabled    = roofDone,
        onSelect    = function()
            if not CanInteract('doorRemove', vehicle) then return end
            if not FD.HasItem('rescuesaw') then FD.Notify(T('no_item'), 'error') return end

            local done = FD.PlayAnimWithProp('Dach aufschneiden', Config.Attachments.saw, Config.Items.rescuesaw.useTime + 2000)
            if not done then return end
            if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

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

    -- ── Batterie ─────────────────────────────
    local battDone = FD.State.Get(vehicle, 'extrication', 'battery') == true
    options[#options + 1] = {
        title       = 'Batterie entfernen',
        description = battDone and '✓ Bereits entfernt' or nil,
        icon        = 'fas fa-car-battery',
        disabled    = battDone,
        onSelect    = function()
            if not CanInteract('doorRemove', vehicle) then return end

            local done = FD.PlayAnimWithProp('Batterie entfernen', Config.Attachments.spreizer, 6000)
            if not done then return end
            if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

            SetVehicleEngineOn(vehicle, false, true, true)
            SetVehicleUndriveable(vehicle, true)
            SetVehicleEngineHealth(vehicle, 500.0)
            FD.State.Set(vehicle, 'extrication', 'battery', nil, true)
            SetCD('doorRemove', vehicle)
            FD.Notify('Batterie entfernt – Fahrzeug nicht mehr startbar.', 'success')
            FD.Debug('extrication', 'Batterie entfernt – Fahrzeug %d', vehicle)
        end,
    }

    -- ── Airbag ───────────────────────────────
    local airbagDone = FD.State.Get(vehicle, 'extrication', 'airbag') == true
    options[#options + 1] = {
        title       = T('airbag_deactivate'),
        description = airbagDone and '✓ Bereits deaktiviert' or nil,
        icon        = 'fas fa-wind',
        disabled    = airbagDone,
        onSelect    = function()
            if not CanInteract('airbag', vehicle) then return end

            local done = FD.Progress(T('airbag_deactivate'), 'kneel', Config.Cooldowns.airbag)
            if not done then return end
            if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

            SetVehicleCanBeVisiblyDamaged(vehicle, false)
            FD.State.Set(vehicle, 'extrication', 'airbag', nil, true)
            SetCD('airbag', vehicle)
            FD.Notify(T('airbag_done'), 'success')
        end,
    }

    -- ── Stabilisieren ────────────────────────
    local stabi = FD.State.Get(vehicle, 'extrication', 'stabilized') == true
    if not stabi then
        options[#options + 1] = {
            title       = 'Fahrzeug stabilisieren',
            description = IsVehicleRolled(vehicle) and '⚠ Empfohlen – Fahrzeug liegt auf der Seite' or nil,
            icon        = 'fas fa-car-crash',
            onSelect    = function()
                if not CanInteract('doorRemove', vehicle) then return end

                local done = FD.Progress('Fahrzeug stabilisieren', 'place', 4000)
                if not done then return end
                if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end

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
            title = 'Stabilisierung lösen',
            icon  = 'fas fa-unlock',
            onSelect = function()
                if not RequestControl(vehicle) then FD.Notify('Fahrzeug nicht erreichbar.', 'error') return end
                FreezeEntityPosition(vehicle, false)
                FD.ClearProps('cones')
                FD.State.Set(vehicle, 'extrication', 'stabilized', nil, false)
                stabilizedVehicles[vehicle] = nil
                FD.Notify('Stabilisierung aufgehoben.', 'inform')
            end,
        }
    end

    lib.registerContext({ id = 'fd_extrication_menu', title = 'Fahrzeugbefreiung', options = options })
    lib.showContext('fd_extrication_menu')
end

-- ─────────────────────────────────────────────
--  ox_target
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
--  Admin Befehl: /fdclear
-- ─────────────────────────────────────────────

RegisterCommand('fdclear', function()
    local ped     = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 10.0, 0, 70)
    if not vehicle or vehicle == 0 then FD.Notify('Kein Fahrzeug in der Nähe.', 'error') return end
    local plate = GetVehicleNumberPlateText(vehicle)
    FD.State.Clear(vehicle)
    FD.Notify(('States gelöscht: %s'):format(plate), 'success')
    FD.Debug('extrication', '/fdclear: States gelöscht für %s', plate)
end, false)

-- ─────────────────────────────────────────────
--  Scan Thread
-- ─────────────────────────────────────────────

CreateThread(function()
    Config.Extrication    = Config.Extrication    or { onlyWrecked = false }
    Config.PlayerVehicles = Config.PlayerVehicles or { enabled = true }
    Wait(500)

    while FD.ModuleEnabled('Extrication') do

        if not FD.HasJob() then
            if next(activeTargets) then
                for vehicle in pairs(activeTargets) do
                    if DoesEntityExist(vehicle) then exports.ox_target:removeLocalEntity(vehicle) end
                    activeTargets[vehicle]      = nil
                    stabilizedVehicles[vehicle] = nil
                end
                HideProgressLog()
            end
            Wait(5000)
            goto continue
        end

        do
            local pCoords   = GetEntityCoords(PlayerPedId())
            local closestVeh = nil
            local closestDist = Config.Target.distance + 1.0

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

            -- Progresslog für nächstes Fahrzeug in Reichweite
            for vehicle in pairs(activeTargets) do
                if DoesEntityExist(vehicle) then
                    local dist = #(pCoords - GetEntityCoords(vehicle))
                    if dist < closestDist then
                        closestDist = dist
                        closestVeh  = vehicle
                    end
                end
            end

            if closestVeh then
                ShowProgressLog(closestVeh)
            else
                HideProgressLog()
            end

            -- Cleanup
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
    HideProgressLog()
    for vehicle in pairs(activeTargets) do
        if DoesEntityExist(vehicle) then exports.ox_target:removeLocalEntity(vehicle) end
    end
    for vehicle in pairs(stabilizedVehicles) do
        if DoesEntityExist(vehicle) then FreezeEntityPosition(vehicle, false) end
    end
end)