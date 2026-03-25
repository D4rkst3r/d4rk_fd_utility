---------------------------------------------------
--  d4rk_fd_utility – Modul: Equipment
--  Thermocam / Feuerlöscher / Leitern / Atemschutz
---------------------------------------------------
if not FD.ModuleEnabled('Equipment') then return end

-- ─────────────────────────────────────────────
--  Lokaler Status
-- ─────────────────────────────────────────────

local thermocamActive  = false
local gasmaskActive    = false
local ladderProps      = {}   -- { { obj, netId } }

-- ─────────────────────────────────────────────
--  Wärmebildkamera
-- ─────────────────────────────────────────────

local function ToggleThermocam()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('thermocam') then
        FD.Notify(T('equip_no_thermocam'), 'error') return
    end

    thermocamActive = not thermocamActive

    if thermocamActive then
        SetTimecycleModifier(Config.Equipment.thermocamModifier or 'thermal')
        SetTimecycleModifierStrength(Config.Equipment.thermocamStrength or 1.0)
        FD.Notify(T('equip_thermocam_on'), 'success')
        FD.Debug('equipment', 'Thermocam aktiviert')
    else
        ClearTimecycleModifier()
        FD.Notify(T('equip_thermocam_off'), 'inform')
        FD.Debug('equipment', 'Thermocam deaktiviert')
    end
end

-- ─────────────────────────────────────────────
--  Feuerlöscher
-- ─────────────────────────────────────────────

local function ToggleExtinguisher()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not FD.HasItem('fireextinguisher') then
        FD.Notify(T('equip_no_extinguisher'), 'error') return
    end

    local ped        = PlayerPedId()
    local weaponHash = GetHashKey(Config.Equipment.extinguisherWeapon or 'WEAPON_FIREEXTINGUISHER')
    local hasWeapon  = HasPedGotWeapon(ped, weaponHash, false)

    if not hasWeapon then
        -- Waffe geben + sofort in Hand nehmen
        GiveWeaponToPed(ped, weaponHash, 1, false, true)
        FD.Notify(T('equip_extinguisher_on'), 'success')
        FD.Debug('equipment', 'Feuerlöscher ausgerüstet')
    else
        -- Waffe entfernen + Item verbrauchen
        RemoveWeaponFromPed(ped, weaponHash)
        FD.RemoveItem('fireextinguisher', 1)
        FD.Notify(T('equip_extinguisher_off'), 'inform')
        FD.Debug('equipment', 'Feuerlöscher weggelegt – Item verbraucht')
    end
end

-- ─────────────────────────────────────────────
--  Leitern
-- ─────────────────────────────────────────────

local function PlaceLadder(model, label)
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        FD.Notify(T('not_in_vehicle'), 'error') return
    end
    if not FD.HasItem('ladder') then
        FD.Notify(T('equip_no_ladder'), 'error') return
    end
    if not FD.CheckCooldown('equip_ladder') then
        FD.Notify(T('cooldown'), 'warning') return
    end

    local done = FD.Progress(T('equip_ladder_place'), 'place', Config.Items.ladder.useTime)
    if not done then return end

    local ped     = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local coords  = GetEntityCoords(ped)
    local dist    = 1.2

    local x = coords.x + dist * math.sin(-math.rad(heading))
    local y = coords.y + dist * math.cos(-math.rad(heading))
    local _, z = GetGroundZFor_3dCoord(x, y, coords.z + 1.0, false)
    if not z then z = coords.z end

    local hash = GetHashKey(model)
    lib.requestModel(hash)
    local obj = CreateObjectNoOffset(hash, x, y, z, true, true, true)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    local netId = ObjToNet(obj)
    SetNetworkIdExistsOnAllMachines(netId, true)

    ladderProps[#ladderProps + 1] = { obj = obj, netId = netId }

    exports.ox_target:addLocalEntity(obj, {{
        name        = 'fd_ladder_pickup_' .. tostring(obj),
        icon        = 'fas fa-hand',
        label       = T('equip_ladder_pickup'),
        distance    = 2.5,
        onSelect    = function()
            for i, entry in ipairs(ladderProps) do
                if entry.obj == obj then
                    exports.ox_target:removeLocalEntity(obj)
                    if DoesEntityExist(obj) then DeleteObject(obj) end
                    table.remove(ladderProps, i)
                    break
                end
            end
            FD.ReturnItem('ladder', 1)
            FD.Notify(T('equip_ladder_picked'), 'inform')
        end,
        canInteract = function() return FD.HasJob() end,
    }})

    TriggerServerEvent('d4rk_fd_utility:sv_removeItemDirect', 'ladder', 1)
    FD.SetCooldown('equip_ladder', 'ladderPlace')
    FD.Notify(T('equip_ladder_placed'), 'success')
    FD.Debug('equipment', 'Leiter platziert: %s', model)
end

-- ─────────────────────────────────────────────
--  Atemschutzmaske
-- ─────────────────────────────────────────────

local function ToggleGasmask()
    if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end
    if not gasmaskActive and not FD.HasItem('gasmask') then
        FD.Notify(T('equip_no_gasmask'), 'error') return
    end

    gasmaskActive = not gasmaskActive
    local ped = PlayerPedId()

    if gasmaskActive then
        for _, comp in ipairs(Config.Equipment.gasmask or {}) do
            SetPedComponentVariation(ped, comp.component, comp.drawable, comp.texture, comp.palette or 0)
        end
        TriggerServerEvent('d4rk_fd_utility:sv_equipGasmask', true)
        FD.Notify(T('equip_gasmask_on'), 'success')
        FD.Debug('equipment', 'Atemschutzmaske an')
    else
        -- Nur Masken-Komponente zurücksetzen (component 1)
        SetPedComponentVariation(ped, 1, 0, 0, 0)
        TriggerServerEvent('d4rk_fd_utility:sv_equipGasmask', false)
        FD.Notify(T('equip_gasmask_off'), 'inform')
        FD.Debug('equipment', 'Atemschutzmaske aus')
    end
end

-- ─────────────────────────────────────────────
--  Radial Menü
-- ─────────────────────────────────────────────

lib.addRadialItem({
    id       = 'fd_equipment_radial',
    label    = 'Equipment',
    icon     = 'fas fa-toolbox',
    onSelect = function()
        if not FD.HasJob() then FD.Notify(T('no_job'), 'error') return end

        local ladderCount = FD.CountItem('ladder')

        local options = {
            {
                title       = thermocamActive and T('equip_thermocam_off') or T('equip_thermocam_on'),
                icon        = 'fas fa-camera',
                description = thermocamActive and T('equip_active') or T('equip_inactive'),
                onSelect    = ToggleThermocam,
            },
            {
                title       = T('equip_extinguisher_toggle'),
                icon        = 'fas fa-fire-extinguisher',
                description = HasPedGotWeapon(PlayerPedId(), GetHashKey(Config.Equipment.extinguisherWeapon or 'WEAPON_FIREEXTINGUISHER'), false)
                              and T('equip_active') or T('equip_inactive'),
                disabled    = not FD.HasItem('fireextinguisher')
                              and not HasPedGotWeapon(PlayerPedId(), GetHashKey(Config.Equipment.extinguisherWeapon or 'WEAPON_FIREEXTINGUISHER'), false),
                onSelect    = ToggleExtinguisher,
            },
            {
                title       = T('equip_ladder_small'),
                icon        = 'fas fa-border-all',
                description = ('Im Inventar: %d'):format(ladderCount),
                disabled    = ladderCount == 0,
                onSelect    = function() PlaceLadder(Config.Props.ladderSmall, T('equip_ladder_small')) end,
            },
            {
                title       = T('equip_ladder_long'),
                icon        = 'fas fa-border-all',
                description = ('Im Inventar: %d'):format(ladderCount),
                disabled    = ladderCount == 0,
                onSelect    = function() PlaceLadder(Config.Props.ladderLong, T('equip_ladder_long')) end,
            },
            {
                title       = gasmaskActive and T('equip_gasmask_off') or T('equip_gasmask_on'),
                icon        = 'fas fa-head-side-mask',
                description = gasmaskActive and T('equip_active') or T('equip_inactive'),
                disabled    = not gasmaskActive and not FD.HasItem('gasmask'),
                onSelect    = ToggleGasmask,
            },
        }

        lib.registerContext({ id = 'fd_equipment_menu', title = 'Equipment', options = options })
        lib.showContext('fd_equipment_menu')
    end,
})

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if thermocamActive then ClearTimecycleModifier() end
    if gasmaskActive then SetPedComponentVariation(PlayerPedId(), 1, 0, 0, 0) end
    for _, entry in ipairs(ladderProps) do
        if DoesEntityExist(entry.obj) then DeleteObject(entry.obj) end
    end
end)

FD.Debug('equipment', 'Equipment Modul geladen')