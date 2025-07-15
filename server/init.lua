local QBCore = exports['qb-core']:GetCoreObject()

GlobalState.VehicleShops = GlobalState.VehicleShops or {}
GlobalState.WarehouseStock = GlobalState.WarehouseStock or {}

local modules = {}

local function loadModule(name, path)
    local module = lib.require(path)
    modules[name] = module
    return module
end

loadModule('database', 'modules.database.server')
loadModule('shops', 'modules.shops.server')
loadModule('warehouse', 'modules.warehouse.server')
loadModule('employees', 'modules.employees.server')
loadModule('vehicles', 'modules.vehicles.server')
loadModule('funds', 'modules.funds.server')
loadModule('sales', 'modules.sales.server')
loadModule('finance', 'modules.finance.server')
loadModule('prices', 'modules.prices.server')
loadModule('transport', 'modules.transport.server')

lib.versionCheck('eduardo/advanced-vehicleshop')

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    
    modules.database.init()
    modules.warehouse.init()
    modules.warehouse.startRefreshTimer()
    modules.finance.init()
    modules.transport.init()
    
    print('^2[advanced-vehicleshop]^7 All modules loaded successfully')
end)
