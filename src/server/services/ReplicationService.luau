--!strict
-- F1-3: red de estado del jugador. Ver docs/specs/remotes.md.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Guard = require(script.Parent:WaitForChild("RemoteGuard"))
local Service = {}
local remotes: { [string]: RemoteEvent }
local players: any
local network: any
local playerConfig: any
local objectivesConfig: any
local connections: { RBXScriptConnection } = {}
local lastSnapshot: { [Player]: number } = {}
local lastError: { [Player]: number } = {}
local revisions: { [Player]: number } = {}
local session: any

local function currentRunId(): string
	return session.GetRunId() or ""
end

local function result(player: Player, payload: any, ok: boolean, code: string)
	if not ok then
		local now = os.clock()
		if now - (lastError[player] or 0) < 0.5 then
			return
		end
		lastError[player] = now
	end
	remotes.ActionResult:FireClient(player, {
		runId = currentRunId(),
		requestId = if typeof(payload) == "table" and typeof(payload.requestId) == "string"
			then payload.requestId
			else "",
		ok = ok,
		code = code,
		revision = revisions[player] or 0,
	})
end

function Service.Init(context: { [string]: unknown })
	remotes = context.Remotes :: { [string]: RemoteEvent }
	players = (context.Services :: any).PlayerService
	network = (context.Configs :: any).NetworkConfig
	playerConfig = (context.Configs :: any).PlayerConfig
	objectivesConfig = (context.Configs :: any).ObjectivesConfig
	session = (context.Services :: any).SessionService
	Guard.Init(network)
end

function Service.PublishSnapshot(player: Player)
	local own = players.GetState(player)
	local views = {}
	for _, other in Players:GetPlayers() do
		local state = players.GetState(other)
		if state then
			table.insert(views, {
				id = tostring(other.UserId),
				userId = other.UserId,
				participant = true,
				ready = true,
				life = state.life,
				health = state.health,
				maxHealth = playerConfig.Health.Max,
				flashlightOn = state.flashlightOn,
				flashlightDirection = Vector3.new(0, 0, -1),
			})
		end
	end
	local runId = currentRunId()
	local revision = (revisions[player] or 0) + 1
	revisions[player] = revision
	local snapshot = {
		protocolVersion = 1,
		runId = runId,
		revision = revision,
		serverTime = Workspace:GetServerTimeNow(),
		phase = if runId == "" then "Lobby" else "Day",
		day = 1,
		night = 1,
		phaseEndsAt = 0,
		rosterSize = #views,
		players = views,
		self = {
			profile = "Ready",
			save = "Pending",
			stamina = if own then own.stamina else 0,
			maxStamina = playerConfig.Stamina.Max,
			battery = if own then own.battery else 0,
			maxBattery = playerConfig.Flashlight.MaxBattery,
			moveMode = if own then own.mode else "Walk",
			equippedSlot = 0,
			inventory = {},
			soloChanceAvailable = false,
		},
		objectives = {
			radioId = "",
			pieces = {},
			installedCount = 0,
			transmissionState = "Incomplete",
			elapsedSeconds = 0,
			requiredSeconds = objectivesConfig.TransmissionSeconds,
		},
		structures = {},
		containers = {},
	}
	remotes.StateSnapshot:FireClient(player, snapshot)
	lastSnapshot[player] = os.clock()
end

local function bind(name: string, handler: (Player, any) -> ())
	table.insert(
		connections,
		remotes[name].OnServerEvent:Connect(function(player: Player, ...)
			local ok, code, payload = Guard.Check(player, name, ...)
			if not ok then
				result(player, payload, false, code)
				return
			end
			handler(player, payload)
		end)
	)
end

function Service.BindRemotes()
	bind("RequestSnapshot", function(player)
		Service.PublishSnapshot(player)
	end)
	bind("SetMovementMode", function(player, payload)
		if payload.runId ~= currentRunId() or payload.runId == "" then
			result(player, payload, false, "StaleRun")
			return
		end
		if players.SetMovementMode(player, payload.mode) then
			result(player, payload, true, "Ok")
		else
			local state = players.GetState(player)
			result(player, payload, false, if state == nil or state.life ~= "Alive" then "NotAlive" else "InvalidState")
		end
		Service.PublishSnapshot(player)
	end)
	bind("SetFlashlight", function(player, payload)
		if payload.runId ~= currentRunId() or payload.runId == "" then
			result(player, payload, false, "StaleRun")
			return
		end
		result(player, payload, players.SetFlashlight(player, payload.enabled), "Ok")
		Service.PublishSnapshot(player)
	end)
	for _, name in
		{
			"SetReady",
			"EquipTool",
			"HitResource",
			"CraftItem",
			"PlaceStructure",
			"DropObjective",
			"BeginInteraction",
			"CancelInteraction",
			"Shout",
			"SetFlashlightAim",
		}
	do
		bind(name, function(player, payload)
			if name ~= "SetFlashlightAim" then
				result(player, payload, false, "WrongPhase")
			end
		end)
	end
	for _, name in { "StateSnapshot", "ActionResult", "InteractionState", "Feedback" } do
		table.insert(
			connections,
			remotes[name].OnServerEvent:Connect(function(player: Player)
				Guard.Check(player, name, {})
			end)
		)
	end
end

function Service.Start()
	Service.BindRemotes()
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				if now - (lastSnapshot[player] or 0) >= 1 / network.SnapshotMaxPerSecond then
					Service.PublishSnapshot(player)
				end
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			Guard.Forget(player)
			lastSnapshot[player] = nil
			lastError[player] = nil
			revisions[player] = nil
		end)
	)
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end
return Service
