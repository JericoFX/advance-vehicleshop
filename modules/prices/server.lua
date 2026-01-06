local prices = {}
local QBCore = exports['qb-core']:GetCoreObject()
local business = lib.require('modules.business.server')

lib.callback.register('vehicleshop:updateVehiclePrice', function(source, shopId, model, newPrice)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end

    if type(model) ~= 'string' or model == '' then
        return false, 'invalid_vehicle'
    end
    model = model:lower()

    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)

    if employeeRank < 3 then
        return false, 'no_permission'
    end
    
    newPrice = tonumber(newPrice)
    if not newPrice or newPrice < 0 then
        return false, 'invalid_price'
    end
    
    local result = MySQL.query.await([[
        SELECT price FROM vehicleshop_stock
        WHERE shop_id = ? AND model = ?
        LIMIT 1
    ]], {shopId, model})

    if not result or not result[1] then
        return false, 'invalid_vehicle'
    end

    local oldPrice = result[1].price

    MySQL.update.await([[
        UPDATE vehicleshop_stock
        SET price = ?
        WHERE shop_id = ? AND model = ?
    ]], {newPrice, shopId, model})

    prices.logPriceChange(shopId, model, oldPrice, newPrice, citizenid)

    TriggerClientEvent('vehicleshop:priceUpdated', -1, shopId, model, newPrice)
    
    return true
end)

lib.callback.register('vehicleshop:getPriceHistory', function(source, shopId, model)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end

    if type(model) ~= 'string' or model == '' then
        return false
    end
    model = model:lower()

    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    if employeeRank < 1 then return false end
    
    local history = MySQL.query.await([[
        SELECT ph.*, p.charinfo
        FROM vehicleshop_price_history ph
        LEFT JOIN players p ON ph.changed_by = p.citizenid
        WHERE ph.shop_id = ? AND ph.model = ?
        ORDER BY ph.changed_at DESC
        LIMIT 20
    ]], {shopId, model})
    
    for _, record in ipairs(history or {}) do
        if record.charinfo then
            local charinfo = json.decode(record.charinfo)
            record.changed_by_name = charinfo.firstname .. ' ' .. charinfo.lastname
        end
    end
    
    return history
end)

function prices.logPriceChange(shopId, model, oldPrice, newPrice, changedBy)
    MySQL.insert.await([[
        INSERT INTO vehicleshop_price_history (shop_id, model, old_price, new_price, changed_by)
        VALUES (?, ?, ?, ?, ?)
    ]], {shopId, model, oldPrice, newPrice, changedBy})
end

MySQL.query([[
    CREATE TABLE IF NOT EXISTS `vehicleshop_price_history` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `shop_id` INT(11) NOT NULL,
        `model` VARCHAR(50) NOT NULL,
        `old_price` INT(11) NOT NULL,
        `new_price` INT(11) NOT NULL,
        `changed_by` VARCHAR(50) NOT NULL,
        `changed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE,
        INDEX `price_history` (`shop_id`, `model`, `changed_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

return prices
