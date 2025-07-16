local funds = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')
local business = lib.require('modules.business.server')

lib.callback.register('vehicleshop:getShopFunds', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local rank = business.getEmployeeRank(citizenid, shopId)
    
    if rank < 3 then
        return false
    end
    
    return business.getBusinessFunds(shopId)
end)

lib.callback.register('vehicleshop:depositFunds', function(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local rank = business.getEmployeeRank(citizenid, shopId)
    
    if rank < 1 then
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
        if not Player.Functions.RemoveMoney('bank', amount) then
            return false, 'remove_money_failed'
        end
    else
        if not Player.Functions.RemoveMoney('cash', amount) then
            return false, 'remove_money_failed'
        end
    end
    
    if business.updateBusinessFunds(shopId, amount, false) then
        funds.logTransaction(shopId, citizenid, 'deposit', amount)
        return true
    else
        -- Revertir si falló la actualización
        if hasBank then
            Player.Functions.AddMoney('bank', amount)
        else
            Player.Functions.AddMoney('cash', amount)
        end
        return false, 'deposit_failed'
    end
end)

lib.callback.register('vehicleshop:withdrawFunds', function(source, shopId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local rank = business.getEmployeeRank(citizenid, shopId)
    
    if rank < 4 then
        return false, 'no_permission'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'invalid_amount'
    end
    
    local currentFunds = business.getBusinessFunds(shopId)
    if currentFunds < amount then
        return false, 'insufficient_funds'
    end
    
    if business.updateBusinessFunds(shopId, amount, true) then
        Player.Functions.AddMoney('bank', amount)
        funds.logTransaction(shopId, citizenid, 'withdraw', amount)
        return true
    else
        return false, 'withdraw_failed'
    end
end)

lib.callback.register('vehicleshop:getTransactions', function(source, shopId, limit)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local rank = business.getEmployeeRank(citizenid, shopId)
    
    if rank < 3 then
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
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Verificar permisos usando advance-manager
    local fromRank = business.getEmployeeRank(citizenid, fromShopId)
    local toRank = business.getEmployeeRank(citizenid, toShopId)
    
    if fromRank < 4 or toRank < 4 then
        return false, 'no_permission'
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, 'invalid_amount'
    end
    
    local fromFunds = business.getBusinessFunds(fromShopId)
    if fromFunds < amount then
        return false, 'insufficient_funds'
    end
    
    -- Realizar transferencia usando advance-manager
    local withdrawSuccess = business.updateBusinessFunds(fromShopId, amount, true)
    if not withdrawSuccess then
        return false, 'withdraw_failed'
    end
    
    local depositSuccess = business.updateBusinessFunds(toShopId, amount, false)
    if not depositSuccess then
        -- Revertir retiro si falló el depósito
        business.updateBusinessFunds(fromShopId, amount, false)
        return false, 'deposit_failed'
    end
    
    -- Obtener nombres de tiendas para logs
    local fromBusiness = business.getBusinessByShop(fromShopId)
    local toBusiness = business.getBusinessByShop(toShopId)
    
    local fromName = fromBusiness and fromBusiness.name or 'Unknown Shop'
    local toName = toBusiness and toBusiness.name or 'Unknown Shop'
    
    funds.logTransaction(fromShopId, citizenid, 'transfer_out', amount, 'Transfer to ' .. toName)
    funds.logTransaction(toShopId, citizenid, 'transfer_in', amount, 'Transfer from ' .. fromName)
    
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
