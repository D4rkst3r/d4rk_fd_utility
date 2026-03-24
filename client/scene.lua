---------------------------------------------------
--  d4rk_fd_utility – Modul: Scene Management
--  Kegel / Absperrband / Lichtmast / Warnzeichen
---------------------------------------------------
if not FD.ModuleEnabled('Scene') then return end

-- ─────────────────────────────────────────────
--  Lokaler Status
-- ─────────────────────────────────────────────

-- { category = { { obj, netId } } }
local sceneProps = {
    cones       = {},
    barriers    = {},
    lightstands = {},
    flares      = {},
}

-- Lichtmast-Threads aktiv halten
local lightActive = {}   -- { [obj] = true }

-- ─────────────────────────────────────────────
--  Cooldown-Key Mapping (Kategorie → Config.Cooldowns Key)
-- ─────────────────────────────────────────────

local categoryProgressTime = {
    cones       = 1500,
    barriers    = 2000,
    lightstands = 4000,
    flares      = 1000,
}

-- ─────────────────────────────────────────────
--  Preview Placement System
--  Raycast-basiert mit Ghost-Prop, Rotation via Q/E
--  Bestätigen: E | Abbrechen: X oder ESC
-- ─────────────────────────────────────────────

local PLACE_CONFIRM = 38   -- E
local PLACE_CANCEL  = 47   -- X
local PLACE_ROT_L   = 44   -- Q
local PLACE_ROT_R   = 45   -- R

local function GetRaycastCoords()
    local camCoords = GetGameplayCamCoord()
    local camRot    = GetGameplayCamRot(2)
    local camFwd    = vector3(
        -math.sin(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
         math.cos(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
         math.sin(math.rad(camRot.x))
    )
    local dest  = camCoords + camFwd * (Config.Scene.raycastDistance or 15.0)
    local ray   = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 1 | 16, PlayerPedId(), 0)
    local _, hit, coords, _, _ = GetShapeTestResult(ray)
    if hit == 1 then return coords end
    -- Fallback: Boden unter Kamera-Ziel
    local found, z = GetGroundZFor_3dCoord(dest.x, dest.y, dest.z, false)
    return vector3(dest.x, dest.y, found and z or dest.z)
end

-- Gibt { coords, heading } zurück oder nil wenn abgebrochen
local function RunPlacementPreview(model)
    local hash = GetHashKey(model)
    lib.requestModel(hash)

    -- Warten bis das Kontextmenü komplett geschlossen ist
    Wait(200)

    -- Ghost-Prop spawnen (nicht networked, nur lokal)
    local ghost = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetModelAsNoLongerNeeded(hash)

    local heading   = GetEntityHeading(PlayerPedId())
    local result    = nil
    local lastCoords = vector3(0, 0, 0)

    -- TextUI einmal setzen, nicht jeden Frame
    lib.showTextUI('[E] Platzieren  [Q/R] Rotieren  [X] Abbrechen', {
        position = 'bottom-center',
        icon     = 'fas fa-arrows-up-down-left-right',
    })

    while not result do
        local coords = GetRaycastCoords()

        SetEntityCoords(ghost, coords.x, coords.y, coords.z, false, false, false, false)
        SetEntityHeading(ghost, heading)

        -- PlaceObjectOnGroundProperly nur wenn Coords sich geändert haben
        local moved = #(coords - lastCoords) > 0.1
        if moved then
            PlaceObjectOnGroundProperly(ghost)
            lastCoords = coords
        end

        if IsControlJustPressed(0, PLACE_ROT_L) then heading = (heading + 15.0) % 360.0 end
        if IsControlJustPressed(0, PLACE_ROT_R) then heading = (heading - 15.0) % 360.0 end

        if IsControlJustPressed(0, PLACE_CONFIRM) then
            local finalCoords = GetEntityCoords(ghost)
            result = { coords = finalCoords, heading = heading, confirmed = true }
        end

        if IsControlJustPressed(0, PLACE_CANCEL) or IsControlJustPressed(0, 200) then
            result = { confirmed = false }
        end

        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)

        Wait(0)
    end

    lib.hideTextUI()
    DeleteObject(ghost)
    return result
end

local function SpawnNetworkProp(model, coords, heading, keepModel)
    local hash = GetHashKey(model)
    lib.requestModel(hash)

    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHeading(obj, Config.Scene.alignToPlayer and heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)

    if not keepModel then
        SetModelAsNoLongerNeeded(hash)
    end

    local netId = ObjToNet(obj)
    SetNetworkIdExistsOnAllMachines(netId, true)

    return obj, netId
end

local function CountProps(category)
    local valid = {}
    for _, entry in ipairs(sceneProps[category]) do
        if DoesEntityExist(entry.obj) then
            valid[#valid + 1] = entry
        end
    end
    sceneProps[category] = valid
    return #valid
end

-- Alle Props zählen für Statusanzeige
local function GetAllCounts()
    return {
        cones       = CountProps('cones'),
        barriers    = CountProps('barriers'),
        lightstands = CountProps('lightstands'),
        flares      = CountProps('flares'),
    }
end

local function RemovePropFromCategory(category, obj)
    for i, entry in ipairs(sceneProps[category]) do
        if entry.obj == obj then
            lightActive[obj] = nil
            exports.ox_target:removeLocalEntity(obj)
            if DoesEntityExist(obj) then DeleteObject(obj) end
            table.remove(sceneProps[category], i)
            FD.Debug('scene', 'Prop entfernt aus %s (Handle %d)', category, obj)
            return true
        end
    end
    return false
end

-- Lichtmast: Licht via DrawLightWithRange – läuft in einem
-- zentralen Thread statt einem Thread pro Mast
local lightThread = false

local function EnsureLightThread()
    if lightThread then return end
    lightThread = true
    CreateThread(function()
        -- Coords-Cache: Lichtmaste sind frozen → Position nur alle 60 Frames neu holen
        local coordCache = {}
        local frame = 0
        while lightThread do
            frame = frame + 1
            local any = false
            for obj, light in pairs(lightActive) do
                if DoesEntityExist(obj) then
                    any = true
                    -- Coords nur alle 60 Frames aktualisieren (frozen Props bewegen sich nicht)
                    if frame % 60 == 0 or not coordCache[obj] then
                        coordCache[obj] = GetEntityCoords(obj)
                    end
                    local pos = coordCache[obj]
                    DrawLightWithRange(
                        pos.x, pos.y, pos.z + (light.offset or 2.5),
                        light.r, light.g, light.b,
                        light.range,
                        light.intensity
                    )
                else
                    lightActive[obj] = nil
                    coordCache[obj]  = nil
                end
            end
            if not any then
                lightThread = false
                return
            end
            Wait(0)
        end
    end)
end

-- ─────────────────────────────────────────────
--  Prop-Platzierung
-- ─────────────────────────────────────────────

local function PlacePropWithTarget(model, category, label, cooldownKey, item, withLight, isFlare)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

    -- Kein Platzieren im Fahrzeug
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        FD.Notify('Du kannst keine Props aus einem Fahrzeug heraus platzieren.', 'error')
        return
    end

    local cdKey = 'scene_' .. category
    if not FD.CheckCooldown(cdKey) then FD.Notify(T('cooldown'), 'warning') return end

    local configLimit = Config.Limits[category] or 10
    local itemCount   = item and FD.CountItem(item) or configLimit
    local limit       = math.min(configLimit, itemCount)

    if item and itemCount == 0 then
        FD.Notify(('Keine %s im Inventar.'):format(label), 'error')
        return
    end

    if CountProps(category) >= limit then
        FD.Notify(('%s Limit erreicht – noch %d Item(s) übrig'):format(label, itemCount), 'warning')
        return
    end

    -- Preview-Modus: Spieler wählt Position mit Ghost-Prop
    local placement = RunPlacementPreview(model)
    if not placement or not placement.confirmed then
        FD.Notify('Platzierung abgebrochen.', 'inform')
        return
    end

    -- Progress Bar nach Bestätigung
    local done = FD.Progress(
        ('Stelle %s auf'):format(label),
        'place',
        categoryProgressTime[category] or 2000
    )
    if not done then return end

    local obj, netId = SpawnNetworkProp(model, placement.coords, placement.heading)

    sceneProps[category][#sceneProps[category] + 1] = { obj = obj, netId = netId, item = item }

    if withLight then
        lightActive[obj] = { r = Config.Scene.lightColor.r, g = Config.Scene.lightColor.g, b = Config.Scene.lightColor.b, range = Config.Scene.lightRange, intensity = Config.Scene.lightIntensity, offset = 2.5 }
        EnsureLightThread()
    end

    if isFlare then
        lib.requestNamedPtfxAsset('core')
        UseParticleFxAssetNextCall('core')
        local ptfx = StartParticleFxLoopedOnEntity(
            'fire_entity_s',
            obj, 0.0, 0.0, 0.1,
            0.0, 0.0, 0.0,
            0.5, false, false, false
        )
        lightActive[obj] = { r = 255, g = 80, b = 0, range = 8.0, intensity = 5.0, offset = 0.2 }
        EnsureLightThread()
        sceneProps[category][#sceneProps[category]].ptfx = ptfx
    end

    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'fd_pickup_' .. tostring(obj),
            icon     = 'fas fa-hand',
            label    = label .. ' aufheben',
            distance = 2.5,
            onSelect = function()
                for _, entry in ipairs(sceneProps[category]) do
                    if entry.obj == obj and entry.ptfx then
                        StopParticleFxLooped(entry.ptfx, false)
                    end
                end
                RemovePropFromCategory(category, obj)
                TriggerServerEvent('d4rk_fd_utility:sv_removeSceneProp', netId)
                if item then
                    FD.Notify(label .. ' aufgehoben – Item zurück im Inventar.', 'inform')
                else
                    FD.Notify(label .. ' aufgehoben.', 'inform')
                end
            end,
            canInteract = function() return FD.HasJob() end,
        }
    })

    if item then TriggerServerEvent('d4rk_fd_utility:sv_removeItem', item, 1) end
    -- Prop beim Server registrieren für andere FD-Spieler
    TriggerServerEvent('d4rk_fd_utility:sv_registerSceneProp', netId, category, label, item)
    FD.SetCooldown(cdKey, cooldownKey)
    FD.Notify(label .. ' aufgestellt.', 'success')
    FD.Debug('scene', '%s platziert | NetID %d', label, netId)

    return obj
end

-- ─────────────────────────────────────────────
--  Absperrband: Zwei-Punkt System
-- ─────────────────────────────────────────────

local function RunTwoPointPreview(model)
    local hash = GetHashKey(model)
    lib.requestModel(hash)
    Wait(200)

    -- Ghost für Punkt A
    local ghostA = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghostA, 150, false)
    SetEntityCollision(ghostA, false, false)
    FreezeEntityPosition(ghostA, true)

    -- Ghost für Punkt B
    local ghostB = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghostB, 100, false)
    SetEntityCollision(ghostB, false, false)
    FreezeEntityPosition(ghostB, true)
    SetModelAsNoLongerNeeded(hash)

    local pointA     = nil
    local confirmed  = false
    local lastCoords = vector3(0, 0, 0)
    local lastPhase  = nil  -- 'A' oder 'B' – TextUI nur bei Phasenwechsel neu setzen

    while not confirmed do
        local coords = GetRaycastCoords()
        local moved  = #(coords - lastCoords) > 0.1

        if not pointA then
            if lastPhase ~= 'A' then
                lib.showTextUI('[E] Punkt A setzen  [X] Abbrechen', {
                    position = 'bottom-center',
                    icon     = 'fas fa-map-pin',
                })
                lastPhase = 'A'
            end

            SetEntityCoords(ghostA, coords.x, coords.y, coords.z, false, false, false, false)
            if moved then PlaceObjectOnGroundProperly(ghostA) end
            SetEntityCoords(ghostB, coords.x, coords.y, coords.z, false, false, false, false)

            if IsControlJustPressed(0, PLACE_CONFIRM) then
                pointA = GetEntityCoords(ghostA)
                lastPhase = nil  -- Phase wechselt → TextUI neu setzen
            end
        else
            local pointB = coords
            local dist   = #(vector2(pointA.x, pointA.y) - vector2(pointB.x, pointB.y))
            local needed = math.max(1, math.floor(dist / 2.5) + 1)

            -- TextUI nur aktualisieren wenn sich Anzahl oder Phase geändert hat
            lib.showTextUI(('[E] Bestätigen  [X] Abbrechen  |  Länge: %.1fm  Pfosten: ~%d'):format(dist, needed), {
                position = 'bottom-center',
                icon     = 'fas fa-ruler',
            })

            SetEntityCoords(ghostB, pointB.x, pointB.y, pointB.z, false, false, false, false)
            if moved then PlaceObjectOnGroundProperly(ghostB) end

            if IsControlJustPressed(0, PLACE_CONFIRM) then
                local finalB = GetEntityCoords(ghostB)
                lib.hideTextUI()
                DeleteObject(ghostA)
                DeleteObject(ghostB)
                return { pointA = pointA, pointB = finalB, confirmed = true }
            end
        end

        if moved then lastCoords = coords end

        if IsControlJustPressed(0, PLACE_CANCEL) or IsControlJustPressed(0, 200) then
            lib.hideTextUI()
            DeleteObject(ghostA)
            DeleteObject(ghostB)
            return { confirmed = false }
        end

        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        Wait(0)
    end
end

local function PlaceBarrierLine()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        FD.Notify('Du kannst keine Props aus einem Fahrzeug heraus platzieren.', 'error') return
    end
    if not FD.CheckCooldown('scene_barriers') then FD.Notify(T('cooldown'), 'warning') return end

    local barrierItems = FD.CountItem('safetybarrier')
    if barrierItems == 0 then FD.Notify('Keine Absperrungen im Inventar.', 'error') return end

    local placement = RunTwoPointPreview(Config.Props.barrier)
    if not placement or not placement.confirmed then
        FD.Notify('Platzierung abgebrochen.', 'inform') return
    end

    local pA   = placement.pointA
    local pB   = placement.pointB

    -- Abstand in 3D berechnen
    local dx   = pB.x - pA.x
    local dy   = pB.y - pA.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Barrier-Prop ist ~2.5m lang → Abstand 2.5m zwischen Pfosten
    local spacing = 2.5
    local count   = math.max(1, math.floor(dist / spacing) + 1)
    local maxSlots = Config.Limits.barriers - CountProps('barriers')
    count = math.min(count, barrierItems, maxSlots)

    FD.Debug('scene', 'Absperrlinie: dist=%.1fm spacing=%.1fm count=%d items=%d maxSlots=%d',
        dist, spacing, count, barrierItems, maxSlots)

    if count == 0 then
        FD.Notify('Nicht genug Platz oder Items.', 'warning') return
    end

    -- Heading von A → B
    local heading = math.deg(math.atan(dx, dy)) % 360.0

    local done = FD.Progress(
        ('Absperrlinie aufstellen (%d Pfosten)'):format(count),
        'place',
        math.max(2000, count * 600)
    )
    if not done then return end

    -- Modell einmal laden
    local hash = GetHashKey(Config.Props.barrier)
    lib.requestModel(hash)

    -- Pfosten platzieren
    for i = 0, count - 1 do
        local t
        if count == 1 then
            t = 0.0
        else
            t = i / (count - 1)
        end

        local x = pA.x + dx * t
        local y = pA.y + dy * t
        local _, z = GetGroundZFor_3dCoord(x, y, pA.z + 2.0, false)
        if not z then z = pA.z end

        FD.Debug('scene', 'Pfosten %d/%d bei t=%.2f pos=(%.1f,%.1f,%.1f)', i+1, count, t, x, y, z)

        local obj, netId = SpawnNetworkProp(Config.Props.barrier, vector3(x, y, z), heading, true)
        sceneProps.barriers[#sceneProps.barriers + 1] = { obj = obj, netId = netId, item = 'safetybarrier' }

        TriggerServerEvent('d4rk_fd_utility:sv_registerSceneProp', netId, 'barriers', 'Absperrung', 'safetybarrier')
        TriggerServerEvent('d4rk_fd_utility:sv_removeItemDirect', 'safetybarrier', 1)

        local capturedObj   = obj
        local capturedNetId = netId
        exports.ox_target:addLocalEntity(obj, {
            {
                name        = 'fd_pickup_' .. tostring(capturedObj),
                icon        = 'fas fa-hand',
                label       = 'Absperrung aufheben',
                distance    = 2.5,
                onSelect    = function()
                    RemovePropFromCategory('barriers', capturedObj)
                    TriggerServerEvent('d4rk_fd_utility:sv_removeSceneProp', capturedNetId)
                    FD.Notify('Absperrung aufgehoben – Item zurück im Inventar.', 'inform')
                end,
                canInteract = function() return FD.HasJob() end,
            }
        })
    end

    SetModelAsNoLongerNeeded(hash)
    FD.SetCooldown('scene_barriers', 'barrierPlace')
    FD.Notify(('Absperrlinie: %d Pfosten aufgestellt.'):format(count), 'success')
end

-- ─────────────────────────────────────────────
--  Fremde Props: Server-Sync Handler
-- ─────────────────────────────────────────────

-- { [netId] = true } – Props von anderen Spielern wo wir bereits Target gesetzt haben
local foreignTargets = {}

RegisterNetEvent('d4rk_fd_utility:cl_scenePropSync', function(netId, category, label, item, ownerSrc)
    if not FD.HasJob() then return end

    -- nil = Prop wurde entfernt
    if not category then
        if foreignTargets[netId] then
            local obj = NetToObj(netId)
            if obj and obj ~= 0 then
                exports.ox_target:removeLocalEntity(obj)
            end
            foreignTargets[netId] = nil
        end
        return
    end

    -- Eigene Props nicht doppelt registrieren
    if ownerSrc == GetPlayerServerId(PlayerId()) then return end

    -- Kurz warten bis Objekt im Netzwerk verfügbar
    SetTimeout(500, function()
        local obj = NetToObj(netId)
        if not obj or obj == 0 or not DoesEntityExist(obj) then return end
        if foreignTargets[netId] then return end

        foreignTargets[netId] = true

        exports.ox_target:addLocalEntity(obj, {
            {
                name        = 'fd_pickup_foreign_' .. tostring(netId),
                icon        = 'fas fa-hand',
                label       = (label or 'Prop') .. ' aufheben',
                distance    = 2.5,
                onSelect    = function()
                    -- Server entfernt das Obj und gibt Item zurück
                    TriggerServerEvent('d4rk_fd_utility:sv_removeSceneProp', netId)
                    foreignTargets[netId] = nil
                    -- Obj lokal löschen
                    if DoesEntityExist(obj) then
                        exports.ox_target:removeLocalEntity(obj)
                        DeleteObject(obj)
                    end
                    FD.Notify((label or 'Prop') .. ' aufgehoben.', 'inform')
                end,
                canInteract = function() return FD.HasJob() end,
            }
        })
        FD.Debug('scene', 'Fremdes Prop registriert: NetID %d (%s)', netId, label or '?')
    end)
end)



local function ClearAllScene()
    local total = 0
    for category, props in pairs(sceneProps) do
        for _, entry in ipairs(props) do
            if DoesEntityExist(entry.obj) then
                lightActive[entry.obj] = nil
                exports.ox_target:removeLocalEntity(entry.obj)
                DeleteObject(entry.obj)
                total = total + 1
            end
        end
        sceneProps[category] = {}
    end
    lightThread = false
    FD.Debug('scene', 'Szene geräumt: %d Props', total)
    return total
end

-- ─────────────────────────────────────────────
--  Szenen-Menü
-- ─────────────────────────────────────────────

local function OpenSceneMenu()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

    -- Einmal zählen, nicht pro Option
    local counts = GetAllCounts()
    local coneItems    = FD.CountItem('trafficcone')
    local barrierItems = FD.CountItem('safetybarrier')
    local lightItems   = FD.CountItem('lightstand')

    local options = {
        -- ── Kegel ────────────────────────────
        {
            title       = 'Kegel aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(coneItems, counts.cones, Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            disabled    = coneItems == 0 or counts.cones >= Config.Limits.cones,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.cone, 'cones', 'Verkehrskegel', 'conePlace', 'trafficcone')
            end,
        },
        {
            title       = 'Großen Kegel aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(coneItems, counts.cones, Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            disabled    = coneItems == 0 or counts.cones >= Config.Limits.cones,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.coneBig, 'cones', 'Großer Kegel', 'conePlace', 'trafficcone')
            end,
        },

        -- ── Absperrung ───────────────────────
        {
            title       = 'Absperrung aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(barrierItems, counts.barriers, Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            disabled    = barrierItems == 0 or counts.barriers >= Config.Limits.barriers,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.barrier, 'barriers', 'Absperrung', 'barrierPlace', 'safetybarrier')
            end,
        },
        {
            title       = 'Lange Absperrung aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(barrierItems, counts.barriers, Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            disabled    = barrierItems == 0 or counts.barriers >= Config.Limits.barriers,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.barrierLong, 'barriers', 'Lange Absperrung', 'barrierPlace', 'safetybarrier')
            end,
        },
        {
            title       = 'Warnzeichen aufstellen',
            description = ('Platziert: %d/%d'):format(counts.barriers, Config.Limits.barriers),
            icon        = 'fas fa-triangle-exclamation',
            disabled    = counts.barriers >= Config.Limits.barriers,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.warningSign, 'barriers', 'Warnzeichen', 'barrierPlace', nil)
            end,
        },
        {
            title       = 'Absperrlinie spannen',
            description = ('Im Inventar: %d – Zwei Punkte wählen'):format(barrierItems),
            icon        = 'fas fa-grip-lines',
            disabled    = FD.CountItem('safetybarrier') == 0 or counts.barriers >= Config.Limits.barriers,
            onSelect    = function() PlaceBarrierLine() end,
        },

        -- ── Lichtmast ────────────────────────
        {
            title       = 'Lichtmast aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(lightItems, counts.lightstands, Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            disabled    = lightItems == 0 or counts.lightstands >= Config.Limits.lightstands,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.lightstand, 'lightstands', 'Lichtmast', 'lightPlace', 'lightstand', true)
            end,
        },
        {
            title       = 'Großen Lichtmast aufstellen',
            description = ('Im Inventar: %d | Platziert: %d/%d'):format(lightItems, counts.lightstands, Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            disabled    = lightItems == 0 or counts.lightstands >= Config.Limits.lightstands,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.lightstandBig, 'lightstands', 'Großer Lichtmast', 'lightPlace', 'lightstand', true)
            end,
        },

        -- ── Fackel ───────────────────────────
        {
            title       = 'Fackel platzieren',
            description = ('Platziert: %d/%d'):format(counts.flares, Config.Limits.flares),
            icon        = 'fas fa-fire',
            disabled    = counts.flares >= Config.Limits.flares,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.flare, 'flares', 'Fackel', 'conePlace', nil, false, true)
            end,
        },

        -- ── Räumen ───────────────────────────
        {
            title       = 'Eigene Szene räumen',
            description = ('Gesamt: %d Props'):format(
                counts.cones + counts.barriers + counts.lightstands + counts.flares
            ),
            icon        = 'fas fa-trash',
            disabled    = (counts.cones + counts.barriers + counts.lightstands + counts.flares) == 0,
            onSelect    = function()
                local count = ClearAllScene()
                FD.Notify(('Szene geräumt – %d Props entfernt.'):format(count), 'inform')
            end,
        },
    }

    lib.registerContext({ id = 'fd_scene_menu', title = 'Szene einrichten', options = options })
    lib.showContext('fd_scene_menu')
end

-- ─────────────────────────────────────────────
--  Radial Menü
-- ─────────────────────────────────────────────

lib.addRadialItem({
    id       = 'fd_scene_radial',
    label    = 'Szene',
    icon     = 'fas fa-traffic-cone',
    onSelect = function() OpenSceneMenu() end,
})

-- ─────────────────────────────────────────────
--  Befehle
-- ─────────────────────────────────────────────

RegisterCommand('fdscene', function(_, args)
    if not args[1] then
        OpenSceneMenu()
        return
    end
    if args[1] == 'clear' then
        local count = ClearAllScene()
        FD.Notify(('Szene geräumt – %d Props entfernt.'):format(count), 'inform')
    elseif args[1] == 'status' then
        local counts = GetAllCounts()
        local msg = ('Kegel: %d | Absperr: %d | Licht: %d | Fackeln: %d'):format(
            counts.cones, counts.barriers, counts.lightstands, counts.flares
        )
        FD.Notify(msg, 'inform')
    end
end, false)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearAllScene()
end)

FD.Debug('scene', 'Scene Modul geladen')