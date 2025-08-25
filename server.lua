local RSGCore = exports['rsg-core']:GetCoreObject()
local playersInRace = {}
local raceStarted = false
local rewardAmount = 100
local racePoints = {}
local totalLaps = 1
local raceResults = {}
local currentRaceFinishers = {}


RegisterServerEvent('horse_race:setLaps')
AddEventHandler('horse_race:setLaps', function(laps)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    totalLaps = math.max(1, math.min(5, laps)) -- Clamp between 1-5
    TriggerClientEvent('horse_race:syncLaps', -1, totalLaps)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Horse Race',
        description = 'Race laps set to ' .. totalLaps .. ' by ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        type = 'inform'
    })
end)


RegisterServerEvent('horse_race:joinRace')
AddEventHandler('horse_race:joinRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if #racePoints < 2 then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'No track created yet!', type = 'error'})
        return
    end
    
    if raceStarted then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Race already started!', type = 'error'})
        return
    end
    
    if playersInRace[src] then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'You are already in the race!', type = 'error'})
        return
    end
    
    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    playersInRace[src] = playerName
    TriggerClientEvent('horse_race:joinedRace', src)
    TriggerClientEvent('horse_race:updatePlayers', -1, playersInRace, raceStarted)
    TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'You joined the race!', type = 'success'})
end)


RegisterServerEvent('horse_race:trackCreated')
AddEventHandler('horse_race:trackCreated', function(points)
    local src = source
    if #points < 2 then return end
    racePoints = points
    TriggerClientEvent('horse_race:syncTrack', -1, points, true)
    TriggerClientEvent('ox_lib:notify', -1, {title = 'Horse Race', description = 'Track created! Players can join.', type = 'success'})
end)


RegisterServerEvent('horse_race:leaveRace')
AddEventHandler('horse_race:leaveRace', function()
    local src = source
    if playersInRace[src] then
        playersInRace[src] = nil
        TriggerClientEvent('horse_race:leftRace', src)
        TriggerClientEvent('horse_race:updatePlayers', -1, playersInRace, raceStarted)
    end
end)


RegisterServerEvent('horse_race:startRace')
AddEventHandler('horse_race:startRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Player data not found!', type = 'error'})
        return
    end
    
    if #racePoints < 2 then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'No track created!', type = 'error'})
        return
    end
    
    local playerCount = 0
    for _ in pairs(playersInRace) do playerCount = playerCount + 1 end
    if playerCount < 1 then -- Minimum 1 player (adjustable)
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'At least 1 player required!', type = 'error'})
        return
    end
    
    if raceStarted then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Race already in progress!', type = 'error'})
        return
    end
    
    raceStarted = true
    TriggerClientEvent('horse_race:updatePlayers', -1, playersInRace, raceStarted)
    TriggerClientEvent('horse_race:startRace', -1)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Horse Race',
        description = 'Race started by ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. '!',
        type = 'success'
    })
end)


RegisterServerEvent('horse_race:finishRace')
AddEventHandler('horse_race:finishRace', function(playerLaps)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not playersInRace[src] or playerLaps < totalLaps then return end
    
    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    local position = #currentRaceFinishers + 1
    table.insert(currentRaceFinishers, {name = playerName, position = position, laps = totalLaps})
    
    TriggerClientEvent('horse_race:showFinisherNotification', -1, playerName, position)
    
    if position == 1 then
        Player.Functions.AddMoney('cash', rewardAmount)
        TriggerClientEvent('horse_race:rewardReceived', src, rewardAmount)
    end
    
    playersInRace[src] = nil
    TriggerClientEvent('horse_race:syncResults', -1, currentRaceFinishers)
    
    local playerCount = 0
    for _ in pairs(playersInRace) do playerCount = playerCount + 1 end
    if playerCount == 0 then
        table.insert(raceResults, {finishers = currentRaceFinishers, raceId = #raceResults + 1})
        if #raceResults > 5 then table.remove(raceResults, 1) end
        
        TriggerClientEvent('horse_race:finishRace', -1)
        raceStarted = false
        racePoints = {}
        playersInRace = {}
        currentRaceFinishers = {}
        totalLaps = 1
        TriggerClientEvent('horse_race:resetRace', -1, false)
        TriggerClientEvent('horse_race:updatePlayers', -1, playersInRace, raceStarted)
        TriggerClientEvent('horse_race:syncResults', -1, {})
        TriggerClientEvent('ox_lib:notify', -1, {
            title = 'Horse Race',
            description = 'Race ended! Ready for a new one.',
            type = 'inform'
        })
    end
end)


RegisterServerEvent('horse_race:countdownFinished')
AddEventHandler('horse_race:countdownFinished', function()
    TriggerClientEvent('horse_race:raceStarted', -1)
end)


RegisterServerEvent('horse_race:resetRace')
AddEventHandler('horse_race:resetRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    racePoints = {}
    playersInRace = {}
    raceStarted = false
    totalLaps = 1
    raceResults = {}
    currentRaceFinishers = {}
    TriggerClientEvent('horse_race:resetRace', -1, true)
    TriggerClientEvent('ox_lib:notify', -1, {title = 'Horse Race', description = 'Race reset!', type = 'inform'})
end)