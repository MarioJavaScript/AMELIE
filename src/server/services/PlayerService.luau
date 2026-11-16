--!strict
-- F1-3: docs/specs/jugador.md
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Service = {}
type State = {
	health: number,
	stamina: number,
	battery: number,
	flashlightOn: boolean,
	mode: string,
	life: string,
	validPosition: Vector3?,
	windowPosition: Vector3?,
	windowAt: number,
	lastSample: number,
	lastUpdate: number,
	lastDrain: number,
	lastLight: number,
	airSince: number?,
	airStartY: number?,
	sprintExhausted: boolean,
	previousSpeed: number,
	graceUntil: number,
	corrections: { number },
	character: Model?,
	loading: boolean,
}
local states: { [Player]: State } = {}
local playerConfig: any
local net: any
local connections: { RBXScriptConnection } = {}

local function parts(character: Model): (BasePart?, Humanoid?)
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil, character:FindFirstChildOfClass("Humanoid")
end

local function speed(state: State): number
	if state.life == "Downed" then
		return playerConfig.Speed.Downed
	end
	if state.mode == "Sprint" and not state.sprintExhausted and state.stamina > 0 then
		return playerConfig.Speed.Sprint
	end
	if state.mode == "Crouch" then
		return playerConfig.Speed.Crouch
	end
	return playerConfig.Speed.Walk
end

local function configure(state: State)
	if not state.character then
		return
	end
	local _, humanoid = parts(state.character)
	if not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = speed(state)
	humanoid.Health = humanoid.MaxHealth
end

local function reload(player: Player, state: State)
	if state.loading or state.life == "Spectating" then
		return
	end
	state.loading = true
	task.spawn(function()
		local ok = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("No se pudo recargar el personaje")
		end
		state.loading = false
	end)
end

local function correct(state: State, root: BasePart, now: number)
	if not state.validPosition then
		return
	end
	root.Anchored = true
	root.CFrame = CFrame.new(state.validPosition) * (root.CFrame - root.Position)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = false
	table.insert(state.corrections, now)
	while #state.corrections > 0 and now - state.corrections[1] > 10 do
		table.remove(state.corrections, 1)
	end
	if #state.corrections > 5 then
		warn("Correcciones de movimiento frecuentes")
		table.clear(state.corrections)
	end
end

local function crossesWall(from: Vector3, target: Vector3, character: Model): boolean
	local direction = target - from
	if direction.Magnitude < 0.05 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	for _, offset in { 0, -1.5 } do
		local hit = Workspace:Raycast(from + Vector3.new(0, offset, 0), direction, params)
		if hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide and math.abs(hit.Normal.Y) < 0.5 then
			return true
		end
	end
	return false
end

local function sample(state: State, now: number)
	local character = state.character
	if not character then
		return
	end
	local root, humanoid = parts(character)
	if not root or not humanoid then
		return
	end
	local target = root.Position
	local from = state.validPosition
	if not from then
		state.validPosition = target
		state.windowPosition = target
		state.windowAt = now
		state.lastSample = now
		return
	end
	local windowFrom = state.windowPosition or from
	local elapsed = math.max(0, now - state.lastSample)
	local windowElapsed = math.min(now - state.windowAt, net.MovementWindowSeconds)
	local allowed = speed(state)
	if now < state.graceUntil then
		allowed = math.max(allowed, state.previousSpeed)
	end
	local horizontal = (Vector3.new(target.X - from.X, 0, target.Z - from.Z)).Magnitude
	local windowHorizontal = (Vector3.new(target.X - windowFrom.X, 0, target.Z - windowFrom.Z)).Magnitude
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local ground = Workspace:Raycast(target, Vector3.new(0, -net.MaxHoverStuds, 0), params)
	if ground then
		state.airSince = nil
		state.airStartY = nil
	elseif not state.airSince then
		state.airSince = now
		state.airStartY = target.Y
	end
	local airDuration = if state.airSince then now - state.airSince else 0
	local requiredDescent = net.MaxClimbStudsPerSecond * math.max(0, airDuration - net.MaxAirSeconds)
	local invalid = horizontal > allowed * elapsed + net.MovementToleranceStuds
		or windowHorizontal > allowed * windowElapsed + net.MovementToleranceStuds
		or target.Y - windowFrom.Y > net.MaxClimbStudsPerSecond * windowElapsed + 1
		or (airDuration > net.MaxAirSeconds and (state.airStartY or target.Y) - target.Y < requiredDescent)
		or crossesWall(from, target, character)
	if invalid then
		correct(state, root, now)
		state.airSince = nil
		state.airStartY = nil
	else
		state.validPosition = target
		if now - state.windowAt >= net.MovementWindowSeconds then
			state.windowAt = now
			state.windowPosition = target
		end
	end
	state.lastSample = now
end

local function onCharacter(player: Player, state: State, character: Model)
	state.character = character
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		reload(player, state)
		return
	end
	if state.validPosition then
		character:PivotTo(CFrame.new(state.validPosition))
	else
		state.validPosition = root.Position
	end
	state.windowPosition = state.validPosition
	state.windowAt = os.clock()
	state.lastSample = state.windowAt
	configure(state)
	character.Destroying:Connect(function()
		if states[player] == state and state.character == character then
			state.character = nil
			reload(player, state)
		end
	end)
end

local function addPlayer(player: Player)
	if states[player] then
		return
	end
	local now = os.clock()
	local state: State = {
		health = playerConfig.Health.Max,
		stamina = playerConfig.Stamina.Max,
		battery = playerConfig.Flashlight.InitialBattery,
		flashlightOn = false,
		mode = "Walk",
		life = "Alive",
		validPosition = nil,
		windowPosition = nil,
		windowAt = now,
		lastSample = now,
		lastUpdate = now,
		lastDrain = now,
		lastLight = now,
		airSince = nil,
		airStartY = nil,
		sprintExhausted = false,
		previousSpeed = playerConfig.Speed.Walk,
		graceUntil = 0,
		corrections = {},
		character = nil,
		loading = false,
	}
	states[player] = state
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, state, character)
	end)
	reload(player, state)
end

function Service.Init(context: { [string]: unknown })
	local configs = context.Configs :: any
	playerConfig = configs.PlayerConfig
	net = configs.NetworkConfig
	Players.CharacterAutoLoads = false
end

function Service.Start()
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			states[player] = nil
		end)
	)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for player, state in states do
				local dt = now - state.lastUpdate
				state.lastUpdate = now
				if state.flashlightOn then
					state.battery =
						math.max(0, state.battery - (now - state.lastLight) * playerConfig.Flashlight.DrainPerSecond)
					if state.battery == 0 then
						state.flashlightOn = false
					end
				end
				state.lastLight = now
				local root = if state.character then (parts(state.character)) else nil
				if
					state.mode == "Sprint"
					and state.life == "Alive"
					and root
					and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 0.5
					and state.stamina > 0
				then
					state.stamina = math.max(0, state.stamina - dt * playerConfig.Stamina.SprintDrainPerSecond)
					state.lastDrain = now
					if state.stamina == 0 then
						state.sprintExhausted = true
						state.previousSpeed = playerConfig.Speed.Sprint
						state.graceUntil = now + net.SpeedDowngradeGraceSeconds
					end
				elseif now - state.lastDrain >= playerConfig.Stamina.RegenDelaySeconds then
					state.stamina =
						math.min(playerConfig.Stamina.Max, state.stamina + dt * playerConfig.Stamina.RegenPerSecond)
					if state.stamina >= playerConfig.Stamina.RestartSprintAt then
						state.sprintExhausted = false
					end
				end
				if state.character then
					local _, human = parts(state.character)
					if human and human.Health <= 0 then
						reload(player, state)
					end
				end
				configure(state)
				if now - state.lastSample >= net.MovementSampleSeconds then
					sample(state, now)
				end
				if state.character then
					local part, human = parts(state.character)
					if not part or not human or not state.character:FindFirstChild("Head") then
						reload(player, state)
					end
				end
			end
		end)
	)
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end
function Service.GetValidatedPosition(player: Player): Vector3?
	local state = states[player]
	return if state then state.validPosition else nil
end
function Service.GetState(player: Player): State?
	return states[player]
end
function Service.SetMovementMode(player: Player, mode: string): boolean
	local state = states[player]
	if not state or state.life ~= "Alive" then
		return false
	end
	local previous = speed(state)
	if mode == "Sprint" and (state.sprintExhausted or state.stamina < playerConfig.Stamina.RestartSprintAt) then
		return false
	end
	state.mode = mode
	if speed(state) < previous then
		state.previousSpeed = previous
		state.graceUntil = os.clock() + net.SpeedDowngradeGraceSeconds
	end
	configure(state)
	return true
end
function Service.SetFlashlight(player: Player, enabled: boolean): boolean
	local state = states[player]
	if not state or state.life ~= "Alive" or (enabled and state.battery <= 0) then
		return false
	end
	local now = os.clock()
	if state.flashlightOn then
		state.battery = math.max(0, state.battery - (now - state.lastLight) * playerConfig.Flashlight.DrainPerSecond)
	end
	state.lastLight = now
	state.flashlightOn = enabled and state.battery > 0
	return true
end
function Service.ApplyDamage(player: Player, amount: number)
	local state = states[player]
	if not state or state.life ~= "Alive" or amount ~= amount or math.abs(amount) == math.huge or amount <= 0 then
		return
	end
	state.health = math.max(0, state.health - amount)
	if state.health == 0 then
		state.life = "Downed"
		state.flashlightOn = false
		state.mode = "Walk"
		configure(state)
	end
end
function Service.RespawnAtDawn(_player: Player)
	-- TODO: ciclo-partida.md; SessionService aun no implementa Amanecer.
end
return Service
