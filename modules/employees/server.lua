local employees = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')
local business = lib.require('modules.business.server')

lib.callback.register('vehicleshop:getEmployees', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local playerRank = business.getEmployeeRank(citizenid, shopId)
    
    if playerRank < 3 then
        return false
    end
    
    -- Usar advance-manager para obtener empleados con caché segura
    local employeeList = exports['advance-manager']:getBusinessEmployees(businessData.id)
    
    -- Formatear para compatibilidad con sistema vehicleshop
    local formattedEmployees = {}
    for _, employee in pairs(employeeList) do
        table.insert(formattedEmployees, {
            citizenid = employee.citizenid,
            name = employee.name,
            rank = employee.grade + 1, -- Convertir grade a rank
            hired_at = employee.hired_at or os.time(),
            wage = employee.wage or 0
        })
    end
    
    return formattedEmployees
end)

lib.callback.register('vehicleshop:hireEmployee', function(source, shopId, targetId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local playerRank = business.getEmployeeRank(citizenid, shopId)
    
    if playerRank < 3 then
        return false, 'no_permission'
    end
    
    -- Usar advance-manager para contratar empleado
    local success, message = business.hireEmployee(shopId, targetId, 0) -- Grade 0 = rank 1
    
    if success then
        TriggerClientEvent('vehicleshop:employeeUpdate', targetId, shopId, 'hired')
        return true
    else
        return false, message
    end
end)

lib.callback.register('vehicleshop:fireEmployee', function(source, shopId, targetCitizenid)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local playerRank = business.getEmployeeRank(citizenid, shopId)
    
    if playerRank < 3 then
        return false, 'no_permission'
    end
    
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false end
    
    if targetCitizenid == businessData.owner then
        return false, 'cannot_fire_owner'
    end
    
    if targetCitizenid == citizenid then
        return false, 'cannot_fire_self'
    end
    
    -- Usar advance-manager para despedir empleado
    local success, message = business.fireEmployee(shopId, targetCitizenid)
    
    if success then
        local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
        if targetPlayer then
            TriggerClientEvent('vehicleshop:employeeUpdate', targetPlayer.PlayerData.source, shopId, 'fired')
        end
        return true
    else
        return false, message
    end
end)

lib.callback.register('vehicleshop:updateEmployeeRank', function(source, shopId, targetCitizenid, newRank)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local playerRank = business.getEmployeeRank(citizenid, shopId)
    
    if playerRank < 4 then
        return false, 'no_permission'
    end
    
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false end
    
    if targetCitizenid == businessData.owner then
        return false, 'cannot_change_owner_rank'
    end
    
    if newRank < 1 or newRank > 3 then
        return false, 'invalid_rank'
    end
    
    -- Usar advance-manager para actualizar grade (rank - 1)
    local success, message = business.updateEmployeeGrade(shopId, targetCitizenid, newRank - 1)
    
    if success then
        local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
        if targetPlayer then
            TriggerClientEvent('vehicleshop:employeeUpdate', targetPlayer.PlayerData.source, shopId, 'rank_changed', newRank)
        end
        return true
    else
        return false, message
    end
end)

lib.callback.register('vehicleshop:getEmployeeRank', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Usar advance-manager para obtener el rank del empleado
    return business.getEmployeeRank(citizenid, shopId)
end)

lib.callback.register('vehicleshop:getCommissionRate', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    
    local citizenid = Player.PlayerData.citizenid
    local employeeRank = business.getEmployeeRank(citizenid, shopId)
    
    if employeeRank == 0 then return 0 end
    
    local commissionRates = {
        [1] = 0.05,
        [2] = 0.07,
        [3] = 0.10,
        [4] = 0.15
    }
    
    return commissionRates[employeeRank] or 0.05
end)

return employees
