fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'Horse Racing Script for RSG-Core'
author 'Phil Mcracken'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua'
    
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'rsg-core',
    'ox_lib'
    
}

lua54 'yes'