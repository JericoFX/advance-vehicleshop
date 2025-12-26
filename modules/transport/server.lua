local transport = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

local activeTransports = {}
local trailerProtections = {}

local function parseTimestamp(value)
    if not value then return nil end

    if type(value) == 'number' then
        return value
    end

    if type(value) == 'string' then
        local year, month, day, hour, min, sec = value:match('(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)')
        if year then
            return os.time({
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = tonumber(hour),
                min = tonumber(min),
                sec = tonumber(sec)
            })
        end
    end

    return nil
end

function transport.init()
    transport.loadActiveTransports()
    -- Cron job now handles delivery checks
end

function transport.loadActiveTransports()
    local result = MySQL.query.await([[SELECT * FROM vehicleshop_transports WHERE status IN ('pending', 'ready')]])
    if result then
        for _, transport in ipairs(result) do
            local deliveryTimestamp = parseTimestamp(transport.delivery_time)
            local createdTimestamp = parseTimestamp(transport.created_at) or os.time()

            local vehiclesData = json.decode(transport.vehicles)
            if type(vehiclesData) ~= 'table' then
                vehiclesData = {}
            end

            activeTransports[transport.id] = {
                id = transport.id,
                shopId = transport.shop_id,
                playerId = transport.player_id,
                vehicles = vehiclesData,
                totalCost = transport.total_cost,
                transportType = transport.transport_type,
                status = transport.status,
                createdAt = createdTimestamp,
                deliveryTime = transport.delivery_time,
                deliveryTimestamp = deliveryTimestamp
            }
        end
    end
end

-- Removed in favor of cron job

function transport.checkDeliveries()
    local currentTime = os.time()

    for transportId, data in pairs(activeTransports) do
        if data.status == 'pending' and data.deliveryTimestamp and currentTime >= data.deliveryTimestamp then
            transport.completeDelivery(transportId)
        end
    end
end

function transport.completeDelivery(transportId)
    local transportData = activeTransports[transportId]
    if not transportData then return end
    
    for _, vehicle in ipairs(transportData.vehicles or {}) do
        database.addStock(transportData.shopId, vehicle.model, vehicle.price, vehicle.amount)
    end

    MySQL.update.await('UPDATE vehicleshop_transports SET status = ?, completed_at = NOW() WHERE id = ?', {'completed', transportId})

    activeTransports[transportId] = nil

    if transportData.playerId and GetPlayerName(transportData.playerId) then
        TriggerClientEvent('vehicleshop:deliveryCompleted', transportData.playerId, transportData.vehicles)
    end

    lib.logger(transportData.playerId, 'transportDeliveryCompleted', {
        transportId = transportId,
        shopId = transportData.shopId,
        vehicles = transportData.vehicles,
        transportType = transportData.transportType
    })
end

RegisterNetEvent('vehicleshop:createTransport')
AddEventHandler('vehicleshop:createTransport', function(shopId, vehicles, transportType, isExpress)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
    if not isEmployee then return end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    if type(vehicles) ~= 'table' or #vehicles < 1 then
        TriggerClientEvent('vehicleshop:notify', source, 'invalid_request')
        return
    end
    
    if transportType ~= 'delivery' and transportType ~= 'trailer' then
        TriggerClientEvent('vehicleshop:notify', source, 'invalid_request')
        return
    end
    
    isExpress = isExpress == true
    
    local totalCost = 0
    local warehouseStock = GlobalState.WarehouseStock or {}
    local payloadVehicles = {}
    
    for _, vehicle in ipairs(vehicles) do
        if type(vehicle) ~= 'table' or type(vehicle.model) ~= 'string' then
            TriggerClientEvent('vehicleshop:notify', source, 'invalid_request')
            return
        end

        local amount = tonumber(vehicle.amount)
        if not amount or amount < 1 then
            TriggerClientEvent('vehicleshop:notify', source, 'invalid_request')
            return
        end

        amount = math.floor(amount)

        local stockData = warehouseStock[vehicle.model]
        if not stockData or stockData.stock < amount then
            TriggerClientEvent('vehicleshop:notify', source, 'insufficient_stock')
            return
        end
        
        local cost = stockData.currentPrice * amount
        if isExpress then
            cost = cost * Config.Transport.expressCostMultiplier
        end
        
        totalCost = totalCost + cost
        payloadVehicles[#payloadVehicles + 1] = {
            model = vehicle.model,
            amount = amount,
            price = stockData.currentPrice,
            name = stockData.name or vehicle.name or vehicle.model
        }
    end
    
    if shop.funds < totalCost then
        TriggerClientEvent('vehicleshop:notify', source, 'insufficient_funds')
        return
    end

    local deliveryTime = os.time()
    local createdTimestamp = deliveryTime
    local deliveryTimestamp

    if transportType == 'delivery' then
        local delay = (isExpress and Config.Transport.expressDeliveryTime or Config.Transport.deliveryTime) / 1000
        deliveryTimestamp = deliveryTime + math.max(1, math.floor(delay))
    elseif transportType == 'trailer' then
        deliveryTimestamp = deliveryTime + 300
    end

    local createdAt = os.date('%Y-%m-%d %H:%M:%S', createdTimestamp)
    local deliveryAt = deliveryTimestamp and os.date('%Y-%m-%d %H:%M:%S', deliveryTimestamp) or nil

    local transportId = MySQL.insert.await([[
        INSERT INTO vehicleshop_transports (shop_id, player_id, vehicles, total_cost, transport_type, status, created_at, delivery_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        shopId,
        source,
        json.encode(payloadVehicles),
        totalCost,
        transportType,
        transportType == 'delivery' and 'pending' or 'ready',
        createdAt,
        deliveryAt
    })

    if transportId then
        database.updateShop(shopId, 'funds', shop.funds - totalCost)
        shop.funds = (shop.funds or 0) - totalCost

        for _, vehicle in ipairs(payloadVehicles) do
            local stockData = warehouseStock[vehicle.model]
            if stockData then
                stockData.stock = stockData.stock - vehicle.amount
            end
        end
        GlobalState.WarehouseStock = warehouseStock

        local storedVehicles = json.decode(json.encode(payloadVehicles))

        activeTransports[transportId] = {
            id = transportId,
            shopId = shopId,
            playerId = source,
            vehicles = storedVehicles,
            totalCost = totalCost,
            transportType = transportType,
            status = transportType == 'delivery' and 'pending' or 'ready',
            createdAt = createdTimestamp,
            deliveryTime = deliveryAt,
            deliveryTimestamp = deliveryTimestamp
        }

        if transportType ~= 'delivery' then
            TriggerClientEvent('vehicleshop:trailerReady', source, transportId)
        end

        TriggerClientEvent('vehicleshop:notify', source, 'transport_created')
    else
        TriggerClientEvent('vehicleshop:notify', source, 'database_error')
    end
end)

RegisterNetEvent('vehicleshop:unloadTrailer', function(transportId, shopId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local transportData = activeTransports[transportId]
    if not transportData then return end
    
    if transportData.playerId ~= source then return end
    if transportData.shopId ~= shopId then return end
    if transportData.transportType ~= 'trailer' then return end
    if transportData.status ~= 'ready' then return end
    
    local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
    if not isEmployee then return end
    
    for _, vehicle in ipairs(transportData.vehicles or {}) do
        database.addStock(transportData.shopId, vehicle.model, vehicle.price, vehicle.amount)
    end
    
    MySQL.update.await('UPDATE vehicleshop_transports SET status = ?, completed_at = NOW() WHERE id = ?', {'completed', transportId})
    activeTransports[transportId] = nil
    
    TriggerClientEvent('vehicleshop:notify', source, 'trailer_unloaded')
end)

RegisterNetEvent('vehicleshop:protectTrailerOnDisconnect', function(transportId, trailerNetId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    local transportData = activeTransports[transportId]
    if not transportData then return end
    
    if transportData.playerId ~= source then return end
    if transportData.transportType ~= 'trailer' then return end
    
    transportData.trailerNetId = trailerNetId
    transportData.trailerProtectedAt = os.time()
end)

lib.callback.register('vehicleshop:payTrailerCommission', function(source, transportId, totalCost)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'invalid_player' end
    
    local transportData = activeTransports[transportId]
    if not transportData then return false, 'transport_not_found' end
    
    totalCost = transportData.totalCost
    local paymentMethod = Config.Transport.trailerCommission.paymentMethod
    
    if paymentMethod == 'cash' then
        local playerMoney = Player.Functions.GetMoney('cash')
        if playerMoney < totalCost then
            return false, 'insufficient_cash'
        end

        Player.Functions.RemoveMoney('cash', totalCost, 'trailer-commission')

        lib.logger(source, 'payTrailerCommission', {
            transportId = transportId,
            amount = totalCost,
            method = 'cash'
        })

        return true
    elseif paymentMethod == 'shop_funds' then
        local shop = GlobalState.VehicleShops[transportData.shopId]
        if not shop then return false, 'shop_not_found' end

        if shop.funds < totalCost then
            return false, 'insufficient_shop_funds'
        end

        database.updateShop(transportData.shopId, 'funds', shop.funds - totalCost)
        shop.funds = shop.funds - totalCost

        lib.logger(source, 'payTrailerCommission', {
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
    
    local result = MySQL.query.await('SELECT * FROM vehicleshop_transports WHERE id = ? AND player_id = ?', {transportId, source})
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
