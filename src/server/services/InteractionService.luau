--!strict
-- Acciones mantenidas (docs/specs/remotes.md, subcontrato de BeginInteraction). El servidor mide el hold, revalida
-- cada ValidationIntervalSeconds y al final, y despacha a los handlers que registran los servicios propietarios.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Guard = require(script.Parent:WaitForChild("RemoteGuard"))
local Spatial = require(script.Parent:WaitForChild("Spatial"))

local Service = {}

export type Context = { [string]: unknown }
-- hitbox/model: si hay hitbox se exige rango (InteractionConfig.RangeStuds) y linea de vision.
export type PrepareInfo = {
	hold: number,
	key: string,
	model: Instance?,
	hitbox: BasePart?,
	cancelOnDamage: boolean,
}
-- Prepare valida el estado actual (se llama al empezar, cada 0.1 s y al final); Commit aplica el efecto sin yield.
export type ActionDef = {
	Prepare: (player: Player, targetId: string) -> (string, PrepareInfo?),
	Commit: (player: Player, targetId: string) -> string,
}
type Active = {
	id: string,
	requestId: string,
	runId: string,
	action: string,
	targetId: string,
	startedAt: number,
	endsAt: number,
	key: string,
	startPosition: Vector3,
	cancelOnDamage: boolean,
	nextCheck: number,
	def: ActionDef,
}

local handlers: { [string]: ActionDef } = {}
local active: { [Player]: Active } = {}
local reserved: { [string]: Player } = {}
local beginReady: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local counter = 0
local remotes: { [string]: RemoteEvent }
local config: any
local eyeOffset = Vector3.zero
local players: any
local session: any
local onChange: ((Player) -> ())? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function release(player: Player, interaction: Active)
	active[player] = nil
	if reserved[interaction.key] == player then
		reserved[interaction.key] = nil
	end
end

local function finish(player: Player, interaction: Active, state: string, code: string)
	release(player, interaction)
	remotes.InteractionState:FireClient(player, {
		runId = interaction.runId,
		interactionId = interaction.id,
		requestId = interaction.requestId,
		action = interaction.action,
		targetId = interaction.targetId,
		state = state,
		startedAt = interaction.startedAt,
		endsAt = interaction.endsAt,
		code = code,
	})
	if onChange then
		onChange(player)
	end
end

-- Estado vital, run, movimiento, estado del objetivo, rango y linea de vision.
local function validate(
	player: Player,
	runId: string,
	startPosition: Vector3,
	action: string,
	targetId: string
): (string, PrepareInfo?)
	local state = players.GetState(player)
	local position = players.GetValidatedPosition(player)
	if not state or state.life ~= "Alive" or not position then
		return "NotAlive", nil
	end
	if session.GetRunId() ~= runId then
		return "StaleRun", nil
	end
	if (position - startPosition).Magnitude > config.MaxMovementFromStartStuds then
		return "Cancelled", nil
	end
	local code, info = handlers[action].Prepare(player, targetId)
	if code ~= "Ok" or not info then
		return if code == "Ok" then "InternalError" else code, nil
	end
	if info.hitbox then
		local point = Spatial.ClosestPoint(info.hitbox, position)
		if (point - position).Magnitude > config.RangeStuds then
			return "OutOfRange", nil
		end
		if not Spatial.HasLineOfSight(position + eyeOffset, point, info.model or info.hitbox) then
			return "Blocked", nil
		end
	end
	return "Ok", info
end

function Service.Init(context: Context)
	local configs = context.Configs :: any
	local services = context.Services :: any
	remotes = context.Remotes :: { [string]: RemoteEvent }
	config = configs.InteractionConfig
	eyeOffset = Vector3.new(0, configs.PlayerConfig.EyeOffsetStuds, 0)
	players = services.PlayerService
	session = services.SessionService
end

function Service.Start()
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			if next(active) == nil then
				return
			end
			local now = serverNow()
			for player, interaction in active do
				if now >= interaction.endsAt then
					local code = validate(
						player,
						interaction.runId,
						interaction.startPosition,
						interaction.action,
						interaction.targetId
					)
					if code == "Ok" then
						code = interaction.def.Commit(player, interaction.targetId)
					end
					finish(player, interaction, if code == "Ok" then "Completed" else "Cancelled", code)
				elseif now >= interaction.nextCheck then
					interaction.nextCheck = now + config.ValidationIntervalSeconds
					local code = validate(
						player,
						interaction.runId,
						interaction.startPosition,
						interaction.action,
						interaction.targetId
					)
					if code ~= "Ok" then
						finish(player, interaction, "Cancelled", code)
					end
				end
			end
		end)
	)
	-- Dano de enemigo cancela salvo que sea despues de endsAt o la accion lo ignore (UseItem con CancelOnDamage false).
	players.OnEnemyDamage(function(player: Player)
		local interaction = active[player]
		if interaction and interaction.cancelOnDamage and serverNow() < interaction.endsAt then
			finish(player, interaction, "Cancelled", "Cancelled")
		end
	end)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			local interaction = active[player]
			if interaction then
				release(player, interaction)
			end
			beginReady[player] = nil
		end)
	)
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function Service.Register(action: string, def: ActionDef)
	handlers[action] = def
end

function Service.OnChange(callback: (Player) -> ())
	onChange = callback
end

function Service.HasActive(player: Player): boolean
	return active[player] ~= nil
end

function Service.GetActive(
	player: Player
): { id: string, action: string, targetId: string, startedAt: number, endsAt: number }?
	local interaction = active[player]
	if not interaction then
		return nil
	end
	return {
		id = interaction.id,
		action = interaction.action,
		targetId = interaction.targetId,
		startedAt = interaction.startedAt,
		endsAt = interaction.endsAt,
	}
end

-- Devuelve "Accepted" con el interactionId, o el codigo de rechazo.
function Service.Begin(player: Player, requestId: string, action: string, targetId: string): (string, string?)
	local def = handlers[action]
	if not def then
		return "WrongPhase", nil
	end
	local state = players.GetState(player)
	local position = players.GetValidatedPosition(player)
	if not state or state.life ~= "Alive" or not position then
		return "NotAlive", nil
	end
	if active[player] then
		return "Busy", nil
	end
	if not players.HandsFree(player) then
		return "HandsBusy", nil
	end
	local now = os.clock()
	if not Guard.CooldownOk(beginReady, player, now) then
		return "Cooldown", nil
	end
	local runId = session.GetRunId() or ""
	local code, info = validate(player, runId, position, action, targetId)
	if not info then
		return code, nil
	end
	if reserved[info.key] then
		return "Busy", nil
	end
	Guard.CooldownArm(beginReady, player, config.BeginCooldownSeconds, now)
	counter += 1
	local startedAt = serverNow()
	local interaction: Active = {
		id = "I" .. counter,
		requestId = requestId,
		runId = runId,
		action = action,
		targetId = targetId,
		startedAt = startedAt,
		endsAt = startedAt + info.hold,
		key = info.key,
		startPosition = position,
		cancelOnDamage = info.cancelOnDamage,
		nextCheck = startedAt + config.ValidationIntervalSeconds,
		def = def,
	}
	active[player] = interaction
	reserved[info.key] = player
	remotes.InteractionState:FireClient(player, {
		runId = runId,
		interactionId = interaction.id,
		requestId = requestId,
		action = action,
		targetId = targetId,
		state = "Started",
		startedAt = interaction.startedAt,
		endsAt = interaction.endsAt,
		code = "Accepted",
	})
	return "Accepted", interaction.id
end

function Service.Cancel(player: Player, interactionId: string): string
	local interaction = active[player]
	if not interaction or interaction.id ~= interactionId then
		return "NotFound"
	end
	finish(player, interaction, "Cancelled", "Cancelled")
	return "Ok"
end

-- Nueva run o fin de run: cancela todo antes de cualquier otro procesamiento.
function Service.CancelAll(code: string)
	for player, interaction in active do
		finish(player, interaction, "Cancelled", code)
	end
	table.clear(reserved)
	table.clear(beginReady)
end

return Service
