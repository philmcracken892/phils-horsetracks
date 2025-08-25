local RSGCore = exports['rsg-core']:GetCoreObject()
local inRace = false
local raceStarted = false
local playersInRace = {}
local racePoints = {}
local trackCreated = false
local raceBlip = nil
local playerLaps = 0
local totalLaps = 1
local particleHandles = {}
local raceResults = {}
local currentRaceFinishers = {}
local savedTracks = {}
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local racePrompt = nil
local isGpsActive = false
local isWaitingForTracks = false
Citizen.CreateThread(function()
    local str = 'Open Race Menu'
    racePrompt = PromptRegisterBegin()
    PromptSetControlAction(racePrompt, 0xF3830D8E) -- J key
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(racePrompt, str)
    PromptSetEnabled(racePrompt, false)
    PromptSetVisible(racePrompt, false)
    PromptSetHoldMode(racePrompt, true)
    PromptSetGroup(racePrompt, promptGroup)
    PromptRegisterEnd(racePrompt)
end)

local function CreateRaceBlip()
    if raceBlip then RemoveBlip(raceBlip) end
    if racePoints[1] then
        raceBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, racePoints[1].x, racePoints[1].y, racePoints[1].z)
        SetBlipSprite(raceBlip, 1754506823, 1)
        SetBlipScale(raceBlip, 1.0)
        Citizen.InvokeNative(0x9CB1A1623062F402, raceBlip, "Horse Race Start")
    end
end

local function ClearParticles()
    for _, handle in pairs(particleHandles) do
        if DoesParticleFxLoopedExist(handle) then StopParticleFxLooped(handle, false) end
    end
    particleHandles = {}
end

local function ApplyParticleEffect(coords)
    if not coords then return end
    local ptfxDict = "scr_net_target_races"
    local ptfxName = "scr_net_target_fire_ring_mp"
    if not HasNamedPtfxAssetLoaded(ptfxDict) then
        RequestNamedPtfxAsset(ptfxDict)
        while not HasNamedPtfxAssetLoaded(ptfxDict) do Wait(0) end
    end
    UseParticleFxAsset(ptfxDict)
    local handle = StartParticleFxLoopedAtCoord(ptfxName, coords.x, coords.y, coords.z + 1.5, 0.0, 0.0, 0.0, 4.5, false, false, false, false)
    if handle then SetParticleFxLoopedColour(handle, 1.0, 0.0, 0.0, false) end
    return handle
end

local function SetRaceGPS()
    if not racePoints[1] or not racePoints[2] then return end
    if isGpsActive then
        ClearGpsMultiRoute()
        isGpsActive = false
    end
    StartGpsMultiRoute(0x3D9A8F9E, true, true)
    AddPointToGpsMultiRoute(racePoints[1].x, racePoints[1].y, racePoints[1].z)
    AddPointToGpsMultiRoute(racePoints[2].x, racePoints[2].y, racePoints[2].z)
    SetGpsMultiRouteRender(true)
    isGpsActive = true
end

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if trackCreated and racePoints[1] and not raceStarted then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            local startPoint = racePoints[1]
            if not particleHandles[1] then
                local handle = ApplyParticleEffect(startPoint)
                if handle then table.insert(particleHandles, handle) end
            end
            if Vdist(coords.x, coords.y, coords.z, startPoint.x, startPoint.y, startPoint.z) < 10.0 then
                PromptSetEnabled(racePrompt, true)
                PromptSetVisible(racePrompt, true)
                PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', 'Horse Race'))
                if PromptHasHoldModeCompleted(racePrompt) then
                    OpenRaceMenu()
                    Wait(1000)
                end
            else
                PromptSetEnabled(racePrompt, false)
                PromptSetVisible(racePrompt, false)
            end
        else
            ClearParticles()
            PromptSetEnabled(racePrompt, false)
            PromptSetVisible(racePrompt, false)
        end
    end
end)

RegisterNetEvent('rsg-track:syncTracks')
AddEventHandler('rsg-track:syncTracks', function(tracks)
   
    savedTracks = tracks or {}
    if type(savedTracks) ~= 'table' then
        
        savedTracks = {}
    end
   
    
    if lib.getOpenContextMenu() == 'horse_race_menu' then
       
        OpenRaceMenu()
    end
    
    if isWaitingForTracks and #savedTracks > 0 then
       
        isWaitingForTracks = false
        OpenRaceMenu()
    end
end)


function LoadTracksFromServer()
    TriggerServerEvent('rsg-track:requestTracks')
    
end

function OpenRaceMenu()
  
    LoadTracksFromServer()
    
    if lib.getOpenContextMenu() == 'horse_race_menu' then
        return
    end
    
    local options = {
        {
            title = '\xF0\x9F\x8F\x81 Create Track',
            description = 'Set points for a new race track',
            onSelect = CreateRaceTrack,
            disabled = trackCreated or raceStarted
        },
        {
            title = '\xF0\x9F\x97\xBA Load Saved Track',
            description = 'Select a previously saved track',
            onSelect = function()
                local trackOptions = {}
                for _, track in ipairs(savedTracks) do
                    table.insert(trackOptions, {
                        title = track.name,
                        description = 'Load track ID ' .. track.track_id,
                        onSelect = function()
                            TriggerServerEvent('rsg-track:loadTrack', track.track_id)
                            lib.notify({title = 'Horse Race', description = 'Loading track: ' .. track.name, type = 'inform'})
                        end
                    })
                end
                if #trackOptions == 0 then
                    table.insert(trackOptions, {title = 'No Tracks Available', description = 'No saved tracks found', disabled = true})
                end
                lib.registerContext({
                    id = 'horse_race_load_track_menu',
                    title = '\xF0\x9F\x97\xBA Saved Tracks',
                    options = trackOptions
                })
                lib.showContext('horse_race_load_track_menu')
            end,
            disabled = raceStarted or #savedTracks == 0
        },
        {
            title = '\xF0\x9F\x97\x91\xEF\xB8\x8F Delete Saved Track',
            description = 'Delete a previously saved track',
            onSelect = function()
                local trackOptions = {}
                for _, track in ipairs(savedTracks) do
                    table.insert(trackOptions, {
                        title = track.name,
                        description = 'Delete track ID ' .. track.track_id,
                        onSelect = function()
                            local confirm = lib.inputDialog('Confirm Deletion', {
                                {type = 'confirm', label = 'Delete ' .. track.name .. '?'}
                            })
                            if confirm then
                                TriggerServerEvent('rsg-track:deleteTrack', track.track_id)
                                lib.notify({title = 'Horse Race', description = 'Requested deletion of track: ' .. track.name, type = 'inform'})
                            end
                        end
                    })
                end
                if #trackOptions == 0 then
                    table.insert(trackOptions, {title = 'No Tracks Available', description = 'No saved tracks to delete', disabled = true})
                end
                lib.registerContext({
                    id = 'horse_race_delete_track_menu',
                    title = '\xF0\x9F\x97\x91\xEF\xB8\x8F Delete Saved Tracks',
                    options = trackOptions
                })
                lib.showContext('horse_race_delete_track_menu')
            end,
            disabled = raceStarted or #savedTracks == 0
        },
        {
            title = '\xF0\x9F\x90\xB4 Join Race',
            description = 'Join the horse race',
            onSelect = function() TriggerServerEvent('rsg-track:joinRace') end,
            disabled = inRace or raceStarted or not trackCreated
        },
        {
            title = '\xF0\x9F\x90\xBE Set Laps',
            description = 'Set laps (1-5)',
            onSelect = function()
                local input = lib.inputDialog('Set Laps', {{type = 'number', label = 'Laps', required = true, min = 1, max = 5}})
                if input then TriggerServerEvent('rsg-track:setLaps', input[1]) end
            end,
            disabled = raceStarted or not trackCreated
        },
        {
            title = '\xF0\x9F\x9A\xAA Leave Race',
            description = 'Leave the race if joined',
            onSelect = function() TriggerServerEvent('rsg-track:leaveRace') end,
            disabled = not inRace or raceStarted
        },
        {
            title = '\xE2\x96\xB6\xEF\xB8\x8F Start Race',
            description = 'Start the race (Host only)',
            onSelect = function() TriggerServerEvent('rsg-track:startRace') end,
            disabled = raceStarted or not trackCreated or next(playersInRace) == nil
        },
        {
            title = '\xF0\x9F\x91\xA5 View Participants',
            description = 'See who is in the race',
            onSelect = function()
                local participantList = {}
                for _, name in pairs(playersInRace) do
                    table.insert(participantList, name)
                end
                local list = 'Participants: ' .. (#participantList > 0 and table.concat(participantList, ', ') or 'None')
                lib.notify({title = 'Horse Race', description = list, type = 'inform'})
            end,
            disabled = not trackCreated
        },
        {
            title = '\xF0\x9F\x93\x8A View Last Race Results',
            description = 'View results of the last race',
            onSelect = function()
                local resultList = {}
                local lastRace = raceResults[#raceResults]
                if lastRace and lastRace.finishers then
                    for pos, finisher in ipairs(lastRace.finishers) do
                        table.insert(resultList, pos .. '. ' .. finisher.name .. ' (' .. finisher.laps .. ' laps)')
                    end
                end
                local results = 'Last Race Results: ' .. (#resultList > 0 and table.concat(resultList, ', ') or 'No results available')
                lib.notify({title = 'Horse Race', description = results, type = 'inform'})
            end,
            disabled = #raceResults == 0
        },
        {
            title = '\xF0\x9F\x94\x84 Reset Track',
            description = 'Reset the current race track and all race data',
            onSelect = function() TriggerServerEvent('rsg-track:resetRace') end,
            disabled = raceStarted
        }
    }
    
    lib.registerContext({
        id = 'horse_race_menu',
        title = '\xF0\x9F\x8F\x87 Race Menu',
        options = options
    })
    lib.showContext('horse_race_menu')
end



RegisterCommand('racerace', function()
   
    OpenRaceMenu()
end, false)



function CreateRaceTrack()
    racePoints = {}
    lib.notify({title = 'Horse Race', description = 'Set start point with J'})
    Citizen.CreateThread(function()
        while #racePoints < 2 do
            Wait(0)
            local coords = GetEntityCoords(PlayerPedId())
            DrawMarker(28, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 1.5, 1.5, 1.5, 255, 0, 0, 150, false, true, 2)
            if IsControlJustPressed(0, 0xF3830D8E) then
                table.insert(racePoints, {x = coords.x, y = coords.y, z = coords.z})
                lib.notify({title = 'Horse Race', description = #racePoints == 1 and 'Start set! Now set end point' or 'Track points set!'})
                if #racePoints == 2 then
                    local input = lib.inputDialog('Name Your Track', {{type = 'input', label = 'Track Name', required = true, max = 50}})
                    if input then
                        trackCreated = true
                        TriggerServerEvent('horse_race:trackCreated', racePoints, input[1])
                        CreateRaceBlip()
                        SetRaceGPS()
                        OpenRaceMenu()
                    else
                        racePoints = {}
                        lib.notify({title = 'Horse Race', description = 'Track creation cancelled', type = 'error'})
                    end
                end
            end
        end
    end)
end

RegisterNetEvent('rsg-track:syncTrack')
AddEventHandler('rsg-track:syncTrack', function(points, created)
   
    racePoints = points or {}
    trackCreated = created
    if created and racePoints[1] and racePoints[2] then
        CreateRaceBlip()
        SetRaceGPS()
    else
        if raceBlip then RemoveBlip(raceBlip) raceBlip = nil end
        if isGpsActive then
            ClearGpsMultiRoute()
            isGpsActive = false
        end
    end
end)

RegisterNetEvent('rsg-track:syncTracks')
AddEventHandler('rsg-track:syncTracks', function(tracks)
    savedTracks = tracks or {}
    if type(savedTracks) ~= 'table' then
        
        savedTracks = {}
    end
    if lib.getOpenContextMenu() == 'horse_race_menu' then
        OpenRaceMenu()
    end
end)

local function StartRaceCountdown()
    local count = 10
    Citizen.CreateThread(function()
        while count > 0 do
            lib.notify({title = 'Horse Race', description = 'Starting in ' .. count .. '...', type = 'inform'})
            Wait(1000)
            count = count - 1
        end
        lib.notify({title = 'Horse Race', description = 'GO!', type = 'success'})
        TriggerServerEvent('horse_race:countdownFinished')
    end)
end




Citizen.CreateThread(function()
    local lastCheckpointTime = 0
    local minCheckpointDelay = 3000 
    local raceActive = false
    
    while true do
        Wait(100) 
        
        if raceStarted and inRace then
            local coords = GetEntityCoords(PlayerPedId())
            local endPoint = racePoints[2]
            local currentTime = GetGameTimer()
            
           
            if not particleHandles[2] and endPoint then
                local handle = ApplyParticleEffect(endPoint)
                if handle then 
                    table.insert(particleHandles, handle) 
                end
            end
            
           
            if not isGpsActive then
                SetRaceGPS()
            end
            
            if endPoint then
               
                local distToEnd = Vdist(coords.x, coords.y, coords.z, endPoint.x, endPoint.y, endPoint.z)
                
             
                local pointDistance = racePoints[1] and Vdist(racePoints[1].x, racePoints[1].y, racePoints[1].z, endPoint.x, endPoint.y, endPoint.z) or 15.0
                local detectionRadius = math.max(4.0, math.min(8.0, pointDistance / 3))
                
              
                if distToEnd < detectionRadius and (currentTime - lastCheckpointTime) > minCheckpointDelay then
                    playerLaps = playerLaps + 1
                    lastCheckpointTime = currentTime
                    
                    if playerLaps == 1 then
                      
                        raceActive = true
                        lib.notify({
                            title = 'Horse Race', 
                            description = 'Lap 1/' .. totalLaps .. ' completed!', 
                            type = 'success'
                        })
                    elseif playerLaps >= totalLaps then
                        -- Race finished
                        lib.notify({
                            title = 'Horse Race', 
                            description = 'Race Finished! Total laps: ' .. playerLaps .. '/' .. totalLaps, 
                            type = 'success'
                        })
                        TriggerServerEvent('horse_race:finishRace', playerLaps)
                        
                      
                        inRace = false
                        playerLaps = 0
                        raceActive = false
                        
                      
                        if isGpsActive then
                            ClearGpsMultiRoute()
                            isGpsActive = false
                        end
                    else
                        
                        lib.notify({
                            title = 'Horse Race', 
                            description = 'Lap ' .. playerLaps .. '/' .. totalLaps .. ' completed!', 
                            type = 'inform'
                        })
                    end
                end
            end
        else
            
            ClearParticles()
            playerLaps = 0
            raceActive = false
            lastCheckpointTime = 0
            
            if isGpsActive then
                ClearGpsMultiRoute()
                isGpsActive = false
            end
        end
    end
end)




RegisterNetEvent('rsg-track:syncLaps')
AddEventHandler('rsg-track:syncLaps', function(laps)
   
    totalLaps = laps
end)

RegisterNetEvent('rsg-track:updatePlayers')
AddEventHandler('rsg-track:updatePlayers', function(playerList, started)
   
    playersInRace = playerList
    raceStarted = started
end)

RegisterNetEvent('rsg-track:joinedRace')
AddEventHandler('rsg-track:joinedRace', function()
    inRace = true
    playerLaps = 0
    lib.notify({title = 'Horse Race', description = 'You joined the race!'})
end)

RegisterNetEvent('rsg-track:leftRace')
AddEventHandler('rsg-track:leftRace', function()
    inRace = false
    playerLaps = 0
    lib.notify({title = 'Horse Race', description = 'You left the race'})
end)

RegisterNetEvent('rsg-track:startRace')
AddEventHandler('rsg-track:startRace', function()
    if inRace then StartRaceCountdown() end
end)

RegisterNetEvent('rsg-track:raceStarted')
AddEventHandler('rsg-track:raceStarted', function()
    raceStarted = true
    lib.notify({title = 'Horse Race', description = 'Race has started! Cross the finish line to complete laps.', type = 'success'})
end)

RegisterNetEvent('rsg-track:finishRace')
AddEventHandler('rsg-track:finishRace', function()
    raceStarted = false
    inRace = false
    playerLaps = 0
    ClearParticles()
    if isGpsActive then
        ClearGpsMultiRoute()
        isGpsActive = false
    end
    if raceBlip then 
        RemoveBlip(raceBlip) 
        raceBlip = nil 
    end
end)

RegisterNetEvent('rsg-track:rewardReceived')
AddEventHandler('rsg-track:rewardReceived', function(amount)
    lib.notify({title = 'Horse Race', description = 'You won $' .. amount .. '!'})
end)

RegisterNetEvent('rsg-track:showFinisherNotification')
AddEventHandler('rsg-track:showFinisherNotification', function(name, pos)
    lib.notify({title = 'Horse Race', description = name .. ' finished in position ' .. pos .. '!'})
end)

RegisterNetEvent('rsg-track:syncResults')
AddEventHandler('rsg-track:syncResults', function(finishers)
    currentRaceFinishers = finishers
  
end)

RegisterNetEvent('rsg-track:syncRaceResults')
AddEventHandler('rsg-track:syncRaceResults', function(results)
    raceResults = results
   
end)

RegisterNetEvent('rsg-track:resetRace')
AddEventHandler('rsg-track:resetRace', function(manual)
    racePoints = {}
    inRace = false
    raceStarted = false
    playersInRace = {}
    trackCreated = false
    playerLaps = 0
    totalLaps = 1
    if manual then 
        raceResults = {} 
        currentRaceFinishers = {} 
    end
    ClearParticles()
    if isGpsActive then
        ClearGpsMultiRoute()
        isGpsActive = false
    end
    if raceBlip then 
        RemoveBlip(raceBlip) 
        raceBlip = nil 
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if racePrompt then PromptDelete(racePrompt) end
        ClearParticles()
        if isGpsActive then
            ClearGpsMultiRoute()
            isGpsActive = false
        end
        if raceBlip then RemoveBlip(raceBlip) end
    end
end)
