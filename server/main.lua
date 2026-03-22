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
