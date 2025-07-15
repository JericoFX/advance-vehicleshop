local sales = {}
local QBCore = exports['qb-core']:GetCoreObject()
local currentPurchase = nil

function sales.init()
    sales.setupEventHandlers()
end

function sales.setupEventHandlers()
    RegisterNetEvent('vehicleshop:startPurchase', function(model, paymentMethod)
        local shops = lib.require('modules.shops.client')
        local shopId = shops.getCurrentShop()
        
        if not shopId then
            lib.notify({
                title = locale('ui.error'),
                description = locale('sales.no_shop_selected'),
                type = 'error'
            })
            return
        end
        
        if paymentMethod == 'cash' then
            sales.purchaseWithCash(shopId, model)
        elseif paymentMethod == 'finance' then
            sales.showFinanceOptions(shopId, model)
        end
    end)
    
    RegisterNetEvent('vehicleshop:showCatalog', function(shopId)
        sales.openCatalog(shopId)
    end)
end

function sales.openCatalog(shopId)
    local stock = lib.callback.await('vehicleshop:getShopVehicles', false, shopId)
    local categories = {}
    local vehiclesByCategory = {}
    
    for _, vehicle in ipairs(stock or {}) do
        local vehicleData = QBCore.Shared.Vehicles[vehicle.model]
        if vehicleData then
            local category = vehicleData.category or 'compacts'
            if not vehiclesByCategory[category] then
                vehiclesByCategory[category] = {}
            end
            table.insert(vehiclesByCategory[category], {
                model = vehicle.model,
                name = vehicleData.name,
                brand = vehicleData.brand,
                price = vehicle.price,
                stock = vehicle.amount
            })
        end
    end
    
    for category, vehicles in pairs(vehiclesByCategory) do
        table.insert(categories, {
            title = Config.VehicleCategories[category] or category,
            description = string.format('%d vehicles available', #vehicles),
            icon = 'car',
            onSelect = function()
                sales.showCategoryVehicles(shopId, category, vehicles)
            end
        })
    end
    
    lib.registerContext({
        id = 'shop_catalog',
        title = locale('sales.title'),
        options = categories
    })
    
    lib.showContext('shop_catalog')
end

function sales.showCategoryVehicles(shopId, category, vehicles)
    local options = {}
    
    for _, vehicle in ipairs(vehicles) do
        table.insert(options, {
            title = vehicle.name,
            description = string.format('%s | %s: $%s | %s: %d',
                vehicle.brand,
                locale('sales.price'),
                vehicle.price,
                locale('warehouse.stock'),
                vehicle.stock
            ),
            icon = 'car',
            disabled = vehicle.stock == 0,
            onSelect = function()
                sales.showVehicleOptions(shopId, vehicle)
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            sales.openCatalog(shopId)
        end
    })
    
    lib.registerContext({
        id = 'shop_category',
        title = Config.VehicleCategories[category],
        options = options
    })
    
    lib.showContext('shop_category')
end

function sales.showVehicleOptions(shopId, vehicle)
    lib.registerContext({
        id = 'vehicle_options',
        title = vehicle.name,
        options = {
            {
                title = locale('vehicles.brand'),
                description = vehicle.brand,
                readOnly = true
            },
            {
                title = locale('sales.price'),
                description = '$' .. vehicle.price,
                readOnly = true
            },
            {
                title = locale('sales.buy_cash'),
                icon = 'money-bill',
                onSelect = function()
                    sales.purchaseWithCash(shopId, vehicle.model)
                end
            },
            {
                title = locale('sales.finance'),
                icon = 'credit-card',
                onSelect = function()
                    sales.showFinanceOptions(shopId, vehicle.model)
                end
            },
            {
                title = locale('sales.test_drive'),
                icon = 'car',
                onSelect = function()
                    TriggerEvent('vehicleshop:startTestDrive', vehicle.model)
                end
            }
        }
    })
    
    lib.showContext('vehicle_options')
end

function sales.purchaseWithCash(shopId, model)
    local alert = lib.alertDialog({
        header = locale('sales.confirm_purchase'),
        content = locale('sales.confirm_cash_purchase'),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        local success, plate = lib.callback.await('vehicleshop:purchaseVehicle', false, shopId, model, 'cash')
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('sales.purchased'),
                type = 'success'
            })
            
            sales.spawnPurchasedVehicle(model, plate)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('sales.' .. (plate or 'purchase_failed')),
                type = 'error'
            })
        end
    end
end

function sales.showFinanceOptions(shopId, model)
    local vehicleData = QBCore.Shared.Vehicles[model]
    if not vehicleData then return end
    
    local price = vehicleData.price or 0
    local options = {}
    
    for _, option in ipairs(Config.FinanceOptions) do
        local downPayment = math.floor(price * option.downPayment)
        local financed = price - downPayment
        local interest = financed * option.interest
        local total = financed + interest
        local monthly = math.floor(total / option.months)
        
        table.insert(options, {
            title = option.label,
            description = string.format(
                'Down: $%s | Monthly: $%s x %d | Total: $%s',
                downPayment,
                monthly,
                option.months,
                total
            ),
            icon = 'credit-card',
            onSelect = function()
                sales.confirmFinance(shopId, model, {
                    downPayment = option.downPayment,
                    interest = option.interest,
                    months = option.months,
                    totalAmount = total,
                    remainingAmount = financed + interest,
                    monthlyPayment = monthly
                })
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            sales.showVehicleOptions(shopId, {
                model = model,
                name = vehicleData.name,
                brand = vehicleData.brand,
                price = price
            })
        end
    })
    
    lib.registerContext({
        id = 'finance_options',
        title = locale('sales.finance'),
        options = options
    })
    
    lib.showContext('finance_options')
end

function sales.confirmFinance(shopId, model, financeData)
    local alert = lib.alertDialog({
        header = locale('sales.confirm_purchase'),
        content = locale('sales.confirm_finance_purchase', financeData.downPayment * 100),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        local success, plate = lib.callback.await('vehicleshop:purchaseVehicle', false, shopId, model, 'finance', financeData)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('sales.purchased'),
                type = 'success'
            })
            
            sales.spawnPurchasedVehicle(model, plate)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('sales.' .. (plate or 'purchase_failed')),
                type = 'error'
            })
        end
    end
end

function sales.spawnPurchasedVehicle(model, plate)
    local shops = GlobalState.VehicleShops
    local shopId = lib.require('modules.shops.client').getCurrentShop()
    
    if not shopId or not shops[shopId] then return end
    
    local spawn = shops[shopId].spawn
    local modelHash = GetHashKey(model)
    
    lib.requestModel(modelHash)
    
    local vehicle = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, false)
    
    SetVehicleNumberPlateText(vehicle, plate)
    SetPedIntoVehicle(cache.ped, vehicle, -1)
    
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    
    lib.notify({
        title = locale('ui.success'),
        description = locale('sales.vehicle_delivered'),
        type = 'success'
    })
end

return sales
