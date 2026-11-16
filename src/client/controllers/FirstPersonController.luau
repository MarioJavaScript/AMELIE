--!strict
-- Primera persona bloqueada, viewbobbing segun velocidad y agachado visual (docs/specs/jugador.md).
-- Todo es visual: el servidor decide velocidad real y la capsula fisica no cambia al agacharse.
-- La intencion de modo (Walk/Sprint/Crouch) y su envio al servidor viven en MovementController.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("config")
local PlayerConfig = require(Config:WaitForChild("PlayerConfig"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))

local Controller = {}

export type Context = { [string]: unknown }

local localPlayer = Players.LocalPlayer
local controllers: { [string]: any } = {}

local connections: { RBXScriptConnection } = {}
local humanoid: Humanoid? = nil
local reducedMotion = false
local bobPhase = 0
local bobAmplitude = 0
local crouchOffset = 0

local function applyHumanoidRules(target: Humanoid)
	-- Salto deshabilitado en MVP: se usan rampas y escaleras de Studio.
	target.UseJumpPower = true
	target.JumpPower = 0
	target.JumpHeight = 0
	target:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function isCrouching(): boolean
	local movement = controllers.MovementController
	return movement ~= nil and movement.IsCrouching() == true
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
	crouchOffset = if isCrouching() then -PlayerConfig.Camera.CrouchOffsetStuds else 0
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

	local targetCrouch = if isCrouching() then -PlayerConfig.Camera.CrouchOffsetStuds else 0
	crouchOffset += (targetCrouch - crouchOffset) * smoothing(settings.CrouchSmoothing, dt)

	-- Balanceo vertical a la frecuencia base y lateral a la mitad; amplitud lateral reducida.
	local bobX = math.sin(bobPhase * 0.5) * bobAmplitude * 0.5
	local bobY = math.sin(bobPhase) * bobAmplitude
	current.CameraOffset = Vector3.new(bobX, bobY + crouchOffset, 0)
end

-- Desactiva el boton de reiniciar personaje (jugador.md: el servidor controla el ciclo de vida del personaje).
-- SetCore falla mientras el CoreGui no esta listo, asi que se reintenta.
local function disableResetButton()
	local settings = PresentationConfig.FirstPerson
	for _ = 1, settings.ResetButtonRetries do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
			return
		end
		task.wait(settings.ResetButtonRetrySeconds)
	end
	warn("FirstPersonController: no se pudo desactivar el boton de reiniciar personaje")
end

function Controller.Init(context: Context)
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
	task.spawn(disableResetButton)
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if humanoid ~= nil then
		humanoid.CameraOffset = Vector3.zero
	end
end

-- Opcion de accesibilidad: amplitud de balanceo = PresentationConfig.ReducedMotionBobAmplitudeStuds.
function Controller.SetReducedMotion(enabled: boolean)
	reducedMotion = enabled
end

return Controller
