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
local world: any
local inventory: any
local resources: any
local interaction: any

local function currentRunId(): string
	return session.GetRunId() or ""
end

-- Envia ActionResult (los errores se limitan a 2/s) y devuelve el paquete para el cache de deduplicacion.
local function send(player: Player, packet: any)
	if not packet.ok then
		local now = os.clock()
		if now - (lastError[player] or 0) < 0.5 then
			return
		end
		lastError[player] = now
	end
	remotes.ActionResult:FireClient(player, packet)
end

local function result(player: Player, payload: any, ok: boolean, code: string, entityId: string?): any
	local packet = {
		runId = currentRunId(),
		requestId = if typeof(payload) == "table" and typeof(payload.requestId) == "string"
			then payload.requestId
			else "",
		ok = ok,
		code = code,
		revision = revisions[player] or 0,
		entityId = entityId,
	}
	send(player, packet)
	return packet
end

function Service.Init(context: { [string]: unknown })
	remotes = context.Remotes :: { [string]: RemoteEvent }
	players = (context.Services :: any).PlayerService
	network = (context.Configs :: any).NetworkConfig
	playerConfig = (context.Configs :: any).PlayerConfig
	objectivesConfig = (context.Configs :: any).ObjectivesConfig
	session = (context.Services :: any).SessionService
	world = (context.Services :: any).WorldService
	inventory = (context.Services :: any).InventoryService
	resources = (context.Services :: any).ResourceService
	interaction = (context.Services :: any).InteractionService
	Guard.Init(network)
end

function Service.PublishSnapshot(player: Player)
	local own = players.GetState(player)
	local userId = player.UserId
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
			hunger = if own then own.hunger else 0,
			maxHunger = playerConfig.Hunger.Max,
			moveMode = if own then own.mode else "Walk",
			equippedSlot = inventory.GetEquippedSlot(userId),
			inventory = inventory.GetSnapshot(userId),
			interaction = interaction.GetActive(player),
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
		containers = resources.GetContainerViews(player),
	}
	remotes.StateSnapshot:FireClient(player, snapshot)
	lastSnapshot[player] = os.clock()
end

-- Remotes que cambian el estado propio: tras un exito se publica un snapshot antes del ActionResult.
local function bind(name: string, handler: (Player, any) -> (boolean, string, string?))
	table.insert(
		connections,
		remotes[name].OnServerEvent:Connect(function(player: Player, ...)
			local ok, code, payload = Guard.Check(player, name, ...)
			if not ok then
				send(player, { ok = false, code = code, runId = currentRunId(), requestId = "", revision = 0 })
				return
			end
			local status, previous = Guard.Recall(player, name, payload)
			if status == "Replay" then
				send(player, previous)
				return
			elseif status == "Conflict" then
				result(player, payload, false, "InvalidPayload")
				return
			end
			local success, outcome, entityId = handler(player, payload)
			if success then
				Service.PublishSnapshot(player)
			end
			Guard.Remember(player, name, payload, result(player, payload, success, outcome, entityId))
		end)
	)
end

local function stale(payload: any): boolean
	return payload.runId ~= currentRunId() or payload.runId == ""
end

-- G: run vigente y Alive; con `free` ademas sin interaccion activa y con manos libres.
local function gate(player: Player, payload: any, free: boolean): string
	if stale(payload) then
		return "StaleRun"
	end
	local state = players.GetState(player)
	if not state or state.life ~= "Alive" then
		return "NotAlive"
	end
	if free then
		if interaction.HasActive(player) then
			return "Busy"
		end
		if not players.HandsFree(player) then
			return "HandsBusy"
		end
	end
	return "Ok"
end

-- Envuelve un handler que devuelve solo un ResultCode ("Ok" o "Accepted" cuentan como exito).
local function coded(
	free: boolean,
	action: (Player, any) -> (string, string?)
): (Player, any) -> (boolean, string, string?)
	return function(player, payload)
		local code = gate(player, payload, free)
		local entityId: string? = nil
		if code == "Ok" then
			code, entityId = action(player, payload)
		end
		return code == "Ok" or code == "Accepted", code, entityId
	end
end

function Service.BindRemotes()
	table.insert(
		connections,
		remotes.RequestSnapshot.OnServerEvent:Connect(function(player: Player, ...)
			if Guard.Check(player, "RequestSnapshot", ...) then
				Service.PublishSnapshot(player)
			end
		end)
	)
	table.insert(
		connections,
		remotes.SetFlashlightAim.OnServerEvent:Connect(function(player: Player, ...)
			Guard.Check(player, "SetFlashlightAim", ...)
		end)
	)
	bind(
		"SetMovementMode",
		coded(false, function(player, payload)
			if players.SetMovementMode(player, payload.mode) then
				return "Ok", nil
			end
			return "InvalidState", nil
		end)
	)
	bind(
		"SetFlashlight",
		coded(false, function(player, payload)
			return if players.SetFlashlight(player, payload.enabled) then "Ok" else "InvalidState", nil
		end)
	)
	bind(
		"EquipTool",
		coded(true, function(player, payload)
			return inventory.Equip(player.UserId, payload.slot), nil
		end)
	)
	bind(
		"HitResource",
		coded(true, function(player, payload)
			return resources.Hit(player, payload.targetId), payload.targetId
		end)
	)
	bind(
		"CraftItem",
		coded(true, function(player, payload)
			return inventory.Craft(player.UserId, payload.recipeId, payload.count), nil
		end)
	)
	bind(
		"BeginInteraction",
		coded(false, function(player, payload)
			return interaction.Begin(player, payload.requestId, payload.action, payload.targetId)
		end)
	)
	bind("CancelInteraction", function(player, payload)
		local state = players.GetState(player)
		if stale(payload) then
			return false, "StaleRun", nil
		elseif not state or state.life == "Spectating" then
			return false, "NotAlive", nil
		end
		local code = interaction.Cancel(player, payload.interactionId)
		return code == "Ok", code, nil
	end)
	-- Debug del puente: solo Studio, la decision y el cambio los hace el servidor.
	bind("DebugBridge", function(_player, payload)
		if not RunService:IsStudio() then
			return false, "Forbidden", nil
		end
		if stale(payload) then
			return false, "StaleRun", nil
		end
		local ok = world.setBridgeBuilt(payload.enabled)
		return ok, if ok then "Ok" else "InvalidState", nil
	end)
	for _, name in { "SetReady", "PlaceStructure", "DropObjective", "Shout" } do
		bind(name, function()
			return false, "WrongPhase", nil
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

-- Feedback cosmetico a los jugadores a <= FeedbackRangeStuds de `position` (o a `audience`).
function Service.EmitFeedback(cueId: string, sourceId: string, position: Vector3, audience: { Player }?)
	local runId = currentRunId()
	if runId == "" then
		return
	end
	local packet =
		{ runId = runId, cueId = cueId, sourceId = sourceId, position = position, at = Workspace:GetServerTimeNow() }
	for _, player in audience or Players:GetPlayers() do
		local at = players.GetValidatedPosition(player)
		if audience or (at and (at - position).Magnitude <= network.FeedbackRangeStuds) then
			remotes.Feedback:FireClient(player, packet)
		end
	end
end

function Service.Start()
	Service.BindRemotes()
	interaction.OnChange(Service.PublishSnapshot)
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
