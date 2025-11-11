local finance = {}
local QBCore = exports['qb-core']:GetCoreObject()

function finance.init()
    -- Cron job now handles payment processing
end

function finance.processPayments()
    local currentTime = os.time()
    local financedVehicles = MySQL.query.await([[
        SELECT * FROM vehicle_financing 
        WHERE status = 'active' AND next_payment <= NOW()
    ]])
    
    for _, loan in ipairs(financedVehicles or {}) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(loan.citizenid)
        
        if Player then
            local hasMoney = Player.Functions.GetMoney('bank') >= loan.monthly_payment
            
            if hasMoney then
                Player.Functions.RemoveMoney('bank', loan.monthly_payment)
                finance.recordPayment(loan.id, loan.monthly_payment)
                
                TriggerClientEvent('vehicleshop:financePayment', Player.PlayerData.source, {
                    success = true,
                    amount = loan.monthly_payment,
                    remaining = loan.months_remaining - 1
                })
            else
                finance.missedPayment(loan.id)
                TriggerClientEvent('vehicleshop:financePayment', Player.PlayerData.source, {
                    success = false,
                    amount = loan.monthly_payment
                })
            end
        else
            finance.processOfflinePayment(loan)
        end
    end
end

function finance.recordPayment(loanId, amount)
    MySQL.query.await([[
        UPDATE vehicle_financing
        SET remaining_amount = remaining_amount - monthly_payment,
            months_remaining = months_remaining - 1,
            last_payment = NOW(),
            next_payment = DATE_ADD(NOW(), INTERVAL 1 MONTH)
        WHERE id = ?
    ]], {loanId})

    MySQL.update.await([[ 
        UPDATE vehicle_financing_missed
        SET processed = 1,
            processed_at = NOW()
        WHERE loan_id = ? AND processed = 0
    ]], {loanId})

    local result = MySQL.query.await('SELECT months_remaining FROM vehicle_financing WHERE id = ?', {loanId})

    if result[1] and result[1].months_remaining <= 0 then
        MySQL.update.await('UPDATE vehicle_financing SET status = ? WHERE id = ?', {'paid', loanId})
    end
end

function finance.missedPayment(loanId)
    MySQL.query.await([[
        INSERT INTO vehicle_financing_missed (loan_id, missed_date, amount)
        VALUES (?, NOW(), (SELECT monthly_payment FROM vehicle_financing WHERE id = ?))
    ]], {loanId, loanId})
    
    local missedCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM vehicle_financing_missed 
        WHERE loan_id = ? AND processed = 0
    ]], {loanId})
    
    if missedCount >= 3 then
        finance.repossessVehicle(loanId)
    end
end

function finance.processOfflinePayment(loan)
    local playerData = MySQL.query.await('SELECT money FROM players WHERE citizenid = ?', {loan.citizenid})

    if playerData[1] then
        local accountData = json.decode(playerData[1].money or '{}') or {}
        local bankMoney = accountData.bank or 0

        if bankMoney >= loan.monthly_payment then
            accountData.bank = bankMoney - loan.monthly_payment

            MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', {
                json.encode(accountData),
                loan.citizenid
            })
            finance.recordPayment(loan.id, loan.monthly_payment)
        else
            finance.missedPayment(loan.id)
        end
    end
end

function finance.repossessVehicle(loanId)
    local loan = MySQL.query.await('SELECT * FROM vehicle_financing WHERE id = ?', {loanId})
    
    if loan[1] then
        MySQL.update.await('UPDATE vehicle_financing SET status = ? WHERE id = ?', {'defaulted', loanId})
        MySQL.update.await('UPDATE player_vehicles SET garage = ? WHERE plate = ?', {'impound', loan[1].plate})
        
        local Player = QBCore.Functions.GetPlayerByCitizenId(loan[1].citizenid)
        if Player then
            TriggerClientEvent('vehicleshop:vehicleRepossessed', Player.PlayerData.source, loan[1].vehicle)
        end
    end
end

lib.callback.register('vehicleshop:getFinanceInfo', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    
    local loans = MySQL.query.await([[
        SELECT vf.*, COUNT(vfm.id) as missed_payments
        FROM vehicle_financing vf
        LEFT JOIN vehicle_financing_missed vfm ON vf.id = vfm.loan_id AND vfm.processed = 0
        WHERE vf.citizenid = ? AND vf.status = 'active'
        GROUP BY vf.id
    ]], {Player.PlayerData.citizenid})
    
    return loans
end)

lib.callback.register('vehicleshop:makeExtraPayment', function(source, loanId, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local loan = MySQL.query.await('SELECT * FROM vehicle_financing WHERE id = ? AND citizenid = ?',
        {loanId, Player.PlayerData.citizenid})

    if not loan[1] then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    if amount > loan[1].remaining_amount then
        amount = loan[1].remaining_amount
    end

    local hasBank = Player.Functions.GetMoney('bank') >= amount
    local hasCash = Player.Functions.GetMoney('cash') >= amount

    if not hasBank and not hasCash then
        return false, 'no_money'
    end

    if hasBank then
        Player.Functions.RemoveMoney('bank', amount)
    else
        Player.Functions.RemoveMoney('cash', amount)
    end

    MySQL.update.await([[
        UPDATE vehicle_financing
        SET remaining_amount = remaining_amount - ?
        WHERE id = ?
    ]], {amount, loanId})

    if loan[1].remaining_amount - amount <= 0 then
        MySQL.update.await('UPDATE vehicle_financing SET status = ?, remaining_amount = 0 WHERE id = ?',
            {'paid', loanId})
    end

    return true
end)

return finance
