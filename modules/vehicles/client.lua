local vehicles = {}
local QBCore = exports['qb-core']:GetCoreObject()
local displayVehicles = {}
local previewVehicle = nil
local vehicleCamera = nil

function vehicles.init()
    vehicles.loadDisplayVehicles()
    vehicles.setupEventHandlers()
end

function vehicles.cleanup()
    vehicles.clearDisplayVehicles()
    vehicles.clearPreview()
end

function vehicles.setupEventHandlers()
    RegisterNetEvent('vehicleshop:displayVehicleAdded', function(shopId, vehicleData)
        vehicles.spawnDisplayVehicle(shopId, vehicleData)
    end)
    
    RegisterNetEvent('vehicleshop:displayVehicleRemoved', function(shopId, displayId)
        vehicles.removeDisplayVehicle(shopId, displayId)
    end)
    
    RegisterNetEvent('vehicleshop:displayVehicleUpdated', function(shopId, displayId, props)
        vehicles.updateDisplayVehicle(shopId, displayId, props)
    end)
end

function vehicles.loadDisplayVehicles()
    local shops = GlobalState.VehicleShops or {}
    
    for shopId, shop in pairs(shops) do
        local displayVehicles = lib.callback.await('vehicleshop:getDisplayVehicles', false, shopId)
        
        for _, vehicle in ipairs(displayVehicles or {}) do
            vehicles.spawnDisplayVehicle(shopId, vehicle)
        end
    end
end

function vehicles.spawnDisplayVehicle(shopId, vehicleData)
    local model = GetHashKey(vehicleData.model)
    
    lib.requestModel(model)
    
    local vehicle = CreateVehicle(model, vehicleData.position.x, vehicleData.position.y, vehicleData.position.z, vehicleData.position.w or 0.0, false, false)
    
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityInvincible(vehicle, true)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleDoorsLocked(vehicle, 2)
    FreezeEntityPosition(vehicle, true)
    SetVehicleNumberPlateText(vehicle, 'DISPLAY')
    
    if vehicleData.props then
        lib.setVehicleProperties(vehicle, vehicleData.props)
    end
    
    if not displayVehicles[shopId] then
        displayVehicles[shopId] = {}
    end
    
    displayVehicles[shopId][vehicleData.id] = {
        entity = vehicle,
        model = vehicleData.model,
        position = vehicleData.position,
        props = vehicleData.props
    }
end

function vehicles.removeDisplayVehicle(shopId, displayId)
    if displayVehicles[shopId] and displayVehicles[shopId][displayId] then
        local vehicle = displayVehicles[shopId][displayId].entity
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
        displayVehicles[shopId][displayId] = nil
    end
end

function vehicles.updateDisplayVehicle(shopId, displayId, props)
    if displayVehicles[shopId] and displayVehicles[shopId][displayId] then
        local vehicle = displayVehicles[shopId][displayId].entity
        if DoesEntityExist(vehicle) then
            lib.setVehicleProperties(vehicle, props)
            displayVehicles[shopId][displayId].props = props
        end
    end
end

function vehicles.clearDisplayVehicles()
    for shopId, vehicles in pairs(displayVehicles) do
        for displayId, data in pairs(vehicles) do
            if DoesEntityExist(data.entity) then
                DeleteEntity(data.entity)
            end
        end
    end
    displayVehicles = {}
end

function vehicles.startPlacementMode(shopId, model)
    local shops = lib.require('modules.shops.client')
    shops.setCurrentShop(shopId)
    
    vehicles.createPreview(model)
    vehicles.enterPlacementMode(shopId, model)
end

function vehicles.createPreview(model)
    local modelHash = GetHashKey(model)
    lib.requestModel(modelHash)
    
    local coords = GetEntityCoords(cache.ped)
    previewVehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, 0.0, false, false)
    
    SetEntityAlpha(previewVehicle, 150, false)
    SetEntityCollision(previewVehicle, false, false)
    FreezeEntityPosition(previewVehicle, true)
    SetVehicleDoorsLocked(previewVehicle, 2)
end

function vehicles.enterPlacementMode(shopId, model)
    lib.showTextUI(locale('vehicles.place_vehicle'))
    
    CreateThread(function()
        while previewVehicle do
            local hit, coords, entity = lib.raycast.fromCamera(511, 4, 100.0)
            
            if hit then
                SetEntityCoords(previewVehicle, coords.x, coords.y, coords.z)
                
                if IsControlPressed(0, 174) then -- LEFT ARROW
                    local heading = GetEntityHeading(previewVehicle)
                    SetEntityHeading(previewVehicle, heading - 2.0)
                elseif IsControlPressed(0, 175) then -- RIGHT ARROW
                    local heading = GetEntityHeading(previewVehicle)
                    SetEntityHeading(previewVehicle, heading + 2.0)
                end
                
                if IsControlJustPressed(0, 38) then -- E
                    local position = {
                        x = coords.x,
                        y = coords.y,
                        z = coords.z,
                        w = GetEntityHeading(previewVehicle)
                    }
                    
                    local success = lib.callback.await('vehicleshop:addDisplayVehicle', false, shopId, model, position)
                    
                    if success then
                        lib.notify({
                            title = locale('ui.success'),
                            description = locale('vehicles.display_added'),
                            type = 'success'
                        })
                    else
                        lib.notify({
                            title = locale('ui.error'),
                            description = locale('vehicles.display_failed'),
                            type = 'error'
                        })
                    end
                    
                    vehicles.clearPreview()
                    lib.hideTextUI()
                    break
                elseif IsControlJustPressed(0, 73) then -- X
                    vehicles.clearPreview()
                    lib.hideTextUI()
                    break
                end
            end
            
            Wait(0)
        end
    end)
end

function vehicles.clearPreview()
    if previewVehicle then
        DeleteEntity(previewVehicle)
        previewVehicle = nil
    end
end

function vehicles.setupCamera(coords, rotation)
    vehicleCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(vehicleCamera, coords.x, coords.y, coords.z)
    SetCamRot(vehicleCamera, rotation.x, rotation.y, rotation.z, 2)
    SetCamActive(vehicleCamera, true)
    RenderScriptCams(true, true, 1000, true, true)
end

function vehicles.destroyCamera()
    if vehicleCamera then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(vehicleCamera, true)
        vehicleCamera = nil
    end
end

function vehicles.showVehicleInfo(vehicle)
    local model = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(model)
    local vehicleData = QBCore.Shared.Vehicles[modelName:lower()]
    
    if vehicleData then
        lib.registerContext({
            id = 'vehicle_info',
            title = vehicleData.name or modelName,
            options = {
                {
                    title = locale('vehicles.brand'),
                    description = vehicleData.brand or 'Unknown',
                    readOnly = true
                },
                {
                    title = locale('vehicles.category'),
                    description = Config.VehicleCategories[vehicleData.category] or 'Unknown',
                    readOnly = true
                },
                {
                    title = locale('vehicles.price'),
                    description = '$' .. (vehicleData.price or 0),
                    readOnly = true
                },
                {
                    title = locale('sales.buy_cash'),
                    icon = 'money-bill',
                    onSelect = function()
                        TriggerEvent('vehicleshop:startPurchase', modelName:lower(), 'cash')
                    end
                },
                {
                    title = locale('sales.finance'),
                    icon = 'credit-card',
                    onSelect = function()
                        TriggerEvent('vehicleshop:startPurchase', modelName:lower(), 'finance')
                    end
                },
                {
                    title = locale('sales.test_drive'),
                    icon = 'car',
                    onSelect = function()
                        TriggerEvent('vehicleshop:startTestDrive', modelName:lower())
                    end
                }
            }
        })
        
        lib.showContext('vehicle_info')
    end
end

return vehicles
