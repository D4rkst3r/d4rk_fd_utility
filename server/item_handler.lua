---------------------------------------------------
--  d4rk_fd_utility – Server Item Handler
---------------------------------------------------

-- Item entfernen (vom Client getriggert nach Nutzung)
RegisterNetEvent('d4rk_fd_utility:sv_removeItem', function(itemName, amount)
    local src = source
    if not Config.UseInventory then return end

    local cfg = Config.Items[itemName]
    if not cfg or not cfg.consume then return end

    exports.ox_inventory:RemoveItem(src, itemName, amount or 1)
    if Config.Debug then
        print(('[d4rk_fd_utility] Item entfernt: %s x%d von Player %d'):format(itemName, amount or 1, src))
    end
end)

-- Airbag-Deaktivierung loggen / für andere Scripte nutzbar
RegisterNetEvent('d4rk_fd_utility:sv_airbagDeactivated', function(netVehicle)
    local src = source
    if Config.Debug then
        print(('[d4rk_fd_utility] Airbag deaktiviert – Player %d, Fahrzeug NetID %d'):format(src, netVehicle))
    end
    -- Hier könnte man z.B. ein Log-Event feuern oder CAD-System informieren
end)


AddEventHandler('playerDropped', function(reason)
    local src = source
    TriggerClientEvent('d4rk_fd_utility:cl_cleanupProps', src)
    if Config.Debug then
        print(('[d4rk_fd_utility] Props cleanup für Player %d (%s)'):format(src, reason))
    end
end)
