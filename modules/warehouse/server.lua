local warehouse = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

local vehicleData = nil
local refreshTimer = nil

function warehouse.init()
    warehouse.loadVehicleData()
    warehouse.generateInitialStock()
end

function warehouse.loadVehicleData()
    vehicleData = QBCore.Shared.Vehicles
end

function warehouse.getVehicleData(model)
    return vehicleData[model]
end

function warehouse.generateInitialStock()
    local warehouseStock = {}
    
    for model, data in pairs(vehicleData or {}) do
        if data.shop then
            local basePrice = data.price or 10000
            local variation = math.random(Config.PriceVariation.min, Config.PriceVariation.max) / 100
            local finalPrice = math.floor(basePrice * (1 + variation))
            
            warehouseStock[model] = {
                model = model,
                name = data.name or model,
                brand = data.brand or 'Unknown',
                category = data.category or 'compacts',
                basePrice = basePrice,
                currentPrice = finalPrice,
                stock = math.random(1, 5),
                lastUpdate = os.time()
            }
        end
    end
    
    GlobalState.WarehouseStock = warehouseStock
end

function warehouse.refreshStock()
    local currentStock = GlobalState.WarehouseStock or {}
    local updatedStock = {}
    
    for model, data in pairs(vehicleData or {}) do
        if data.shop then
            local basePrice = data.price or 10000
            local variation = math.random(Config.PriceVariation.min, Config.PriceVariation.max) / 100
            local finalPrice = math.floor(basePrice * (1 + variation))
            
            local existingStock = currentStock[model]
            local newStock = math.random(0, 3)
            
            if existingStock then
                newStock = math.min(5, existingStock.stock + newStock)
            end
            
            updatedStock[model] = {
                model = model,
                name = data.name or model,
                brand = data.brand or 'Unknown',
                category = data.category or 'compacts',
                basePrice = basePrice,
                currentPrice = finalPrice,
                stock = newStock,
                lastUpdate = os.time()
            }
        end
    end
    
    GlobalState.WarehouseStock = updatedStock
    TriggerClientEvent('vehicleshop:warehouseRefreshed', -1)
end

function warehouse.startRefreshTimer()
    if refreshTimer then
        SetTimeout(refreshTimer, function() end)
    end
    
    refreshTimer = SetTimeout(Config.WarehouseRefreshTime, function()
        warehouse.refreshStock()
        warehouse.startRefreshTimer()
    end)
end

lib.callback.register('vehicleshop:getWarehouseStock', function(source, category)
    local stock = GlobalState.WarehouseStock or {}
    
    if category then
        local filtered = {}
        for model, data in pairs(stock) do
            if data.category == category then
                filtered[model] = data
            end
        end
        return filtered
    end
    
    return stock
end)

lib.callback.register('vehicleshop:purchaseFromWarehouse', function(source, shopId, model, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
    if not isEmployee then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local stock = GlobalState.WarehouseStock or {}
    local vehicle = stock[model]
    
    if not vehicle or vehicle.stock < amount then
        return false, 'no_stock'
    end
    
    local totalCost = vehicle.currentPrice * amount
    
    if shop.funds < totalCost then
        return false, 'insufficient_funds'
    end
    
    database.updateShop(shopId, 'funds', shop.funds - totalCost)
    database.addStock(shopId, model, vehicle.currentPrice, amount)
    
    stock[model].stock = stock[model].stock - amount
    GlobalState.WarehouseStock = stock
    
    return true
end)

lib.callback.register('vehicleshop:getWarehouseRefreshTime', function(source)
    return Config.WarehouseRefreshTime
end)

return warehouse
