local cron = {}
local QBCore = exports['qb-core']:GetCoreObject()

function cron.init()
    cron.setupFinancePaymentsCron()
    cron.setupTransportDeliveryCron()
    cron.setupKeyCleanupCron()
    cron.setupDailyMaintenanceCron()
end

-- Process finance payments every hour at minute 0
function cron.setupFinancePaymentsCron()
    lib.cron.new('0 * * * *', function()
        local finance = lib.require('modules.finance.server')
        if finance.processPayments then
            finance.processPayments()
            
            lib.logger(-1, 'cronFinancePayments', {
                time = os.date('%Y-%m-%d %H:%M:%S'),
                task = 'finance_payments'
            })
        end
    end)
end

-- Check transport deliveries every minute
function cron.setupTransportDeliveryCron()
    lib.cron.new('* * * * *', function()
        local transport = lib.require('modules.transport.server')
        if transport.checkDeliveries then
            transport.checkDeliveries()
        end
    end)
end

-- Clean up expired keys every 5 minutes
function cron.setupKeyCleanupCron()
    lib.cron.new('*/5 * * * *', function()
        local garage = lib.require('modules.garage.server')
        if garage.cleanupExpiredKeys then
            garage.cleanupExpiredKeys()
            
            lib.logger(-1, 'cronKeyCleanup', {
                time = os.date('%Y-%m-%d %H:%M:%S'),
                task = 'key_cleanup'
            })
        end
    end)
end

-- Daily maintenance tasks at 3 AM
function cron.setupDailyMaintenanceCron()
    lib.cron.new('0 3 * * *', function()
        -- Clean up old test drive logs
        MySQL.query.await([[
            DELETE FROM vehicleshop_logs 
            WHERE action LIKE 'testDrive%' 
            AND created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)
        ]])
        
        -- Clean up completed transports older than 30 days
        MySQL.query.await([[
            DELETE FROM vehicleshop_transports 
            WHERE status = 'completed' 
            AND created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
        ]])
        
        -- Archive old sales data
        MySQL.query.await([[
            INSERT INTO vehicleshop_sales_archive 
            SELECT * FROM vehicleshop_sales 
            WHERE sale_date < DATE_SUB(NOW(), INTERVAL 90 DAY)
        ]])
        
        MySQL.query.await([[
            DELETE FROM vehicleshop_sales 
            WHERE sale_date < DATE_SUB(NOW(), INTERVAL 90 DAY)
        ]])
        
        lib.logger(-1, 'cronDailyMaintenance', {
            time = os.date('%Y-%m-%d %H:%M:%S'),
            task = 'daily_maintenance'
        })
    end)
end

-- Add more cron jobs as needed
function cron.addCustomJob(pattern, callback, name)
    lib.cron.new(pattern, function()
        local success, err = pcall(callback)
        if not success then
            lib.logger(-1, 'cronError', {
                job = name or 'unknown',
                error = err,
                time = os.date('%Y-%m-%d %H:%M:%S')
            })
        end
    end)
end

-- Get all active cron jobs info (for debugging)
lib.callback.register('vehicleshop:getCronInfo', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end
    
    if not QBCore.Functions.HasPermission(source, 'admin') then
        return {}
    end
    
    return {
        jobs = {
            {name = 'Finance Payments', pattern = '0 * * * *', description = 'Process vehicle loan payments every hour'},
            {name = 'Transport Delivery', pattern = '* * * * *', description = 'Check pending deliveries every minute'},
            {name = 'Key Cleanup', pattern = '*/5 * * * *', description = 'Remove expired temporary keys every 5 minutes'},
            {name = 'Daily Maintenance', pattern = '0 3 * * *', description = 'Clean up old data daily at 3 AM'}
        },
        serverTime = os.date('%Y-%m-%d %H:%M:%S')
    }
end)

return cron
