---------------------------------------------------
--  d4rk_fd_utility – Modul: Scene Management
--  Kegel / Absperrband / Lichtmast / Warnzeichen
---------------------------------------------------
if not FD.ModuleEnabled('Scene') then return end

-- ─────────────────────────────────────────────
--  Lokaler Status
--  Netzwerk-Objekte damit alle Spieler sie sehen
-- ─────────────────────────────────────────────

-- { category = { { obj, netId } } }
local sceneProps = {
    cones       = {},
    barriers    = {},
    lightstands = {},
    flares      = {},
}

-- Licht-Handles für Lichtmaste
local lightHandles = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function GetPlaceCoords()
    local ped     = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local coords  = GetEntityCoords(ped)
    local dist    = Config.Scene.placeDistance

    local x = coords.x + dist * math.sin(-math.rad(heading))
    local y = coords.y + dist * math.cos(-math.rad(heading))

    -- Boden-Z finden
    local found, z = GetGroundZFor_3dCoord(x, y, coords.z + 2.0, false)
    if not found then z = coords.z end

    return vector3(x, y, z), heading
end

local function SpawnNetworkProp(model, coords, heading)
    local hash = GetHashKey(model)
    lib.requestModel(hash)

    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, true, true, true)
    SetEntityHeading(obj, Config.Scene.alignToPlayer and heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    -- Als Netzwerk-Objekt setzen damit andere Spieler es sehen
    local netId = ObjToNet(obj)
    SetNetworkIdExistsOnAllMachines(netId, true)

    return obj, netId
end

local function RemovePropFromCategory(category, obj)
    for i, entry in ipairs(sceneProps[category]) do
        if entry.obj == obj then
            -- Licht entfernen falls Lichtmast
            if lightHandles[obj] then
                RemoveLightHandle(lightHandles[obj])
                lightHandles[obj] = nil
            end
            -- ox_target entfernen
            exports.ox_target:removeLocalEntity(obj)
            -- Prop löschen
            if DoesEntityExist(obj) then DeleteObject(obj) end
            table.remove(sceneProps[category], i)
            return true
        end
    end
    return false
end

local function CountProps(category)
    -- Ungültige Props aufräumen
    local valid = {}
    for _, entry in ipairs(sceneProps[category]) do
        if DoesEntityExist(entry.obj) then
            valid[#valid + 1] = entry
        end
    end
    sceneProps[category] = valid
    return #valid
end

local function AddLightToStand(obj)
    local c = Config.Scene.lightColor
    local handle = AddLightToRendertarget and nil or nil

    -- GTA native Licht
    CreateThread(function()
        while DoesEntityExist(obj) do
            local coords = GetEntityCoords(obj)
            DrawLightWithRange(
                coords.x, coords.y, coords.z + 2.0,
                c.r, c.g, c.b,
                Config.Scene.lightRange,
                Config.Scene.lightIntensity
            )
            Wait(0)
        end
    end)
end

-- ─────────────────────────────────────────────
--  Prop-Platzierung mit ox_target zum Aufheben
-- ─────────────────────────────────────────────

local function PlacePropWithTarget(model, category, label, onPlace)
    local limit = Config.Limits[category] or 10

    if CountProps(category) >= limit then
        FD.Notify(('%s Limit erreicht (%d/%d)'):format(label, limit, limit), 'warning')
        return
    end

    local done = FD.Progress(('Stelle %s auf'):format(label), 'place', Config.Cooldowns[category .. 'Place'] or 2000)
    if not done then return end

    local coords, heading = GetPlaceCoords()
    local obj, netId      = SpawnNetworkProp(model, coords, heading)

    sceneProps[category][#sceneProps[category] + 1] = { obj = obj, netId = netId }

    -- Callback für spezielle Aktionen (z.B. Licht)
    if onPlace then onPlace(obj) end

    -- ox_target auf das Prop zum Aufheben
    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'fd_scene_remove_' .. tostring(obj),
            icon     = 'fas fa-times',
            label    = label .. ' aufheben',
            distance = 2.5,
            onSelect = function()
                RemovePropFromCategory(category, obj)
                FD.Notify(label .. ' aufgehoben.', 'inform')
                FD.Debug('scene', '%s aufgehoben (Kategorie: %s)', label, category)
            end,
            canInteract = function() return FD.HasJob() end,
        }
    })

    FD.Notify(label .. ' aufgestellt.', 'success')
    FD.Debug('scene', '%s platziert bei %s (NetID %d)', label, tostring(coords), netId)

    return obj
end

-- ─────────────────────────────────────────────
--  Einzelne Platzier-Funktionen
-- ─────────────────────────────────────────────

local function PlaceCone(big)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('trafficcone') then FD.Notify(T('no_item'), 'error') return end
    if not FD.CheckCooldown('scene_cone') then FD.Notify(T('cooldown'), 'warning') return end

    local model = big and Config.Props.coneBig or Config.Props.cone
    PlacePropWithTarget(model, 'cones', 'Verkehrskegel')
    FD.SetCooldown('scene_cone', 'conePlace')
    FD.RemoveItem('trafficcone', 1)
end

local function PlaceBarrier(long)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('safetybarrier') then FD.Notify(T('no_item'), 'error') return end
    if not FD.CheckCooldown('scene_barrier') then FD.Notify(T('cooldown'), 'warning') return end

    local model = long and Config.Props.barrierLong or Config.Props.barrier
    PlacePropWithTarget(model, 'barriers', 'Absperrung')
    FD.SetCooldown('scene_barrier', 'barrierPlace')
    FD.RemoveItem('safetybarrier', 1)
end

local function PlaceLightStand(big)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('lightstand') then FD.Notify(T('no_item'), 'error') return end
    if not FD.CheckCooldown('scene_light') then FD.Notify(T('cooldown'), 'warning') return end

    local model = big and Config.Props.lightstandBig or Config.Props.lightstand
    PlacePropWithTarget(model, 'lightstands', 'Lichtmast', function(obj)
        AddLightToStand(obj)
    end)
    FD.SetCooldown('scene_light', 'lightPlace')
    FD.RemoveItem('lightstand', 1)
end

local function PlaceFlare()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.CheckCooldown('scene_flare') then FD.Notify(T('cooldown'), 'warning') return end

    local coords, heading = GetPlaceCoords()
    local obj, netId      = SpawnNetworkProp(Config.Props.flare, coords, heading)

    sceneProps.flares[#sceneProps.flares + 1] = { obj = obj, netId = netId }

    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'fd_scene_remove_flare_' .. tostring(obj),
            icon     = 'fas fa-times',
            label    = 'Fackel aufheben',
            distance = 2.5,
            onSelect = function()
                RemovePropFromCategory('flares', obj)
                FD.Notify('Fackel aufgehoben.', 'inform')
            end,
            canInteract = function() return FD.HasJob() end,
        }
    })

    FD.SetCooldown('scene_flare', 'conePlace')
    FD.Notify('Fackel platziert.', 'success')
end

local function PlaceWarningSign()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.CheckCooldown('scene_sign') then FD.Notify(T('cooldown'), 'warning') return end

    PlacePropWithTarget(Config.Props.warningSign, 'barriers', 'Warnzeichen')
    FD.SetCooldown('scene_sign', 'barrierPlace')
end

-- ─────────────────────────────────────────────
--  Alles räumen
-- ─────────────────────────────────────────────

local function ClearAllScene()
    local total = 0
    for category, props in pairs(sceneProps) do
        for _, entry in ipairs(props) do
            if DoesEntityExist(entry.obj) then
                if lightHandles[entry.obj] then
                    lightHandles[entry.obj] = nil
                end
                exports.ox_target:removeLocalEntity(entry.obj)
                DeleteObject(entry.obj)
                total = total + 1
            end
        end
        sceneProps[category] = {}
    end
    FD.Debug('scene', 'Szene geräumt: %d Props entfernt', total)
    return total
end

-- ─────────────────────────────────────────────
--  Szenen-Übersicht Menü
-- ─────────────────────────────────────────────

local function OpenSceneMenu()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

    local options = {
        -- ── Kegel ────────────────────────────
        {
            title       = T('cone_place'),
            description = ('Platziert %d/%d'):format(CountProps('cones'), Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            arrow       = true,
            onSelect    = function() PlaceCone(false) end,
        },
        {
            title       = 'Großen Kegel aufstellen',
            description = ('Platziert %d/%d'):format(CountProps('cones'), Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            onSelect    = function() PlaceCone(true) end,
        },

        -- ── Absperrung ───────────────────────
        {
            title       = T('barrier_place'),
            description = ('Platziert %d/%d'):format(CountProps('barriers'), Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            onSelect    = function() PlaceBarrier(false) end,
        },
        {
            title       = 'Lange Absperrung aufstellen',
            description = ('Platziert %d/%d'):format(CountProps('barriers'), Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            onSelect    = function() PlaceBarrier(true) end,
        },
        {
            title       = 'Warnzeichen aufstellen',
            description = ('Platziert %d/%d'):format(CountProps('barriers'), Config.Limits.barriers),
            icon        = 'fas fa-triangle-exclamation',
            onSelect    = function() PlaceWarningSign() end,
        },

        -- ── Licht ────────────────────────────
        {
            title       = T('light_place'),
            description = ('Platziert %d/%d'):format(CountProps('lightstands'), Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            onSelect    = function() PlaceLightStand(false) end,
        },
        {
            title       = 'Großen Lichtmast aufstellen',
            description = ('Platziert %d/%d'):format(CountProps('lightstands'), Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            onSelect    = function() PlaceLightStand(true) end,
        },

        -- ── Fackel ───────────────────────────
        {
            title       = 'Fackel platzieren',
            description = ('Platziert %d/%d'):format(CountProps('flares'), Config.Limits.flares),
            icon        = 'fas fa-fire',
            onSelect    = function() PlaceFlare() end,
        },

        -- ── Räumen ───────────────────────────
        {
            title       = 'Eigene Szene räumen',
            description = 'Alle eigenen Props entfernen',
            icon        = 'fas fa-trash',
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
    id      = 'fd_scene_radial',
    label   = 'Szene',
    icon    = 'fas fa-fire-extinguisher',
    onSelect = function()
        OpenSceneMenu()
    end,
})

-- ─────────────────────────────────────────────
--  ox_target auf Boden – Schnellzugriff
-- ─────────────────────────────────────────────

-- Globale Ground-Zone für schnelles Platzieren
exports.ox_target:addGlobalPed({
    {
        name        = 'fd_scene_open',
        icon        = 'fas fa-traffic-cone',
        label       = 'Szene einrichten',
        distance    = 1.5,
        onSelect    = function() OpenSceneMenu() end,
        canInteract = function() return FD.HasJob() end,
    }
})

-- ─────────────────────────────────────────────
--  Admin Befehl: /fdscene
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
        print('[d4rk_fd_utility] Szenen-Props:')
        for category, props in pairs(sceneProps) do
            print(('  %s: %d'):format(category, CountProps(category)))
        end
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