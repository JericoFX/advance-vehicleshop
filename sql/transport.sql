CREATE TABLE IF NOT EXISTS `vehicleshop_transports` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shop_id` INT NOT NULL,
    `player_id` INT NOT NULL,
    `vehicles` TEXT NOT NULL,
    `total_cost` DECIMAL(10, 2) NOT NULL,
    `transport_type` ENUM('delivery', 'trailer') NOT NULL,
    `status` ENUM('pending', 'ready', 'in_transit', 'completed', 'cancelled') NOT NULL DEFAULT 'pending',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `delivery_time` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    INDEX `shop_id` (`shop_id`),
    INDEX `player_id` (`player_id`),
    INDEX `status` (`status`)
);
