local vehicles = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

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
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 2 then
        return false, 'no_permission'
    end
    
    local stock = database.getStock(shopId)
    local hasStock = false
    
    for _, vehicle in ipairs(stock) do
        if vehicle.model == model and vehicle.amount > 0 then
            hasStock = true
            break
        end
    end
    
    if not hasStock then
        return false, 'no_stock'
    end
    
    local id = database.addDisplayVehicle(shopId, model, position)
    
    if id then
        TriggerClientEvent('vehicleshop:displayVehicleAdded', -1, shopId, {
            id = id,
            model = model,
            position = position
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
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 2 then
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
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 2 then
        return false, 'no_permission'
    end
    
    MySQL.update.await('UPDATE vehicleshop_display SET props = ? WHERE id = ?', {
        json.encode(props),
        displayId
    })
    
    TriggerClientEvent('vehicleshop:displayVehicleUpdated', -1, shopId, displayId, props)
    
    return true
end)

lib.callback.register('vehicleshop:purchaseVehicle', function(source, shopId, model, paymentMethod, financeData)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
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
    
    if paymentMethod == 'finance' and financeData then
        downPayment = math.floor(totalPrice * financeData.downPayment)
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
    
    database.removeStock(shopId, model, 1)
    
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
    
    database.updateShop(shopId, 'funds', shop.funds + totalPrice - commission)
    
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
