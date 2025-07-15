local employees = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

lib.callback.register('vehicleshop:getEmployees', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false
    end
    
    local employeeList = {}
    for cid, data in pairs(shop.employees) do
        local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(cid)
        local name = 'Unknown'
        
        if targetPlayer then
            name = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
        else
            local result = MySQL.query.await('SELECT charinfo FROM players WHERE citizenid = ?', {cid})
            if result[1] then
                local charinfo = json.decode(result[1].charinfo)
                name = charinfo.firstname .. ' ' .. charinfo.lastname
            end
        end
        
        table.insert(employeeList, {
            citizenid = cid,
            name = name,
            rank = data.rank,
            hired_at = data.hired_at
        })
    end
    
    return employeeList
end)

lib.callback.register('vehicleshop:hireEmployee', function(source, shopId, targetId)
    local Player = QBCore.Functions.GetPlayer(source)
    local Target = QBCore.Functions.GetPlayer(targetId)
    
    if not Player or not Target then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false, 'no_permission'
    end
    
    local targetCitizenid = Target.PlayerData.citizenid
    
    if shop.employees[targetCitizenid] then
        return false, 'already_employee'
    end
    
    database.addEmployee(shopId, targetCitizenid, 1)
    
    TriggerClientEvent('vehicleshop:employeeUpdate', targetId, shopId, 'hired')
    
    return true
end)

lib.callback.register('vehicleshop:fireEmployee', function(source, shopId, targetCitizenid)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false, 'no_permission'
    end
    
    if targetCitizenid == shop.owner then
        return false, 'cannot_fire_owner'
    end
    
    if targetCitizenid == citizenid then
        return false, 'cannot_fire_self'
    end
    
    database.removeEmployee(shopId, targetCitizenid)
    
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        TriggerClientEvent('vehicleshop:employeeUpdate', targetPlayer.PlayerData.source, shopId, 'fired')
    end
    
    return true
end)

lib.callback.register('vehicleshop:updateEmployeeRank', function(source, shopId, targetCitizenid, newRank)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if shop.owner ~= citizenid and (not employee or employee.rank < 4) then
        return false, 'no_permission'
    end
    
    if targetCitizenid == shop.owner then
        return false, 'cannot_change_owner_rank'
    end
    
    if newRank < 1 or newRank > 3 then
        return false, 'invalid_rank'
    end
    
    database.updateEmployeeRank(shopId, targetCitizenid, newRank)
    
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        TriggerClientEvent('vehicleshop:employeeUpdate', targetPlayer.PlayerData.source, shopId, 'rank_changed', newRank)
    end
    
    return true
end)

lib.callback.register('vehicleshop:getEmployeeRank', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return 0 end
    
    local citizenid = Player.PlayerData.citizenid
    
    if shop.owner == citizenid then
        return 4
    end
    
    local employee = shop.employees[citizenid]
    return employee and employee.rank or 0
end)

lib.callback.register('vehicleshop:getCommissionRate', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return 0 end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee then return 0 end
    
    local commissionRates = {
        [1] = 0.05,
        [2] = 0.07,
        [3] = 0.10,
        [4] = 0.15
    }
    
    return commissionRates[employee.rank] or 0.05
end)

return employees
