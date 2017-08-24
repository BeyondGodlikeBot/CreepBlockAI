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
		GameRules:GetGameModeEntity():SetThink("Setup", self, 5)
	end
end

function CreepBlockAI:Setup()
	goodSpawn = Entities:FindByName( nil, "npc_dota_spawner_good_mid_staging" )
	goodWP = Entities:FindByName ( nil, "lane_mid_pathcorner_goodguys_1")
	heroSpawn = Entities:FindByName (nil, "dota_goodguys_tower2_mid")
	hero = Entities:FindByName (nil, "npc_dota_hero_nevermore")
	t1 =  Entities:FindByName(nil, "dota_goodguys_tower1_mid")
	t1Pos = t1:GetAbsOrigin()
	t1_c = t1Pos.y + t1Pos.x + 2000
	
	PlayerResource:SetCameraTarget(0, hero)
	
	heroSpeed = hero:GetBaseMoveSpeed()
	
	baseURL = "http://localhost:5000/CreepBlockAI"
	
	ai_state = STATE_GETMODEL
	ep = 1
	self:Reset()
	GameRules:GetGameModeEntity():SetThink("MainLoop", self)
	hero:SetContextThink("BotThink", function() return self:BotLoop() end, 0.2)
end

--------------------------------------------------------------------------------

STATE_GETMODEL = 0
STATE_SIMULATING = 1
STATE_SENDDATA = 2

function CreepBlockAI:MainLoop()
	if ai_state == STATE_GETMODEL then
		Say(hero, "Getting Latest Model..", false)
		request = CreateHTTPRequestScriptVM( "GET", baseURL .. "/model")
		request:Send( 	function( result ) 
							if result["StatusCode"] == 200 and ai_state == STATE_GETMODEL then
								local data = package.loaded['game/dkjson'].decode(result['Body'])
								self:UpdateModel(data)
								
								Say(hero, "Loaded Latest Model", false)								
								Say(hero, "Starting Episode " .. ep, false)
								
								self:Start()  
								ai_state = STATE_SIMULATING								
							end
						end )
	elseif ai_state == STATE_SIMULATING then
	
	elseif ai_state == STATE_SENDDATA then
		Say(hero, "Sending Experience..", false)
		request = CreateHTTPRequestScriptVM( "POST", baseURL .. "/update")
		request:SetHTTPRequestHeaderValue("Accept", "application/json")		
		request:SetHTTPRequestRawPostBody('application/json', package.loaded['game/dkjson'].encode(SAR))
		request:Send( 	function( result ) 
							if result["StatusCode"] == 200 and ai_state == STATE_SENDDATA then  
								Say(hero, "Model Updated", false)
								ai_state = STATE_GETMODEL
							end
						end )
	else
		Warning("Some shit has gone bad..")
	end
	
	return 3
end

function CreepBlockAI:BotLoop()
	if ai_state ~= STATE_SIMULATING then
		return 0.2
	end
			
	self:UpdatePositions()
	
	local terminal, action = self:UpdateSAR()
	if terminal then
		self:Reset()
		ai_state = STATE_SENDDATA
		return 0.2
	end
	
	hero:MoveToPosition(hPos + action)
		
	if t > 0 then
		Say(hero, "Gained Reward " .. SAR[t-1]['r'], false)
	end
	
	t = t + 1
	
	return 0.2
end

--------------------------------------------------------------------------------

function CreepBlockAI:UpdatePositions()
	hPos = hero:GetAbsOrigin()
	cPos = {}
	for i = 1,4 do
		cPos[i] = creeps[i]:GetAbsOrigin()
	end
end

function CreepBlockAI:UpdateSAR()	
	local s_t = {}
	for i = 1,4 do
		s_t[i*2-1] = (cPos[i].x - hPos.x) / heroSpeed
		s_t[i*2] = (cPos[i].y - hPos.y) / heroSpeed
	end
	
	local action = self:Run(s_t)
		
	if t > 0 then
		local reward = 0
		for i = 1,4 do
			local dist = (cPos[i] - last_cPos[i]):Length2D()
			local hdist = (hPos - cPos[i]):Length2D()
			if hdist < 500 then
				if dist < 20 then
					reward = reward + 0.5
				elseif dist < 40 then
					reward = reward + 0.35	
				elseif dist < 60 then
					reward = reward + 0.2
				end
			end
		end
		
		SAR[t-1]['r'] = reward
	end
	
	last_cPos = cPos
	
	local terminal = false
	local c1 = hPos.y + hPos.x + 100
	local min_dist = 100000
	local target = Vector(0,0,0)
	for i = 1,4 do
		local c2 = cPos[i].y - cPos[i].x
		local x = (c1 - c2) / 2.0
		local y = -x + c1
		if cPos[i].y > (-cPos[i].x + c1) then
			SAR[t-1]['r'] = SAR[t-1]['r'] - 1
			terminal = true
		end
		if cPos[i].y > (-cPos[i].x + t1_c) then
			terminal = true
		end
	end
	
	if not terminal then
		SAR[t] = { s=s_t, a={action.x, action.y}, r=0 }
	end
	
	return terminal, action
end

--------------------------------------------------------------------------------

function CreepBlockAI:Reset()	
	hero:Stop()
	SendToServerConsole( "dota_dev hero_refresh" )
	FindClearSpaceForUnit(hero, heroSpawn:GetAbsOrigin() + Vector(150,-150,0), true)
	
	if creeps ~= nil then
		for i = 1,4 do
			creeps[i]:ForceKill(false)
		end	
	end
end

function CreepBlockAI:Start()
	t = 0
	SAR = {}
	SAR['ep'] = ep
	ep = ep + 1
	
	creeps = {}
	for i=1,3 do
		creeps[i] = CreateUnitByName( "npc_dota_creep_goodguys_melee" , goodSpawn:GetAbsOrigin() + RandomVector( RandomFloat( 0, 200 ) ), true, nil, nil, DOTA_TEAM_GOODGUYS )				
	end
	creeps[4] = CreateUnitByName( "npc_dota_creep_goodguys_ranged" , goodSpawn:GetAbsOrigin() + RandomVector( RandomFloat( 0, 200 ) ), true, nil, nil, DOTA_TEAM_GOODGUYS )
	
	for i = 1,4 do 
		creeps[i]:SetInitialGoalEntity( goodWP )
	end		
end    

--------------------------------------------------------------------------------

function CreepBlockAI:UpdateModel(data)
	self.explore = data.explore
	self.boot_strap = data.boot_strap
	if ep == 1 or data.replace then
		self.W1 = data.W1
		self.b1 = data.b1
		self.W2 = data.W2
		self.b2 = data.b2
		self.W3 = data.W3
		self.b3 = data.b3
	end
end

function CreepBlockAI:Run(s_t)
	local action = Vector(0,0,0)
	if RandomInt(1,100) <= self.boot_strap then
		action = self:BestMoveEst()
		DebugDrawCircle(hPos + Vector(action[1],action[2],0), Vector(0,255,0), 255, 25, true, 0.2)
	else	
		local fc1 = RELU(FC(s_t, self.W1, self.b1))
		local fc2 = RELU(FC(fc1, self.W2, self.b2))
		local fc3 = FC(fc2, self.W3, self.b3)
		
		local weight = {}
		local max_i = 1
		for i = 1,20 do
			weight[i] = math.exp(fc3[i])
			if weight[i] > weight[max_i] then
				max_i = i
			end
		end
				
		for i = 1,20 do
			if i == max_i then
				DebugDrawCircle(hPos + Vector(fc3[20+i],fc3[40+i],0), Vector(0,255,0), 255, 25, true, 0.2)
			else
				DebugDrawCircle(hPos + Vector(fc3[20+i],fc3[40+i],0), Vector(255,0,0), 255*weight[i]/weight[max_i], 25, true, 0.2)
			end
		end
		action = Vector(fc3[max_i+20],fc3[max_i+40],0)
		action.x = action.x + RandomFloat(-self.explore,self.explore)
		action.y = action.y + RandomFloat(-self.explore,self.explore)
	end
	
	return action
end

function CreepBlockAI:ClosestCreep()
	local closest = 10000
	for i = 1,4 do
		local dist = (hPos - cPos[i]):Length2D()
		if dist < closest then
			closest = dist
		end
	end
	return closest
end

function CreepBlockAI:BestMoveEst()
	local action = Vector(0,0,0)
		
	local c1 = hPos.y + hPos.x
	local min_dist = 100000
	local target = Vector(0,0,0)
	for i = 1,4 do
		local c2 = cPos[i].y - cPos[i].x
		local x = (c1 - c2) / 2.0
		local y = -x + c1
		local dist = (Vector(x,y,0) - cPos[i]):Length2D()
		local creep_ahead = cPos[i].y > (-cPos[i].x + c1)
		
		if not creep_ahead and dist < min_dist then
			target = cPos[i] + Vector(100,100,0)
			min_dist = dist 
		end			
	end
	
	if target.x == 0 then
		action.x = 100
		action.y = 100
	else
		action.x = target.x - hPos.x
		action.y = target.y - hPos.y
	end
		
	return action
end

function FC(x, W, b)
	local y = {}
	for j = 1,#b do
		y[j] = 0
		for i = 1,#x do
			y[j] = y[j] + x[i]*W[i][j]
		end
		y[j] = y[j] + b[j]
	end
	return y
end

function RELU(x)
	local y = {}
	for i = 1,#x do
		if x[i] < 0 then
			y[i] = 0
		else
			y[i] = x[i]
		end
	end
	return y
end
