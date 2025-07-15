local ui = {}
local QBCore = exports['qb-core']:GetCoreObject()

function ui.init()
    ui.setupNUICallbacks()
end

function ui.showNotification(data)
    lib.notify({
        title = data.title,
        description = data.description,
        type = data.type or 'info',
        duration = data.duration or 5000
    })
end

function ui.showProgressBar(data)
    return lib.progressBar({
        duration = data.duration,
        label = data.label,
        useWhileDead = false,
        canCancel = data.canCancel or false,
        disable = {
            car = true,
            move = data.disableMove or false,
            combat = true
        },
        anim = data.anim or {
            dict = 'missheistdockssetup1clipboard@base',
            clip = 'base'
        }
    })
end

function ui.showInput(title, inputs)
    return lib.inputDialog(title, inputs)
end

function ui.showConfirmation(data)
    return lib.alertDialog({
        header = data.header,
        content = data.content,
        centered = true,
        cancel = true,
        labels = {
            confirm = data.confirmLabel or locale('ui.confirm'),
            cancel = data.cancelLabel or locale('ui.cancel')
        }
    })
end

function ui.showMenu(data)
    lib.registerContext({
        id = data.id,
        title = data.title,
        options = data.options,
        menu = data.menu,
        onExit = data.onExit
    })
    
    lib.showContext(data.id)
end

function ui.closeMenu()
    lib.hideContext()
end

function ui.showTextUI(text, position)
    lib.showTextUI(text, {
        position = position or 'left-center'
    })
end

function ui.hideTextUI()
    lib.hideTextUI()
end

function ui.drawText3D(coords, text, scale)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    
    if onScreen then
        SetTextScale(scale or 0.35, scale or 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
        
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 0, 0, 0, 75)
    end
end

function ui.createBlip(data)
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    
    SetBlipSprite(blip, data.sprite or 1)
    SetBlipDisplay(blip, data.display or 4)
    SetBlipScale(blip, data.scale or 0.8)
    SetBlipColour(blip, data.color or 0)
    SetBlipAsShortRange(blip, data.shortRange or true)
    
    if data.label then
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(data.label)
        EndTextCommandSetBlipName(blip)
    end
    
    return blip
end

function ui.removeBlip(blip)
    if DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

function ui.createMarker(data)
    DrawMarker(
        data.type or 1,
        data.coords.x,
        data.coords.y,
        data.coords.z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        data.scale.x or 1.0,
        data.scale.y or 1.0,
        data.scale.z or 1.0,
        data.color.r or 255,
        data.color.g or 255,
        data.color.b or 255,
        data.color.a or 100,
        data.bobUpAndDown or false,
        data.faceCamera or false,
        2,
        data.rotate or false,
        nil, nil, false
    )
end

function ui.playSound(sound, volume)
    PlaySoundFrontend(-1, sound, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
end

function ui.setupNUICallbacks()
    RegisterNUICallback('closeUI', function(data, cb)
        SetNuiFocus(false, false)
        cb('ok')
    end)
    
    RegisterNUICallback('playSound', function(data, cb)
        ui.playSound(data.sound)
        cb('ok')
    end)
end

function ui.showLoadingSpinner(text, duration)
    if duration then
        lib.notify({
            title = text,
            type = 'info',
            duration = duration,
            position = 'top',
            style = {
                backgroundColor = '#141517',
                color = '#C1C2C5',
                ['.description'] = {
                    color = '#909296'
                }
            }
        })
    else
        lib.showTextUI(text, {
            position = 'right-center',
            icon = 'spinner',
            iconAnimation = 'spin'
        })
    end
end

function ui.hideLoadingSpinner()
    lib.hideTextUI()
end

function ui.createRadialMenu(items)
    lib.registerRadial({
        id = 'vehicleshop_radial',
        items = items
    })
    
    lib.addRadialItem({
        id = 'vehicleshop_menu',
        label = locale('management.title'),
        icon = 'car',
        menu = 'vehicleshop_radial'
    })
end

function ui.removeRadialMenu()
    lib.removeRadialItem('vehicleshop_menu')
end

return ui
