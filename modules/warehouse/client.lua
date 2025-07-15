local warehouse = {}
local QBCore = exports['qb-core']:GetCoreObject()
local warehouseZone = nil
local insideWarehouse = false
local warehouseCamera = nil

function warehouse.init()
    warehouse.createZone()
end

function warehouse.cleanup()
    if warehouseZone then
        warehouseZone:remove()
        warehouseZone = nil
    end
    if insideWarehouse then
        warehouse.exitWarehouse()
    end
end

function warehouse.createZone()
    warehouseZone = lib.zones.sphere({
        coords = Config.Warehouse.entry,
        radius = 3.0,
        debug = Config.Debug,
        onEnter = function()
            lib.showTextUI(locale('warehouse.enter'))
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        inside = function()
            if IsControlJustPressed(0, 38) then
                warehouse.enterWarehouse()
            end
        end
    })
end

function warehouse.enterWarehouse()
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(cache.ped, Config.Warehouse.exit.x, Config.Warehouse.exit.y, Config.Warehouse.exit.z)
    SetEntityHeading(cache.ped, Config.Warehouse.exit.w)
    
    insideWarehouse = true
    warehouse.setupCamera()
    warehouse.createExitZone()
    
    DoScreenFadeIn(500)
    warehouse.openWarehouseMenu()
end

function warehouse.exitWarehouse()
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(cache.ped, Config.Warehouse.entry.x, Config.Warehouse.entry.y, Config.Warehouse.entry.z)
    SetEntityHeading(cache.ped, Config.Warehouse.entry.w)
    
    insideWarehouse = false
    warehouse.destroyCamera()
    
    DoScreenFadeIn(500)
end

function warehouse.setupCamera()
    warehouseCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(warehouseCamera, Config.Warehouse.camera.start.x, Config.Warehouse.camera.start.y, Config.Warehouse.camera.start.z)
    SetCamRot(warehouseCamera, Config.Warehouse.camera.rotation.x, Config.Warehouse.camera.rotation.y, Config.Warehouse.camera.rotation.z, 2)
    SetCamActive(warehouseCamera, true)
    RenderScriptCams(true, true, 1000, true, true)
end

function warehouse.destroyCamera()
    if warehouseCamera then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(warehouseCamera, true)
        warehouseCamera = nil
    end
end

function warehouse.createExitZone()
    local exitZone = lib.zones.sphere({
        coords = Config.Warehouse.exit,
        radius = 2.0,
        debug = Config.Debug,
        onEnter = function()
            lib.showTextUI(locale('warehouse.exit'))
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        inside = function()
            if IsControlJustPressed(0, 38) then
                warehouse.exitWarehouse()
                exitZone:remove()
            end
        end
    })
end

function warehouse.openWarehouseMenu()
    local stock = lib.callback.await('vehicleshop:getWarehouseStock', false)
    local categories = {}
    
    for category, label in pairs(Config.VehicleCategories) do
        table.insert(categories, {
            title = label,
            description = locale('warehouse.category_description'),
            icon = 'car',
            onSelect = function()
                warehouse.showCategoryVehicles(category)
            end
        })
    end
    
    lib.registerContext({
        id = 'warehouse_menu',
        title = locale('warehouse.title'),
        options = categories
    })
    
    lib.showContext('warehouse_menu')
end

function warehouse.showCategoryVehicles(category)
    local stock = lib.callback.await('vehicleshop:getWarehouseStock', false, category)
    local options = {}
    
    for model, data in pairs(stock) do
        table.insert(options, {
            title = data.name,
            description = string.format('%s | %s: $%s | %s: %d', 
                data.brand, 
                locale('warehouse.price'), 
                data.currentPrice,
                locale('warehouse.stock'),
                data.stock
            ),
            icon = 'car',
            disabled = data.stock == 0,
            onSelect = function()
                warehouse.previewVehicle(model, data)
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            warehouse.openWarehouseMenu()
        end
    })
    
    lib.registerContext({
        id = 'warehouse_category',
        title = Config.VehicleCategories[category],
        options = options
    })
    
    lib.showContext('warehouse_category')
end

function warehouse.previewVehicle(model, data)
    local shopId = lib.require('modules.shops.client').getCurrentShop()
    if not shopId then
        lib.notify({
            title = locale('ui.error'),
            description = locale('warehouse.no_shop_selected'),
            type = 'error'
        })
        return
    end
    
    local input = lib.inputDialog(locale('warehouse.purchase'), {
        {
            type = 'number',
            label = locale('warehouse.amount'),
            description = locale('warehouse.amount_description'),
            default = 1,
            min = 1,
            max = data.stock
        }
    })
    
    if input then
        local amount = input[1]
        local success, reason = lib.callback.await('vehicleshop:purchaseFromWarehouse', false, shopId, model, amount)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('warehouse.purchased', amount, data.name),
                type = 'success'
            })
            warehouse.showCategoryVehicles(data.category)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('warehouse.' .. (reason or 'purchase_failed')),
                type = 'error'
            })
        end
    end
end

RegisterNetEvent('vehicleshop:warehouseRefreshed', function()
    lib.notify({
        title = locale('warehouse.title'),
        description = locale('warehouse.stock_refreshed'),
        type = 'info'
    })
end)

return warehouse
