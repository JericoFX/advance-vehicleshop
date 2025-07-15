local module = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

lib.callback.register('vehicleshop:createShop', function(source, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    if not data.name or not data.price or not data.locations then
        return false
    end
    
    local requiredLocations = {'entry', 'management', 'spawn', 'camera'}
    for _, loc in ipairs(requiredLocations) do
        if not data.locations[loc] then
            return false
        end
    end
    
    local shops = GlobalState.VehicleShops
    if shops[data.name] then
        return false
    end
    
    return database.createShop(data)
end)

lib.callback.register('vehicleshop:purchaseShop', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shops = GlobalState.VehicleShops
    local shop = shops[shopId]
    
    if not shop then return false end
    if shop.owner then return false end
    
    local money = Player.Functions.GetMoney('bank')
    if money < shop.price then
        money = Player.Functions.GetMoney('cash')
        if money < shop.price then
            return false
        end
        Player.Functions.RemoveMoney('cash', shop.price)
    else
        Player.Functions.RemoveMoney('bank', shop.price)
    end
    
    local citizenid = Player.PlayerData.citizenid
    
    database.updateShop(shopId, 'owner', citizenid)
    database.addEmployee(shopId, citizenid, 4)
    
    return true
end)

lib.callback.register('vehicleshop:getShopData', function(source, shopId)
    local shops = GlobalState.VehicleShops
    return shops[shopId]
end)

lib.callback.register('vehicleshop:isShopOwner', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shops = GlobalState.VehicleShops
    local shop = shops[shopId]
    
    if not shop then return false end
    
    return shop.owner == Player.PlayerData.citizenid
end)

lib.callback.register('vehicleshop:isShopEmployee', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shops = GlobalState.VehicleShops
    local shop = shops[shopId]
    
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    return shop.employees[citizenid] ~= nil
end)

lib.callback.register('vehicleshop:deleteShop', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local isAdmin = QBCore.Functions.HasPermission(source, 'admin')
    if not isAdmin then return false end
    
    MySQL.query.await('DELETE FROM vehicleshops WHERE id = ?', {shopId})
    
    local shops = GlobalState.VehicleShops
    shops[shopId] = nil
    GlobalState.VehicleShops = shops
    
    return true
end)

lib.callback.register('vehicleshop:transferOwnership', function(source, shopId, newOwnerCitizenId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    if shop.owner ~= Player.PlayerData.citizenid then
        return false, 'not_owner'
    end
    
    database.updateShop(shopId, 'owner', newOwnerCitizenId)
    database.removeEmployee(shopId, Player.PlayerData.citizenid)
    database.addEmployee(shopId, newOwnerCitizenId, 4)
    
    return true
end)

return module
