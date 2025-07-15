local funds = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

lib.callback.register('vehicleshop:getShopFunds', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false
    end
    
    return shop.funds
end)

lib.callback.register('vehicleshop:depositFunds', function(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee then
        return false, 'not_employee'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'invalid_amount'
    end
    
    local hasBank = Player.Functions.GetMoney('bank') >= amount
    local hasCash = Player.Functions.GetMoney('cash') >= amount
    
    if not hasBank and not hasCash then
        return false, 'no_money'
    end
    
    if hasBank then
        Player.Functions.RemoveMoney('bank', amount)
    else
        Player.Functions.RemoveMoney('cash', amount)
    end
    
    database.updateShop(shopId, 'funds', shop.funds + amount)
    
    funds.logTransaction(shopId, citizenid, 'deposit', amount)
    
    return true
end)

lib.callback.register('vehicleshop:withdrawFunds', function(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    
    if shop.owner ~= citizenid then
        local employee = shop.employees[citizenid]
        if not employee or employee.rank < 4 then
            return false, 'no_permission'
        end
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'invalid_amount'
    end
    
    if shop.funds < amount then
        return false, 'insufficient_funds'
    end
    
    database.updateShop(shopId, 'funds', shop.funds - amount)
    Player.Functions.AddMoney('bank', amount)
    
    funds.logTransaction(shopId, citizenid, 'withdraw', amount)
    
    return true
end)

lib.callback.register('vehicleshop:getTransactions', function(source, shopId, limit)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false
    end
    
    return funds.getTransactionHistory(shopId, limit)
end)

function funds.logTransaction(shopId, citizenid, type, amount, description)
    MySQL.insert.await([[
        INSERT INTO vehicleshop_transactions (shop_id, citizenid, type, amount, description)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        shopId,
        citizenid,
        type,
        amount,
        description or ''
    })
end

function funds.getTransactionHistory(shopId, limit)
    return MySQL.query.await([[
        SELECT t.*, p.charinfo
        FROM vehicleshop_transactions t
        LEFT JOIN players p ON t.citizenid = p.citizenid
        WHERE t.shop_id = ?
        ORDER BY t.created_at DESC
        LIMIT ?
    ]], {shopId, limit or 50})
end

lib.callback.register('vehicleshop:transferFunds', function(source, fromShopId, toShopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local fromShop = GlobalState.VehicleShops[fromShopId]
    local toShop = GlobalState.VehicleShops[toShopId]
    
    if not fromShop or not toShop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    
    if fromShop.owner ~= citizenid then
        return false, 'not_owner'
    end
    
    if toShop.owner ~= citizenid then
        return false, 'not_owner'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'invalid_amount'
    end
    
    if fromShop.funds < amount then
        return false, 'insufficient_funds'
    end
    
    database.updateShop(fromShopId, 'funds', fromShop.funds - amount)
    database.updateShop(toShopId, 'funds', toShop.funds + amount)
    
    funds.logTransaction(fromShopId, citizenid, 'transfer_out', amount, 'Transfer to ' .. toShop.name)
    funds.logTransaction(toShopId, citizenid, 'transfer_in', amount, 'Transfer from ' .. fromShop.name)
    
    return true
end)

MySQL.query([[
    CREATE TABLE IF NOT EXISTS `vehicleshop_transactions` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `shop_id` INT(11) NOT NULL,
        `citizenid` VARCHAR(50) NOT NULL,
        `type` VARCHAR(20) NOT NULL,
        `amount` INT(11) NOT NULL,
        `description` VARCHAR(255) DEFAULT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE,
        INDEX `shop_transactions` (`shop_id`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

return funds
