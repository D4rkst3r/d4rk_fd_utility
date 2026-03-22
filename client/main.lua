---------------------------------------------------
--  d4rk_fd_utility – Client Main
---------------------------------------------------

-- Prop-Cleanup auf Server-Request
RegisterNetEvent('d4rk_fd_utility:cl_cleanupProps', function()
    FD.ClearAllProps()
end)

-- Resource-Stop: eigene Props aufräumen
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    FD.ClearAllProps()
end)

-- Startup Log
CreateThread(function()
    Wait(1000)
    if Config.Debug then
        FD.Debug('Client geladen – Framework: %s | Inventory: %s | Target: %s',
            Config.Framework,
            tostring(Config.UseInventory),
            tostring(Config.UseTarget)
        )
    end
end)
