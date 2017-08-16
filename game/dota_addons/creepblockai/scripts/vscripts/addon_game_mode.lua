if CreepBlockAI == nil then
	_G.CreepBlockAI = class({})	
end

function Activate()
    GameRules.CreepBlockAI = CreepBlockAI()
    GameRules.CreepBlockAI:InitGameMode()
end

function CreepBlockAI:InitGameMode()
	GameRules:SetShowcaseTime( 0 )
	GameRules:SetStrategyTime( 0 )
	GameRules:SetHeroSelectionTime( 0 )
	
	GameRules:GetGameModeEntity():SetCustomGameForceHero("npc_dota_hero_nevermore")
	
	ListenToGameEvent( "game_rules_state_change", Dynamic_Wrap( CreepBlockAI, 'OnGameRulesStateChange' ), self )
end

function CreepBlockAI:OnGameRulesStateChange()
	local s = GameRules:State_Get()  
	if  s == DOTA_GAMERULES_STATE_PRE_GAME then
		SendToServerConsole( "dota_all_vision 1" )
		SendToServerConsole( "dota_creeps_no_spawning  1" )
		SendToServerConsole( "dota_dev forcegamestart" )
		
	elseif  s == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		GameRules:GetGameModeEntity():SetThink("Setup", self, 1)
	end
end

function CreepBlockAI:Setup()
	goodSpawn = Entities:FindByName( nil, "npc_dota_spawner_good_mid_staging" )
	goodWP = Entities:FindByName ( nil, "lane_mid_pathcorner_goodguys_1")
	heroSpawn = Entities:FindByName (nil, "dota_goodguys_tower2_mid")
	hero = Entities:FindByName (nil, "npc_dota_hero_nevermore")
	
	directions = {}
	directions["N"] = Vector( 0, 1, 0 )
	directions["NNE"] = Vector( 0.383, 0.924, 0 )
	directions["NE"] = Vector( 0.707, 0.707, 0 )
	directions["NEE"] = Vector( 0.924, 0.383, 0 )
	directions["E"] = Vector( 1, 0, 0 )
	directions["SEE"] = Vector( 0.924, -0.383, 0 )
	directions["SE"] = Vector( 0.707, -0.707, 0 )
	directions["SSE"] = Vector( 0.383, -0.924, 0 )
	directions["S"] = Vector( 0, -1, 0 )
	directions["SSW"] = Vector( -0.383, -0.924, 0 )
	directions["SW"] = Vector( -0.707, -0.707, 0 )
	directions["SWW"] = Vector( -0.924, -0.383, 0 )
	directions["W"] = Vector( -1, 0, 0 )
	directions["NWW"] = Vector( -0.924, 0.383, 0 )
	directions["NW"] = Vector( -0.707, 0.707, 0 )
	directions["NNW"] = Vector( -0.383, 0.924, 0 )

	baseURL = "http://localhost:5000/CreepBlockAI/service"
	
	self:Reset()
	hero:SetContextThink("BotThink", function() return self:BotThink() end, 0.2)
end

--------------------------------------------------------------------------------

function CreepBlockAI:BotThink()		
	request = CreateHTTPRequestScriptVM( "POST", baseURL )
	if scenarioRunning then	
		stepCount = stepCount + 1
		request:SetHTTPRequestHeaderValue("Accept", "application/json")		
		request:SetHTTPRequestRawPostBody('application/json', self:JSONState())
	end
	request:Send( 	function( result ) 
						if result["StatusCode"] == 200 then  
							self:ParseCommand(result['Body'])
						else 
						end
					end )
	
	
	if stepCount == 80 then -- time for each episode = 80 x 0.2 = 16 seconds
		self:Reset()
	end
	if not scenarioRunning then
		return 1
	else
		return 0.2
	end
end

function CreepBlockAI:ParseCommand(body)
	local result = package.loaded['game/dkjson'].decode(body)
	local command = result.command
	
	if command == "STARTSCENARIO"  then
		self:Start()
	elseif command == "STOP"  then
		hero:Stop()
	elseif directions[command] ~= nil then
		local position = hero:GetAbsOrigin()
		hero:MoveToPosition(position + 50*directions[command])
	elseif command ~= "NIL" then
		Warning("Invalid command " .. body)
	end
end

function CreepBlockAI:JSONState()
	local state = {}
	state['step'] = stepCount
	state['hero'] = VectorToArray(hero:GetAbsOrigin())
		
	local creeps = Entities:FindAllByName("npc_dota_creep_lane")
	local i = 1
	for k,v in pairs( creeps ) do
		state['creep' .. tostring(i)] = VectorToArray(v:GetAbsOrigin())
		i = i + 1
	end   
	
	return package.loaded['game/dkjson'].encode(state)
end

 function VectorToArray(v)
	return {v.x, v.y, v.z}
 end
--------------------------------------------------------------------------------

function CreepBlockAI:Reset()
	stepCount = 0
	scenarioRunning = false
	
	SendToServerConsole( "dota_dev hero_refresh" )
	FindClearSpaceForUnit(hero, heroSpawn:GetAbsOrigin() + RandomVector( RandomFloat( 0, 200 ) ), true)
	
	local creeps = Entities:FindAllByName("npc_dota_creep_lane")
	for k,v in pairs( creeps ) do
		v:ForceKill(false)
	end		
end

function CreepBlockAI:Start()
	if scenarioRunning then
		return
	end
	scenarioRunning = true
		
	local creeps = {}
	for i=1,3 do
		creeps[i] = CreateUnitByName( "npc_dota_creep_goodguys_melee" , goodSpawn:GetAbsOrigin() + RandomVector( RandomFloat( 0, 200 ) ), true, nil, nil, DOTA_TEAM_GOODGUYS )				
	end
	creeps[4] = CreateUnitByName( "npc_dota_creep_goodguys_ranged" , goodSpawn:GetAbsOrigin() + RandomVector( RandomFloat( 0, 200 ) ), true, nil, nil, DOTA_TEAM_GOODGUYS )
	
	for i = 1,4 do 
		creeps[i]:SetInitialGoalEntity( goodWP )
	end
end    
