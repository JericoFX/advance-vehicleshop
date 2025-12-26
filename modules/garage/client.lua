local garage = {}
local QBCore = exports['qb-core']:GetCoreObject()

local shopZones = {}
local currentShopId = nil
local currentTransportVehicle = nil
local currentTrailer = nil
local loadedVehicles = {}
local isTrailerLowered = false
local currentTransportId = nil
local temporaryKeys = {}

function garage.init()
    garage.loadShopZones()
    garage.registerEvents()
end

function garage.cleanup()
    garage.clearZones()
    garage.clearTransportVehicles()
end

function garage.loadShopZones()
    local shops = GlobalState.VehicleShops or {}
    
    for shopId, shop in pairs(shops) do
        if shop.garage or shop.unload or shop.stock then
            garage.createShopZones(shopId, shop)
        end
    end
end

function garage.createShopZones(shopId, shop)
    if not shopZones[shopId] then
        shopZones[shopId] = {}
    end
    
    if shop.garage then
        shopZones[shopId].garage = lib.zones.sphere({
            coords = shop.garage,
            radius = Config.ShopTransport.garageRadius,
            debug = Config.Debug,
            onEnter = function()
                currentShopId = shopId
                lib.showTextUI(locale('garage.access_garage'))
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustPressed(0, 38) then
                    garage.openGarageMenu(shopId)
                end
            end
        })
    end
    
    if shop.unload then
        shopZones[shopId].unload = lib.zones.sphere({
            coords = shop.unload,
            radius = Config.ShopTransport.unloadRadius,
            debug = Config.Debug,
            onEnter = function()
                currentShopId = shopId
                if currentTransportVehicle then
                    lib.showTextUI(locale('garage.unload_vehicle'))
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustPressed(0, 38) and currentTransportVehicle then
                    garage.showUnloadMenu()
                end
            end
        })
    end
    
    if shop.stock then
        shopZones[shopId].stock = lib.zones.sphere({
            coords = shop.stock,
            radius = Config.ShopTransport.stockRadius,
            debug = Config.Debug,
            onEnter = function()
                currentShopId = shopId
                local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0)
                if vehicle and not garage.isTransportVehicle(vehicle) then
                    lib.showTextUI(locale('garage.store_vehicle'))
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustPressed(0, 38) then
                    garage.storeVehicleInStock(shopId)
                end
            end
        })
    end
end

function garage.clearZones()
    for shopId, zones in pairs(shopZones) do
        for _, zone in pairs(zones) do
            if zone then
                zone:remove()
            end
        end
    end
    shopZones = {}
end

function garage.registerEvents()
    RegisterNetEvent('vehicleshop:shopUpdated', function(shopId, shop)
        if shopZones[shopId] then
            for _, zone in pairs(shopZones[shopId]) do
                if zone then
                    zone:remove()
                end
            end
        end
        garage.createShopZones(shopId, shop)
    end)
    
    RegisterNetEvent('vehicleshop:transportVehicleSpawned', function(vehicleData)
        lib.notify({
            title = locale('garage.vehicle_spawned'),
            description = locale('garage.vehicle_spawned_desc'),
            type = 'success'
        })
    end)
end

function garage.openGarageMenu(shopId)
    local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', false, shopId)
    if not isEmployee then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.not_employee'),
            type = 'error'
        })
        return
    end
    
    local options = {}
    
    if not currentTransportVehicle then
        table.insert(options, {
            title = locale('garage.spawn_trailer'),
            description = locale('garage.spawn_trailer_desc'),
            icon = 'truck',
            onSelect = function()
                garage.spawnTrailer(shopId)
            end
        })
        
        table.insert(options, {
            title = locale('garage.spawn_flatbed'),
            description = locale('garage.spawn_flatbed_desc'),
            icon = 'truck-pickup',
            onSelect = function()
                garage.spawnFlatbed(shopId)
            end
        })
    else
        table.insert(options, {
            title = locale('garage.store_transport'),
            description = locale('garage.store_transport_desc'),
            icon = 'warehouse',
            onSelect = function()
                garage.storeTransportVehicle()
            end
        })
        
        if currentTrailer then
            table.insert(options, {
                title = locale('garage.trailer_controls'),
                description = locale('garage.trailer_controls_desc'),
                icon = 'cog',
                onSelect = function()
                    garage.showTrailerControls()
                end
            })
        end
    end
    
    lib.registerContext({
        id = 'garage_menu',
        title = locale('garage.title'),
        options = options
    })
    
    lib.showContext('garage_menu')
end

function garage.spawnTrailer(shopId)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop or not shop.garage then return end
    
    local success, transportId = lib.callback.await('vehicleshop:spawnTransportVehicle', false, shopId, 'trailer')
    if not success then
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.spawn_failed'),
            type = 'error'
        })
        return
    end
    
    currentTransportId = transportId
    
    local coords = shop.garage
    local spawnOffset = vector3(5.0, 0.0, 0.0)
    
    lib.requestModel(Config.Transport.truckModel)
    lib.requestModel(Config.Transport.trailerModel)
    
    currentTransportVehicle = CreateVehicle(GetHashKey(Config.Transport.truckModel), coords.x + spawnOffset.x, coords.y + spawnOffset.y, coords.z, coords.w, true, false)
    currentTrailer = CreateVehicle(GetHashKey(Config.Transport.trailerModel), coords.x + spawnOffset.x - 10.0, coords.y + spawnOffset.y, coords.z, coords.w, true, false)
    
    if currentTransportVehicle and currentTrailer then
        SetVehicleNumberPlateText(currentTransportVehicle, "SHOP")
        SetVehicleNumberPlateText(currentTrailer, "TRLR")
        
        SetVehicleEngineOn(currentTransportVehicle, true, true, false)
        SetVehicleOnGroundProperly(currentTransportVehicle)
        SetVehicleOnGroundProperly(currentTrailer)
        
        TaskWarpPedIntoVehicle(cache.ped, currentTransportVehicle, -1)
        
        lib.callback.await('vehicleshop:registerTransportVehicle', false, currentTransportId, NetworkGetNetworkIdFromEntity(currentTransportVehicle), 'truck')
        lib.callback.await('vehicleshop:registerTransportVehicle', false, currentTransportId, NetworkGetNetworkIdFromEntity(currentTrailer), 'trailer')
        
        lib.notify({
            title = locale('garage.trailer_spawned'),
            description = locale('garage.trailer_spawned_desc'),
            type = 'success'
        })
    else
        if currentTransportId then
            lib.callback.await('vehicleshop:removeTransport', false, currentTransportId)
        end
        currentTransportId = nil
    end
end

function garage.spawnFlatbed(shopId)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop or not shop.garage then return end
    
    local success, transportId = lib.callback.await('vehicleshop:spawnTransportVehicle', false, shopId, 'flatbed')
    if not success then
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.spawn_failed'),
            type = 'error'
        })
        return
    end
    
    currentTransportId = transportId
    
    local coords = shop.garage
    local spawnOffset = vector3(5.0, 0.0, 0.0)
    
    lib.requestModel(Config.Transport.flatbedModel)
    
    currentTransportVehicle = CreateVehicle(GetHashKey(Config.Transport.flatbedModel), coords.x + spawnOffset.x, coords.y + spawnOffset.y, coords.z, coords.w, true, false)
    
    if currentTransportVehicle then
        SetVehicleNumberPlateText(currentTransportVehicle, "SHOP")
        SetVehicleEngineOn(currentTransportVehicle, true, true, false)
        SetVehicleOnGroundProperly(currentTransportVehicle)
        
        TaskWarpPedIntoVehicle(cache.ped, currentTransportVehicle, -1)
        
        lib.callback.await('vehicleshop:registerTransportVehicle', false, currentTransportId, NetworkGetNetworkIdFromEntity(currentTransportVehicle), 'flatbed')
        
        lib.notify({
            title = locale('garage.flatbed_spawned'),
            description = locale('garage.flatbed_spawned_desc'),
            type = 'success'
        })
    else
        if currentTransportId then
            lib.callback.await('vehicleshop:removeTransport', false, currentTransportId)
        end
        currentTransportId = nil
    end
end

function garage.storeTransportVehicle()
    if currentTransportVehicle then
        DeleteEntity(currentTransportVehicle)
        currentTransportVehicle = nil
    end
    
    if currentTrailer then
        DeleteEntity(currentTrailer)
        currentTrailer = nil
    end
    
    garage.clearLoadedVehicles()
    isTrailerLowered = false
    
    if currentTransportId then
        lib.callback.await('vehicleshop:removeTransport', false, currentTransportId)
        currentTransportId = nil
    end
    
    lib.notify({
        title = locale('garage.vehicle_stored'),
        description = locale('garage.vehicle_stored_desc'),
        type = 'success'
    })
end

function garage.showTrailerControls()
    local options = {}
    
    if not isTrailerLowered then
        table.insert(options, {
            title = locale('garage.lower_trailer'),
            description = locale('garage.lower_trailer_desc'),
            icon = 'angle-down',
            onSelect = function()
                garage.lowerTrailer()
            end
        })
    else
        table.insert(options, {
            title = locale('garage.raise_trailer'),
            description = locale('garage.raise_trailer_desc'),
            icon = 'angle-up',
            onSelect = function()
                garage.raiseTrailer()
            end
        })
    end
    
    if isTrailerLowered then
        table.insert(options, {
            title = locale('garage.load_warehouse_vehicle'),
            description = locale('garage.load_warehouse_vehicle_desc'),
            icon = 'car',
            onSelect = function()
                garage.loadVehicleFromWarehouse()
            end
        })
    end
    
    lib.registerContext({
        id = 'trailer_controls',
        title = locale('garage.trailer_controls'),
        options = options
    })
    
    lib.showContext('trailer_controls')
end

function garage.lowerTrailer()
    if not currentTrailer then return end
    
    SetVehicleExtra(currentTrailer, 1, 0)
    isTrailerLowered = true
    
    lib.notify({
        title = locale('garage.trailer_lowered'),
        description = locale('garage.trailer_lowered_desc'),
        type = 'success'
    })
end

function garage.raiseTrailer()
    if not currentTrailer then return end
    
    SetVehicleExtra(currentTrailer, 1, 1)
    isTrailerLowered = false
    
    lib.notify({
        title = locale('garage.trailer_raised'),
        description = locale('garage.trailer_raised_desc'),
        type = 'success'
    })
end

function garage.loadVehicleFromWarehouse()
    local availableVehicles = lib.callback.await('vehicleshop:getAvailableVehiclesForTransport', false)
    
    if not availableVehicles or #availableVehicles == 0 then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.no_vehicles_available'),
            type = 'error'
        })
        return
    end
    
    local options = {}
    
    for _, vehicle in ipairs(availableVehicles) do
        table.insert(options, {
            title = vehicle.name,
            description = locale('garage.load_vehicle_desc', vehicle.model),
            icon = 'car',
            onSelect = function()
                garage.loadVehicleOnTransport(vehicle.model)
            end
        })
    end
    
    lib.registerContext({
        id = 'load_vehicle_menu',
        title = locale('garage.load_vehicle'),
        options = options
    })
    
    lib.showContext('load_vehicle_menu')
end

function garage.loadVehicleOnTransport(model)
    if not currentTransportVehicle then return end
    if not currentTransportId then return end
    
    local maxVehicles = currentTrailer and Config.Transport.maxVehiclesPerTrailer or 1
    if #loadedVehicles >= maxVehicles then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.transport_full'),
            type = 'error'
        })
        return
    end
    
    lib.requestModel(model)
    
    local coords = GetEntityCoords(currentTransportVehicle)
    local heading = GetEntityHeading(currentTransportVehicle)
    
    local offsetX = currentTrailer and -3.0 + (#loadedVehicles * 2.0) or 0.0
    local offsetY = currentTrailer and 0.0 or -5.0
    local offsetZ = currentTrailer and 1.0 or 1.5
    
    local spawnCoords = GetOffsetFromEntityInWorldCoords(currentTransportVehicle, offsetX, offsetY, offsetZ)
    
    local vehicle = CreateVehicle(GetHashKey(model), spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
    
    if vehicle then
        SetVehicleOnGroundProperly(vehicle)
        
        if Config.Transport.freezeVehicles then
            FreezeEntityPosition(vehicle, true)
        end
        
        SetEntityInvincible(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleDoorsLocked(vehicle, 2)
        
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        table.insert(loadedVehicles, {
            entity = vehicle,
            model = model,
            netId = netId,
            props = lib.getVehicleProperties(vehicle)
        })
        
    local registered = lib.callback.await('vehicleshop:registerLoadedVehicle', false, currentTransportId, netId, model, loadedVehicles[#loadedVehicles].props)
    if not registered then
        DeleteEntity(vehicle)
        table.remove(loadedVehicles, #loadedVehicles)
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.load_failed'),
            type = 'error'
        })
        return
    end
        
        lib.notify({
            title = locale('garage.vehicle_loaded'),
            description = locale('garage.vehicle_loaded_desc', GetDisplayNameFromVehicleModel(GetHashKey(model))),
            type = 'success'
        })
    end
end

function garage.showUnloadMenu()
    if #loadedVehicles == 0 then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.no_vehicles_to_unload'),
            type = 'error'
        })
        return
    end
    
    local options = {}
    
    -- Opción para descargar todos directo al stock
    if #loadedVehicles > 1 then
        table.insert(options, {
            title = locale('garage.unload_all_to_stock'),
            description = locale('garage.unload_all_to_stock_desc', #loadedVehicles),
            icon = 'boxes',
            onSelect = function()
                garage.unloadAllToStock()
            end
        })
    end
    
    -- Opciones individuales para cada vehículo
    for i, vehicleData in ipairs(loadedVehicles) do
        local vehicleName = GetDisplayNameFromVehicleModel(GetHashKey(vehicleData.model))
        
        table.insert(options, {
            title = vehicleName,
            description = locale('garage.choose_unload_method'),
            icon = 'car',
            onSelect = function()
                garage.showVehicleUnloadOptions(i, vehicleName)
            end
        })
    end
    
    lib.registerContext({
        id = 'unload_vehicle_menu',
        title = locale('garage.unload_vehicle'),
        options = options
    })
    
    lib.showContext('unload_vehicle_menu')
end

function garage.showVehicleUnloadOptions(index, vehicleName)
    local options = {
        {
            title = locale('garage.unload_to_ground'),
            description = locale('garage.unload_to_ground_desc'),
            icon = 'car',
            onSelect = function()
                garage.unloadSpecificVehicle(index)
            end
        },
        {
            title = locale('garage.unload_to_stock'),
            description = locale('garage.unload_to_stock_desc'),
            icon = 'warehouse',
            onSelect = function()
                garage.sendVehicleToStock(index, vehicleName)
            end
        }
    }

    lib.registerContext({
        id = 'vehicle_unload_options',
        title = vehicleName,
        options = options
    })
    
    lib.showContext('vehicle_unload_options')
end

function garage.unloadSpecificVehicle(index)
    local vehicleData = loadedVehicles[index]
    if not vehicleData then return end
    if not currentTransportId then return end
    
    local shop = GlobalState.VehicleShops[currentShopId]
    if not shop or not shop.unload then return end
    
    local ok, keyId = lib.callback.await('vehicleshop:unloadVehicleToGround', false, currentTransportId, vehicleData.netId, vehicleData.model)
    if not ok then
        lib.notify({
            title = locale('ui.error'),
            description = locale('transport.load_failed'),
            type = 'error'
        })
        return
    end
    
    temporaryKeys[vehicleData.netId] = keyId
    
    if DoesEntityExist(vehicleData.entity) then
        local coords = shop.unload
        local spawnOffset = vector3(math.random(-3, 3), math.random(-3, 3), 0.0)
        
        SetEntityCoords(vehicleData.entity, coords.x + spawnOffset.x, coords.y + spawnOffset.y, coords.z)
        SetEntityHeading(vehicleData.entity, coords.w)
        
        FreezeEntityPosition(vehicleData.entity, false)
        SetEntityInvincible(vehicleData.entity, false)
        SetVehicleDoorsLocked(vehicleData.entity, 1)
        
        lib.notify({
            title = locale('garage.vehicle_unloaded'),
            description = locale('garage.vehicle_unloaded_desc', GetDisplayNameFromVehicleModel(GetHashKey(vehicleData.model))),
            type = 'success'
        })
    end
    
    table.remove(loadedVehicles, index)
end

function garage.unloadAllToStock()
    for index, vehicleData in ipairs(loadedVehicles) do
        local vehicleName = GetDisplayNameFromVehicleModel(GetHashKey(vehicleData.model))
        garage.sendVehicleToStock(index, vehicleName)
    end
    loadedVehicles = {}
end

function garage.sendVehicleToStock(index, vehicleName)
    local vehicleData = loadedVehicles[index]
    if not vehicleData then return end
    
    local keyId = temporaryKeys[vehicleData.netId]
    local success = lib.callback.await('vehicleshop:storeVehicleInStock', false, currentShopId, vehicleData.model, vehicleData.props, keyId, vehicleData.netId, currentTransportId)
    
    if success and DoesEntityExist(vehicleData.entity) then
        DeleteEntity(vehicleData.entity)
        temporaryKeys[vehicleData.netId] = nil
        lib.notify({
            title = locale('garage.vehicle_stored_stock'),
            description = locale('garage.vehicle_stored_stock_desc', vehicleName),
            type = 'success'
        })
    else
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.store_failed'),
            type = 'error'
        })
    end

    table.remove(loadedVehicles, index)
end

function garage.storeVehicleInStock(shopId)
    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0)
    if not vehicle then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.no_vehicle_nearby'),
            type = 'error'
        })
        return
    end
    
    if garage.isTransportVehicle(vehicle) then
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.cannot_store_transport'),
            type = 'error'
        })
        return
    end
    
    local model = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(model)
    local props = lib.getVehicleProperties(vehicle)
    
    local success = lib.callback.await('vehicleshop:storeVehicleInStock', false, shopId, modelName:lower(), props, nil, nil, nil)
    
    if success then
        DeleteEntity(vehicle)
        lib.notify({
            title = locale('garage.vehicle_stored_stock'),
            description = locale('garage.vehicle_stored_stock_desc', modelName),
            type = 'success'
        })
    else
        lib.notify({
            title = locale('ui.error'),
            description = locale('garage.store_failed'),
            type = 'error'
        })
    end
end

function garage.isTransportVehicle(vehicle)
    return vehicle == currentTransportVehicle or vehicle == currentTrailer
end

function garage.clearLoadedVehicles()
    for _, vehicleData in ipairs(loadedVehicles) do
        if DoesEntityExist(vehicleData.entity) then
            DeleteEntity(vehicleData.entity)
        end
    end
    loadedVehicles = {}
end

function garage.clearTransportVehicles()
    if currentTransportVehicle and DoesEntityExist(currentTransportVehicle) then
        DeleteEntity(currentTransportVehicle)
    end
    
    if currentTrailer and DoesEntityExist(currentTrailer) then
        DeleteEntity(currentTrailer)
    end
    
    garage.clearLoadedVehicles()
    
    currentTransportVehicle = nil
    currentTrailer = nil
    isTrailerLowered = false
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        garage.cleanup()
    end
end)

return garage
