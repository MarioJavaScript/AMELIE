--!strict
-- Camara propia (Scriptable) en primera y tercera persona, tecla V (docs/specs/jugador.md, F2-6).
-- Mouse-look propio con el raton bloqueado al centro; el personaje gira con el yaw de la camara. Primera persona:
-- viewbobbing y cuerpo oculto salvo brazos, manos y modelos en mano. Tercera: detras del hombro derecho con spherecast.
-- Todo es visual: no se envia nada al servidor y la capsula fisica no cambia al agacharse.
-- La intencion de modo (Walk/Sprint/Crouch) y su envio al servidor viven en MovementController.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("config")
local PlayerConfig = require(Config:WaitForChild("PlayerConfig"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))

local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))

local Controller = {}

export type Context = { [string]: unknown }
type Mode = "First" | "Third"

local BIND_NAME = "CameraController"
local ARM_PARTS: { [string]: boolean } = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
}

local localPlayer = Players.LocalPlayer
local controllers = {} :: ClientTypes.Controllers

local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local parts: { BasePart } = {}
local partsDirty = true
local humanoid: Humanoid? = nil
local mode: Mode = if PlayerConfig.Camera.DefaultMode == "Third" then "Third" else "First"
local reducedMotion = false
local yaw = 0
local pitch = 0
local distance = 0
local bobPhase = 0
local bobAmplitude = 0
local crouchOffset = 0

local function smoothing(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function isCrouching(): boolean
	local movement = controllers.MovementController
	return movement ~= nil and movement.IsCrouching() == true
end

local function menuOpen(): boolean
	return controllers.InventoryController.IsMenuOpen()
end

local function applyHumanoidRules(target: Humanoid)
	-- Salto deshabilitado en MVP: se usan rampas y escaleras de Studio.
	target.UseJumpPower = true
	target.JumpPower = 0
	target.JumpHeight = 0
	target:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	-- El personaje gira con la camara, no con la direccion de movimiento.
	target.AutoRotate = false
end

local function setTransparency(value: (BasePart) -> number)
	if partsDirty then
		partsDirty = false
		table.clear(parts)
		local character = localPlayer.Character
		for _, descendant in if character ~= nil then character:GetDescendants() else {} do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	for _, part in parts do
		part.LocalTransparencyModifier = value(part)
	end
end

local function isVisibleInFirstPerson(part: BasePart): boolean
	return ARM_PARTS[part.Name] == true
		or part:FindFirstAncestor("HeldRight") ~= nil
		or part:FindFirstAncestor("HeldLeft") ~= nil
end

local function bindCharacter(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	partsDirty = true
	table.insert(
		characterConnections,
		character.DescendantAdded:Connect(function()
			partsDirty = true
		end)
	)
	table.insert(
		characterConnections,
		character.DescendantRemoving:Connect(function()
			partsDirty = true
		end)
	)

	local found = character:WaitForChild("Humanoid", 10)
	if found == nil or not found:IsA("Humanoid") then
		return
	end
	humanoid = found
	applyHumanoidRules(found)
	bobPhase = 0
	bobAmplitude = 0
	crouchOffset = if isCrouching() then -PlayerConfig.Camera.CrouchOffsetStuds else 0
	local root = found.RootPart or character:WaitForChild("HumanoidRootPart", 10)
	if root ~= nil and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = 0
		distance = PlayerConfig.Camera.ThirdPerson.DistanceStuds
	end
end

-- Lanza un spherecast que ignora personajes (y por tanto sus modelos en mano) y partes sin colision.
local function sphereCast(origin: Vector3, direction: Vector3): RaycastResult?
	if direction.Magnitude < PresentationConfig.CameraRig.MinCastStuds then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	return workspace:Spherecast(origin, PlayerConfig.Camera.ThirdPerson.CollisionRadiusStuds, direction, params)
end

local function updateCamera(camera: Camera, head: BasePart, dt: number)
	local rig = PresentationConfig.CameraRig
	local third = PlayerConfig.Camera.ThirdPerson
	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local base = head.Position + Vector3.new(0, crouchOffset, 0)

	if mode == "First" then
		local bob = rotation:VectorToWorldSpace(
			Vector3.new(math.sin(bobPhase * 0.5) * bobAmplitude * 0.5, math.sin(bobPhase) * bobAmplitude, 0)
		)
		camera.CFrame = rotation + base + bob
		setTransparency(function(part)
			return if isVisibleInFirstPerson(part) then 0 else 1
		end)
		return
	end

	-- Pivote: cabeza + hombro (espacio de camara); si la pared lo tapa se recorta desde la cabeza.
	local pivot = base + rotation:VectorToWorldSpace(third.ShoulderOffset)
	local toPivot = sphereCast(base, pivot - base)
	if toPivot ~= nil then
		pivot = base + (pivot - base).Unit * toPivot.Distance
	end
	local desired = third.DistanceStuds
	local hit = sphereCast(pivot, -rotation.LookVector * desired)
	-- MinDistanceStuds nunca empuja la camara dentro de la pared: como mucho la deja a medio radio de la cara.
	local target = if hit ~= nil
		then math.max(hit.Distance, math.min(third.MinDistanceStuds, hit.Distance + third.CollisionRadiusStuds * 0.5))
		else desired
	-- Acercar al instante, alejar suavizado.
	distance = if target < distance
		then target
		else distance + (target - distance) * smoothing(third.PushOutSmoothing, dt)
	camera.CFrame = rotation + pivot - rotation.LookVector * distance

	local faded = (camera.CFrame.Position - head.Position).Magnitude < rig.FadeDistanceStuds
	local value = if faded then rig.FadedTransparency else 0
	setTransparency(function()
		return value
	end)
end

local function onCamera(dt: number)
	local camera = workspace.CurrentCamera
	local current = humanoid
	if camera == nil or current == nil or current.Parent == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = current
	camera.FieldOfView = PlayerConfig.Camera.Fov

	local character = current.Parent :: Model
	local head = character:FindFirstChild("Head")
	local root = current.RootPart
	if head == nil or not head:IsA("BasePart") or root == nil then
		return
	end

	local rig = PresentationConfig.CameraRig
	if menuOpen() then
		-- El boton Modal libera el cursor: no se gira ni se bloquea el raton con un menu abierto.
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
			* rig.MouseDegreesPerPixel
			* UserSettings():GetService("UserGameSettings").MouseSensitivity
		local limit = math.rad(rig.PitchLimitDegrees)
		yaw = (yaw - math.rad(delta.X)) % (2 * math.pi)
		pitch = math.clamp(pitch - math.rad(delta.Y), -limit, limit)
	end

	if current.Health > 0 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end

	-- Viewbobbing segun velocidad (solo se aplica en primera persona) y agachado visual.
	local settings = PresentationConfig.FirstPerson
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local factor = 0
	if current.FloorMaterial ~= Enum.Material.Air and speed >= settings.BobMinSpeedStudsPerSecond then
		factor = math.clamp(speed / PlayerConfig.Speed.Walk, 0, settings.BobMaxSpeedFactor)
	end
	local baseAmplitude = if reducedMotion
		then PresentationConfig.ReducedMotionBobAmplitudeStuds
		else PlayerConfig.Camera.BobAmplitudeStuds
	bobAmplitude += (baseAmplitude * factor - bobAmplitude) * smoothing(settings.BobAmplitudeSmoothing, dt)
	bobPhase = (bobPhase + dt * 2 * math.pi * PlayerConfig.Camera.BobFrequencyHz * factor) % (4 * math.pi)
	local targetCrouch = if isCrouching() then -PlayerConfig.Camera.CrouchOffsetStuds else 0
	crouchOffset += (targetCrouch - crouchOffset) * smoothing(settings.CrouchSmoothing, dt)

	updateCamera(camera, head, dt)
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
	warn("CameraController: no se pudo desactivar el boton de reiniciar personaje")
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
end

function Controller.Start()
	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function(character)
			bindCharacter(character)
		end)
	)
	if localPlayer.Character ~= nil then
		task.spawn(bindCharacter, localPlayer.Character)
	end
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or input.KeyCode ~= PresentationConfig.InputBindings.ToggleCamera or menuOpen() then
				return
			end
			mode = if mode == "First" then "Third" else "First"
		end)
	)
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, onCamera)
	task.spawn(disableResetButton)
end

function Controller.Stop()
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	setTransparency(function()
		return 0
	end)
	if humanoid ~= nil then
		humanoid.AutoRotate = true
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local camera = workspace.CurrentCamera
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function Controller.GetMode(): Mode
	return mode
end

-- Opcion de accesibilidad: amplitud de balanceo = PresentationConfig.ReducedMotionBobAmplitudeStuds.
function Controller.SetReducedMotion(enabled: boolean)
	reducedMotion = enabled
end

return Controller
