local QBCore = exports['qb-core']:GetCoreObject()

local modules = {}

local function loadModule(name, path)
    local module = lib.require(path)
    modules[name] = module
    return module
end

loadModule('shops', 'modules.shops.client')
loadModule('warehouse', 'modules.warehouse.client')
loadModule('creator', 'modules.creator.client')
loadModule('management', 'modules.management.client')
loadModule('vehicles', 'modules.vehicles.client')
loadModule('sales', 'modules.sales.client')
loadModule('testdrive', 'modules.testdrive.client')
loadModule('ui', 'modules.ui.client')

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    
    modules.shops.init()
    modules.warehouse.init()
    modules.vehicles.init()
    modules.sales.init()
    modules.testdrive.init()
    modules.management.init()
    modules.ui.init()
    
    print('^2[advanced-vehicleshop]^7 Client modules loaded')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    
    modules.shops.cleanup()
    modules.warehouse.cleanup()
    modules.vehicles.cleanup()
end)
