local database = {}

function database.init()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicleshops` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(50) NOT NULL,
            `owner` VARCHAR(50) DEFAULT NULL,
            `price` INT(11) NOT NULL DEFAULT 250000,
            `funds` INT(11) NOT NULL DEFAULT 0,
            `entry` LONGTEXT NOT NULL,
            `management` LONGTEXT NOT NULL,
            `spawn` LONGTEXT NOT NULL,
            `camera` LONGTEXT NOT NULL,
            `garage` LONGTEXT DEFAULT NULL,
            `unload` LONGTEXT DEFAULT NULL,
            `stock` LONGTEXT DEFAULT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `name` (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicleshop_employees` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `citizenid` VARCHAR(50) NOT NULL,
            `rank` INT(11) NOT NULL DEFAULT 1,
            `hired_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `shop_employee` (`shop_id`, `citizenid`),
            FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicleshop_stock` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `model` VARCHAR(50) NOT NULL,
            `price` INT(11) NOT NULL,
            `amount` INT(11) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            UNIQUE KEY `shop_vehicle` (`shop_id`, `model`),
            FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicleshop_display` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `model` VARCHAR(50) NOT NULL,
            `position` LONGTEXT NOT NULL,
            `props` LONGTEXT DEFAULT NULL,
            PRIMARY KEY (`id`),
            FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicleshop_sales` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `shop_id` INT(11) NOT NULL,
            `seller` VARCHAR(50) NOT NULL,
            `buyer` VARCHAR(50) NOT NULL,
            `model` VARCHAR(50) NOT NULL,
            `price` INT(11) NOT NULL,
            `commission` INT(11) NOT NULL DEFAULT 0,
            `finance_data` LONGTEXT DEFAULT NULL,
            `sold_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            FOREIGN KEY (`shop_id`) REFERENCES `vehicleshops`(`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicle_financing` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `vehicle` VARCHAR(50) NOT NULL,
            `plate` VARCHAR(10) NOT NULL,
            `total_amount` INT(11) NOT NULL,
            `down_payment` INT(11) NOT NULL,
            `remaining_amount` INT(11) NOT NULL,
            `monthly_payment` INT(11) NOT NULL,
            `months_total` INT(11) NOT NULL,
            `months_remaining` INT(11) NOT NULL,
            `last_payment` TIMESTAMP NULL DEFAULT NULL,
            `next_payment` TIMESTAMP NOT NULL,
            `status` ENUM('active', 'paid', 'defaulted') DEFAULT 'active',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `plate` (`plate`),
            INDEX `citizen_financing` (`citizenid`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    database.loadShops()
end

function database.loadShops()
    local shops = MySQL.query.await('SELECT * FROM vehicleshops')
    local shopData = {}
    
    for _, shop in ipairs(shops or {}) do
        shop.entry = json.decode(shop.entry)
        shop.management = json.decode(shop.management)
        shop.spawn = json.decode(shop.spawn)
        shop.camera = json.decode(shop.camera)
        
        if shop.garage then
            shop.garage = json.decode(shop.garage)
        end
        if shop.unload then
            shop.unload = json.decode(shop.unload)
        end
        if shop.stock then
            shop.stock = json.decode(shop.stock)
        end
        
        local employees = MySQL.query.await('SELECT * FROM vehicleshop_employees WHERE shop_id = ?', {shop.id})
        shop.employees = {}
        for _, employee in ipairs(employees or {}) do
            shop.employees[employee.citizenid] = {
                rank = employee.rank,
                hired_at = employee.hired_at
            }
        end
        
        shopData[shop.id] = shop
    end
    
    GlobalState.VehicleShops = shopData
end

function database.createShop(data)
    local id = MySQL.insert.await([[
        INSERT INTO vehicleshops (name, owner, price, entry, management, spawn, camera, garage, unload, stock)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.owner,
        data.price,
        json.encode(data.entry),
        json.encode(data.management),
        json.encode(data.spawn),
        json.encode(data.camera),
        data.garage and json.encode(data.garage) or nil,
        data.unload and json.encode(data.unload) or nil,
        data.stock and json.encode(data.stock) or nil
    })
    
    if id then
        data.id = id
        data.funds = 0
        data.employees = {}
        
        if data.owner then
            database.addEmployee(id, data.owner, 4)
        end
        
        local shops = GlobalState.VehicleShops
        shops[id] = data
        GlobalState.VehicleShops = shops
    end
    
    return id
end

function database.updateShop(shopId, field, value)
    MySQL.update.await('UPDATE vehicleshops SET ?? = ? WHERE id = ?', {field, value, shopId})
    
    local shops = GlobalState.VehicleShops
    if shops[shopId] then
        shops[shopId][field] = value
        GlobalState.VehicleShops = shops
    end
end

function database.addEmployee(shopId, citizenid, rank)
    MySQL.insert.await([[
        INSERT INTO vehicleshop_employees (shop_id, citizenid, rank)
        VALUES (?, ?, ?)
    ]], {shopId, citizenid, rank})
    
    local shops = GlobalState.VehicleShops
    if shops[shopId] then
        shops[shopId].employees[citizenid] = {
            rank = rank,
            hired_at = os.date('%Y-%m-%d %H:%M:%S')
        }
        GlobalState.VehicleShops = shops
    end
end

function database.removeEmployee(shopId, citizenid)
    MySQL.query.await('DELETE FROM vehicleshop_employees WHERE shop_id = ? AND citizenid = ?', {shopId, citizenid})
    
    local shops = GlobalState.VehicleShops
    if shops[shopId] and shops[shopId].employees[citizenid] then
        shops[shopId].employees[citizenid] = nil
        GlobalState.VehicleShops = shops
    end
end

function database.updateEmployeeRank(shopId, citizenid, rank)
    MySQL.update.await('UPDATE vehicleshop_employees SET rank = ? WHERE shop_id = ? AND citizenid = ?', {rank, shopId, citizenid})
    
    local shops = GlobalState.VehicleShops
    if shops[shopId] and shops[shopId].employees[citizenid] then
        shops[shopId].employees[citizenid].rank = rank
        GlobalState.VehicleShops = shops
    end
end

function database.addStock(shopId, model, price, amount)
    MySQL.insert.await([[
        INSERT INTO vehicleshop_stock (shop_id, model, price, amount)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE price = VALUES(price), amount = amount + VALUES(amount)
    ]], {shopId, model, price, amount})
end

function database.removeStock(shopId, model, amount)
    MySQL.update.await([[
        UPDATE vehicleshop_stock 
        SET amount = GREATEST(0, amount - ?) 
        WHERE shop_id = ? AND model = ?
    ]], {amount, shopId, model})
end

function database.getStock(shopId)
    return MySQL.query.await('SELECT * FROM vehicleshop_stock WHERE shop_id = ?', {shopId})
end

function database.addDisplayVehicle(shopId, model, position, props)
    return MySQL.insert.await([[
        INSERT INTO vehicleshop_display (shop_id, model, position, props)
        VALUES (?, ?, ?, ?)
    ]], {shopId, model, json.encode(position), props and json.encode(props) or nil})
end

function database.removeDisplayVehicle(displayId)
    MySQL.query.await('DELETE FROM vehicleshop_display WHERE id = ?', {displayId})
end

function database.getDisplayVehicles(shopId)
    local vehicles = MySQL.query.await('SELECT * FROM vehicleshop_display WHERE shop_id = ?', {shopId})
    
    for _, vehicle in ipairs(vehicles or {}) do
        vehicle.position = json.decode(vehicle.position)
        if vehicle.props then
            vehicle.props = json.decode(vehicle.props)
        end
    end
    
    return vehicles
end

function database.recordSale(data)
    return MySQL.insert.await([[
        INSERT INTO vehicleshop_sales (shop_id, seller, buyer, model, price, commission, finance_data)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.shopId,
        data.seller,
        data.buyer,
        data.model,
        data.price,
        data.commission,
        data.financeData and json.encode(data.financeData) or nil
    })
end

function database.getSales(shopId, limit)
    return MySQL.query.await([[
        SELECT * FROM vehicleshop_sales 
        WHERE shop_id = ? 
        ORDER BY sold_at DESC 
        LIMIT ?
    ]], {shopId, limit or 50})
end

return database
