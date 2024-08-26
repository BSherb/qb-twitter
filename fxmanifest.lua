fx_version 'cerulean'
game 'gta5'

author 'B_Sherb'
description 'QB Twitter Logging to Discord'
version '1.0.0'

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Include this line to ensure oxmysql is loaded
    'server.lua'
}
