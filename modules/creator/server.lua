local module = {}
local QBCore = exports['qb-core']:GetCoreObject()

lib.addCommand('createshop', {
    help = 'Create a new vehicle shop',
    restricted = 'group.admin'
}, function(source)
    local success = lib.callback.await('vehicleshop:startShopCreation', source)
    if not success then
        lib.notify(source, {
            title = locale('ui.error'),
            description = 'Failed to start shop creation',
            type = 'error'
        })
    end
end)

lib.callback.register('vehicleshop:startShopCreation', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local isAdmin = QBCore.Functions.HasPermission(source, 'admin')
    if not isAdmin then return false end
    
    TriggerClientEvent('vehicleshop:startCreation', source)
    return true
end)

return module
