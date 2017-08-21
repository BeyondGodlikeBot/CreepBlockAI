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
		GameRules:GetGameModeEntity():SetThink("Setup", self, 2)
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
	
	heroSpeed = hero:GetBaseMoveSpeed()
	
	PlayerResource:SetCameraTarget(0, hero)
	
	directions = {}
	directions[1] = Vector( 0, 1, 0 ) --N
	directions[2] = Vector( 0.707, 0.707, 0 ) --NE
	directions[3] = Vector( 1, 0, 0 ) --E
	directions[4] = Vector( 0.707, -0.707, 0 ) --SE
	directions[5] = Vector( 0, -1, 0 ) --S
	directions[6] = Vector( -0.707, -0.707, 0 ) --SW
	directions[7] = Vector( -1, 0, 0 ) --W
	directions[8] = Vector( -0.707, 0.707, 0 ) --NW
	
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
								self:Update(data)
								
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
			
	local terminal = self:UpdateSAR()
	if terminal then
		self:Reset()
		ai_state = STATE_SENDDATA
		return 0.2
	end
	
	local action = SAR[t]['a']

	if action == 9 then
		hero:Stop()
	else
		hero:MoveToPosition(hPos + heroSpeed*directions[action]) --let it run as far as it can, also action + 1 is to convert 0 index to 1 index
	end
		
	if t > 0 then
		Say(hero, "Gained Reward " .. SAR[t-1]['r'], false)
	end
	
	t = t + 1
	
	return 0.2
end

--------------------------------------------------------------------------------

function CreepBlockAI:UpdateSAR()
	hPos = hero:GetAbsOrigin()
	cPos = {}
	for i = 1,4 do
		cPos[i] = creeps[i]:GetAbsOrigin()
	end
	
	local s_t = {}
	for i = 1,4 do
		s_t[i*2-1] = (cPos[i].x - hPos.x) / (2 * heroSpeed) --rough normalization factor
		s_t[i*2] = (cPos[i].y - hPos.y) / (2 * heroSpeed)
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
					reward = reward + 0.25	
				elseif dist < 60 then
					reward = reward + 0.1
				end
			end
		end
		
		SAR[t-1]['r'] = reward
	end
	
	last_cPos = cPos
	
	SAR[t] = { s=s_t, a=action, r=0 }
	
	local c1 = hPos.y + hPos.x + 100
	local min_dist = 100000
	local target = Vector(0,0,0)
	for i = 1,4 do
		local c2 = cPos[i].y - cPos[i].x
		local x = (c1 - c2) / 2.0
		local y = -x + c1
		if cPos[i].y > (-cPos[i].x + c1) then
			return true
		end
		if cPos[i].y > (-cPos[i].x + t1_c) then
			return true
		end
	end
		
	return false
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

function CreepBlockAI:Update(data)
	self.boot_strap = data.boot_strap
	
	if data.replace or self.ep == 1 then
		self.W1 = data.W1
		self.b1 = data.b1
		self.W2 = data.W2
		self.b2 = data.b2
		self.W3 = data.W3
		self.b3 = data.b3
		self.W4 = data.W4
		self.b4 = data.b4
	end
	
	Say(hero, "BootStrap(%): " .. self.boot_strap, false)
end

function CreepBlockAI:Run(s_t)
	local action = 1
	local a = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	if RandomInt(1,100) <= self.boot_strap then
		action = self:BestMoveEst()
		a[action] = 1
	else	
		local fc1, fc2 = {}, {}
		for i = 1,4 do
			local s_t_creep = { s_t[i*2-1], s_t[i*2] }
			fc1[i] = TANH(FC(s_t_creep, self.W1, self.b1))
			fc2[i] = TANH(FC(s_t_creep, self.W2, self.b2))
		end
		
		local features, weights = {}, {}
		for i = 1,4 do
			features[i], weights[i] = SPLIT(fc2[i])
		end
		
		local max_weights = MAX2D(weights)
		local norm_weights = ELEMENTWISE_SUB(weights, max_weights)
		local norm_weights = SOFTMAX2D(norm_weights)
		local features_pooled = REDUCESUM(ELEMENTWISE_MUL(features,norm_weights))
		
		local fc3 = TANH(FC(features_pooled, self.W3, self.b3))
		a = FC(fc3, self.W4, self.b4)
		a = SOFTMAX(a)
		action = SAMPLE(a)
	end
	
	for i = 1,8 do
		if action == i then
			DebugDrawCircle(hPos + heroSpeed*directions[i], Vector(0,255,0), 255 * a[i] / a[action], 25, true, 0.2)
		else
			DebugDrawCircle(hPos + heroSpeed*directions[i], Vector(255,0,0), 255 * a[i] / a[action], 25, true, 0.2)
		end
	end
	if action == 9 then
		DebugDrawCircle(hPos, Vector(0,255,0), 255 * a[9] / a[action], 25, true, 0.2)
	else
		DebugDrawCircle(hPos, Vector(255,0,0), 255 * a[9] / a[action], 25, true, 0.2)
	end
	
	return action
end

function CreepBlockAI:BestMoveEst()
	local closest = 10000
	for i = 1,4 do
		local dist = (hPos - cPos[i]):Length2D()
		if dist < closest then
			closest = dist
		end
	end
	if closest > 500 then
		return 9
	end
		
		
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
		return 2
	end
	
	
	local target_direction = target - hPos
	DebugDrawCircle(target, Vector(0,255,0), 100, 25, true, 0.3)
	if target_direction:Length2D() < 50 then
		return 9
	else
		local best_diff = 1000000
		local dir = 1
		for i = 1,8 do
			local diff = (directions[i] - target_direction):Length2D()
			if diff < best_diff then
				dir = i
				best_diff = diff
			end
		end
		return dir
	end
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

function TANH(x)
	local y = {}
	for i = 1,#x do
		y[i] = math.tanh(x[i])
	end
	return y
end

function SPLIT(x)
	local n = #x/2
	local x1 = {}  
	local x2 = {}
	for j = 1,n do
		x1[j] = x[j] 
		x2[j] = x[n+j]
	end
	return x1, x2
end

function MAX2D(x)
	local max_x = {}
	for i = 1,#x do
		for j = 1,#x[1] do
			if i == 1 or x[i][j] > max_x[j] then
				max_x[j] = x[i][j]
			end
		end
	end
	return max_x
end

function ELEMENTWISE_SUB(x,y)
	local z = {}
	for i = 1,#x do
		z[i] = {}
		for j = 1,#x[1] do
			z[i][j] = x[i][j] - y[j]
		end
	end
	return z
end

function REDUCESUM(x)
	local z = {}
	for j = 1,#x[1] do
		z[j] = x[1][j]
		for i = 2,#x do
			z[j] = z[j] + x[i][j]
		end
	end
	return z
end

function SOFTMAX(x)
	local x_exp = {}
	local x_exp_sum = 0
	for i = 1,#x do
		x_exp[i] = math.exp(x[i])
		x_exp_sum = x_exp_sum + x_exp[i]
	end
	for i = 1,#x do
		x_exp[i] = x_exp[i] / x_exp_sum
	end
	return x_exp
end

function SOFTMAX2D(x)
	local x_exp = {}
	local x_exp_sum = {}
	for i = 1,#x do
		x_exp[i] = {}
		for j = 1,#x[1] do
			x_exp[i][j] = math.exp(x[i][j])
			if i == 1 then
				x_exp_sum[j] = x_exp[i][j]
			else
				x_exp_sum[j] = x_exp_sum[j] + x_exp[i][j]
			end
		end
	end
	for i = 1,#x do
		for j = 1,#x[1] do
			x_exp[i][j] = x_exp[i][j] / x_exp_sum[j]
		end
	end
	return x_exp
end


function ELEMENTWISE_MUL(x,y)
	local z = {}
	for i = 1,#x do
		z[i] = {}
		for j = 1,#x[1] do
			z[i][j] = x[i][j] * y[i][j]
		end
	end
	return z
end

function SAMPLE(p)
	local r = RandomFloat(0.0, 1.0)
	for i = 1,#p do
		if r < p[i] then
			return i
		else
			r = r - p[i]
		end
	end
	return #p
end