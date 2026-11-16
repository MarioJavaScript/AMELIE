--!strict
-- Intencion de modo de movimiento (docs/specs/jugador.md, remotes.md): C alterna agachado, Shift mantenido corre.
-- Sprint y Crouch no coexisten: agachado manda y Shift se ignora mientras se esta agachado. El cliente solo pide
-- el modo; el servidor decide si alcanza la estamina y reconcilia con el snapshot (self.moveMode).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local PresentationConfig = require(Shared:WaitForChild("config"):WaitForChild("PresentationConfig"))

local Controller = {}

export type Context = { [string]: unknown }

type Mode = "Walk" | "Sprint" | "Crouch"

local remotes: { [string]: RemoteEvent } = {}
local controllers: { [string]: any } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}

local crouchIntent = false
local sprintHeld = false
local sentMode: Mode = "Walk"
local reconcileAfter = 0

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

-- Sin snapshot (arranque) se permite; con snapshot exige fase de juego y estado Alive.
local function canChangeMode(): boolean
	local state = controllers.StateController
	local snapshot = state.Get()
	if snapshot == nil then
		return true
	end
	if not isPlayablePhase(snapshot.phase) then
		return false
	end
	local view = state.GetSelfPlayer()
	return view == nil or view.life == "Alive"
end

local function desiredMode(): Mode
	if crouchIntent then
		return "Crouch"
	end
	if sprintHeld then
		return "Sprint"
	end
	return "Walk"
end

-- Envia SetMovementMode solo cuando el modo deseado cambia respecto al ultimo enviado.
local function sync()
	local mode = desiredMode()
	if mode == sentMode or not canChangeMode() then
		return
	end
	sentMode = mode
	reconcileAfter = os.clock() + PresentationConfig.FirstPerson.ModeReconcileSeconds
	local request = controllers.StateController.NewRequest()
	local payload: Types.SetMovementMode = { requestId = request.requestId, runId = request.runId, mode = mode }
	remotes.SetMovementMode:FireServer(payload)
end

-- El servidor manda: pasado el tiempo de espera, el modo confirmado reemplaza al enviado. Si la tecla sigue
-- pulsada, sync() vuelve a pedir el modo (por ejemplo Sprint cuando la estamina se recupera).
local function onSnapshot(snapshot: Types.Snapshot)
	local view = controllers.StateController.GetSelfPlayer()
	if view ~= nil and view.life ~= "Alive" then
		crouchIntent = false
		sentMode = "Walk"
		return
	end
	if controllers.StateController.IsDebug() or os.clock() < reconcileAfter then
		return
	end
	local serverMode = snapshot.self.moveMode
	if serverMode ~= sentMode then
		sentMode = serverMode
		crouchIntent = serverMode == "Crouch"
	end
	sync()
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local bindings = PresentationConfig.InputBindings
	if input.KeyCode == bindings.Crouch then
		if not crouchIntent and not canChangeMode() then
			return
		end
		crouchIntent = not crouchIntent
		sync()
	elseif input.KeyCode == bindings.Sprint then
		sprintHeld = true
		sync()
	end
end

local function onInputEnded(input: InputObject)
	if input.KeyCode == PresentationConfig.InputBindings.Sprint then
		sprintHeld = false
		sync()
	end
end

function Controller.Init(context: Context)
	remotes = context.Remotes :: { [string]: RemoteEvent }
	controllers = context.Controllers :: { [string]: any }
end

function Controller.Start()
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	-- Si la ventana pierde el foco no llega el InputEnded de Shift.
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			sprintHeld = false
			sync()
		end)
	)
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, unsubscribe in unsubscribers do
		unsubscribe()
	end
	table.clear(unsubscribers)
end

function Controller.IsCrouching(): boolean
	return crouchIntent
end

-- Modo que el cliente cree vigente (el servidor lo confirma o corrige en el siguiente snapshot).
function Controller.GetMode(): Mode
	return sentMode
end

return Controller
