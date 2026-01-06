local warehouse = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')
local business = lib.require('modules.business.server')

local vehicleData = nil
local refreshTimer = nil
local stockLock = false
local purchaseCooldowns = {}
local PURCHASE_COOLDOWN_SECONDS = 2

local function isOnCooldown(cooldownTable, source, duration)
    local now = os.time()
    local last = cooldownTable[source] or 0
    if now - last < duration then
        return true
    end
    cooldownTable[source] = now
    return false
end

local function isNearShopManagement(source, shop)
    if not shop or not shop.management then
        return false
    end

    local ped = GetPlayerPed(source)
    if not ped then return false end

    local coords = GetEntityCoords(ped)
    local target = shop.management
    local dist = #(coords - vector3(target.x, target.y, target.z))

    return dist <= (Config.ShopTransport and Config.ShopTransport.garageRadius or 3.0)
end

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
        ClearTimeout(refreshTimer)
    end

    refreshTimer = SetTimeout(Config.WarehouseRefreshTime, function()
        warehouse.refreshStock()
        warehouse.startRefreshTimer()
    end)
end

function warehouse.acquireStockLock()
    if stockLock then
        return false
    end
    stockLock = true
    return true
end

function warehouse.releaseStockLock()
    stockLock = false
end

function warehouse.withStockLock(callback)
    if not warehouse.acquireStockLock() then
        return false, 'busy'
    end

    local ok, result1, result2, result3 = pcall(callback)
    warehouse.releaseStockLock()

    if not ok then
        return false, 'error'
    end

    return result1, result2, result3
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

lib.callback.register('vehicleshop:getAvailableVehiclesForTransport', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local citizenid = Player.PlayerData.citizenid
    local shops = GlobalState.VehicleShops or {}
    local isEmployee = false

    for shopId, _ in pairs(shops) do
        if business.getEmployeeRank(citizenid, shopId) > 0 then
            isEmployee = true
            break
        end
    end

    if not isEmployee then
        return {}
    end

    local stock = GlobalState.WarehouseStock or {}
    local available = {}

    for _, data in pairs(stock) do
        if data.stock and data.stock > 0 then
            available[#available + 1] = {
                model = data.model,
                name = data.name or data.model
            }
        end
    end

    return available
end)

lib.callback.register('vehicleshop:purchaseFromWarehouse', function(source, shopId, model, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if isOnCooldown(purchaseCooldowns, source, PURCHASE_COOLDOWN_SECONDS) then
        return false, 'cooldown'
    end

    if type(model) ~= 'string' or model == '' then
        return false, 'invalid_vehicle'
    end
    model = model:lower()

    amount = tonumber(amount)
    if not amount or amount < 1 then
        return false, 'invalid_amount'
    end
    amount = math.floor(amount)

    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    if employeeRank < 1 then return false end

    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    if not isNearShopManagement(source, shop) then return false, 'too_far' end

    local success, reason = warehouse.withStockLock(function()
        local stock = GlobalState.WarehouseStock or {}
        local vehicle = stock[model]

        if not vehicle or vehicle.stock < amount then
            return false, 'no_stock'
        end

        local totalCost = vehicle.currentPrice * amount
        local fundsOk = database.tryAdjustShopFunds(shopId, -totalCost)
        if not fundsOk then
            return false, 'insufficient_funds'
        end

        database.addStock(shopId, model, vehicle.currentPrice, amount)

        stock[model].stock = stock[model].stock - amount
        stock[model].lastUpdate = os.time()
        GlobalState.WarehouseStock = stock

        return true
    end)

    if not success then
        return false, reason
    end

    return true
end)

lib.callback.register('vehicleshop:getWarehouseRefreshTime', function(source)
    return Config.WarehouseRefreshTime
end)

return warehouse
