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
    
    local vehiclePoint = lib.points.new({
        coords = vehicleData.position,
        distance = Config.ShopTransport.displayRadius,
        onEnter = function()
            lib.showTextUI(locale('vehicles.view_info'))
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        nearby = function()
            if IsControlJustPressed(0, 38) then
                vehicles.showVehicleInfo(vehicle)
            end
        end
    })
    
    displayVehicles[shopId][vehicleData.id] = {
        entity = vehicle,
        model = vehicleData.model,
        position = vehicleData.position,
        props = vehicleData.props,
        point = vehiclePoint
    }
end

function vehicles.removeDisplayVehicle(shopId, displayId)
    if displayVehicles[shopId] and displayVehicles[shopId][displayId] then
        local data = displayVehicles[shopId][displayId]
        
        if DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
        
        if data.point then
            data.point:remove()
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
            if data.point then
                data.point:remove()
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
    lib.showTextUI(locale('vehicles.place_controls'))
    
    local placementDistance = 10.0
    
    CreateThread(function()
        while previewVehicle do
            local camCoords = GetGameplayCamCoord()
            local camRot = GetGameplayCamRot(2)
            local direction = vehicles.rotationToDirection(camRot)
            
            -- Distance control with mouse wheel
            if IsControlJustPressed(0, 241) then -- Mouse wheel up
                placementDistance = math.min(placementDistance + 1.0, 50.0)
            elseif IsControlJustPressed(0, 242) then -- Mouse wheel down
                placementDistance = math.max(placementDistance - 1.0, 5.0)
            end
            
            -- Calculate position based on camera direction and distance
            local coords = vector3(
                camCoords.x + direction.x * placementDistance,
                camCoords.y + direction.y * placementDistance,
                camCoords.z + direction.z * placementDistance
            )
            
            -- Raycast to find ground
            local rayHandle = StartShapeTestRay(
                coords.x, coords.y, coords.z + 10.0,
                coords.x, coords.y, coords.z - 10.0,
                1, previewVehicle, 0
            )
            local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
            
            if hit then
                coords = endCoords
            end
            
            -- Set vehicle position
            SetEntityCoords(previewVehicle, coords.x, coords.y, coords.z + 0.5)
            
            -- Keep vehicle on ground properly
            PlaceObjectOnGroundProperly(previewVehicle)
            local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0)
            if groundZ then
                SetEntityCoords(previewVehicle, coords.x, coords.y, groundZ)
            end
            
            -- Rotation controls
            if IsControlPressed(0, 174) then -- LEFT ARROW
                local heading = GetEntityHeading(previewVehicle)
                SetEntityHeading(previewVehicle, heading - 2.0)
            elseif IsControlPressed(0, 175) then -- RIGHT ARROW
                local heading = GetEntityHeading(previewVehicle)
                SetEntityHeading(previewVehicle, heading + 2.0)
            end
                
                -- Check validity
                local canPlace, reason = vehicles.canPlaceVehicle(previewVehicle, shopId)
                
                -- Update preview color based on validity
                if canPlace then
                    SetEntityAlpha(previewVehicle, 200, false)
                    ResetEntityAlpha(previewVehicle)
                else
                    SetEntityAlpha(previewVehicle, 100, false)
                end
                
                -- Show placement info
                local vehicleCoords = GetEntityCoords(previewVehicle)
                vehicles.drawPlacementInfo(vehicleCoords, canPlace, reason)
                
                -- Place vehicle
                if IsControlJustPressed(0, 38) then -- E
                    if canPlace then
                        local position = {
                            x = vehicleCoords.x,
                            y = vehicleCoords.y,
                            z = vehicleCoords.z,
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
                    else
                        lib.notify({
                            title = locale('ui.error'),
                            description = reason,
                            type = 'error'
                        })
                    end
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
        local currentPrice = lib.callback.await('vehicleshop:getCurrentPrice', false, modelName:lower())
        local shopInfo = lib.callback.await('vehicleshop:getShopInfo', false)
        
        lib.registerContext({
            id = 'vehicle_info',
            title = vehicleData.name or modelName,
            options = {
                {
                    title = locale('vehicles.vehicle_info'),
                    description = locale('vehicles.vehicle_info_desc'),
                    icon = 'info-circle',
                    readOnly = true,
                    metadata = {
                        {label = locale('vehicles.brand'), value = vehicleData.brand or 'Unknown'},
                        {label = locale('vehicles.model'), value = vehicleData.name or modelName},
                        {label = locale('vehicles.category'), value = Config.VehicleCategories[vehicleData.category] or 'Unknown'},
                        {label = locale('vehicles.base_price'), value = '$' .. (vehicleData.price or 0)},
                        {label = locale('vehicles.current_price'), value = '$' .. (currentPrice or vehicleData.price or 0)},
                        {label = locale('vehicles.shop_owner'), value = shopInfo and shopInfo.owner or 'Unknown'}
                    }
                },
                {
                    title = locale('sales.buy_cash'),
                    description = locale('sales.buy_cash_desc', currentPrice or vehicleData.price or 0),
                    icon = 'money-bill',
                    onSelect = function()
                        TriggerEvent('vehicleshop:startPurchase', modelName:lower(), 'cash')
                    end
                },
                {
                    title = locale('sales.finance'),
                    description = locale('sales.finance_desc'),
                    icon = 'credit-card',
                    onSelect = function()
                        TriggerEvent('vehicleshop:startPurchase', modelName:lower(), 'finance')
                    end
                },
                {
                    title = locale('sales.test_drive'),
                    description = locale('sales.test_drive_desc'),
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

function vehicles.rotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

function vehicles.canPlaceVehicle(vehicle, shopId)
    local coords = GetEntityCoords(vehicle)
    local shop = GlobalState.VehicleShops[shopId]
    
    if not shop then
        return false, locale('vehicles.invalid_shop')
    end
    
    -- Check distance from shop center
    local shopCenter = shop.entry or coords
    local distance = #(coords - vector3(shopCenter.x, shopCenter.y, shopCenter.z))
    
    if distance > 100.0 then
        return false, locale('vehicles.too_far_from_shop')
    end
    
    -- Check for nearby vehicles
    local nearbyVehicles = lib.getNearbyVehicles(coords, 5.0)
    for _, nearbyVehicle in ipairs(nearbyVehicles) do
        if nearbyVehicle.vehicle ~= vehicle then
            return false, locale('vehicles.too_close_to_vehicle')
        end
    end
    
    -- Check if on valid ground
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z)
    if not groundZ or math.abs(coords.z - groundZ) > 3.0 then
        return false, locale('vehicles.invalid_ground')
    end
    
    -- Check for obstacles
    local rayHandle = StartShapeTestCapsule(
        coords.x, coords.y, coords.z + 1.0,
        coords.x, coords.y, coords.z - 1.0,
        2.0, 10, vehicle, 7
    )
    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)
    
    if hit and entityHit ~= 0 and entityHit ~= vehicle then
        return false, locale('vehicles.obstacle_detected')
    end
    
    return true, nil
end

function vehicles.drawPlacementInfo(coords, canPlace, reason)
    local color = canPlace and {0, 255, 0, 200} or {255, 0, 0, 200}
    local text = canPlace and locale('vehicles.can_place') or (reason or locale('vehicles.cannot_place'))
    
    -- Draw marker
    DrawMarker(
        1, -- Type
        coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        4.0, 4.0, 0.5,
        color[1], color[2], color[3], color[4],
        false, false, 2, false, nil, nil, false
    )
    
    -- Draw text
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(color[1], color[2], color[3], 255)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

return vehicles
