---------------------------------------------------
--  d4rk_fd_utility – Modul: HazMat
--  Ölsperre / Gefahrgut / Anzug / Deko / Zone
---------------------------------------------------
if not FD.ModuleEnabled('HazMat') then return end

-- ─────────────────────────────────────────────
--  State Schema
-- ─────────────────────────────────────────────

FD.RegisterStateSchema('hazmat', {
    fuel_leak = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            -- Visueller Hinweis: Blip über dem Fahrzeug
            -- wird im Tracking-Thread gehandelt
        end,
    },
    hazmat_zone = {
        type    = 'bool',
        indexed = false,
        onApply = function(vehicle, _, value)
            -- Zone-Tracking läuft separat
        end,
    },
})

-- ─────────────────────────────────────────────
--  Lokaler Status
-- ─────────────────────────────────────────────

local wearingSuit      = false   -- Spieler hat HazMat Anzug an
local contaminated     = false   -- Spieler ist kontaminiert
local activeZones      = {}      -- { { coords, radius, obj } }
local oilProps         = {}      -- { { obj, netId } }
local hazmatBlips      = {}      -- { [vehicle] = blip }
local activeTargets    = {}      -- Fahrzeuge mit HazMat-Target

-- ─────────────────────────────────────────────
--  HazMat Anzug
-- ─────────────────────────────────────────────

local function PutOnSuit()
    if wearingSuit then
        FD.Notify('HazMat Anzug bereits an.', 'warning') return
    end
    if not FD.HasItem('hazmatsuit') then
        FD.Notify('Kein HazMat Anzug im Inventar.', 'error') return
    end

    local done = FD.Progress('HazMat Anzug anziehen', 'place', 5000)
    if not done then return end

    wearingSuit = true

    -- Spieler-Komponente ändern (Schutzanzug-Look)
    -- Outfit wird je nach PED-Modell gesetzt
    local ped = PlayerPedId()
    SetPedComponentVariation(ped, 8, 15, 0, 0)  -- Oberkörper
    SetPedComponentVariation(ped, 11, 55, 0, 0) -- Torso

    -- Anderen Spielern mitteilen
    TriggerServerEvent('d4rk_fd_utility:sv_hazmatSuit', true)

    FD.Notify('HazMat Anzug angezogen – Schutz aktiv.', 'success')
    FD.Debug('hazmat', 'Anzug angezogen')
end

local function TakeOffSuit()
    if not wearingSuit then
        FD.Notify('Du trägst keinen HazMat Anzug.', 'warning') return
    end

    local done = FD.Progress('HazMat Anzug ausziehen', 'place', 3000)
    if not done then return end

    wearingSuit = false

    -- Original-Outfit wiederherstellen
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)

    TriggerServerEvent('d4rk_fd_utility:sv_hazmatSuit', false)
    FD.Notify('HazMat Anzug ausgezogen.', 'inform')
    FD.Debug('hazmat', 'Anzug ausgezogen')
end

-- ─────────────────────────────────────────────
--  Kontamination
-- ─────────────────────────────────────────────

local function SetContaminated(state)
    if contaminated == state then return end
    contaminated = state

    if state then
        FD.Notify('⚠ Kontaminiert! Sofort dekontaminieren!', 'error', 8000)
        -- Visueller Effekt: leichte rote Tönung
        SetTimecycleModifier('damage')
        SetTimecycleModifierStrength(0.3)
        FD.Debug('hazmat', 'Spieler kontaminiert')
    else
        ClearTimecycleModifier()
        FD.Debug('hazmat', 'Kontamination aufgehoben')
    end

    TriggerServerEvent('d4rk_fd_utility:sv_hazmatContaminated', state)
end

local function Decontaminate(target)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('deconkit') then
        FD.Notify('Kein Dekontaminationskit vorhanden.', 'error') return
    end

    local label = target and 'Spieler dekontaminieren' or 'Selbst dekontaminieren'
    local done  = FD.Progress(label, 'kneel', Config.HazMat.deconTime)
    if not done then return end

    if target then
        -- Anderen Spieler dekontaminieren
        TriggerServerEvent('d4rk_fd_utility:sv_decontaminate', GetPlayerServerId(target))
    else
        SetContaminated(false)
    end

    FD.RemoveItem('deconkit', 1)
    FD.Notify('Dekontamination abgeschlossen.', 'success')
end

-- ─────────────────────────────────────────────
--  Ölsperre platzieren
-- ─────────────────────────────────────────────

local function PlaceOilBarrier()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        FD.Notify('Nicht im Fahrzeug möglich.', 'error') return
    end
    if not FD.HasItem('oilbarrier') then
        FD.Notify('Keine Ölsperre im Inventar.', 'error') return
    end
    if not FD.CheckCooldown('hazmat_oil') then
        FD.Notify(T('cooldown'), 'warning') return
    end

    local done = FD.Progress(T('oil_place'), 'place', Config.Items.oilbarrier.useTime)
    if not done then return end

    local ped     = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local coords  = GetEntityCoords(ped)
    local dist    = 1.5

    local x = coords.x + dist * math.sin(-math.rad(heading))
    local y = coords.y + dist * math.cos(-math.rad(heading))
    local _, z = GetGroundZFor_3dCoord(x, y, coords.z + 1.0, false)
    if not z then z = coords.z end

    local hash = GetHashKey(Config.Props.oilBarrier)  -- Sandsack als physische Sperre
    lib.requestModel(hash)
    local obj = CreateObjectNoOffset(hash, x, y, z, true, true, true)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    local netId = ObjToNet(obj)
    SetNetworkIdExistsOnAllMachines(netId, true)

    oilProps[#oilProps + 1] = { obj = obj, netId = netId }

    -- Target zum Entfernen
    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'fd_oil_remove_' .. tostring(obj),
            icon     = 'fas fa-times',
            label    = 'Ölsperre entfernen',
            distance = 2.0,
            onSelect = function()
                for i, entry in ipairs(oilProps) do
                    if entry.obj == obj then
                        exports.ox_target:removeLocalEntity(obj)
                        if DoesEntityExist(obj) then DeleteObject(obj) end
                        table.remove(oilProps, i)
                        break
                    end
                end
                FD.Notify('Ölsperre entfernt.', 'inform')
            end,
            canInteract = function() return FD.HasJob() end,
        }
    })

    FD.RemoveItem('oilbarrier', 1)
    FD.SetCooldown('hazmat_oil', 'oilPlace')
    FD.Notify(T('oil_placed'), 'success')
    FD.Debug('hazmat', 'Ölsperre platziert bei (%.1f, %.1f)', x, y)
end

-- ─────────────────────────────────────────────
--  Gefahrenzone markieren
-- ─────────────────────────────────────────────

local function PlaceHazmatZone()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        FD.Notify('Nicht im Fahrzeug möglich.', 'error') return
    end

    local coords = GetEntityCoords(PlayerPedId())

    -- Radius per Input wählen
    local input = lib.inputDialog('Gefahrenzone', {
        { type = 'number', label = 'Radius (Meter)', default = 20, min = 5, max = 100 }
    })
    if not input or not input[1] then return end

    local radius = tonumber(input[1]) or 20

    local done = FD.Progress('Gefahrenzone markieren', 'place', 3000)
    if not done then return end

    -- Zone lokal speichern
    local zone = { coords = coords, radius = radius }
    activeZones[#activeZones + 1] = zone

    -- Server informieren für andere Spieler
    TriggerServerEvent('d4rk_fd_utility:sv_hazmatZone', coords.x, coords.y, coords.z, radius, true)

    FD.Notify(('Gefahrenzone gesetzt – Radius: %dm'):format(radius), 'success')
    FD.Debug('hazmat', 'Zone platziert bei (%.1f, %.1f) Radius: %d', coords.x, coords.y, radius)
end

local function ClearHazmatZones()
    activeZones = {}
    TriggerServerEvent('d4rk_fd_utility:sv_hazmatZone', 0, 0, 0, 0, false)
    FD.Notify('Gefahrenzonen gelöscht.', 'inform')
end

-- ─────────────────────────────────────────────
--  Gefahrgut-Kennzeichnung auf Fahrzeug
-- ─────────────────────────────────────────────

local function MarkVehicleHazmat(vehicle)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

    local isMarked = FD.State.Get(vehicle, 'hazmat', 'hazmat_zone') == true

    if isMarked then
        -- Markierung entfernen
        FD.State.Set(vehicle, 'hazmat', 'hazmat_zone', nil, false)
        FD.State.Set(vehicle, 'hazmat', 'fuel_leak', nil, false)
        if hazmatBlips[vehicle] then
            RemoveBlip(hazmatBlips[vehicle])
            hazmatBlips[vehicle] = nil
        end
        -- Öl-Pfütze unter dem Fahrzeug entfernen
        for i = #oilProps, 1, -1 do
            local entry = oilProps[i]
            if entry.isLeak and entry.vehicle == vehicle then
                if entry.obj and DoesEntityExist(entry.obj) then
                    DeleteObject(entry.obj)
                end
                table.remove(oilProps, i)
            end
        end
        FD.ClearVehicleOptions(vehicle, 'hazmat')
        FD.Notify('Gefahrgut-Kennzeichnung entfernt.', 'inform')
    else
        -- Markierung setzen
        FD.State.Set(vehicle, 'hazmat', 'hazmat_zone', nil, true)

        -- Blip über dem Fahrzeug
        local blip = AddBlipForEntity(vehicle)
        SetBlipSprite(blip, 436)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 1.2)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Gefahrgut')
        EndTextCommandSetBlipName(blip)
        hazmatBlips[vehicle] = blip

        -- Öl-Pfütze automatisch unter dem Fahrzeug spawnen
        local vCoords = GetEntityCoords(vehicle)
        local _, gz = GetGroundZFor_3dCoord(vCoords.x, vCoords.y, vCoords.z, false)
        local groundZ = gz or vCoords.z

        local oilHash = GetHashKey(Config.Props.oilPatch)
        lib.requestModel(oilHash)

        local oilObj = nil
        if IsModelValid(oilHash) then
            oilObj = CreateObjectNoOffset(oilHash, vCoords.x, vCoords.y, groundZ, true, true, false)
            SetEntityHeading(oilObj, GetEntityHeading(vehicle))
            FreezeEntityPosition(oilObj, true)
            SetModelAsNoLongerNeeded(oilHash)
            FD.Debug('hazmat', 'Öl-Pfütze gespawnt: obj=%d', oilObj)
        else
            FD.Debug('hazmat', 'Warnung: p_oil_slick_01 ungültig – kein visuelles Prop')
        end

        local oilEntry = { obj = oilObj, isLeak = true, absorbed = false, vehicle = vehicle }
        oilProps[#oilProps + 1] = oilEntry

        -- Target auf das Fahrzeug – alle Öl-Optionen auf einmal registrieren
        -- disabled wird dynamisch per canInteract gesteuert (kein Re-Register nötig)
        local oilTargetOptions = {
            {
                name        = 'fd_hazmat_mark',
                icon        = 'fas fa-biohazard',
                label       = 'Gefahrgut-Kennzeichnung entfernen',
                distance    = 4.0,
                onSelect    = function() MarkVehicleHazmat(vehicle) end,
                canInteract = function() return FD.HasJob() end,
            },
            {
                name        = 'fd_oil_absorb',
                icon        = 'fas fa-fill-drip',
                label       = 'Ölbindemittel auftragen',
                distance    = 4.0,
                onSelect    = function()
                    if oilEntry.absorbed then
                        FD.Notify('Ölbindemittel bereits aufgetragen – jetzt kehren!', 'warning') return
                    end
                    if not FD.HasItem('oilabsorbent') then
                        FD.Notify('Kein Ölbindemittel im Inventar.', 'error') return
                    end
                    local done = FD.PlayAnimWithProp(
                        'Ölbindemittel auftragen',
                        Config.Attachments.pour,
                        Config.Items.oilabsorbent.useTime
                    )
                    if not done then return end

                    if oilObj and DoesEntityExist(oilObj) then
                        SetEntityAlpha(oilObj, 100, false)
                    end
                    oilEntry.absorbed = true
                    FD.RemoveItem('oilabsorbent', 1)
                    FD.Notify('Ölbindemittel aufgetragen – jetzt kehren!', 'inform')
                end,
                canInteract = function()
                    return FD.HasJob() and not oilEntry.absorbed
                end,
            },
            {
                name        = 'fd_oil_sweep',
                icon        = 'fas fa-broom',
                label       = 'Ölbindemittel zusammenkehren',
                distance    = 4.0,
                onSelect    = function()
                    if not oilEntry.absorbed then
                        FD.Notify('Zuerst Ölbindemittel auftragen!', 'warning') return
                    end
                    if not FD.HasItem('broom') then
                        FD.Notify('Kein Besen im Inventar.', 'error') return
                    end
                    local done = FD.PlayAnimWithProp('Ölbindemittel zusammenkehren', Config.Attachments.sweep, 8000)
                    if not done then return end

                    if oilObj and DoesEntityExist(oilObj) then DeleteObject(oilObj) end

                    for i = #oilProps, 1, -1 do
                        if oilProps[i] == oilEntry then
                            table.remove(oilProps, i) break
                        end
                    end

                    FD.Notify('Ölpfütze beseitigt – Bereich gesichert.', 'success')
                    FD.Debug('hazmat', 'Ölpfütze unter Fahrzeug %d beseitigt', vehicle)
                end,
                canInteract = function()
                    return FD.HasJob() and oilEntry.absorbed
                end,
            },
        }

        -- Hazmat-Optionen über Target Manager setzen (überschreibt nicht Extrication)
        FD.SetVehicleOptions(vehicle, 'hazmat', oilTargetOptions)
        activeTargets[vehicle] = true

        FD.Debug('hazmat', 'Öl-Pfütze gespawnt unter Fahrzeug %d', vehicle)

        -- Kraftstoffaustritt markieren
        FD.State.Set(vehicle, 'hazmat', 'fuel_leak', nil, true)
        FD.Notify('⚠ Fahrzeug als Gefahrgut markiert – Ölaustritt gesichert.', 'warning', 6000)
    end
end

-- ─────────────────────────────────────────────
--  Gefahrenzone – Draw Thread
-- ─────────────────────────────────────────────

CreateThread(function()
    while not (Config.HazMat and Config.HazMat.zoneColor) do Wait(100) end

    -- Farben einmal cachen – kein Table-Lookup jeden Frame
    local c  = Config.HazMat.zoneColor
    local cb = Config.HazMat.zoneColorBorder

    while FD.ModuleEnabled('HazMat') do
        for _, zone in ipairs(activeZones) do

            -- Boden-Kreis (gefüllt)
            DrawMarker(
                1,                                      -- Typ: Zylinder
                zone.coords.x, zone.coords.y, zone.coords.z - 0.5,
                0.0, 0.0, 0.0,                          -- Rotation
                0.0, 0.0, 0.0,                          -- Ausrichtung
                zone.radius * 2, zone.radius * 2, 1.0, -- Größe
                c.r, c.g, c.b, c.a,                    -- Farbe
                false, false, 2, false, nil, nil, false
            )
            -- Rand (undurchsichtig)
            DrawMarker(
                25,                                     -- Typ: Kreislinie
                zone.coords.x, zone.coords.y, zone.coords.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                zone.radius * 2, zone.radius * 2, 1.5,
                cb.r, cb.g, cb.b, cb.a,
                false, false, 2, false, nil, nil, false
            )
        end
        Wait(0)
    end
end)

-- ─────────────────────────────────────────────
--  Auto-Kontamination in Gefahrenzonen
-- ─────────────────────────────────────────────

CreateThread(function()
    while not (Config.HazMat and Config.HazMat.contaminateCheckInterval) do Wait(100) end

    local autoContaminate    = Config.HazMat.autoContaminate
    local checkInterval      = Config.HazMat.contaminateCheckInterval

    while FD.ModuleEnabled('HazMat') do
        if autoContaminate and #activeZones > 0 then
            local pCoords = GetEntityCoords(PlayerPedId())

            local inZone = false
            for _, zone in ipairs(activeZones) do
                local dist = #(vector2(pCoords.x, pCoords.y) - vector2(zone.coords.x, zone.coords.y))
                if dist <= zone.radius then
                    inZone = true
                    break
                end
            end

            if inZone and not wearingSuit and not contaminated then
                SetContaminated(true)
            elseif not inZone and contaminated then
                -- Automatisch nur zurücksetzen wenn man die Zone verlässt UND Anzug trägt
                if wearingSuit then SetContaminated(false) end
            end
        end
        Wait(checkInterval)
    end
end)

-- ─────────────────────────────────────────────
--  Scan Thread – HazMat Target auf Fahrzeuge
-- ─────────────────────────────────────────────

CreateThread(function()
    Wait(500)
    while FD.ModuleEnabled('HazMat') do
        if not FD.HasJob() then
            -- Alle Targets räumen
            for vehicle in pairs(activeTargets) do
                FD.ClearVehicleOptions(vehicle, 'hazmat')
                activeTargets[vehicle] = nil
            end
            Wait(5000)
        else
            local pCoords = GetEntityCoords(PlayerPedId())
            local closest = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 10.0, 0, 70)

            if closest and closest ~= 0 and not activeTargets[closest] then
                local isMarked = FD.State.Get(closest, 'hazmat', 'hazmat_zone') == true

                FD.SetVehicleOptions(closest, 'hazmat', {
                    {
                        name     = 'fd_hazmat_mark',
                        icon     = 'fas fa-biohazard',
                        label    = isMarked and 'Gefahrgut-Kennzeichnung entfernen' or 'Als Gefahrgut markieren',
                        distance = 4.0,
                        onSelect = function() MarkVehicleHazmat(closest) end,
                        canInteract = function() return FD.HasJob() end,
                    }
                })
                activeTargets[closest] = true
            end

            -- Cleanup entfernte Fahrzeuge
            for vehicle in pairs(activeTargets) do
                if not DoesEntityExist(vehicle) or
                   #(pCoords - GetEntityCoords(vehicle)) > 15.0 then
                    FD.ClearVehicleOptions(vehicle, 'hazmat')
                    activeTargets[vehicle] = nil
                end
            end

            Wait(3000)
        end
    end
end)

-- ─────────────────────────────────────────────
--  Netzwerk Events
-- ─────────────────────────────────────────────

-- Zone von anderen Spielern empfangen
RegisterNetEvent('d4rk_fd_utility:cl_hazmatZone', function(x, y, z, radius, active)
    if active then
        activeZones[#activeZones + 1] = {
            coords = vector3(x, y, z),
            radius = radius
        }
        FD.Notify(('⚠ Gefahrenzone gesetzt – %dm Radius'):format(radius), 'warning', 6000)
    else
        -- Alle fremden Zonen löschen (vereinfacht)
        local own = {}
        for _, zone in ipairs(activeZones) do
            if zone.isOwn then own[#own + 1] = zone end
        end
        activeZones = own
    end
end)

-- Kontamination von Server empfangen
RegisterNetEvent('d4rk_fd_utility:cl_contaminated', function(state)
    SetContaminated(state)
end)

-- ─────────────────────────────────────────────
--  Radial Menü
-- ─────────────────────────────────────────────

lib.addRadialItem({
    id       = 'fd_hazmat_radial',
    label    = 'HazMat',
    icon     = 'fas fa-biohazard',
    onSelect = function()
        if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

        local options = {
            {
                title       = wearingSuit and 'Anzug ausziehen' or 'HazMat Anzug anziehen',
                icon        = 'fas fa-shield-halved',
                description = wearingSuit and 'Schutz: Aktiv' or 'Schutz: Inaktiv',
                onSelect    = function()
                    if wearingSuit then TakeOffSuit() else PutOnSuit() end
                end,
            },
            {
                title       = T('oil_place'),
                icon        = 'fas fa-oil-can',
                description = ('Im Inventar: %d'):format(FD.CountItem('oilbarrier')),
                disabled    = FD.CountItem('oilbarrier') == 0,
                onSelect    = PlaceOilBarrier,
            },
            {
                title       = 'Gefahrenzone markieren',
                icon        = 'fas fa-biohazard',
                onSelect    = PlaceHazmatZone,
            },
            {
                title       = 'Gefahrenzonen löschen',
                icon        = 'fas fa-trash',
                disabled    = #activeZones == 0,
                onSelect    = ClearHazmatZones,
            },
            {
                title       = contaminated and 'Selbst dekontaminieren' or 'Dekontaminieren',
                icon        = 'fas fa-shower',
                description = contaminated and '⚠ Kontaminiert!' or 'Spieler reinigen',
                disabled    = FD.CountItem('deconkit') == 0,
                onSelect    = function() Decontaminate(nil) end,
            },
        }

        lib.registerContext({ id = 'fd_hazmat_menu', title = 'HazMat', options = options })
        lib.showContext('fd_hazmat_menu')
    end,
})

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Anzug ausziehen
    if wearingSuit then
        SetPedDefaultComponentVariation(PlayerPedId())
    end
    -- Kontamination zurücksetzen
    if contaminated then
        ClearTimecycleModifier()
    end
    -- Blips entfernen
    for _, blip in pairs(hazmatBlips) do
        RemoveBlip(blip)
    end
    -- Öl-Props entfernen
    for _, entry in ipairs(oilProps) do
        if DoesEntityExist(entry.obj) then DeleteObject(entry.obj) end
    end
    -- Targets räumen
    for vehicle in pairs(activeTargets) do
        FD.ClearVehicleOptions(vehicle, 'hazmat')
    end
end)

FD.Debug('hazmat', 'HazMat Modul geladen')