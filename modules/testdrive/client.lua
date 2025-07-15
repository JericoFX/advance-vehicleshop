local testdrive = {}
local QBCore = exports['qb-core']:GetCoreObject()
local testDriveVehicle = nil
local testDriveTimer = nil
local originalCoords = nil
local originalVehicle = nil
local testDriveActive = false

function testdrive.init()
    testdrive.setupEventHandlers()
end

function testdrive.setupEventHandlers()
    RegisterNetEvent('vehicleshop:startTestDrive', function(model)
        local shops = lib.require('modules.shops.client')
        local shopId = shops.getCurrentShop()
        
        if not shopId then
            lib.notify({
                title = locale('ui.error'),
                description = locale('testdrive.no_shop'),
                type = 'error'
            })
            return
        end
        
        if testDriveActive then
            lib.notify({
                title = locale('ui.error'),
                description = locale('testdrive.already_active'),
                type = 'error'
            })
            return
        end
        
        testdrive.startTestDrive(shopId, model)
    end)
end

function testdrive.startTestDrive(shopId, model)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    originalCoords = GetEntityCoords(cache.ped)
    originalVehicle = cache.vehicle
    
    if originalVehicle then
        SetEntityAsMissionEntity(originalVehicle, true, true)
        SetEntityCoords(originalVehicle, originalCoords.x, originalCoords.y, originalCoords.z)
    end
    
    local spawn = shop.spawn
    local modelHash = GetHashKey(model)
    
    lib.requestModel(modelHash)
    
    testDriveVehicle = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, false)
    
    SetVehicleNumberPlateText(testDriveVehicle, 'TEST')
    SetPedIntoVehicle(cache.ped, testDriveVehicle, -1)
    SetVehicleEngineOn(testDriveVehicle, true, true, false)
    
    -- Notify server about test drive start
    local vehicleNetId = NetworkGetNetworkIdFromEntity(testDriveVehicle)
    TriggerServerEvent('vehicleshop:testDriveStarted', vehicleNetId, model)
    
    testDriveActive = true
    testdrive.startTimer()
    
    lib.notify({
        title = locale('sales.test_drive'),
        description = locale('sales.test_drive_started', Config.MaxTestDriveTime / 60),
        type = 'info'
    })
    
    testdrive.createReturnZone(shop)
end

function testdrive.startTimer()
    local timeRemaining = Config.MaxTestDriveTime
    
    CreateThread(function()
        while testDriveActive and timeRemaining > 0 do
            Wait(1000)
            timeRemaining = timeRemaining - 1
            
            if timeRemaining == 60 then
                lib.notify({
                    title = locale('sales.test_drive'),
                    description = locale('testdrive.one_minute_remaining'),
                    type = 'warning'
                })
            elseif timeRemaining == 30 then
                lib.notify({
                    title = locale('sales.test_drive'),
                    description = locale('testdrive.thirty_seconds_remaining'),
                    type = 'warning'
                })
            elseif timeRemaining == 10 then
                lib.notify({
                    title = locale('sales.test_drive'),
                    description = locale('testdrive.ten_seconds_remaining'),
                    type = 'error'
                })
            elseif timeRemaining == 0 then
                testdrive.endTestDrive(true)
            end
        end
    end)
    
    CreateThread(function()
        while testDriveActive do
            Wait(0)
            
            local minutes = math.floor(timeRemaining / 60)
            local seconds = timeRemaining % 60
            local text = string.format(locale('testdrive.time_remaining'), minutes, seconds)
            
            SetTextFont(4)
            SetTextProportional(1)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 255, 255, 255)
            SetTextDropShadow(0, 0, 0, 0, 255)
            SetTextEdge(2, 0, 0, 0, 255)
            SetTextDropShadow()
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(text)
            DrawText(0.5, 0.95)
            
            if IsControlJustPressed(0, 73) then -- X
                testdrive.showEndConfirmation()
            end
        end
    end)
end

function testdrive.createReturnZone(shop)
    local returnZone = lib.zones.sphere({
        coords = shop.spawn,
        radius = 5.0,
        debug = Config.Debug,
        onEnter = function()
            if testDriveActive and cache.vehicle == testDriveVehicle then
                lib.showTextUI(locale('testdrive.return_vehicle'))
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        inside = function()
            if testDriveActive and cache.vehicle == testDriveVehicle then
                if IsControlJustPressed(0, 38) then -- E
                    testdrive.endTestDrive(false)
                    returnZone:remove()
                end
            end
        end
    })
end

function testdrive.showEndConfirmation()
    local alert = lib.alertDialog({
        header = locale('sales.test_drive'),
        content = locale('testdrive.end_confirm'),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        testdrive.endTestDrive(false)
    end
end

function testdrive.endTestDrive(timeExpired)
    if not testDriveActive then return end
    
    testDriveActive = false
    lib.hideTextUI()
    
    -- Notify server about test drive end
    if testDriveVehicle then
        local vehicleNetId = NetworkGetNetworkIdFromEntity(testDriveVehicle)
        TriggerServerEvent('vehicleshop:testDriveEnded', vehicleNetId, timeExpired and 'expired' or 'returned')
    end
    
    DoScreenFadeOut(500)
    Wait(500)
    
    if DoesEntityExist(testDriveVehicle) then
        DeleteEntity(testDriveVehicle)
    end
    
    SetEntityCoords(cache.ped, originalCoords.x, originalCoords.y, originalCoords.z)
    
    if originalVehicle and DoesEntityExist(originalVehicle) then
        SetPedIntoVehicle(cache.ped, originalVehicle, -1)
    end
    
    DoScreenFadeIn(500)
    
    if timeExpired then
        lib.notify({
            title = locale('sales.test_drive'),
            description = locale('testdrive.time_expired'),
            type = 'error'
        })
    else
        lib.notify({
            title = locale('sales.test_drive'),
            description = locale('sales.test_drive_ended'),
            type = 'success'
        })
    end
    
    testDriveVehicle = nil
    originalCoords = nil
    originalVehicle = nil
end

lib.onCache('vehicle', function(value)
    if testDriveActive and value ~= testDriveVehicle then
        CreateThread(function()
            Wait(1000)
            if testDriveActive and cache.vehicle ~= testDriveVehicle then
                testdrive.endTestDrive(false)
            end
        end)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if testDriveActive then
            testdrive.endTestDrive(false)
        end
    end
end)

return testdrive
