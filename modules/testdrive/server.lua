local testdrive = {}
local QBCore = exports['qb-core']:GetCoreObject()

local activeTestDrives = {}

function testdrive.init()
    testdrive.setupEventHandlers()
    testdrive.startCleanupTimer()
end

function testdrive.setupEventHandlers()
    RegisterNetEvent('QBCore:Server:PlayerUnloaded', function(playerId)
        local Player = QBCore.Functions.GetPlayer(playerId)
        if not Player then return end
        
        local citizenid = Player.PlayerData.citizenid
        if activeTestDrives[citizenid] then
            testdrive.handleDisconnect(citizenid, playerId)
        end
    end)
    
    RegisterNetEvent('vehicleshop:testDriveStarted', function(vehicleNetId, model)
        local source = source
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        
        activeTestDrives[Player.PlayerData.citizenid] = {
            vehicleNetId = vehicleNetId,
            model = model,
            startTime = os.time(),
            playerId = source
        }
        
        lib.logger(source, 'testDriveStarted', {
            model = model,
            vehicleNetId = vehicleNetId
        })
    end)
    
    RegisterNetEvent('vehicleshop:testDriveEnded', function(vehicleNetId, reason)
        local source = source
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end

        local citizenid = Player.PlayerData.citizenid
        local testDriveData = activeTestDrives[citizenid]

        if testDriveData then
            activeTestDrives[citizenid] = nil

            lib.logger(source, 'testDriveEnded', {
                reason = reason,
                duration = os.time() - testDriveData.startTime,
                model = testDriveData.model,
                vehicleNetId = testDriveData.vehicleNetId
            })
        end
    end)
end

function testdrive.handleDisconnect(citizenid, playerId)
    local testDriveData = activeTestDrives[citizenid]
    if not testDriveData then return end
    
    -- Try to delete the vehicle if it still exists
    local vehicle = NetworkGetEntityFromNetworkId(testDriveData.vehicleNetId)
    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
    
    activeTestDrives[citizenid] = nil
    
    lib.logger(playerId, 'testDriveDisconnect', {
        model = testDriveData.model,
        duration = os.time() - testDriveData.startTime
    })
end

function testdrive.startCleanupTimer()
    lib.cron.new('*/5 * * * *', function()
        local currentTime = os.time()
        
        for citizenid, data in pairs(activeTestDrives) do
            -- Clean up test drives older than max time + 5 minutes
            if currentTime - data.startTime > (Config.MaxTestDriveTime + 300) then
                local vehicle = NetworkGetEntityFromNetworkId(data.vehicleNetId)
                if DoesEntityExist(vehicle) then
                    DeleteEntity(vehicle)
                end
                
                activeTestDrives[citizenid] = nil
                
                lib.logger(data.playerId, 'testDriveCleanup', {
                    model = data.model,
                    duration = currentTime - data.startTime
                })
            end
        end
    end)
end

lib.callback.register('vehicleshop:getActiveTestDrives', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end
    
    -- Admin only
    if not QBCore.Functions.HasPermission(source, 'admin') then
        return {}
    end
    
    local testDrives = {}
    for citizenid, data in pairs(activeTestDrives) do
        local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        table.insert(testDrives, {
            citizenid = citizenid,
            name = player and player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname or 'Unknown',
            model = data.model,
            duration = os.time() - data.startTime,
            vehicleNetId = data.vehicleNetId
        })
    end
    
    return testDrives
end)

return testdrive
