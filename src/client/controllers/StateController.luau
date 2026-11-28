--!strict
-- Recibe StateSnapshot, descarta revisiones viejas y distribuye el estado confirmado (docs/specs/arquitectura.md).
-- El cliente nunca calcula vida, estamina ni bateria: solo muestra lo que manda el servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("types"))

local Controller = {}

export type Context = { [string]: unknown }
export type Snapshot = Types.Snapshot
type Listener = (Snapshot) -> ()

local listeners: { [number]: Listener } = {}
local nextListenerId = 0
local current: Snapshot? = nil
local requestCounter = 0
local connection: RBXScriptConnection? = nil
local remotes: { [string]: RemoteEvent } = {}

local function dispatch(snapshot: Snapshot)
	for _, listener in listeners do
		task.spawn(listener, snapshot)
	end
end

local function isSnapshot(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local candidate = value :: { [string]: unknown }
	return typeof(candidate.runId) == "string"
		and typeof(candidate.revision) == "number"
		and typeof(candidate.phase) == "string"
		and typeof(candidate.self) == "table"
		and typeof(candidate.players) == "table"
end

local function accept(snapshot: Snapshot)
	local previous = current
	if previous ~= nil and previous.runId == snapshot.runId and snapshot.revision <= previous.revision then
		return
	end
	current = snapshot
	dispatch(snapshot)
end

function Controller.Init(context: Context)
	remotes = context.Remotes :: { [string]: RemoteEvent }
end

function Controller.Start()
	connection = remotes.StateSnapshot.OnClientEvent:Connect(function(payload: unknown)
		if isSnapshot(payload) then
			accept(payload :: Snapshot)
		end
	end)
end

function Controller.Stop()
	if connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
	table.clear(listeners)
	current = nil
end

function Controller.Get(): Snapshot?
	return current
end

-- Vista propia dentro de la lista de jugadores del snapshot.
function Controller.GetSelfPlayer(): Types.PlayerView?
	local snapshot = current
	if snapshot == nil then
		return nil
	end
	local userId = Players.LocalPlayer.UserId
	for _, view in snapshot.players do
		if view.userId == userId then
			return view
		end
	end
	return nil
end

-- Llama al listener en cada snapshot aceptado y devuelve la funcion para desuscribir.
function Controller.Subscribe(listener: Listener): () -> ()
	nextListenerId += 1
	local id = nextListenerId
	listeners[id] = listener
	return function()
		listeners[id] = nil
	end
end

-- Envolvente comun de solicitudes C->S: requestId unico y runId vigente (vacio antes del primer snapshot).
function Controller.NewRequest(): Types.Req
	requestCounter += 1
	local snapshot = current
	return {
		requestId = string.format("c%d_%d", requestCounter, math.floor(os.clock() * 1000) % 100000),
		runId = if snapshot ~= nil then snapshot.runId else "",
	}
end

-- Solo Studio: inyecta un snapshot parcial para probar HUD y linterna mientras el servidor sigue en stubs.
function Controller.DebugInject(patch: { [string]: unknown })
	if not RunService:IsStudio() then
		return
	end
	local base: Snapshot = current
		or {
			protocolVersion = 1,
			runId = "debug",
			revision = 0,
			serverTime = 0,
			phase = "Day",
			day = 1,
			night = 1,
			phaseEndsAt = 0,
			rosterSize = 1,
			players = {},
			self = {
				profile = "Ready",
				save = "Saved",
				stamina = 100,
				maxStamina = 100,
				battery = 50,
				maxBattery = 100,
				hunger = 100,
				maxHunger = 100,
				moveMode = "Walk",
				equippedSlot = 0,
				inventory = {},
				meta = nil,
				bleedoutAt = nil,
				soloChanceAvailable = false,
				autoReviveAt = nil,
				interaction = nil,
			},
			objectives = {
				radioId = "",
				pieces = {},
				installedCount = 0,
				transmissionState = "Incomplete",
				elapsedSeconds = 0,
				requiredSeconds = 0,
				completedNight = nil,
			},
			structures = {},
			containers = {},
			result = nil,
		}
	local merged = table.clone(base) :: { [string]: unknown }
	for key, value in patch do
		merged[key] = value
	end
	merged.revision = base.revision + 1
	-- Parche de depuracion: se confia en que mantiene la forma de Snapshot (solo Studio).
	accept((merged :: unknown) :: Snapshot)
end

-- Solo Studio: true mientras el snapshot vigente es el inyectado (no hay servidor que lo confirme).
function Controller.IsDebug(): boolean
	local snapshot = current
	return RunService:IsStudio() and snapshot ~= nil and snapshot.runId == "debug"
end

-- Solo Studio: modifica la vista propia dentro de players (vida, linterna) y reinyecta.
function Controller.DebugPatchSelfPlayer(patch: { [string]: unknown })
	if not RunService:IsStudio() then
		return
	end
	local existing = Controller.GetSelfPlayer()
	local view: { [string]: unknown } = if existing ~= nil
		then table.clone(existing) :: { [string]: unknown }
		else {
			id = "debug_self",
			userId = Players.LocalPlayer.UserId,
			participant = true,
			ready = true,
			life = "Alive",
			health = 100,
			maxHealth = 100,
			flashlightOn = false,
			flashlightDirection = Vector3.new(0, 0, -1),
			carrying = nil,
		}
	for key, value in patch do
		view[key] = value
	end
	Controller.DebugInject({ players = { view } })
end

return Controller
