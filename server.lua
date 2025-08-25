local RSGCore = exports['rsg-core']:GetCoreObject()
local playersInRace = {}
local raceStarted = false
local rewardAmount = 100
local racePoints = {}
local totalLaps = 1
local raceResults = {}
local currentRaceFinishers = {}
local savedTracks = {}
local loadLatestTrackOnRestart = true -- Configurable: Set to true to load the most recent track into racePoints on restart

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
       
        local createTableSQL = [[
            CREATE TABLE IF NOT EXISTS horse_race_tracks (
                track_id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(50) NOT NULL,
                points JSON NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ]]
        local success, error = pcall(function()
            exports['oxmysql']:executeSync(createTableSQL)
        end)
        if not success then
           
            return
        end

        
        local result = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
        if not result then
           
            return
        end

        savedTracks = {}
        for _, row in ipairs(result) do
            local points = json.decode(row.points)
            if points then
                table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
            else
                
            end
        end
       

       
        if loadLatestTrackOnRestart and #savedTracks > 0 then
            racePoints = savedTracks[1].points
           
            TriggerClientEvent('rsg-track:syncTrack', -1, racePoints, true)
        end

       
        TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
       
    end
end)

AddEventHandler('playerConnecting', function()
    local src = source
   
    TriggerClientEvent('rsg-track:syncTracks', src, savedTracks)
    if #racePoints >= 2 then
        TriggerClientEvent('rsg-track:syncTrack', src, racePoints, true)
    end
end)


RegisterServerEvent('rsg-track:requestTracks')
AddEventHandler('rsg-track:requestTracks', function()
    local src = source
    
    TriggerClientEvent('rsg-track:syncTracks', src, savedTracks)
    if #racePoints >= 2 then
        TriggerClientEvent('rsg-track:syncTrack', src, racePoints, true)
    end
end)

RegisterServerEvent('rsg-track:setLaps')
AddEventHandler('rsg-track:setLaps', function(laps)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    totalLaps = math.max(1, math.min(5, laps))
    TriggerClientEvent('rsg-track:syncLaps', -1, totalLaps)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Horse Race',
        description = 'Race laps set to ' .. totalLaps .. ' by ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        type = 'inform'
    })
end)

RegisterServerEvent('rsg-track:deleteTrack')
AddEventHandler('rsg-track:deleteTrack', function(trackId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local result = exports['oxmysql']:executeSync('DELETE FROM horse_race_tracks WHERE track_id = :track_id', {track_id = trackId})
    if result.affectedRows > 0 then
        savedTracks = {}
        local tracks = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
        if tracks then
            for _, row in ipairs(tracks) do
                local points = json.decode(row.points)
                if points then
                    table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
                end
            end
        end
        
        TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Race',
            description = 'Track deleted successfully!',
            type = 'success'
        })
        
        if #racePoints > 0 then
            for _, track in ipairs(savedTracks) do
                if track.track_id == trackId then
                    racePoints = {}
                    TriggerClientEvent('rsg-track:syncTrack', -1, {}, false)
                    break
                end
            end
        end
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Race',
            description = 'Track not found or could not be deleted!',
            type = 'error'
        })
    end
end)

RegisterServerEvent('rsg-track:joinRace')
AddEventHandler('rsg-track:joinRace', function()
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
    playersInRace[src] = { name = playerName, laps = 0, passedEndPoint = false }
    TriggerClientEvent('rsg-track:joinedRace', src)
    TriggerClientEvent('rsg-track:updatePlayers', -1, playersInRace, raceStarted)
    TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'You joined the race!', type = 'success'})
end)

RegisterServerEvent('horse_race:trackCreated')
AddEventHandler('horse_race:trackCreated', function(points, trackName)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if #points < 2 then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Invalid track points!', type = 'error'})
        return
    end
    
    local pointsJson = json.encode(points)
    local success, error = pcall(function()
        exports['oxmysql']:executeSync('INSERT INTO horse_race_tracks (name, points) VALUES (:name, :points)', {
            name = trackName or ('Track ' .. (#savedTracks + 1)),
            points = pointsJson
        })
    end)
    if not success then
       
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Failed to save track!', type = 'error'})
        return
    end
    
    local result = exports['oxmysql']:fetchSync('SELECT track_id, name, points FROM horse_race_tracks ORDER BY timestamp DESC')
    if result then
        savedTracks = {}
        for _, row in ipairs(result) do
            local points = json.decode(row.points)
            if points then
                table.insert(savedTracks, {track_id = row.track_id, name = row.name, points = points})
            end
        end
        
    else
        
    end
    
    racePoints = points
    TriggerClientEvent('rsg-track:syncTrack', -1, points, true)
    TriggerClientEvent('rsg-track:syncTracks', -1, savedTracks)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Horse Race',
        description = 'Track "' .. (trackName or 'Unnamed') .. '" created! Players can join.',
        type = 'success'
    })
end)

RegisterServerEvent('rsg-track:loadTrack')
AddEventHandler('rsg-track:loadTrack', function(trackId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if raceStarted then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Cannot load track during a race!', type = 'error'})
        return
    end
    
    for _, track in ipairs(savedTracks) do
        if track.track_id == trackId then
            racePoints = track.points
            TriggerClientEvent('rsg-track:syncTrack', -1, track.points, true)
            TriggerClientEvent('ox_lib:notify', -1, {
                title = 'Horse Race',
                description = 'Track "' .. track.name .. '" loaded by ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                type = 'success'
            })
            return
        end
    end
    TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Track not found!', type = 'error'})
end)

RegisterServerEvent('rsg-track:leaveRace')
AddEventHandler('rsg-track:leaveRace', function()
    local src = source
    if playersInRace[src] then
        playersInRace[src] = nil
        TriggerClientEvent('rsg-track:leftRace', src)
        TriggerClientEvent('rsg-track:updatePlayers', -1, playersInRace, raceStarted)
    end
end)

RegisterServerEvent('rsg-track:startRace')
AddEventHandler('rsg-track:startRace', function()
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
    if playerCount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'At least 1 player required!', type = 'error'})
        return
    end
    
    if raceStarted then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Race in progress!', type = 'error'})
        return
    end
    
    raceStarted = true
    TriggerClientEvent('rsg-track:updatePlayers', -1, playersInRace, raceStarted)
    TriggerClientEvent('rsg-track:startRace', -1)
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
   
    
    if not Player then
        
        return
    end
    if not playersInRace[src] then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'You are not in the race!', type = 'error'})
        return
    end
    if playerLaps < totalLaps then
        TriggerClientEvent('ox_lib:notify', src, {title = 'Horse Race', description = 'Incomplete laps!', type = 'error'})
        return
    end
    
    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    local position = #currentRaceFinishers + 1
    table.insert(currentRaceFinishers, {name = playerName, position = position, laps = totalLaps})
    
    TriggerClientEvent('rsg-track:showFinisherNotification', -1, playerName, position)
    
    if position == 1 then
        Player.Functions.AddMoney('cash', rewardAmount)
        TriggerClientEvent('rsg-track:rewardReceived', src, rewardAmount)
    end
    
    playersInRace[src] = nil
    TriggerClientEvent('rsg-track:syncResults', -1, currentRaceFinishers)
    
    local playerCount = 0
    for _ in pairs(playersInRace) do playerCount = playerCount + 1 end
    
    if playerCount == 0 then
        table.insert(raceResults, {finishers = currentRaceFinishers, raceId = #raceResults + 1})
        if #raceResults > 5 then table.remove(raceResults, 1) end
        
        TriggerClientEvent('rsg-track:syncRaceResults', -1, raceResults)
        TriggerClientEvent('rsg-track:finishRace', -1)
        raceStarted = false
        racePoints = {}
        playersInRace = {}
        currentRaceFinishers = {}
        totalLaps = 1
        TriggerClientEvent('rsg-track:resetRace', -1, false)
        TriggerClientEvent('rsg-track:updatePlayers', -1, playersInRace, raceStarted)
        TriggerClientEvent('rsg-track:syncResults', -1, {})
        TriggerClientEvent('ox_lib:notify', -1, {
            title = 'Horse Race',
            description = 'Race ended! Ready for a new one.',
            type = 'inform'
        })
    end
end)

RegisterServerEvent('horse_race:countdownFinished')
AddEventHandler('horse_race:countdownFinished', function()
    TriggerClientEvent('rsg-track:raceStarted', -1)
end)

RegisterServerEvent('rsg-track:resetRace')
AddEventHandler('rsg-track:resetRace', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    racePoints = {}
    playersInRace = {}
    raceStarted = false
    totalLaps = 1
    raceResults = {}
    currentRaceFinishers = {}
    TriggerClientEvent('rsg-track:syncRaceResults', -1, raceResults)
    TriggerClientEvent('rsg-track:resetRace', -1, true)
    TriggerClientEvent('ox_lib:notify', -1, {title = 'Horse Race', description = 'Race reset!', type = 'inform'})
end)
