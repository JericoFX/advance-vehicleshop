fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'advanced-vehicleshop'
author 'Eduardo'
version '1.0.0'
description 'Advanced modular vehicle shop system'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/init.lua'
}

client_scripts {
    'client/init.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/init.lua',
    'modules/creator/server.lua',
    'modules/testdrive/server.lua',
    'modules/cron/server.lua'
}

files {
    'locales/*.json',
    'modules/**/client.lua',
    'modules/**/shared.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qb-core'
}
