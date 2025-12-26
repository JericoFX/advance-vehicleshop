local transport = {}
local QBCore = exports['qb-core']:GetCoreObject()
local shops = lib.require('modules.shops.client')

local currentTrailer = nil
local currentTruck = nil
local loadedVehicles = {}
local transportData = nil
local isTrailerLowered = false
local trailerZone = nil

function transport.init()
    transport.registerEvents()
end

function transport.registerEvents()
    RegisterNetEvent('vehicleshop:trailerReady', function(transportId)
        transport.showTrailerOptions(transportId)
    end)
    
    RegisterNetEvent('vehicleshop:deliveryCompleted', function(vehicles)
        lib.notify({
            title = locale('transport.delivery_completed'),
            description = locale('transport.vehicles_delivered', #vehicles),
            type = 'success'
        })
    end)
    
    RegisterNetEvent('vehicleshop:notify', function(messageKey)
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.' .. messageKey),
            type = 'error'
        })
    end)
end

function transport.showTrailerOptions(transportId)
    transport.loadTransportData(transportId)
    
    local vehicleCount = 0
    if transportData and transportData.vehicles then
        for _, vehicle in ipairs(transportData.vehicles) do
            vehicleCount = vehicleCount + vehicle.amount
        end
    end
    
    local commission = Config.Transport.trailerCommission
    local totalCost = commission.basePrice + (commission.perVehiclePrice * vehicleCount)
    
    lib.registerContext({
        id = 'trailer_options',
        title = locale('transport.trailer_options'),
        options = {
            {
                title = locale('transport.trailer_info'),
                description = locale('transport.trailer_info_desc'),
                icon = 'info-circle',
                readOnly = true,
                metadata = {
                    {label = locale('transport.vehicle_count'), value = vehicleCount},
                    {label = locale('transport.base_cost'), value = '$' .. commission.basePrice},
                    {label = locale('transport.per_vehicle_cost'), value = '$' .. commission.perVehiclePrice},
                    {label = locale('transport.total_cost'), value = '$' .. totalCost}
                }
            },
            {
                title = locale('transport.spawn_trailer'),
                description = locale('transport.spawn_trailer_desc', totalCost),
                icon = 'truck',
                onSelect = function()
                    transport.confirmTrailerSpawn(transportId, totalCost)
                end
            },
            {
                title = locale('transport.cancel'),
                description = locale('transport.cancel_desc'),
                icon = 'times',
                onSelect = function()
                    lib.hideContext()
                end
            }
        }
    })
    
    lib.showContext('trailer_options')
end

function transport.confirmTrailerSpawn(transportId, totalCost)
    local alert = lib.alertDialog({
        header = locale('transport.confirm_trailer_spawn'),
        content = locale('transport.confirm_trailer_cost', totalCost),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        local success, reason = lib.callback.await('vehicleshop:payTrailerCommission', false, transportId, totalCost)
        
        if success then
            transport.spawnTrailer(transportId)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('transport.' .. (reason or 'payment_failed')),
                type = 'error'
            })
        end
    end
end

function transport.spawnTrailer(transportId)
    local coords = Config.Transport.trailerSpawn
    
    lib.requestModel(Config.Transport.truckModel)
    lib.requestModel(Config.Transport.trailerModel)
    
    currentTruck = CreateVehicle(GetHashKey(Config.Transport.truckModel), coords.x, coords.y, coords.z, coords.w, true, false)
    currentTrailer = CreateVehicle(GetHashKey(Config.Transport.trailerModel), coords.x - 10, coords.y, coords.z, coords.w, true, false)
    
    if currentTruck and currentTrailer then
        SetVehicleNumberPlateText(currentTruck, "SHOP" .. string.sub(tostring(transportId), -4))
        SetVehicleNumberPlateText(currentTrailer, "TRLR" .. string.sub(tostring(transportId), -4))
        
        SetVehicleEngineOn(currentTruck, true, true, false)
        SetVehicleOnGroundProperly(currentTruck)
        SetVehicleOnGroundProperly(currentTrailer)
        
        TaskWarpPedIntoVehicle(cache.ped, currentTruck, -1)
        
        transport.loadTransportData(transportId)
        transport.createTrailerZone()
        
        lib.notify({
            title = locale('transport.trailer_spawned'),
            description = locale('transport.trailer_spawned_desc'),
            type = 'success'
        })
    else
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.spawn_failed'),
            type = 'error'
        })
    end
end

function transport.loadTransportData(transportId)
    local data = lib.callback.await('vehicleshop:getTransportData', false, transportId)
    if data then
        transportData = data
    end
end

function transport.createTrailerZone()
    if not currentTrailer then return end
    
    trailerZone = lib.zones.sphere({
        coords = GetEntityCoords(currentTrailer),
        radius = 5.0,
        debug = Config.Debug,
        onEnter = function()
            lib.showTextUI(locale('transport.trailer_controls'))
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        inside = function()
            if IsControlJustPressed(0, 38) then -- E key
                transport.showTrailerMenu()
            end
        end
    })
end

function transport.showTrailerMenu()
    if not currentTrailer or not transportData then return end
    
    local options = {}
    
    if not isTrailerLowered then
        table.insert(options, {
            title = locale('transport.lower_trailer'),
            description = locale('transport.lower_trailer_desc'),
            icon = 'angle-down',
            onSelect = function()
                transport.lowerTrailer()
            end
        })
    else
        table.insert(options, {
            title = locale('transport.raise_trailer'),
            description = locale('transport.raise_trailer_desc'),
            icon = 'angle-up',
            onSelect = function()
                transport.raiseTrailer()
            end
        })
    end
    
    if isTrailerLowered then
        table.insert(options, {
            title = locale('transport.load_vehicles'),
            description = locale('transport.load_vehicles_desc'),
            icon = 'car',
            onSelect = function()
                transport.showVehicleLoadMenu()
            end
        })
    end
    
    if #loadedVehicles > 0 then
        table.insert(options, {
            title = locale('transport.unload_trailer'),
            description = locale('transport.unload_trailer_desc'),
            icon = 'truck-loading',
            onSelect = function()
                transport.unloadTrailer()
            end
        })
    end
    
    lib.registerContext({
        id = 'trailer_menu',
        title = locale('transport.trailer_menu'),
        options = options
    })
    
    lib.showContext('trailer_menu')
end

function transport.lowerTrailer()
    if not currentTrailer then return end
    
    local trailerModel = GetEntityModel(currentTrailer)
    SetVehicleExtra(currentTrailer, 1, 0)
    
    isTrailerLowered = true
    
    lib.notify({
        title = locale('transport.trailer_lowered'),
        description = locale('transport.trailer_lowered_desc'),
        type = 'success'
    })
end

function transport.raiseTrailer()
    if not currentTrailer then return end
    
    local trailerModel = GetEntityModel(currentTrailer)
    SetVehicleExtra(currentTrailer, 1, 1)
    
    isTrailerLowered = false
    
    lib.notify({
        title = locale('transport.trailer_raised'),
        description = locale('transport.trailer_raised_desc'),
        type = 'success'
    })
end

function transport.showVehicleLoadMenu()
    if not transportData or not isTrailerLowered then return end
    
    local options = {}
    
    for _, vehicle in ipairs(transportData.vehicles) do
        for i = 1, vehicle.amount do
            table.insert(options, {
                title = vehicle.name or vehicle.model,
                description = locale('transport.load_vehicle_desc', vehicle.model),
                icon = 'car',
                onSelect = function()
                    transport.loadVehicle(vehicle.model)
                end
            })
        end
    end
    
    lib.registerContext({
        id = 'vehicle_load_menu',
        title = locale('transport.load_vehicles'),
        options = options
    })
    
    lib.showContext('vehicle_load_menu')
end

function transport.loadVehicle(model)
    if not currentTrailer or #loadedVehicles >= Config.Transport.maxVehiclesPerTrailer then
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.trailer_full'),
            type = 'error'
        })
        return
    end
    
    lib.requestModel(model)
    
    local trailerCoords = GetEntityCoords(currentTrailer)
    local trailerHeading = GetEntityHeading(currentTrailer)
    
    local offsetX = -3.0 + (#loadedVehicles * 2.0)
    local offsetY = 0.0
    local offsetZ = 1.0
    
    local spawnCoords = GetOffsetFromEntityInWorldCoords(currentTrailer, offsetX, offsetY, offsetZ)
    
    local vehicle = CreateVehicle(GetHashKey(model), spawnCoords.x, spawnCoords.y, spawnCoords.z, trailerHeading, true, false)
    
    if vehicle then
        SetVehicleOnGroundProperly(vehicle)
        
        if Config.Transport.freezeVehicles then
            FreezeEntityPosition(vehicle, true)
        end
        
        SetEntityInvincible(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleDoorsLocked(vehicle, 2)
        
        table.insert(loadedVehicles, {
            entity = vehicle,
            model = model,
            netId = NetworkGetNetworkIdFromEntity(vehicle)
        })
        
        lib.notify({
            title = locale('transport.vehicle_loaded'),
            description = locale('transport.vehicle_loaded_desc', GetDisplayNameFromVehicleModel(GetHashKey(model))),
            type = 'success'
        })
    else
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.load_failed'),
            type = 'error'
        })
    end
end

function transport.unloadTrailer()
    if not currentTrailer or #loadedVehicles == 0 then return end
    
    local shopId = shops.getCurrentShop()
    if not shopId then
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.no_shop_selected'),
            type = 'error'
        })
        return
    end
    
    for _, vehicleData in ipairs(loadedVehicles) do
        if DoesEntityExist(vehicleData.entity) then
            DeleteEntity(vehicleData.entity)
        end
    end
    
    if transportData and transportData.id then
        TriggerServerEvent('vehicleshop:unloadTrailer', transportData.id, shopId)
    end
    
    loadedVehicles = {}
    
    lib.notify({
        title = locale('transport.trailer_unloaded'),
        description = locale('transport.trailer_unloaded_desc'),
        type = 'success'
    })
end

function transport.cleanup()
    if currentTruck and DoesEntityExist(currentTruck) then
        DeleteEntity(currentTruck)
    end
    
    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
    end
    
    for _, vehicleData in ipairs(loadedVehicles) do
        if DoesEntityExist(vehicleData.entity) then
            DeleteEntity(vehicleData.entity)
        end
    end
    
    if trailerZone then
        trailerZone:remove()
        trailerZone = nil
    end
    
    currentTruck = nil
    currentTrailer = nil
    loadedVehicles = {}
    transportData = nil
    isTrailerLowered = false
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        transport.cleanup()
    end
end)

AddEventHandler('playerDropped', function()
    if currentTrailer and transportData and transportData.id then
        TriggerServerEvent('vehicleshop:protectTrailerOnDisconnect', transportData.id, NetworkGetNetworkIdFromEntity(currentTrailer))
    end
end)

return transport
