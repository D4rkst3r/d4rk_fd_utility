fx_version 'cerulean'
game 'gta5'

name 'd4rk_fd_utility'
description 'Modular Fire Department Utility - Extrication, HazMat, Scene & more'
author 'd4rk'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/locale.lua',
    'shared/utils.lua',
    'shared/item_registry.lua',
    'shared/core.lua',
}

client_scripts {
    'client/main.lua',
    'client/extrication.lua',
    'client/hazmat.lua',
    'client/scene.lua',
    'client/equipment.lua',
    'client/patient.lua',
    'client/fire.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- MySQL.* global verfügbar machen
    'shared/database.lua',
    'server/vehicle_state.lua',
    'server/main.lua',
    'server/item_handler.lua',
}

dependencies {
    'ox_lib',
    'ox_target',
}

-- ox_inventory ist optional - wird in config aktiviert
