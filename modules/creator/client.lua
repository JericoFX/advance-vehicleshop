local module = {}
local creatingShop = false
local shopData = {}
local blips = {}
local points = {}

local function cleanup()
    for _, blip in pairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    
    for _, point in pairs(points) do
        if point then
            point:remove()
        end
    end
    
    blips = {}
    points = {}
    shopData = {}
    creatingShop = false
end

local function createZonePoint(index, zoneType)
    local function onSelect()
        local coords = GetEntityCoords(cache.ped)
        local heading = GetEntityHeading(cache.ped)
        
        shopData.locations[zoneType] = vec4(coords.x, coords.y, coords.z, heading)
        
        lib.notify({
            title = locale('ui.success'),
            description = zoneType .. ' location set',
            type = 'success'
        })
        
        if DoesBlipExist(blips[zoneType]) then
            RemoveBlip(blips[zoneType])
        end
        
        blips[zoneType] = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blips[zoneType], 1)
        SetBlipColour(blips[zoneType], 2)
        SetBlipScale(blips[zoneType], 0.8)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(shopData.name .. " - " .. zoneType)
        EndTextCommandSetBlipName(blips[zoneType])
        
        return true
    end
    
    lib.showTextUI('[E] - Set ' .. zoneType .. ' location')
    
    CreateThread(function()
        while creatingShop do
            if IsControlJustPressed(0, 38) then
                if onSelect() then
                    lib.hideTextUI()
                    break
                end
            end
            Wait(0)
        end
    end)
end

function module.startCreation()
    if creatingShop then return end
    
    creatingShop = true
    shopData = {
        locations = {}
    }
    
    local input = lib.inputDialog(locale('shop.create_title'), {
        {
            type = 'input',
            label = locale('shop.create_name'),
            required = true,
            min = 3,
            max = 30
        },
        {
            type = 'number',
            label = locale('shop.create_price'),
            default = Config.DefaultShopPrice,
            required = true,
            min = 0
        }
    })
    
    if not input then
        cleanup()
        return
    end
    
    shopData.name = input[1]
    shopData.price = input[2]
    
    lib.notify({
        title = locale('ui.success'),
        description = 'Now set the shop locations',
        type = 'info'
    })
    
    local zones = {'entry', 'management', 'spawn', 'camera'}
    local currentZone = 1
    
    local function nextZone()
        if currentZone <= #zones then
            createZonePoint(currentZone, zones[currentZone])
            currentZone = currentZone + 1
            
            CreateThread(function()
                while not shopData.locations[zones[currentZone - 1]] and creatingShop do
                    Wait(100)
                end
                
                if creatingShop then
                    nextZone()
                end
            end)
        else
            module.confirmCreation()
        end
    end
    
    nextZone()
end

function module.confirmCreation()
    local alert = lib.alertDialog({
        header = locale('shop.create_title'),
        content = string.format('**Shop Name:** %s  \n**Price:** $%s  \n\nConfirm shop creation?',
            shopData.name, lib.math.groupdigits(shopData.price)),
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        local success = lib.callback.await('vehicleshop:createShop', false, shopData)
        
        if success then
            lib.notify({
                title = locale('ui.success'),
                description = locale('shop.created'),
                type = 'success'
            })
        else
            lib.notify({
                title = locale('ui.error'),
                description = 'Failed to create shop',
                type = 'error'
            })
        end
    end
    
    cleanup()
end

lib.addCommand('createshop', {
    help = 'Create a new vehicle shop',
    restricted = 'group.admin'
}, function()
    module.startCreation()
end)

return module
