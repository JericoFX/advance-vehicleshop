local vehicles = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')
local business = lib.require('modules.business.server')
local purchaseCooldowns = {}
local PURCHASE_COOLDOWN_SECONDS = 2
local DISPLAY_PROPS_MAX_BYTES = 50000

local function isOnCooldown(cooldownTable, source, duration)
    local now = os.time()
    local last = cooldownTable[source] or 0
    if now - last < duration then
        return true
    end
    cooldownTable[source] = now
    return false
end

local function isNearShopEntry(source, shop)
    if not shop or not shop.entry then
        return false
    end

    local ped = GetPlayerPed(source)
    if not ped then return false end

    local coords = GetEntityCoords(ped)
    local target = shop.entry
    local dist = #(coords - vector3(target.x, target.y, target.z))
    return dist <= (Config.ShopTransport and Config.ShopTransport.displayRadius or 2.0)
end

local function getNearestShop(source)
    local ped = GetPlayerPed(source)
    if not ped then return nil end

    local coords = GetEntityCoords(ped)
    local shops = GlobalState.VehicleShops or {}
    local nearest = nil
    local nearestDist = nil

    for _, shop in pairs(shops) do
        if shop.entry then
            local dist = #(coords - vector3(shop.entry.x, shop.entry.y, shop.entry.z))
            if not nearestDist or dist < nearestDist then
                nearest = shop
                nearestDist = dist
            end
        end
    end

    if nearestDist and nearestDist <= (Config.ShopTransport and Config.ShopTransport.maxDisplayDistance or 100.0) then
        return nearest
    end

    return nil
end

local function matchFinanceOption(financeData)
    if type(financeData) ~= 'table' then
        return nil
    end

    for _, option in ipairs(Config.FinanceOptions or {}) do
        if financeData.label and financeData.label == option.label then
            return option
        end

        if financeData.downPayment and financeData.interest and financeData.months then
            local downMatch = math.abs(financeData.downPayment - option.downPayment) < 0.0001
            local interestMatch = math.abs(financeData.interest - option.interest) < 0.0001
            local monthsMatch = financeData.months == option.months
            if downMatch and interestMatch and monthsMatch then
                return option
            end
        end
    end

    return nil
end

lib.callback.register('vehicleshop:getShopVehicles', function(source, shopId)
    return database.getStock(shopId)
end)

lib.callback.register('vehicleshop:getDisplayVehicles', function(source, shopId)
    return database.getDisplayVehicles(shopId)
end)

lib.callback.register('vehicleshop:addDisplayVehicle', function(source, shopId, model, position)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    
    if employeeRank < 2 then
        return false, 'no_permission'
    end
    
    local stock = database.getStock(shopId)
    local availableStock = 0
    local stockPrice = 0
    
    for _, vehicle in ipairs(stock) do
        if vehicle.model == model then
            availableStock = vehicle.amount
            stockPrice = vehicle.price
            break
        end
    end
    
    if availableStock < 1 then
        return false, 'no_stock'
    end
    
    local displayVehicles = database.getDisplayVehicles(shopId)
    local alreadyOnDisplay = 0
    
    for _, display in ipairs(displayVehicles) do
        if display.model == model then
            alreadyOnDisplay = alreadyOnDisplay + 1
        end
    end
    
    if alreadyOnDisplay >= availableStock then
        return false, 'all_on_display'
    end
    
    local id = database.addDisplayVehicle(shopId, model, position)
    
    if id then
        TriggerClientEvent('vehicleshop:displayVehicleAdded', -1, shopId, {
            id = id,
            model = model,
            position = position,
            price = stockPrice
        })
        return true
    end
    
    return false
end)

lib.callback.register('vehicleshop:removeDisplayVehicle', function(source, shopId, displayId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end

    local display = database.getDisplayVehicleById(displayId)
    if not display or display.shop_id ~= shopId then
        return false, 'invalid_display'
    end
    
    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    
    if employeeRank < 2 then
        return false, 'no_permission'
    end
    
    database.removeDisplayVehicle(displayId)
    TriggerClientEvent('vehicleshop:displayVehicleRemoved', -1, shopId, displayId)
    
    return true
end)

lib.callback.register('vehicleshop:updateVehicleProps', function(source, shopId, displayId, props)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end

    local display = database.getDisplayVehicleById(displayId)
    if not display or display.shop_id ~= shopId then
        return false, 'invalid_display'
    end
    
    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    
    if employeeRank < 2 then
        return false, 'no_permission'
    end

    if type(props) ~= 'table' then
        return false, 'invalid_props'
    end

    local encodedProps = json.encode(props)
    if not encodedProps or #encodedProps > DISPLAY_PROPS_MAX_BYTES then
        return false, 'invalid_props'
    end
    
    MySQL.update.await('UPDATE vehicleshop_display SET props = ? WHERE id = ?', {
        encodedProps,
        displayId
    })
    
    TriggerClientEvent('vehicleshop:displayVehicleUpdated', -1, shopId, displayId, props)
    
    return true
end)

lib.callback.register('vehicleshop:purchaseVehicle', function(source, shopId, model, paymentMethod, financeData)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if isOnCooldown(purchaseCooldowns, source, PURCHASE_COOLDOWN_SECONDS) then
        return false, 'cooldown'
    end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    if not isNearShopEntry(source, shop) then return false, 'too_far' end
    
    local stock = database.getStock(shopId)
    local vehicleStock = nil
    
    for _, vehicle in ipairs(stock) do
        if vehicle.model == model then
            vehicleStock = vehicle
            break
        end
    end
    
    if not vehicleStock or vehicleStock.amount < 1 then
        return false, 'no_stock'
    end
    
    local totalPrice = vehicleStock.price
    local downPayment = totalPrice
    
    if paymentMethod == 'finance' then
        local option = matchFinanceOption(financeData)
        if not option then
            return false, 'invalid_finance'
        end
        financeData = option
        downPayment = math.floor(totalPrice * financeData.downPayment)
        if downPayment < 1 then
            return false, 'invalid_finance'
        end
    end
    
    local hasBank = Player.Functions.GetMoney('bank') >= downPayment
    local hasCash = Player.Functions.GetMoney('cash') >= downPayment
    
    if not hasBank and not hasCash then
        return false, 'no_money'
    end
    
    if hasBank then
        Player.Functions.RemoveMoney('bank', downPayment)
    else
        Player.Functions.RemoveMoney('cash', downPayment)
    end
    
    local removed = database.tryRemoveStock(shopId, model, 1)
    if not removed then
        if hasBank then
            Player.Functions.AddMoney('bank', downPayment)
        else
            Player.Functions.AddMoney('cash', downPayment)
        end
        return false, 'no_stock'
    end
    
    local seller = nil
    for cid, _ in pairs(shop.employees) do
        local emp = QBCore.Functions.GetPlayerByCitizenId(cid)
        if emp and emp.PlayerData.source == source then
            seller = cid
            break
        end
    end
    
    local commissionRate = lib.callback.await('vehicleshop:getCommissionRate', source, shopId)
    local commission = math.floor(totalPrice * commissionRate)
    
    database.tryAdjustShopFunds(shopId, totalPrice - commission)
    
    if seller then
        local sellerPlayer = QBCore.Functions.GetPlayerByCitizenId(seller)
        if sellerPlayer then
            sellerPlayer.Functions.AddMoney('bank', commission)
        end
    end
    
    database.recordSale({
        shopId = shopId,
        seller = seller or 'unknown',
        buyer = Player.PlayerData.citizenid,
        model = model,
        price = totalPrice,
        commission = commission,
        financeData = financeData
    })
    
    local plate = vehicles.generatePlate()
    local vehicleData = QBCore.Shared.Vehicles[model]
    
    MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.license,
        Player.PlayerData.citizenid,
        model,
        GetHashKey(model),
        '{}',
        plate,
        'pillboxgarage',
        1
    })
    
    if paymentMethod == 'finance' and financeData then
        vehicles.createFinanceContract(Player.PlayerData.citizenid, model, plate, financeData)
    end
    
    return true, plate
end)

lib.callback.register('vehicleshop:getCurrentPrice', function(source, model)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if type(model) ~= 'string' or model == '' then
        return false
    end

    local shop = getNearestShop(source)
    if not shop then
        local vehicleData = QBCore.Shared.Vehicles[model]
        return vehicleData and vehicleData.price or 0
    end

    local result = MySQL.query.await('SELECT price FROM vehicleshop_stock WHERE shop_id = ? AND model = ? LIMIT 1', {
        shop.id,
        model
    })

    if result and result[1] then
        return result[1].price
    end

    local vehicleData = QBCore.Shared.Vehicles[model]
    return vehicleData and vehicleData.price or 0
end)

lib.callback.register('vehicleshop:getShopInfo', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    local shop = getNearestShop(source)
    if not shop then
        return nil
    end

    return {
        id = shop.id,
        name = shop.name,
        owner = shop.owner
    }
end)

function vehicles.generatePlate()
    local plate = ''
    local characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    
    for i = 1, #Config.PlateFormat do
        if Config.PlateFormat:sub(i, i) == 'X' then
            local index = math.random(1, #characters)
            plate = plate .. characters:sub(index, index)
        else
            plate = plate .. Config.PlateFormat:sub(i, i)
        end
    end
    
    local result = MySQL.query.await('SELECT plate FROM player_vehicles WHERE plate = ?', {plate})
    if result[1] then
        return vehicles.generatePlate()
    end
    
    return plate
end

function vehicles.createFinanceContract(citizenid, model, plate, financeData)
    local downPayment = math.floor(financeData.totalAmount * financeData.downPayment)
    local nextPaymentDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 30 * 24 * 60 * 60) -- 30 days from now
    
    MySQL.insert.await([[
        INSERT INTO vehicle_financing (citizenid, vehicle, plate, total_amount, down_payment, remaining_amount, monthly_payment, months_total, months_remaining, next_payment)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        model,
        plate,
        financeData.totalAmount,
        downPayment,
        financeData.remainingAmount,
        financeData.monthlyPayment,
        financeData.months,
        financeData.months,
        nextPaymentDate
    })
end

return vehicles
