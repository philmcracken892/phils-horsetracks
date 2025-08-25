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
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local racePrompt = nil
local isGpsActive = false

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

function OpenRaceMenu()
    print("currentRaceFinishers:", json.encode(currentRaceFinishers), "Length:", #currentRaceFinishers)
    print("raceResults:", json.encode(raceResults), "Length:", #raceResults)
    lib.registerContext({
        id = 'horse_race_menu',
        title = 'ðŸ‡ Race Menu',
        options = {
            {
                title = 'ðŸ Create Track',
                description = 'Set points for the race track',
                onSelect = CreateRaceTrack,
                disabled = trackCreated or raceStarted
            },
            {
                title = 'ðŸ´ Join Race',
                description = 'Join the horse race',
                onSelect = function() TriggerServerEvent('horse_race:joinRace') end,
                disabled = inRace or raceStarted or not trackCreated
            },
            {
                title = 'ðŸ Set Laps',
                description = 'Set laps (1-5)',
                onSelect = function()
                    local input = lib.inputDialog('Set Laps', {{type = 'number', label = 'Laps', required = true, min = 1, max = 5}})
                    if input then TriggerServerEvent('horse_race:setLaps', input[1]) end
                end,
                disabled = raceStarted or not trackCreated
            },
            {
                title = 'ðŸšª Leave Race',
                description = 'Leave the race if joined',
                onSelect = function() TriggerServerEvent('horse_race:leaveRace') end,
                disabled = not inRace or raceStarted
            },
            {
                title = 'â–¶ï¸ Start Race',
                description = 'Start the race (Host only)',
                onSelect = function() TriggerServerEvent('horse_race:startRace') end,
                disabled = raceStarted or not trackCreated or next(playersInRace) == nil
            },
            {
                title = 'ðŸ‘¥ View Participants',
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
                title = 'ðŸ“Š View Last Race Results',
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
                title = 'ðŸ”„ Reset Track',
                description = 'Reset the current race track and all race data',
                onSelect = function() TriggerServerEvent('horse_race:resetRace') end,
                disabled = raceStarted
            }
        }
    })
    lib.showContext('horse_race_menu')
end

RegisterCommand('racerace', OpenRaceMenu, false)

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
                lib.notify({title = 'Horse Race', description = #racePoints == 1 and 'Start set! Now set end point' or 'Track created!'})
                if #racePoints == 2 then
                    trackCreated = true
                    TriggerServerEvent('horse_race:trackCreated', racePoints)
                    CreateRaceBlip()
                    SetRaceGPS()
                    OpenRaceMenu()
                end
            end
        end
    end)
end

RegisterNetEvent('horse_race:syncTrack')
AddEventHandler('horse_race:syncTrack', function(points, created)
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

RegisterNetEvent('horse_race:syncRaceResults')
AddEventHandler('horse_race:syncRaceResults', function(results)
    raceResults = results
    print("Received raceResults:", json.encode(raceResults))
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
    while true do
        Wait(0)
        if raceStarted and inRace then
            local coords = GetEntityCoords(PlayerPedId())
            local startPoint = racePoints[1]
            local endPoint = racePoints[2]
            if not particleHandles[2] then table.insert(particleHandles, ApplyParticleEffect(endPoint)) end
            if not isGpsActive then
                SetRaceGPS()
            end
            if Vdist(coords.x, coords.y, coords.z, startPoint.x, startPoint.y, startPoint.z) < 5.0 then
                playerLaps = playerLaps == 0 and 1 or playerLaps
            elseif Vdist(coords.x, coords.y, coords.z, endPoint.x, endPoint.y, endPoint.z) < 5.0 and playerLaps > 0 then
                playerLaps = playerLaps + 1
                lib.notify({title = 'Horse Race', description = 'Lap ' .. playerLaps .. '/' .. totalLaps})
                if playerLaps >= totalLaps then
                    TriggerServerEvent('horse_race:finishRace', playerLaps)
                    inRace = false
                    playerLaps = 0
                    if isGpsActive then
                        ClearGpsMultiRoute()
                        isGpsActive = false
                    end
                end
            end
        else
            ClearParticles()
            playerLaps = 0
            if isGpsActive then
                ClearGpsMultiRoute()
                isGpsActive = false
            end
        end
    end
end)

RegisterNetEvent('horse_race:syncLaps')
AddEventHandler('horse_race:syncLaps', function(laps) totalLaps = laps end)

RegisterNetEvent('horse_race:updatePlayers')
AddEventHandler('horse_race:updatePlayers', function(playerList, started)
    playersInRace = playerList
    raceStarted = started
end)

RegisterNetEvent('horse_race:joinedRace')
AddEventHandler('horse_race:joinedRace', function()
    inRace = true
    playerLaps = 0
    lib.notify({title = 'Horse Race', description = 'You joined the race!'})
end)

RegisterNetEvent('horse_race:leftRace')
AddEventHandler('horse_race:leftRace', function()
    inRace = false
    playerLaps = 0
    lib.notify({title = 'Horse Race', description = 'You left the race'})
end)

RegisterNetEvent('horse_race:startRace')
AddEventHandler('horse_race:startRace', function()
    if inRace then StartRaceCountdown() end
end)

RegisterNetEvent('horse_race:raceStarted')
AddEventHandler('horse_race:raceStarted', function() raceStarted = true end)

RegisterNetEvent('horse_race:finishRace')
AddEventHandler('horse_race:finishRace', function()
    raceStarted = false
    inRace = false
    playerLaps = 0
    ClearParticles()
    if isGpsActive then
        ClearGpsMultiRoute()
        isGpsActive = false
    end
    if raceBlip then RemoveBlip(raceBlip) raceBlip = nil end
end)

RegisterNetEvent('horse_race:rewardReceived')
AddEventHandler('horse_race:rewardReceived', function(amount)
    lib.notify({title = 'Horse Race', description = 'You won $' .. amount .. '!'})
end)

RegisterNetEvent('horse_race:showFinisherNotification')
AddEventHandler('horse_race:showFinisherNotification', function(name, pos)
    lib.notify({title = 'Horse Race', description = name .. ' finished in position ' .. pos .. '!'})
end)

RegisterNetEvent('horse_race:syncResults')
AddEventHandler('horse_race:syncResults', function(finishers)
    currentRaceFinishers = finishers
    print("Received currentRaceFinishers:", json.encode(currentRaceFinishers))
end)

RegisterNetEvent('horse_race:resetRace')
AddEventHandler('horse_race:resetRace', function(manual)
    racePoints = {}
    inRace = false
    raceStarted = false
    playersInRace = {}
    trackCreated = false
    playerLaps = 0
    totalLaps = 1
    if manual then raceResults = {} currentRaceFinishers = {} end
    ClearParticles()
    if isGpsActive then
        ClearGpsMultiRoute()
        isGpsActive = false
    end
    if raceBlip then RemoveBlip(raceBlip) raceBlip = nil end
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
