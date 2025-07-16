local business = {}
local QBCore = exports['qb-core']:GetCoreObject()

-- Funciones para interactuar con advance-manager
function business.createBusiness(shopId, ownerId, shopName)
    local success, businessId = exports['advance-manager']:createBusiness(
        shopName,
        ownerId,
        'cardealer',
        Config.DefaultShopPrice,
        {
            shop_id = shopId,
            type = 'vehicleshop'
        }
    )
    
    return success, businessId
end

function business.getBusinessByShop(shopId)
    local businesses = exports['advance-manager']:getBusinessByOwner(shopId)
    if businesses and #businesses > 0 then
        for _, business in pairs(businesses) do
            if business.metadata and business.metadata.shop_id == shopId then
                return business
            end
        end
    end
    return nil
end

function business.isBusinessBoss(citizenId, shopId)
    local business = business.getBusinessByShop(shopId)
    if not business then return false end
    
    return exports['advance-manager']:isBusinessBoss(citizenId, business.id)
end

function business.hasBusinessPermission(citizenId, shopId, permission)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false end
    
    return exports['advance-manager']:hasBusinessPermission(citizenId, businessData.id, permission)
end

function business.getBusinessFunds(shopId)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return 0 end
    
    return exports['advance-manager']:getBusinessFunds(businessData.id)
end

function business.updateBusinessFunds(shopId, amount, isWithdrawal)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false end
    
    return exports['advance-manager']:updateBusinessFunds(businessData.id, amount, isWithdrawal)
end

function business.getBusinessEmployees(shopId)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return {} end
    
    local employees = {}
    local result = MySQL.query.await([[
        SELECT be.*, p.charinfo
        FROM business_employees be
        LEFT JOIN players p ON p.citizenid = be.citizenid
        WHERE be.business_id = ?
    ]], {businessData.id})
    
    if result then
        for _, employee in pairs(result) do
            local charinfo = json.decode(employee.charinfo or '{}')
            table.insert(employees, {
                citizenid = employee.citizenid,
                grade = employee.grade,
                wage = employee.wage,
                name = charinfo.firstname .. ' ' .. charinfo.lastname,
                rank = employee.grade + 1 -- Convertir grade a rank para compatibilidad
            })
        end
    end
    
    return employees
end

function business.hireEmployee(shopId, targetId, grade)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false, 'business_not_found' end
    
    local Target = QBCore.Functions.GetPlayer(targetId)
    if not Target then return false, 'player_not_found' end
    
    local targetCitizenId = Target.PlayerData.citizenid
    
    -- Usar advance-manager para contratar empleado
    local success, message = lib.callback.await('advance-manager:hireEmployee', false, businessData.id, targetId, grade, 50)
    
    if success then
        -- Actualizar job del jugador
        Target.Functions.SetJob('cardealer', grade)
        return true
    else
        return false, message
    end
end

function business.fireEmployee(shopId, targetCitizenId)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false, 'business_not_found' end
    
    local success = lib.callback.await('advance-manager:fireEmployee', false, businessData.id, targetCitizenId)
    
    if success then
        -- Actualizar job del jugador
        local Target = QBCore.Functions.GetPlayerByCitizenId(targetCitizenId)
        if Target then
            Target.Functions.SetJob('unemployed', 0)
        end
        return true
    else
        return false, 'fire_failed'
    end
end

function business.updateEmployeeGrade(shopId, targetCitizenId, newGrade)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return false, 'business_not_found' end
    
    local success = lib.callback.await('advance-manager:updateEmployeeGrade', false, businessData.id, targetCitizenId, newGrade)
    
    if success then
        -- Actualizar job del jugador
        local Target = QBCore.Functions.GetPlayerByCitizenId(targetCitizenId)
        if Target then
            Target.Functions.SetJob('cardealer', newGrade)
        end
        return true
    else
        return false, 'grade_update_failed'
    end
end

function business.getEmployeeRank(citizenId, shopId)
    local businessData = business.getBusinessByShop(shopId)
    if not businessData then return 0 end
    
    -- Verificar si es el dueño del negocio
    if businessData.owner == citizenId then
        return 4
    end
    
    -- Verificar si es boss del negocio
    if exports['advance-manager']:isBusinessBoss(citizenId, businessData.id) then
        return 4
    end
    
    -- Obtener el grade del empleado
    local result = MySQL.query.await([[
        SELECT grade FROM business_employees 
        WHERE business_id = ? AND citizenid = ?
    ]], {businessData.id, citizenId})
    
    if result and result[1] then
        return result[1].grade + 1 -- Convertir grade a rank
    end
    
    return 0
end

return business
