-- Script made by; roblox: Nyxarical | discord: nyxaric

-- Server script for round management
-- The flow is intermission > roundstart > roundend > intermission then repeats

-- Variable setup including the necessary ui elements, remote events, sounds and services
-- Player variable
local players = game:GetService("Players") 

-- Teleport variables
local teleportPart = workspace.Arena:WaitForChild("SpawnPoints"):GetChildren()
local lobbyTele = workspace:WaitForChild("lobby"):WaitForChild("SpawnLocation")

-- Remote event variables
-- remote events allow the server side round system to notify the players client when the round state changes, the client then updates the ui locally
-- keeping the server side separate from the client side makes it easier to manage and update the UI
local replicatedStorage = game:GetService("ReplicatedStorage")
local roundStartev = replicatedStorage.backEnd:WaitForChild("roundStart")
local roundEndev = replicatedStorage.backEnd:WaitForChild("roundEnd")
local intermisEv = replicatedStorage.backEnd:WaitForChild("intermission")
local waveUpdateEv = replicatedStorage.backEnd:WaitForChild("waveUpdate")
local playerKilledEv = replicatedStorage.backEnd:WaitForChild("playerKilled")

-- Sound variables
local soundService = game:GetService("SoundService")
local roundSound = soundService.Battle
local roundEndSound = soundService.End
local lobbyMusic = soundService.Lobby
-- Enemy variables
local serverStorage = game:GetService("ServerStorage")
local enemyModel = serverStorage:WaitForChild("Enemy"):WaitForChild("Zombie")
local enemySpawns = workspace:WaitForChild("EnemySpawner"):GetChildren() -- used more than one spawnpoints to enable a type of hoard attacking feeling

local activeEnemies = {} -- to keep track of enemies for cleanup
local roundKills = {} -- keeps track of players who contributed kills during the round

-- wave n enemy configurations
local wavesPerRound = 5
local enemiesPerWave = 5
local maxEnemiesPerWave = 15 -- The amount of enemies is scaled per wave and is capped by max enemies per wave, the cap increases the more rounds the player does
local defMaxEnemies = 75

-- weapon variables
local weaponFolder = serverStorage:WaitForChild("Weapons") -- refers to the folder that holds the weapons in serverstorage
local shotgun = weaponFolder:WaitForChild("Shotgun") -- the shotgun weapon
local given = false

--module requirement
local playerDataModule = require(game.ServerScriptService:WaitForChild("PlayerDataModule")) -- the module that stores the players kills and wins data

-- badge variables
local badgeService = game:GetService("BadgeService")
local WELCOME_BADGE_ID = 1154174699067590 -- badge for joining the game
local MAX_DIFFICULTY_BADGE_ID = 2995542553686994 -- badge for reaching the max difficulty

-- Miscellaneous configurations
local interDuration = 25
local roundAmount = 0
local status = true -- to open or close the loop, mainly exists to close the loop for testing

-- Enemy configuration functions

-- scales the amount of enemies per round, scales with the number of rounds completed and is capped by maxEnemiesPerWave
local function getRoundBaseEnemies()
	local scaled = enemiesPerWave * (2 ^ roundAmount)
	return math.min(scaled, maxEnemiesPerWave)
end

-- scales the amount of enemies per wave
-- later waves use a higher  muiltiplier, while math min prevents the amount of enemies from going over the max amount of enemies
local function getWaveEnemyCount(roundBase, wave)
	local scaled = roundBase * (2 ^ (wave - 1))
	return math.min(scaled, maxEnemiesPerWave)
end

-- "spawns" the enemies from serverstorage by cloning the enemy model and placing it in the workspace via the spawn points
local function spawnEnemy()
	local spawnPoint = enemySpawns[math.random(1, #enemySpawns)] -- randomizes the spawnpoint per enemyclone so it doesnt get predictable
	local enemyClone = enemyModel:Clone()
	
	enemyClone:PivotTo(spawnPoint.CFrame)
	enemyClone.Parent = workspace
	
	local highlight = Instance.new("Highlight") -- creates a highlight on each enemy so they can remain visually identifiable against the dark environment
	highlight.FillColor = Color3.new(1,0,0)
	highlight.OutlineColor = Color3.new(1,0,0)
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = enemyClone
	
	table.insert(activeEnemies, enemyClone) -- stores the enemy in a table to be able to clear them later on
	
	
	-- this function removes the enemy from the active enemy list once it dies
	-- and gives the player who killed it a kill point if a creator tag is present
	local humaniod = enemyClone:WaitForChild("Humanoid")
	humaniod.Died:Connect(function() 
		local index = table.find(activeEnemies, enemyClone)
		if index then
			table.remove(activeEnemies, index)
		end

		local creatorTag = humaniod:FindFirstChild("creator") -- finds the player that killed the zombie
		if creatorTag and creatorTag.Value then
			playerDataModule.AddKill(creatorTag.Value) -- uses an playerDatamodule function to give the player a kill point
			roundKills[creatorTag.Value] = true
		end
		task.wait(2)
		enemyClone:Destroy()
	end)
end

-- spawns the amount of enemies based on the waves enemy count
local function spawnWave(waveEnemyCount)
	for i = 1, waveEnemyCount do
		spawnEnemy()
		task.wait(0.2)
	end
end

-- force clears all enemies so they dont carry over to other rounds
-- bails if theres no enemies to clear
local function clearEnemies()
	for _, enemy in ipairs(activeEnemies) do
		if enemy and enemy.Parent then
			enemy:Destroy()
		end
	end
	table.clear(activeEnemies)
end

-- weapon configuration functions
-- gives the player the weapons in their inventory when called
local function giveWeapon(plyr)
	local backpack = plyr:WaitForChild("Backpack")

	if not backpack:FindFirstChild(shotgun.Name) then
		local shotgunClone = shotgun:Clone()
		shotgunClone.Parent = backpack
	end

end

-- removes the weapons from the players inventory when called 
-- only removes tools that match the known weapon set (shotgun)
-- so any other Tool a player might have is left untouched
local function takeWeapons(plyr)
	local backpack = plyr:WaitForChild("Backpack")
	local character = plyr.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid:UnequipTools()
	end

	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") and (tool.Name == shotgun.Name) then
			tool:Destroy()
		end
	end
end

-- teleportation function declaration
-- this function teleports the player to the "arena" when the round begins
local function teleportPlayer(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local spawnPart = teleportPart[math.random(1, #teleportPart)] -- a spawn part is chosen randomly so the player get spawned in locations that arent predictable
	humanoidRootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0) -- uses the Y offset to spawn the player slighty above the spawn point so the player doesnt spawn in the floor
	
end

-- this function teleports the player back to the lobby after the round ends
local function teleportToLobby(player) 
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	humanoidRootPart.CFrame = lobbyTele.CFrame + Vector3.new(0, 3, 0) -- uses the Y offset as well to avoid spawning the player in the floor
end

-- this function checks if the player is alive
-- its used in round system to determine if a player can continue playing or not
local function isPlayerAlive(plyr)
	local character = plyr.Character
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	-- a player is considered alive if they have more than 0 health
	return humanoid.Health > 0
end

-- this function checks if all the players died
-- this is used in the round system to determine if the round should end early when all the players died
local function allPlayersDied()
	local currentPlayers = players:GetPlayers()

	if #currentPlayers == 0 then
		return true 
	end
	-- checks each player individually and if any of them is alive then the function will return false, otherwise it will return true
	for _, plyr in ipairs(currentPlayers) do
		if isPlayerAlive(plyr) then
			return false
		end
	end
	return true 
end
	
-- function declarations to enable the while loop to work at the end of this script.

local function intermission() -- the intermission function
	-- keeps the players in the lobby while the UI and music is played
	-- givig the players time to prepare
	lobbyMusic:Play()
	
	print("intermission!")
	for i = interDuration, 0, -1 do  -- countdown that signals to the clients to update the intermission timer
		intermisEv:FireAllClients(i)
		task.wait(1)
	end
	
	lobbyMusic:Stop()
end

-- the round start function, the main character of the round system
-- includes the player teleport, enemy spawning, the wave system and difficulty scaling.
local function roundStart()
	roundSound:Play()
	print("started")

	-- clears the previous round tracked kills to avoid any overlap
	table.clear(roundKills)

    -- moves all current players from the lobby into the arena
	for _, plyr in ipairs(players:GetPlayers()) do
		teleportPlayer(plyr)
	end

	-- weapons are given only once per round
	-- the given flag prevents duplication
	if not given then
		given = true
		for _, plyr in ipairs(players:GetPlayers()) do
			giveWeapon(plyr)
		end
	end
	
	-- gives the player a short breathing period before the first wave starts
	task.wait(3)
	
	-- calculates the base amount of enemies for the  current round
	-- this number increases based on the rounds completed but is capped by the max difficulty to prevent enormous amounts of enemies
	local roundBaseEnemies = getRoundBaseEnemies()
	
	-- runs each wave in the current round
	for wave = 1, wavesPerRound do
		-- checks if all the players died before starting another wave, if so the round ends
		if allPlayersDied() then
			print("everyone died, womp womp")
			break
		end

		print("wave"..wave.."spawning")
		waveUpdateEv:FireAllClients(wave, wavesPerRound)

		-- calculates the number of enemies to spawn in the current wave
		-- later waves contain more enemies than previous waves
		local waveEnemyCount = getWaveEnemyCount(roundBaseEnemies, wave)
		spawnWave(waveEnemyCount)

		local diedMidWave = false
		
		-- waits for all enemies in the current wave to die before moving to the next wave
		while #activeEnemies > 0 do
			-- checks if all the players died, if so the round ends
			if allPlayersDied() then
				print("everyone died, womp womp")
				diedMidWave = true
				break
			end
			task.wait(1)
		end
		
		
        -- prevents another wave from starting if the players all died
		if diedMidWave then
			break
		end
	end
    -- determines if the players won or lost the round
	if allPlayersDied() then
		roundAmount = 0 -- resets the round amount if all the players died since it gets more diffcult if a player survives
	else
		-- completing a round increases the difficulty by raising the cap by five 
		-- but  math.min prevents it from passing the max difficulty cap
		roundAmount = roundAmount + 1
		local wasAtMaxDifficulty = (maxEnemiesPerWave >= defMaxEnemies)
		maxEnemiesPerWave = math.min(maxEnemiesPerWave + 5, defMaxEnemies)
		
		-- awards wins based on the number of rounds completed
		print("Players win")
		local winsEarned = roundAmount * 1
		for _, plyr in ipairs(players:GetPlayers()) do
			playerDataModule.AddWins(plyr, winsEarned)
		end
		
		--if the previous round was at max difficulty, it awards the max difficulty badge to all the players that contributed to the round
		if wasAtMaxDifficulty then
			for plyr, _ in pairs(roundKills) do
				if typeof(plyr) == "Instance" and plyr:IsA("Player") and plyr.Parent then
					local success, err = pcall(function()
						badgeService:AwardBadgeAsync(plyr.UserId, MAX_DIFFICULTY_BADGE_ID)
					end)

					-- prevents a badge api failure from stopping the round ending
					if not success then
						warn("Failed to award max difficulty badge to " .. plyr.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end
end


-- round ending function
-- ends the current round and resets the round related systems
local function roundEnd()
	-- notifies the clients that the round has ended so the ui responds accordingly
	roundEndev:FireAllClients()
	
	-- allows weapons to be given again when the next round starts
	given = false
	
	-- stops the active round music and plays the round end chime
	roundSound:Stop()
   roundEndSound:Play()
   
   -- returns all the players back to lobby and takes away their weapons
	for _, plyr in ipairs(players:GetPlayers()) do
		teleportToLobby(plyr)
		takeWeapons(plyr)
	end
	-- removes all the left over enemies, if there is any, so they dont carry over to the next round
   clearEnemies()
end

-- sets up functions that fire when a player spawns
local function onCharacterAdded(character ,plyr)

	local humanoid = character:WaitForChild("Humanoid")
	-- listens for the player's death and notifies all clients so the UI can respond accordingly
	humanoid.Died:Connect(function()
	 playerKilledEv:FireAllClients(plyr.Name)

	end)
end

-- sets up functions that fire when a player joins

local function onPlayerAdded(plyr)
	-- connects the player added function to the players character added event
	plyr.CharacterAdded:Connect(function(character)
		onCharacterAdded(character,  plyr)
	end)

    -- handles players who alr existed when the function executed
	if plyr.Character then
		onCharacterAdded(plyr.Character, plyr)
	end
	
	-- award the welcome badge to the player
	-- pcall is used to prevent a failure from interrupting anything
	local success, err = pcall(function()
		badgeService:AwardBadgeAsync(plyr.UserId, WELCOME_BADGE_ID)
	end)
	if not success then
		warn("Failed to award welcome badge to " .. plyr.Name .. ": " .. tostring(err))
	end
end


-- connects the playeradded function so new players are covered
players.PlayerAdded:Connect(onPlayerAdded)

-- covers players that existed when the script started
for _, player in ipairs(players:GetPlayers()) do
	onPlayerAdded(player)
end

-- continues the round loop forever until the status is set to false by a developer
while status == true do
	intermission()
	roundStart()
	roundEnd()
end