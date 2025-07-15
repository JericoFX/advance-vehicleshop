local transport = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

local activeTransports = {}
local trailerProtections = {}

function transport.init()
    transport.loadActiveTransports()
    transport.startDeliveryTimer()
end

function transport.loadActiveTransports()
    local result = MySQL.query.await('SELECT * FROM vehicleshop_transports WHERE status = ?', {'pending'})
    if result then
        for _, transport in ipairs(result) do
            activeTransports[transport.id] = {
                id = transport.id,
                shopId = transport.shop_id,
                playerId = transport.player_id,
                vehicles = json.decode(transport.vehicles),
                totalCost = transport.total_cost,
                transportType = transport.transport_type,
                status = transport.status,
                createdAt = transport.created_at,
                deliveryTime = transport.delivery_time
            }
        end
    end
end

function transport.startDeliveryTimer()
    CreateThread(function()
        while true do
            Wait(60000)
            transport.checkDeliveries()
        end
    end)
end

function transport.checkDeliveries()
    local currentTime = os.time()
    
    for transportId, data in pairs(activeTransports) do
        if data.status == 'pending' and currentTime >= data.deliveryTime then
            transport.completeDelivery(transportId)
        end
    end
end

function transport.completeDelivery(transportId)
    local transportData = activeTransports[transportId]
    if not transportData then return end
    
    for _, vehicle in ipairs(transportData.vehicles) do
        database.addStock(transportData.shopId, vehicle.model, vehicle.price, vehicle.amount)
    end
    
    MySQL.update.await('UPDATE vehicleshop_transports SET status = ? WHERE id = ?', {'completed', transportId})
    
    activeTransports[transportId] = nil
    
    TriggerClientEvent('vehicleshop:deliveryCompleted', transportData.playerId, transportData.vehicles)
end

RegisterNetEvent('vehicleshop:createTransport')
AddEventHandler('vehicleshop:createTransport', function(shopId, vehicles, transportType, isExpress)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local employees = lib.require('modules.employees.server')
    local isEmployee = employees.isShopEmployee(source, shopId)
    if not isEmployee then return end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    local totalCost = 0
    local totalVehicles = 0
    local warehouseStock = GlobalState.WarehouseStock or {}
    
    for _, vehicle in ipairs(vehicles) do
        local stockData = warehouseStock[vehicle.model]
        if not stockData or stockData.stock < vehicle.amount then
            TriggerClientEvent('vehicleshop:notify', source, 'insufficient_stock')
            return
        end
        
        local cost = stockData.currentPrice * vehicle.amount
        if isExpress then
            cost = cost * Config.Transport.expressCostMultiplier
        end
        
        totalCost = totalCost + cost
        totalVehicles = totalVehicles + vehicle.amount
    end
    
    if shop.funds < totalCost then
        TriggerClientEvent('vehicleshop:notify', source, 'insufficient_funds')
        return
    end
    
    local deliveryTime = os.time()
    if transportType == 'delivery' then
        deliveryTime = deliveryTime + (isExpress and Config.Transport.expressDeliveryTime or Config.Transport.deliveryTime) / 1000
    elseif transportType == 'trailer' then
        deliveryTime = deliveryTime + 300
    end
    
    local transportId = MySQL.insert.await([[
        INSERT INTO vehicleshop_transports (shop_id, player_id, vehicles, total_cost, transport_type, status, created_at, delivery_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        shopId,
        Player.PlayerData.source,
        json.encode(vehicles),
        totalCost,
        transportType,
        transportType == 'delivery' and 'pending' or 'ready',
        os.time(),
        deliveryTime
    })
    
    if transportId then
        database.updateShop(shopId, 'funds', shop.funds - totalCost)
        
        for _, vehicle in ipairs(vehicles) do
            warehouseStock[vehicle.model].stock = warehouseStock[vehicle.model].stock - vehicle.amount
        end
        GlobalState.WarehouseStock = warehouseStock
        
        if transportType == 'delivery' then
            activeTransports[transportId] = {
                id = transportId,
                shopId = shopId,
                playerId = Player.PlayerData.source,
                vehicles = vehicles,
                totalCost = totalCost,
                transportType = transportType,
                status = 'pending',
                createdAt = os.time(),
                deliveryTime = deliveryTime
            }
        else
            -- Trailer handling here
            TriggerClientEvent('vehicleshop:trailerReady', source, transportId)
        end
        
        TriggerClientEvent('vehicleshop:notify', source, 'transport_created')
    else
        TriggerClientEvent('vehicleshop:notify', source, 'database_error')
    end
end)

lib.callback.register('vehicleshop:payTrailerCommission', function(source, transportId, totalCost)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'invalid_player' end
    
    local paymentMethod = Config.Transport.trailerCommission.paymentMethod
    
    if paymentMethod == 'cash' then
        local playerMoney = Player.Functions.GetMoney('cash')
        if playerMoney < totalCost then
            return false, 'insufficient_cash'
        end
        
        Player.Functions.RemoveMoney('cash', totalCost, 'trailer-commission')
        
        lib.logger(Player.PlayerData.source, 'payTrailerCommission', {
            transportId = transportId,
            amount = totalCost,
            method = 'cash'
        })
        
        return true
    elseif paymentMethod == 'shop_funds' then
        local transportData = activeTransports[transportId]
        if not transportData then return false, 'transport_not_found' end
        
        local shop = GlobalState.VehicleShops[transportData.shopId]
        if not shop then return false, 'shop_not_found' end
        
        if shop.funds < totalCost then
            return false, 'insufficient_shop_funds'
        end
        
        database.updateShop(transportData.shopId, 'funds', shop.funds - totalCost)
        
        lib.logger(Player.PlayerData.source, 'payTrailerCommission', {
            transportId = transportId,
            shopId = transportData.shopId,
            amount = totalCost,
            method = 'shop_funds'
        })
        
        return true
    end
    
    return false, 'invalid_payment_method'
end)

lib.callback.register('vehicleshop:getTransportData', function(source, transportId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end
    
    local result = MySQL.query.await('SELECT * FROM vehicleshop_transports WHERE id = ? AND player_id = ?', {transportId, Player.PlayerData.source})
    if result and result[1] then
        local data = result[1]
        return {
            id = data.id,
            shopId = data.shop_id,
            vehicles = json.decode(data.vehicles),
            totalCost = data.total_cost,
            transportType = data.transport_type,
            status = data.status
        }
    end
    
    return nil
end)

return transport
