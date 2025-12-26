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

    lib.callback.register('vehicleshop:registerLoadedVehicle', function(source, transportId, vehicleNetId, vehicleModel, props)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport or transport.owner ~= Player.PlayerData.citizenid then
            return false
        end
        
        if type(vehicleModel) ~= 'string' or vehicleModel == '' then
            return false
        end
        
        local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
        if not entity or not DoesEntityExist(entity) then
            return false
        end
        
        if NetworkGetEntityOwner(entity) ~= source then
            return false
        end
        
        transport.loadedVehicles[vehicleNetId] = {
            model = vehicleModel,
            props = props
        }
        
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
    
    lib.callback.register('vehicleshop:unloadVehicleToGround', function(source, transportId, vehicleNetId, vehicleModel)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local transport = activeTransports[transportId]
        if not transport then return false end
        
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, transport.shopId)
        if not isEmployee then return false end
        
        local loaded = transport.loadedVehicles[vehicleNetId]
        if not loaded or loaded.model ~= vehicleModel then
            return false, 'invalid_vehicle'
        end
        
        local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
        if not entity or not DoesEntityExist(entity) then
            return false, 'invalid_vehicle'
        end
        
        if NetworkGetEntityOwner(entity) ~= source then
            return false, 'invalid_vehicle'
        end
        
        -- Create temporary key for the unloaded vehicle
        local keyId = garage.generateKeyId()
        temporaryKeys[keyId] = {
            id = keyId,
            shopId = transport.shopId,
            vehicleModel = vehicleModel,
            vehicleNetId = vehicleNetId,
            transportId = transportId,
            createdBy = Player.PlayerData.citizenid,
            createdAt = os.time(),
            expiresAt = os.time() + (KEY_EXPIRATION_TIME / 1000)
        }
        
        transport.loadedVehicles[vehicleNetId] = nil
        
        -- Give keys to all shop employees
        garage.giveKeysToShopEmployees(transport.shopId, keyId, vehicleModel)
        
        return true, keyId
    end)
    
    lib.callback.register('vehicleshop:storeVehicleInStock', function(source, shopId, vehicleModel, props, keyId, vehicleNetId, transportId)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', source, shopId)
        if not isEmployee then return false end
        
        -- Check if player has valid keys for this vehicle
        local citizenid = Player.PlayerData.citizenid
        local hasValidKey = garage.hasValidKey(citizenid, shopId, vehicleModel, keyId, vehicleNetId)
        
        if not hasValidKey and transportId and vehicleNetId then
            local transport = activeTransports[transportId]
            if transport and transport.owner == citizenid then
                local loaded = transport.loadedVehicles[vehicleNetId]
                if loaded and loaded.model == vehicleModel then
                    transport.loadedVehicles[vehicleNetId] = nil
                    hasValidKey = true
                end
            end
        end
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
        if keyId then
            garage.removeTemporaryKey(shopId, vehicleModel, keyId)
        end
        
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

function garage.hasValidKey(citizenid, shopId, vehicleModel, keyId, vehicleNetId)
    if not keyId or not temporaryKeys[keyId] then
        return false
    end
    
    local key = temporaryKeys[keyId]
    if key.shopId ~= shopId or key.vehicleModel ~= vehicleModel then
        return false
    end
    
    if key.vehicleNetId and vehicleNetId and key.vehicleNetId ~= vehicleNetId then
        return false
    end
    
    if os.time() >= key.expiresAt then
        temporaryKeys[keyId] = nil
        return false
    end
    
    return true
end

function garage.removeTemporaryKey(shopId, vehicleModel, keyId)
    local key = temporaryKeys[keyId]
    if key and key.shopId == shopId and key.vehicleModel == vehicleModel then
        temporaryKeys[keyId] = nil
        garage.notifyKeyRemoval(shopId, keyId, vehicleModel)
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

function garage.cleanupExpiredKeys()
    local currentTime = os.time()
    for keyId, key in pairs(temporaryKeys) do
        if currentTime > key.expiresAt then
            garage.notifyKeyRemoval(key.shopId, keyId, key.vehicleModel)
            temporaryKeys[keyId] = nil
        end
    end
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
    local shops = GlobalState.VehicleShops or {}
    
    -- Send active keys for player's shops
    for keyId, key in pairs(temporaryKeys) do
        local shop = shops[key.shopId]
        if shop and shop.employees and shop.employees[citizenid] and os.time() < key.expiresAt then
            local remainingTime = (key.expiresAt - os.time()) * 1000
            TriggerClientEvent('vehicleshop:receiveTemporaryKey', playerId, keyId, key.vehicleModel, remainingTime)
        end
    end
end

return garage
