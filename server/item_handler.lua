---------------------------------------------------
--  d4rk_fd_utility – Server Item Handler
---------------------------------------------------

-- ─────────────────────────────────────────────
--  Server-seitiger Job-Check
--  Sekundäre Sicherheitsebene gegen Client-Cheats
-- ─────────────────────────────────────────────

local function SvHasJob(src)
    local fw = Config.Framework

    if fw == 'qbx' then
        local player = exports['qbx_core']:GetPlayer(src)
        if not player then return false end
        return Config.Jobs[player.PlayerData.job.name] == true

    elseif fw == 'qb' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return Config.Jobs[player.PlayerData.job.name] == true

    elseif fw == 'esx' then
        local ESX    = exports['es_extended']:getSharedObject()
        local player = ESX.GetPlayerFromId(src)
        if not player then return false end
        return Config.Jobs[player.getJob().name] == true
    end

    return true -- standalone
end

-- ─────────────────────────────────────────────
--  Item entfernen
-- ─────────────────────────────────────────────

RegisterNetEvent('d4rk_fd_utility:sv_removeItem', function(itemName, amount)
    local src = source
    if not Config.UseInventory then return end
    if not SvHasJob(src) then return end

    local cfg = Config.Items[itemName]
    if not cfg or not cfg.consume then return end

    exports.ox_inventory:RemoveItem(src, itemName, amount or 1)
    FD.Debug('Item entfernt: %s x%d von Player %d', itemName, amount or 1, src)
end)

-- ─────────────────────────────────────────────
--  Item zurückgeben (z.B. Prop aufheben)
-- ─────────────────────────────────────────────

RegisterNetEvent('d4rk_fd_utility:sv_returnItem', function(itemName, amount)
    local src = source
    if not Config.UseInventory then return end
    if not SvHasJob(src) then return end

    local cfg = Config.Items[itemName]
    if not cfg then return end

    exports.ox_inventory:AddItem(src, itemName, amount or 1)
    FD.Debug('general', 'Item zurückgegeben: %s x%d an Player %d', itemName, amount or 1, src)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    TriggerClientEvent('d4rk_fd_utility:cl_cleanupProps', src)
    FD.Debug('Props cleanup für Player %d (%s)', src, reason)
end)