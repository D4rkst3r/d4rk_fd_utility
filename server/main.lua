---------------------------------------------------
--  d4rk_fd_utility – Server Main
---------------------------------------------------

-- HINWEIS: ox_inventory Items werden NICHT zur Laufzeit registriert.
-- Trag alle Items aus items_for_ox_inventory.lua manuell in
-- ox_inventory/data/items.lua ein. Eine fertige Vorlage liegt
-- im Resource-Ordner unter: items_for_ox_inventory.lua

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('^2[d4rk_fd_utility]^7 Resource gestartet – Version 1.0.0')

    -- Aktive Module loggen
    for module, active in pairs(Config.Modules) do
        if active then
            print(('[d4rk_fd_utility] Modul aktiv: ^3%s^7'):format(module))
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('^1[d4rk_fd_utility]^7 Resource gestoppt')
end)

-- ─────────────────────────────────────────────
--  Scene Prop Tracking
--  Damit andere FD-Spieler Props aufheben können
-- ─────────────────────────────────────────────

local sceneRegistry = {}   -- { [netId] = { src, category, label, item } }

RegisterNetEvent('d4rk_fd_utility:sv_registerSceneProp', function(netId, category, label, item)
    local src = source
    sceneRegistry[netId] = { src = src, category = category, label = label, item = item }
    TriggerClientEvent('d4rk_fd_utility:cl_scenePropSync', -1, netId, category, label, item, src)
    FD.Debug('general', 'Scene Prop registriert: NetID %d von Player %d (%s)', netId, src, label)
end)

RegisterNetEvent('d4rk_fd_utility:sv_removeSceneProp', function(netId)
    local src    = source
    local entry  = sceneRegistry[netId]
    if not entry then return end

    -- Item zurückgeben an den der aufhebt
    if entry.item and Config.UseInventory then
        exports.ox_inventory:AddItem(src, entry.item, 1)
        FD.Debug('general', 'Item zurück: %s an Player %d', entry.item, src)
    end

    sceneRegistry[netId] = nil
    TriggerClientEvent('d4rk_fd_utility:cl_scenePropSync', -1, netId, nil, nil, nil, nil)
end)

-- Neuer Spieler → alle aktiven Props schicken
AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(2000, function()
        for netId, entry in pairs(sceneRegistry) do
            TriggerClientEvent('d4rk_fd_utility:cl_scenePropSync', src, netId, entry.category, entry.label, entry.item, entry.src)
        end
    end)
end)

-- Disconnect → Props des Spielers aus Registry entfernen
AddEventHandler('playerDropped', function()
    local src = source
    for netId, entry in pairs(sceneRegistry) do
        if entry.src == src then
            sceneRegistry[netId] = nil
            TriggerClientEvent('d4rk_fd_utility:cl_scenePropSync', -1, netId, nil, nil, nil, nil)
        end
    end
end)