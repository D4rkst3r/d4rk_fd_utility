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

local categoryCooldown = {
    cones       = 'conePlace',
    barriers    = 'barrierPlace',
    lightstands = 'lightPlace',
    flares      = 'conePlace',
}

local categoryProgressTime = {
    cones       = 1500,
    barriers    = 2000,
    lightstands = 4000,
    flares      = 1000,
}

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
        while lightThread do
            local any = false
            for obj in pairs(lightActive) do
                if DoesEntityExist(obj) then
                    any = true
                    local c = Config.Scene.lightColor
                    local pos = GetEntityCoords(obj)
                    DrawLightWithRange(
                        pos.x, pos.y, pos.z + 2.5,
                        c.r, c.g, c.b,
                        Config.Scene.lightRange,
                        Config.Scene.lightIntensity
                    )
                else
                    lightActive[obj] = nil
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

local function PlacePropWithTarget(model, category, label, cooldownKey, item, withLight)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if item and not FD.HasItem(item) then FD.Notify(T('no_item'), 'error') return end

    local cdKey = 'scene_' .. category
    if not FD.CheckCooldown(cdKey) then FD.Notify(T('cooldown'), 'warning') return end

    local limit = Config.Limits[category] or 10
    if CountProps(category) >= limit then
        FD.Notify(('%s Limit erreicht (%d/%d)'):format(label, limit, limit), 'warning')
        return
    end

    local done = FD.Progress(
        ('Stelle %s auf'):format(label),
        'place',
        categoryProgressTime[category] or 2000
    )
    if not done then return end

    local coords, heading = GetPlaceCoords()
    local obj, netId      = SpawnNetworkProp(model, coords, heading)

    sceneProps[category][#sceneProps[category] + 1] = { obj = obj, netId = netId }

    -- Lichtmast: zentralen Light-Thread starten
    if withLight then
        lightActive[obj] = true
        EnsureLightThread()
    end

    -- ox_target zum Aufheben
    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'fd_pickup_' .. tostring(obj),
            icon     = 'fas fa-hand',
            label    = label .. ' aufheben',
            distance = 2.5,
            onSelect = function()
                RemovePropFromCategory(category, obj)
                if item then FD.RemoveItem(item, -1) end  -- Item zurückgeben wenn consumable = false
                FD.Notify(label .. ' aufgehoben.', 'inform')
            end,
            canInteract = function() return FD.HasJob() end,
        }
    })

    FD.SetCooldown(cdKey, cooldownKey)
    if item then FD.RemoveItem(item, 1) end
    FD.Notify(label .. ' aufgestellt.', 'success')
    FD.Debug('scene', '%s platziert | NetID %d | Pos %s', label, netId, tostring(coords))

    return obj
end

-- ─────────────────────────────────────────────
--  Alles räumen
-- ─────────────────────────────────────────────

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

    local options = {
        -- ── Kegel ────────────────────────────
        {
            title       = 'Kegel aufstellen',
            description = ('Platziert: %d/%d'):format(counts.cones, Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            disabled    = counts.cones >= Config.Limits.cones,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.cone, 'cones', 'Verkehrskegel', 'conePlace', 'trafficcone')
            end,
        },
        {
            title       = 'Großen Kegel aufstellen',
            description = ('Platziert: %d/%d'):format(counts.cones, Config.Limits.cones),
            icon        = 'fas fa-traffic-cone',
            disabled    = counts.cones >= Config.Limits.cones,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.coneBig, 'cones', 'Großer Kegel', 'conePlace', 'trafficcone')
            end,
        },

        -- ── Absperrung ───────────────────────
        {
            title       = 'Absperrung aufstellen',
            description = ('Platziert: %d/%d'):format(counts.barriers, Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            disabled    = counts.barriers >= Config.Limits.barriers,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.barrier, 'barriers', 'Absperrung', 'barrierPlace', 'safetybarrier')
            end,
        },
        {
            title       = 'Lange Absperrung aufstellen',
            description = ('Platziert: %d/%d'):format(counts.barriers, Config.Limits.barriers),
            icon        = 'fas fa-do-not-enter',
            disabled    = counts.barriers >= Config.Limits.barriers,
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

        -- ── Lichtmast ────────────────────────
        {
            title       = 'Lichtmast aufstellen',
            description = ('Platziert: %d/%d'):format(counts.lightstands, Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            disabled    = counts.lightstands >= Config.Limits.lightstands,
            onSelect    = function()
                PlacePropWithTarget(Config.Props.lightstand, 'lightstands', 'Lichtmast', 'lightPlace', 'lightstand', true)
            end,
        },
        {
            title       = 'Großen Lichtmast aufstellen',
            description = ('Platziert: %d/%d'):format(counts.lightstands, Config.Limits.lightstands),
            icon        = 'fas fa-lightbulb',
            disabled    = counts.lightstands >= Config.Limits.lightstands,
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
                PlacePropWithTarget(Config.Props.flare, 'flares', 'Fackel', 'conePlace', nil)
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