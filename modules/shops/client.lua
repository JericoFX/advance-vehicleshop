local shops = {}
local QBCore = exports['qb-core']:GetCoreObject()
local currentShop = nil
local shopZones = {}

function shops.init()
    shops.createZones()
    shops.setupStateBag()
end

function shops.cleanup()
    for _, zone in pairs(shopZones) do
        zone:remove()
    end
    shopZones = {}
end

function shops.setupStateBag()
    AddStateBagChangeHandler('VehicleShops', 'global', function(bagName, key, value)
        if value then
            shops.cleanup()
            shops.createZones()
        end
    end)
end

function shops.createZones()
    local vehicleShops = GlobalState.VehicleShops or {}
    
    for shopId, shop in pairs(vehicleShops) do
        if shop.entry then
            local entryZone = lib.zones.sphere({
                coords = shop.entry,
                radius = 2.0,
                debug = Config.Debug,
                onEnter = function()
                    if shop.owner then
                        lib.showTextUI(locale('shop.enter_owned', shop.name))
                    else
                        lib.showTextUI(locale('shop.enter_for_sale', shop.name, shop.price))
                    end
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustPressed(0, 38) then
                        shops.openShopMenu(shopId, shop)
                    end
                end
            })
            
            shopZones[shopId .. '_entry'] = entryZone
        end
        
        if shop.management then
            local mgmtZone = lib.zones.sphere({
                coords = shop.management,
                radius = 2.0,
                debug = Config.Debug,
                onEnter = function()
                    local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', false, shopId)
                    if isEmployee then
                        lib.showTextUI(locale('management.open'))
                    end
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustPressed(0, 38) then
                        local isEmployee = lib.callback.await('vehicleshop:isShopEmployee', false, shopId)
                        if isEmployee then
                            TriggerEvent('vehicleshop:openManagement', shopId)
                        end
                    end
                end
            })
            
            shopZones[shopId .. '_management'] = mgmtZone
        end
    end
end

function shops.openShopMenu(shopId, shop)
    if not shop.owner then
        shops.showPurchaseDialog(shopId, shop)
    else
        TriggerEvent('vehicleshop:showCatalog', shopId)
    end
end

function shops.showPurchaseDialog(shopId, shop)
    local alert = lib.alertDialog({
        header = locale('shop.purchase_title'),
        content = locale('shop.purchase_confirm', shop.price),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        local success = lib.callback.await('vehicleshop:purchaseShop', false, shopId)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('shop.purchased'),
                type = 'success'
            })
        else
            lib.notify({
                title = locale('ui.error'),
                description = locale('shop.no_money'),
                type = 'error'
            })
        end
    end
end

function shops.getCurrentShop()
    return currentShop
end

function shops.setCurrentShop(shopId)
    currentShop = shopId
end

return shops
