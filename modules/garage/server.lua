local garage = {}
local QBCore = exports['qb-core']:GetCoreObject()

-- Active transport vehicles tracking
local activeTransports = {}
-- Temporary vehicle keys for unloaded vehicles
local temporaryKeys = {}

-- Key expiration time (30 minutes)
local KEY_EXPIRATION_TIME = 30 * 60 * 1000

function garage.init()
    garage.registerCallbacks()
    garage.startKeyCleanupTimer()
end

function garage.registerCallbacks()
    lib.callback.register('vehicleshop:spawnTransportVehicle', function(source, shopId, vehicleType)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local citizenid = Player.PlayerData.citizenid
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
        
        if not isEmployee then
            return false, 'not_employee'
        end
        
        -- Check if player already has an active transport
        if garage.hasActiveTransport(citizenid) then
            return false, 'already_has_transport'
        end
        
        -- Create transport record
        local transportId = garage.generateTransportId()
        activeTransports[transportId] = {
            id = transportId,
            shopId = shopId,
            owner = citizenid,
            vehicleType = vehicleType,
            spawnedBy = source,
            spawnTime = os.time(),
            netIds = {},
            loadedVehicles = {}
        }
        
        return true, transportId
    end)
    
    lib.callback.register('vehicleshop:registerTransportVehicle', function(source, transportId, vehicleNetId, vehicleType)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport or transport.owner ~= Player.PlayerData.citizenid then
            return false
        end
        
        transport.netIds[vehicleType] = vehicleNetId
        return true
    end)
    
    lib.callback.register('vehicleshop:canAccessTransport', function(source, transportId)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport then return false end
        
        -- Check if player is the owner or an employee of the shop
        local citizenid = Player.PlayerData.citizenid
        if transport.owner == citizenid then
            return true
        end
        
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, transport.shopId)
        return isEmployee
    end)
    
    lib.callback.register('vehicleshop:unloadVehicleToGround', function(source, transportId, vehicleModel)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport then return false end
        
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, transport.shopId)
        if not isEmployee then return false end
        
        -- Create temporary key for the unloaded vehicle
        local keyId = garage.generateKeyId()
        temporaryKeys[keyId] = {
            id = keyId,
            shopId = transport.shopId,
            vehicleModel = vehicleModel,
            createdBy = Player.PlayerData.citizenid,
            createdAt = os.time(),
            expiresAt = os.time() + (KEY_EXPIRATION_TIME / 1000)
        }
        
        -- Give keys to all shop employees
        garage.giveKeysToShopEmployees(transport.shopId, keyId, vehicleModel)
        
        return true, keyId
    end)
    
    lib.callback.register('vehicleshop:storeVehicleInStock', function(source, shopId, vehicleModel, props)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
        if not isEmployee then return false end
        
        -- Check if player has valid keys for this vehicle
        local hasValidKey = garage.hasValidKey(Player.PlayerData.citizenid, shopId, vehicleModel)
        if not hasValidKey then
            return false, 'no_valid_keys'
        end
        
        -- Store vehicle in shop stock
        local database = lib.require('modules.database.server')
        local vehicleData = QBCore.Shared.Vehicles[vehicleModel]
        if not vehicleData then return false end
        
        local currentPrice = vehicleData.price -- You can integrate with price system here
        database.addStock(shopId, vehicleModel, currentPrice, 1)
        
        -- Remove temporary key after successful storage
        garage.removeTemporaryKey(shopId, vehicleModel)
        
        return true
    end)
    
    lib.callback.register('vehicleshop:getActiveTransports', function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return {} end
        
        local citizenid = Player.PlayerData.citizenid
        local userTransports = {}
        
        for transportId, transport in pairs(activeTransports) do
            if transport.owner == citizenid then
                table.insert(userTransports, {
                    id = transportId,
                    shopId = transport.shopId,
                    vehicleType = transport.vehicleType,
                    spawnTime = transport.spawnTime,
                    loadedVehicles = transport.loadedVehicles
                })
            end
        end
        
        return userTransports
    end)
    
    lib.callback.register('vehicleshop:removeTransport', function(source, transportId)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport or transport.owner ~= Player.PlayerData.citizenid then
            return false
        end
        
        -- Clean up transport
        activeTransports[transportId] = nil
        
        -- Remove any associated temporary keys
        garage.removeTransportKeys(transport.shopId)
        
        return true
    end)
end

function garage.hasActiveTransport(citizenid)
    for _, transport in pairs(activeTransports) do
        if transport.owner == citizenid then
            return true
        end
    end
    return false
end

function garage.generateTransportId()
    return 'transport_' .. math.random(100000, 999999) .. '_' .. os.time()
end

function garage.generateKeyId()
    return 'key_' .. math.random(100000, 999999) .. '_' .. os.time()
end

function garage.giveKeysToShopEmployees(shopId, keyId, vehicleModel)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    for citizenid, employee in pairs(shop.employees) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if Player then
            TriggerClientEvent('vehicleshop:receiveTemporaryKey', Player.PlayerData.source, keyId, vehicleModel, KEY_EXPIRATION_TIME)
        end
    end
end

function garage.hasValidKey(citizenid, shopId, vehicleModel)
    for keyId, key in pairs(temporaryKeys) do
        if key.shopId == shopId and key.vehicleModel == vehicleModel then
            -- Check if key is still valid (not expired)
            if os.time() < key.expiresAt then
                return true
            else
                -- Remove expired key
                temporaryKeys[keyId] = nil
            end
        end
    end
    return false
end

function garage.removeTemporaryKey(shopId, vehicleModel)
    for keyId, key in pairs(temporaryKeys) do
        if key.shopId == shopId and key.vehicleModel == vehicleModel then
            temporaryKeys[keyId] = nil
            
            -- Notify employees that key was removed
            garage.notifyKeyRemoval(shopId, keyId, vehicleModel)
            break
        end
    end
end

function garage.removeTransportKeys(shopId)
    for keyId, key in pairs(temporaryKeys) do
        if key.shopId == shopId then
            temporaryKeys[keyId] = nil
            garage.notifyKeyRemoval(shopId, keyId, key.vehicleModel)
        end
    end
end

function garage.notifyKeyRemoval(shopId, keyId, vehicleModel)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    for citizenid, employee in pairs(shop.employees) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if Player then
            TriggerClientEvent('vehicleshop:removeTemporaryKey', Player.PlayerData.source, keyId, vehicleModel)
        end
    end
end

function garage.startKeyCleanupTimer()
    CreateThread(function()
        while true do
            Wait(5 * 60 * 1000) -- Check every 5 minutes
            
            local currentTime = os.time()
            for keyId, key in pairs(temporaryKeys) do
                if currentTime > key.expiresAt then
                    garage.notifyKeyRemoval(key.shopId, keyId, key.vehicleModel)
                    temporaryKeys[keyId] = nil
                end
            end
        end
    end)
end

-- Handle player disconnection
RegisterNetEvent('QBCore:Server:PlayerUnloaded', function(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Mark transports as disconnected but don't remove them
    for transportId, transport in pairs(activeTransports) do
        if transport.owner == citizenid then
            transport.ownerDisconnected = true
            transport.disconnectedAt = os.time()
        end
    end
end)

-- Handle player connection
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Restore access to transports
    for transportId, transport in pairs(activeTransports) do
        if transport.owner == citizenid and transport.ownerDisconnected then
            transport.ownerDisconnected = false
            transport.disconnectedAt = nil
            
            -- Notify client about restored transport
            TriggerClientEvent('vehicleshop:restoreTransport', playerId, transportId, transport)
        end
    end
    
    -- Send active temporary keys to player
    garage.sendActiveKeysToPlayer(playerId, citizenid)
end)

function garage.sendActiveKeysToPlayer(playerId, citizenid)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return end
    
    -- Find all shops where player is an employee
    local playerShops = {}
    for shopId, shop in pairs(GlobalState.VehicleShops) do
        if shop.employees[citizenid] then
            playerShops[shopId] = true
        end
    end
    
    -- Send active keys for player's shops
    for keyId, key in pairs(temporaryKeys) do
        if playerShops[key.shopId] and os.time() < key.expiresAt then
            local remainingTime = (key.expiresAt - os.time()) * 1000
            TriggerClientEvent('vehicleshop:receiveTemporaryKey', playerId, keyId, key.vehicleModel, remainingTime)
        end
    end
end

return garage
