--!strict
-- Primera persona bloqueada, viewbobbing segun velocidad y agachado visual (docs/specs/jugador.md).
-- Todo es visual: el servidor decide velocidad real y la capsula fisica no cambia al agacharse.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local Config = Shared:WaitForChild("config")
local PlayerConfig = require(Config:WaitForChild("PlayerConfig"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))

local Controller = {}

export type Context = { [string]: unknown }

local localPlayer = Players.LocalPlayer
local remotes: { [string]: RemoteEvent } = {}
local controllers: { [string]: any } = {}

local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}
local humanoid: Humanoid? = nil
local crouchIntent = false
local reconcileAfter = 0
local reducedMotion = false
local bobPhase = 0
local bobAmplitude = 0
local crouchOffset = 0

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

-- Sin snapshot (arranque o pruebas sin servidor) se permite el cambio visual; con snapshot exige Alive y fase de juego.
local function canChangeMode(): boolean
	local state = controllers.StateController
	local snapshot = if state ~= nil then state.Get() else nil
	if snapshot == nil then
		return true
	end
	if not isPlayablePhase(snapshot.phase) then
		return false
	end
	local view = state.GetSelfPlayer()
	return view == nil or view.life == "Alive"
end

local function applyHumanoidRules(target: Humanoid)
	-- Salto deshabilitado en MVP: se usan rampas y escaleras de Studio.
	target.UseJumpPower = true
	target.JumpPower = 0
	target.JumpHeight = 0
	target:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function bindCharacter(character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if found == nil or not found:IsA("Humanoid") then
		return
	end
	humanoid = found
	applyHumanoidRules(found)
	bobPhase = 0
	bobAmplitude = 0
	crouchOffset = if crouchIntent then -PlayerConfig.Camera.CrouchOffsetStuds else 0
end

local function requestMode(mode: "Walk" | "Crouch")
	local state = controllers.StateController
	local request = state.NewRequest()
	local payload: Types.SetMovementMode = { requestId = request.requestId, runId = request.runId, mode = mode }
	remotes.SetMovementMode:FireServer(payload)
end

local function setCrouch(want: boolean)
	if want == crouchIntent then
		return
	end
	if want and not canChangeMode() then
		return
	end
	crouchIntent = want
	reconcileAfter = os.clock() + PresentationConfig.FirstPerson.ModeReconcileSeconds
	requestMode(if want then "Crouch" else "Walk")
end

-- El snapshot corrige la intencion local pasado el tiempo de espera: el servidor manda.
local function onSnapshot(snapshot: Types.Snapshot)
	local view = controllers.StateController.GetSelfPlayer()
	if view ~= nil and view.life ~= "Alive" then
		crouchIntent = false
		return
	end
	if controllers.StateController.IsDebug() or os.clock() < reconcileAfter then
		return
	end
	local serverCrouch = snapshot.self.moveMode == "Crouch"
	if serverCrouch ~= crouchIntent then
		crouchIntent = serverCrouch
	end
end

local function smoothing(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function onRender(dt: number)
	local camera = workspace.CurrentCamera
	if camera ~= nil and camera.FieldOfView ~= PlayerConfig.Camera.Fov then
		camera.FieldOfView = PlayerConfig.Camera.Fov
	end

	local current = humanoid
	if current == nil or current.Parent == nil then
		return
	end
	local root = current.RootPart
	if root == nil then
		return
	end

	local settings = PresentationConfig.FirstPerson
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = current.FloorMaterial ~= Enum.Material.Air
	local factor = 0
	if grounded and speed >= settings.BobMinSpeedStudsPerSecond then
		factor = math.clamp(speed / PlayerConfig.Speed.Walk, 0, settings.BobMaxSpeedFactor)
	end

	local baseAmplitude = if reducedMotion
		then PresentationConfig.ReducedMotionBobAmplitudeStuds
		else PlayerConfig.Camera.BobAmplitudeStuds
	bobAmplitude += (baseAmplitude * factor - bobAmplitude) * smoothing(settings.BobAmplitudeSmoothing, dt)
	bobPhase = (bobPhase + dt * 2 * math.pi * PlayerConfig.Camera.BobFrequencyHz * factor) % (4 * math.pi)

	local targetCrouch = if crouchIntent then -PlayerConfig.Camera.CrouchOffsetStuds else 0
	crouchOffset += (targetCrouch - crouchOffset) * smoothing(settings.CrouchSmoothing, dt)

	-- Balanceo vertical a la frecuencia base y lateral a la mitad; amplitud lateral reducida.
	local bobX = math.sin(bobPhase * 0.5) * bobAmplitude * 0.5
	local bobY = math.sin(bobPhase) * bobAmplitude
	current.CameraOffset = Vector3.new(bobX, bobY + crouchOffset, 0)
end

function Controller.Init(context: Context)
	remotes = context.Remotes :: { [string]: RemoteEvent }
	controllers = context.Controllers :: { [string]: any }
end

function Controller.Start()
	localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function(character)
			bindCharacter(character)
		end)
	)
	if localPlayer.Character ~= nil then
		task.spawn(bindCharacter, localPlayer.Character)
	end

	table.insert(connections, RunService.RenderStepped:Connect(onRender))

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			if input.KeyCode == PresentationConfig.InputBindings.Crouch then
				setCrouch(not crouchIntent)
			end
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
	if humanoid ~= nil then
		humanoid.CameraOffset = Vector3.zero
	end
end

function Controller.IsCrouching(): boolean
	return crouchIntent
end

-- Opcion de accesibilidad: amplitud de balanceo = PresentationConfig.ReducedMotionBobAmplitudeStuds.
function Controller.SetReducedMotion(enabled: boolean)
	reducedMotion = enabled
end

return Controller
