local management = {}
local QBCore = exports['qb-core']:GetCoreObject()
local ui = lib.require('modules.ui.client')

function management.init()
    management.setupEventHandlers()
end

function management.setupEventHandlers()
    RegisterNetEvent('vehicleshop:openManagement', function(shopId)
        management.openMainMenu(shopId)
    end)
    
    RegisterNetEvent('vehicleshop:employeeUpdate', function(shopId, action, data)
        if action == 'hired' then
            lib.notify({
                title = locale('ui.success'),
                description = locale('employees.hired_notification'),
                type = 'success'
            })
        elseif action == 'fired' then
            lib.notify({
                title = locale('ui.error'),
                description = locale('employees.fired_notification'),
                type = 'error'
            })
        elseif action == 'rank_changed' then
            lib.notify({
                title = locale('ui.success'),
                description = locale('employees.rank_changed_notification', data),
                type = 'info'
            })
        end
    end)
end

function management.openMainMenu(shopId)
    local shop = GlobalState.VehicleShops[shopId]
    if not shop then return end
    
    local rank = lib.callback.await('vehicleshop:getEmployeeRank', false, shopId)
    if rank == 0 then return end
    
    local options = {
        {
            title = locale('management.vehicles'),
            description = locale('management.vehicles_desc'),
            icon = 'car',
            onSelect = function()
                management.openVehicleMenu(shopId, rank)
            end
        },
        {
            title = locale('management.stock'),
            description = locale('management.stock_desc'),
            icon = 'warehouse',
            onSelect = function()
                management.openStockMenu(shopId)
            end
        }
    }
    
    if rank >= 3 then
        table.insert(options, {
            title = locale('management.employees'),
            description = locale('management.employees_desc'),
            icon = 'users',
            onSelect = function()
                management.openEmployeeMenu(shopId, rank)
            end
        })
        
        table.insert(options, {
            title = locale('management.funds'),
            description = locale('management.funds_desc'),
            icon = 'dollar-sign',
            onSelect = function()
                management.openFundsMenu(shopId, rank)
            end
        })
    end
    
    if rank >= 2 then
        table.insert(options, {
            title = locale('management.sales'),
            description = locale('management.sales_desc'),
            icon = 'chart-line',
            onSelect = function()
                management.openSalesMenu(shopId, rank)
            end
        })
    end
    
    if rank == 4 or shop.owner == QBCore.Functions.GetPlayerData().citizenid then
        table.insert(options, {
            title = locale('management.settings'),
            description = locale('management.settings_desc'),
            icon = 'cog',
            onSelect = function()
                management.openSettingsMenu(shopId)
            end
        })
    end
    
    ui.showMenu({
        id = 'shop_management',
        title = locale('management.title') .. ' - ' .. shop.name,
        options = options
    })
end

function management.openVehicleMenu(shopId, rank)
    local displayVehicles = lib.callback.await('vehicleshop:getDisplayVehicles', false, shopId)
    local options = {}
    
    if rank >= 2 then
        table.insert(options, {
            title = locale('vehicles.add_display'),
            description = locale('vehicles.add_display_desc'),
            icon = 'plus',
            onSelect = function()
                management.selectVehicleToDisplay(shopId)
            end
        })
    end
    
    for _, vehicle in ipairs(displayVehicles or {}) do
        local vehicleData = QBCore.Shared.Vehicles[vehicle.model]
        table.insert(options, {
            title = vehicleData and vehicleData.name or vehicle.model,
            description = locale('vehicles.display_vehicle'),
            icon = 'car',
            metadata = {
                {label = locale('vehicles.model'), value = vehicle.model},
                {label = locale('vehicles.id'), value = vehicle.id}
            },
            onSelect = function()
                if rank >= 2 then
                    management.vehicleDisplayOptions(shopId, vehicle)
                end
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openMainMenu(shopId)
        end
    })
    
    ui.showMenu({
        id = 'vehicle_management',
        title = locale('management.vehicles'),
        options = options
    })
end

function management.selectVehicleToDisplay(shopId)
    local stock = lib.callback.await('vehicleshop:getShopVehicles', false, shopId)
    local options = {}
    
    for _, vehicle in ipairs(stock or {}) do
        if vehicle.amount > 0 then
            local vehicleData = QBCore.Shared.Vehicles[vehicle.model]
            table.insert(options, {
                title = vehicleData and vehicleData.name or vehicle.model,
                description = string.format('%s: %d', locale('warehouse.stock'), vehicle.amount),
                icon = 'car',
                onSelect = function()
                    local vehicles = lib.require('modules.vehicles.client')
                    vehicles.startPlacementMode(shopId, vehicle.model)
                    ui.closeMenu()
                end
            })
        end
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openVehicleMenu(shopId, 2)
        end
    })
    
    ui.showMenu({
        id = 'select_display_vehicle',
        title = locale('vehicles.select_vehicle'),
        options = options
    })
end

function management.vehicleDisplayOptions(shopId, vehicle)
    local options = {
        {
            title = locale('vehicles.remove_display'),
            description = locale('vehicles.remove_display_desc'),
            icon = 'trash',
            onSelect = function()
                local confirm = ui.showConfirmation({
                    header = locale('vehicles.remove_display'),
                    content = locale('vehicles.remove_confirm')
                })
                
                if confirm == 'confirm' then
                    local success = lib.callback.await('vehicleshop:removeDisplayVehicle', false, shopId, vehicle.id)
                    if success then
                        lib.notify({
                            title = locale('ui.success'),
                            description = locale('vehicles.display_removed'),
                            type = 'success'
                        })
                        management.openVehicleMenu(shopId, 2)
                    end
                end
            end
        },
        {
            title = locale('ui.back'),
            icon = 'arrow-left',
            onSelect = function()
                management.openVehicleMenu(shopId, 2)
            end
        }
    }
    
    ui.showMenu({
        id = 'vehicle_display_options',
        title = locale('vehicles.display_options'),
        options = options
    })
end

function management.openEmployeeMenu(shopId, rank)
    local employees = lib.callback.await('vehicleshop:getEmployees', false, shopId)
    if not employees then return end
    
    local options = {
        {
            title = locale('employees.hire'),
            description = locale('employees.hire_desc'),
            icon = 'user-plus',
            onSelect = function()
                management.hireEmployee(shopId)
            end
        }
    }
    
    for _, employee in ipairs(employees) do
        local rankLabel = locale('employees.rank_' .. employee.rank)
        table.insert(options, {
            title = employee.name,
            description = rankLabel,
            icon = 'user',
            metadata = {
                {label = locale('employees.rank'), value = rankLabel},
                {label = locale('employees.hired'), value = employee.hired_at}
            },
            onSelect = function()
                management.employeeOptions(shopId, employee, rank)
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openMainMenu(shopId)
        end
    })
    
    ui.showMenu({
        id = 'employee_management',
        title = locale('employees.title'),
        options = options
    })
end

function management.hireEmployee(shopId)
    local input = ui.showInput(locale('employees.hire'), {
        {
            type = 'number',
            label = locale('employees.employee_id'),
            description = locale('employees.employee_id_desc'),
            required = true
        }
    })
    
    if input then
        local targetId = input[1]
        local success, reason = lib.callback.await('vehicleshop:hireEmployee', false, shopId, targetId)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('employees.hired'),
                type = 'success'
            })
            management.openEmployeeMenu(shopId, 3)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('employees.' .. (reason or 'hire_failed')),
                type = 'error'
            })
        end
    end
end

function management.employeeOptions(shopId, employee, rank)
    local options = {}
    
    if rank >= 3 then
        table.insert(options, {
            title = locale('employees.set_rank'),
            description = locale('employees.set_rank_desc'),
            icon = 'arrow-up',
            onSelect = function()
                management.setEmployeeRank(shopId, employee)
            end
        })
        
        table.insert(options, {
            title = locale('employees.fire'),
            description = locale('employees.fire_desc'),
            icon = 'user-minus',
            onSelect = function()
                local confirm = ui.showConfirmation({
                    header = locale('employees.fire'),
                    content = locale('employees.fire_confirm', employee.name)
                })
                
                if confirm == 'confirm' then
                    local success, reason = lib.callback.await('vehicleshop:fireEmployee', false, shopId, employee.citizenid)
                    
                    if success then
                        lib.notify({
                            title = locale('ui.success'),
                            description = locale('employees.fired'),
                            type = 'success'
                        })
                        management.openEmployeeMenu(shopId, rank)
                    else
                        lib.notify({
                            title = locale('ui.error'),
                            description = locale('employees.' .. (reason or 'fire_failed')),
                            type = 'error'
                        })
                    end
                end
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openEmployeeMenu(shopId, rank)
        end
    })
    
    ui.showMenu({
        id = 'employee_options',
        title = employee.name,
        options = options
    })
end

function management.setEmployeeRank(shopId, employee)
    local input = ui.showInput(locale('employees.set_rank'), {
        {
            type = 'select',
            label = locale('employees.rank'),
            options = {
                {value = 1, label = locale('employees.rank_1')},
                {value = 2, label = locale('employees.rank_2')},
                {value = 3, label = locale('employees.rank_3')}
            },
            default = employee.rank
        }
    })
    
    if input then
        local newRank = input[1]
        local success, reason = lib.callback.await('vehicleshop:updateEmployeeRank', false, shopId, employee.citizenid, newRank)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('employees.rank_updated'),
                type = 'success'
            })
            management.openEmployeeMenu(shopId, 3)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('employees.' .. (reason or 'rank_update_failed')),
                type = 'error'
            })
        end
    end
end

function management.openFundsMenu(shopId, rank)
    local currentFunds = lib.callback.await('vehicleshop:getShopFunds', false, shopId)
    
    local options = {
        {
            title = locale('funds.balance'),
            description = '$' .. (currentFunds or 0),
            icon = 'dollar-sign',
            readOnly = true
        },
        {
            title = locale('funds.deposit'),
            description = locale('funds.deposit_desc'),
            icon = 'plus-circle',
            onSelect = function()
                management.depositFunds(shopId)
            end
        }
    }
    
    if rank == 4 then
        table.insert(options, {
            title = locale('funds.withdraw'),
            description = locale('funds.withdraw_desc'),
            icon = 'minus-circle',
            onSelect = function()
                management.withdrawFunds(shopId)
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openMainMenu(shopId)
        end
    })
    
    ui.showMenu({
        id = 'funds_management',
        title = locale('funds.title'),
        options = options
    })
end

function management.depositFunds(shopId)
    local input = ui.showInput(locale('funds.deposit'), {
        {
            type = 'number',
            label = locale('funds.amount'),
            description = locale('funds.amount_desc'),
            required = true,
            min = 1
        }
    })
    
    if input then
        local amount = input[1]
        local success, reason = lib.callback.await('vehicleshop:depositFunds', false, shopId, amount)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('funds.deposited', amount),
                type = 'success'
            })
            management.openFundsMenu(shopId, 3)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('funds.' .. (reason or 'deposit_failed')),
                type = 'error'
            })
        end
    end
end

function management.withdrawFunds(shopId)
    local input = ui.showInput(locale('funds.withdraw'), {
        {
            type = 'number',
            label = locale('funds.amount'),
            description = locale('funds.amount_desc'),
            required = true,
            min = 1
        }
    })
    
    if input then
        local amount = input[1]
        local success, reason = lib.callback.await('vehicleshop:withdrawFunds', false, shopId, amount)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('funds.withdrawn', amount),
                type = 'success'
            })
            management.openFundsMenu(shopId, 4)
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('funds.' .. (reason or 'withdraw_failed')),
                type = 'error'
            })
        end
    end
end

function management.openStockMenu(shopId)
    local stock = lib.callback.await('vehicleshop:getShopVehicles', false, shopId)
    local displayVehicles = lib.callback.await('vehicleshop:getDisplayVehicles', false, shopId)
    local rank = lib.callback.await('vehicleshop:getEmployeeRank', false, shopId)
    local options = {}
    
    for _, vehicle in ipairs(stock or {}) do
        local vehicleData = QBCore.Shared.Vehicles[vehicle.model]
        
        local onDisplay = 0
        for _, display in ipairs(displayVehicles or {}) do
            if display.model == vehicle.model then
                onDisplay = onDisplay + 1
            end
        end
        
        local availableStock = vehicle.amount - onDisplay
        local status = availableStock > 0 and 'Available' or (onDisplay > 0 and 'All on Display' or 'Out of Stock')
        
        table.insert(options, {
            title = vehicleData and vehicleData.name or vehicle.model,
            description = string.format('Total: %d | Display: %d | Available: %d | Price: $%s', 
                vehicle.amount, onDisplay, availableStock, vehicle.price
            ),
            icon = 'car',
            metadata = {
                {label = 'Model', value = vehicle.model},
                {label = 'Total Stock', value = vehicle.amount},
                {label = 'On Display', value = onDisplay},
                {label = 'Available', value = availableStock},
                {label = 'Status', value = status},
                {label = 'Price', value = '$' .. vehicle.price}
            },
            onSelect = function()
                if rank >= 3 then
                    management.vehicleStockOptions(shopId, vehicle, rank)
                end
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openMainMenu(shopId)
        end
    })
    
    ui.showMenu({
        id = 'stock_management',
        title = locale('management.stock'),
        options = options
    })
end

function management.openSalesMenu(shopId, rank)
    local stats = lib.callback.await('vehicleshop:getSalesStats', false, shopId)
    if not stats then return end
    
    local options = {
        {
            title = locale('sales.today'),
            description = string.format('%s: %d | %s: $%s',
                locale('sales.count'), stats.today.count,
                locale('sales.total'), stats.today.total or 0
            ),
            icon = 'calendar-day',
            readOnly = true
        },
        {
            title = locale('sales.week'),
            description = string.format('%s: %d | %s: $%s',
                locale('sales.count'), stats.week.count,
                locale('sales.total'), stats.week.total or 0
            ),
            icon = 'calendar-week',
            readOnly = true
        },
        {
            title = locale('sales.month'),
            description = string.format('%s: %d | %s: $%s',
                locale('sales.count'), stats.month.count,
                locale('sales.total'), stats.month.total or 0
            ),
            icon = 'calendar',
            readOnly = true
        },
        {
            title = locale('sales.top_sellers'),
            description = locale('sales.top_sellers_desc'),
            icon = 'trophy',
            onSelect = function()
                management.showTopSellers(shopId, stats.topSellers)
            end
        },
        {
            title = locale('sales.top_models'),
            description = locale('sales.top_models_desc'),
            icon = 'car',
            onSelect = function()
                management.showTopModels(shopId, stats.topModels)
            end
        }
    }
    
    if rank >= 3 then
        table.insert(options, {
            title = locale('sales.generate_report'),
            description = locale('sales.generate_report_desc'),
            icon = 'file-alt',
            onSelect = function()
                management.generateSalesReport(shopId)
            end
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openMainMenu(shopId)
        end
    })
    
    ui.showMenu({
        id = 'sales_management',
        title = locale('management.sales'),
        options = options
    })
end

function management.showTopSellers(shopId, topSellers)
    local options = {}
    
    for i, seller in ipairs(topSellers) do
        table.insert(options, {
            title = string.format('#%d %s', i, seller.name),
            description = string.format('%s: %d | %s: $%s | %s: $%s',
                locale('sales.count'), seller.sales_count,
                locale('sales.total'), seller.total_sales,
                locale('sales.commission'), seller.total_commission
            ),
            icon = 'user',
            readOnly = true
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openSalesMenu(shopId, 2)
        end
    })
    
    ui.showMenu({
        id = 'top_sellers',
        title = locale('sales.top_sellers'),
        options = options
    })
end

function management.showTopModels(shopId, topModels)
    local options = {}
    
    for i, model in ipairs(topModels) do
        local vehicleData = QBCore.Shared.Vehicles[model.model]
        table.insert(options, {
            title = string.format('#%d %s', i, vehicleData and vehicleData.name or model.model),
            description = string.format('%s: %d | %s: $%s',
                locale('sales.count'), model.sales_count,
                locale('sales.revenue'), model.total_revenue
            ),
            icon = 'car',
            readOnly = true
        })
    end
    
    table.insert(options, {
        title = locale('ui.back'),
        icon = 'arrow-left',
        onSelect = function()
            management.openSalesMenu(shopId, 2)
        end
    })
    
    ui.showMenu({
        id = 'top_models',
        title = locale('sales.top_models'),
        options = options
    })
end

function management.openSettingsMenu(shopId)
    local options = {
        {
            title = locale('settings.transfer_ownership'),
            description = locale('settings.transfer_ownership_desc'),
            icon = 'exchange-alt',
            onSelect = function()
                management.transferOwnership(shopId)
            end
        },
        {
            title = locale('ui.back'),
            icon = 'arrow-left',
            onSelect = function()
                management.openMainMenu(shopId)
            end
        }
    }
    
    ui.showMenu({
        id = 'settings_menu',
        title = locale('management.settings'),
        options = options
    })
end

return management
