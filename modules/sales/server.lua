local sales = {}
local QBCore = exports['qb-core']:GetCoreObject()
local database = lib.require('modules.database.server')

lib.callback.register('vehicleshop:getSalesHistory', function(source, shopId, period)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 2 then
        return false
    end
    
    return database.getSales(shopId, 100)
end)

lib.callback.register('vehicleshop:getEmployeeSales', function(source, shopId, employeeCitizenid, period)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false
    end
    
    local query = [[
        SELECT * FROM vehicleshop_sales 
        WHERE shop_id = ? AND seller = ?
        ORDER BY sold_at DESC
        LIMIT 50
    ]]
    
    return MySQL.query.await(query, {shopId, employeeCitizenid or citizenid})
end)

lib.callback.register('vehicleshop:getSalesStats', function(source, shopId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    local employee = shop.employees[citizenid]
    
    if not employee or employee.rank < 3 then
        return false
    end
    
    local stats = {
        today = sales.getSalesForPeriod(shopId, 'DAY'),
        week = sales.getSalesForPeriod(shopId, 'WEEK'),
        month = sales.getSalesForPeriod(shopId, 'MONTH'),
        topSellers = sales.getTopSellers(shopId),
        topModels = sales.getTopModels(shopId)
    }
    
    return stats
end)

function sales.getSalesForPeriod(shopId, period)
    local query = [[
        SELECT 
            COUNT(*) as count,
            SUM(price) as total,
            SUM(commission) as totalCommission
        FROM vehicleshop_sales
        WHERE shop_id = ? AND sold_at >= DATE_SUB(NOW(), INTERVAL 1 %s)
    ]]
    
    query = string.format(query, period)
    local result = MySQL.query.await(query, {shopId})
    
    return result[1] or {count = 0, total = 0, totalCommission = 0}
end

function sales.getTopSellers(shopId)
    local query = [[
        SELECT 
            s.seller,
            COUNT(*) as sales_count,
            SUM(s.price) as total_sales,
            SUM(s.commission) as total_commission,
            p.charinfo
        FROM vehicleshop_sales s
        LEFT JOIN players p ON s.seller = p.citizenid
        WHERE s.shop_id = ? AND s.sold_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY s.seller
        ORDER BY total_sales DESC
        LIMIT 5
    ]]
    
    local results = MySQL.query.await(query, {shopId})
    
    for _, result in ipairs(results) do
        if result.charinfo then
            local charinfo = json.decode(result.charinfo)
            result.name = charinfo.firstname .. ' ' .. charinfo.lastname
        else
            result.name = 'Unknown'
        end
    end
    
    return results
end

function sales.getTopModels(shopId)
    local query = [[
        SELECT 
            model,
            COUNT(*) as sales_count,
            SUM(price) as total_revenue
        FROM vehicleshop_sales
        WHERE shop_id = ? AND sold_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY model
        ORDER BY sales_count DESC
        LIMIT 10
    ]]
    
    return MySQL.query.await(query, {shopId})
end

lib.callback.register('vehicleshop:generateSalesReport', function(source, shopId, startDate, endDate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return false end
    
    local citizenid = Player.PlayerData.citizenid
    
    if shop.owner ~= citizenid then
        local employee = shop.employees[citizenid]
        if not employee or employee.rank < 4 then
            return false
        end
    end
    
    local query = [[
        SELECT 
            DATE(sold_at) as sale_date,
            COUNT(*) as sales_count,
            SUM(price) as total_revenue,
            SUM(commission) as total_commission
        FROM vehicleshop_sales
        WHERE shop_id = ? AND sold_at BETWEEN ? AND ?
        GROUP BY DATE(sold_at)
        ORDER BY sale_date DESC
    ]]
    
    local dailySales = MySQL.query.await(query, {shopId, startDate, endDate})
    
    local employeeQuery = [[
        SELECT 
            s.seller,
            COUNT(*) as sales_count,
            SUM(s.price) as total_sales,
            SUM(s.commission) as total_commission,
            p.charinfo
        FROM vehicleshop_sales s
        LEFT JOIN players p ON s.seller = p.citizenid
        WHERE s.shop_id = ? AND s.sold_at BETWEEN ? AND ?
        GROUP BY s.seller
        ORDER BY total_sales DESC
    ]]
    
    local employeeSales = MySQL.query.await(employeeQuery, {shopId, startDate, endDate})
    
    for _, employee in ipairs(employeeSales) do
        if employee.charinfo then
            local charinfo = json.decode(employee.charinfo)
            employee.name = charinfo.firstname .. ' ' .. charinfo.lastname
        else
            employee.name = 'Unknown'
        end
    end
    
    return {
        daily = dailySales,
        employees = employeeSales,
        period = {
            start = startDate,
            ['end'] = endDate
        }
    }
end)

return sales
