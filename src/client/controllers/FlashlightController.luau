--!strict
-- Linterna local (docs/specs/jugador.md y estimulos.md). El servidor decide encendido, bateria y orientacion
-- validada; el cliente dibuja la luz, envia la intencion y la orientacion (max 10 Hz) y parpadea por evento.
-- El parpadeo es solo visual: no evita consumo ni deteccion.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local Config = Shared:WaitForChild("config")
local NetworkConfig = require(Config:WaitForChild("NetworkConfig"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))
local StimuliConfig = require(Config:WaitForChild("StimuliConfig"))
local DebugCommands = require(script.Parent.Parent:WaitForChild("DebugCommands"))

local Controller = {}

export type Context = { [string]: unknown }

local AIM_SEND_INTERVAL_SECONDS = 1 / 10

local remotes: { [string]: RemoteEvent } = {}
local controllers: { [string]: any } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}

local lightPart: Part? = nil
local spotLight: SpotLight? = nil

local desiredOn = false
local serverOn = false
local serverAlive = true
local pendingRequestId: string? = nil
local pendingUntil = 0

local flickerUntil = 0
local flickerLevel = 1
local nextFlickerRoll = 0

local lastAimSentAt = 0
local lastAimDirection: Vector3? = nil

local function createLight()
	local part = Instance.new("Part")
	part.Name = "FlashlightLocal"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Range = StimuliConfig.Flashlight.RangeStuds
	light.Angle = StimuliConfig.Flashlight.ConeDegrees
	light.Brightness = PresentationConfig.Flashlight.Brightness
	light.Color = PresentationConfig.Flashlight.Color
	light.Shadows = true
	light.Enabled = false
	light.Parent = part

	part.Parent = workspace.CurrentCamera
	lightPart = part
	spotLight = light
end

local function ensureLight()
	local part = lightPart
	if part == nil or part.Parent == nil then
		createLight()
	end
end

local function localPlayerAlive(): boolean
	local view = controllers.StateController.GetSelfPlayer()
	return view == nil or view.life == "Alive"
end

local function sendToggle(enabled: boolean)
	local request = controllers.StateController.NewRequest()
	local payload: Types.SetFlashlight = { requestId = request.requestId, runId = request.runId, enabled = enabled }
	pendingRequestId = request.requestId
	pendingUntil = os.clock() + NetworkConfig.PendingRequestTimeoutSeconds
	remotes.SetFlashlight:FireServer(payload)
end

local function toggle()
	if not localPlayerAlive() then
		return
	end
	local state = controllers.StateController
	local snapshot = state.Get()
	local turningOn = not desiredOn
	if turningOn and snapshot ~= nil and snapshot.self.battery <= 0 then
		return
	end
	desiredOn = turningOn
	if state.IsDebug() then
		state.DebugPatchSelfPlayer({ flashlightOn = desiredOn })
		return
	end
	sendToggle(desiredOn)
end

-- El snapshot manda: confirma la solicitud pendiente o, pasado el tiempo de espera, corrige la intencion local.
local function onSnapshot(snapshot: Types.Snapshot)
	local view = controllers.StateController.GetSelfPlayer()
	serverOn = view ~= nil and view.flashlightOn
	serverAlive = view == nil or view.life == "Alive"

	if pendingRequestId ~= nil and (serverOn == desiredOn or os.clock() >= pendingUntil) then
		pendingRequestId = nil
	end
	if pendingRequestId == nil then
		desiredOn = serverOn
	end
	if snapshot.self.battery <= 0 and not controllers.StateController.IsDebug() then
		desiredOn = false
	end
end

local function onActionResult(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local result = payload :: { [string]: unknown }
	if result.requestId ~= pendingRequestId or pendingRequestId == nil then
		return
	end
	if result.ok == false then
		-- Rechazo: volvemos a lo que el servidor tiene confirmado.
		desiredOn = serverOn
		pendingRequestId = nil
	end
end

local function onFeedback(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local cue = (payload :: { [string]: unknown }).cueId
	if typeof(cue) == "string" and (PresentationConfig.Flashlight.FlickerCues :: any)[cue] == true then
		Controller.Flicker(PresentationConfig.Flashlight.FlickerSeconds)
	end
end

-- Parpadeo visual por evento. Extiende el parpadeo en curso si ya habia uno.
function Controller.Flicker(seconds: number)
	flickerUntil = math.max(flickerUntil, os.clock() + seconds)
end

local function flickerMultiplier(now: number): number
	if now >= flickerUntil then
		flickerLevel = 1
		return 1
	end
	if now >= nextFlickerRoll then
		nextFlickerRoll = now + 1 / PresentationConfig.Flashlight.FlickerRateHz
		if math.random() < 0.5 then
			flickerLevel = math.random() * PresentationConfig.Flashlight.FlickerDimLevel
		else
			flickerLevel = 0.5 + math.random() * 0.5
		end
	end
	return flickerLevel
end

-- Direccion unitaria con pitch limitado para que el servidor no rechace el payload.
local function aimDirection(look: Vector3): Vector3?
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude < 1e-3 then
		return nil
	end
	local maxPitch =
		math.rad(NetworkConfig.FlashlightMaxPitchDegrees - PresentationConfig.Flashlight.AimPitchMarginDegrees)
	local pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -maxPitch, maxPitch)
	return horizontal.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
end

local function sendAim(now: number, direction: Vector3)
	local request = controllers.StateController.NewRequest()
	local payload: Types.SetFlashlightAim =
		{ requestId = request.requestId, runId = request.runId, direction = direction }
	lastAimSentAt = now
	lastAimDirection = direction
	remotes.SetFlashlightAim:FireServer(payload)
end

local function updateAim(now: number, look: Vector3)
	if not serverOn or controllers.StateController.IsDebug() then
		lastAimDirection = nil
		return
	end
	if now - lastAimSentAt < AIM_SEND_INTERVAL_SECONDS then
		return
	end
	local direction = aimDirection(look)
	if direction == nil then
		return
	end
	local previous = lastAimDirection
	local changed = previous == nil
		or math.deg(math.acos(math.clamp(previous:Dot(direction), -1, 1)))
			>= PresentationConfig.Flashlight.AimMinChangeDegrees
	if changed or now - lastAimSentAt >= PresentationConfig.Flashlight.AimHeartbeatSeconds then
		sendAim(now, direction)
	end
end

local function onRender()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	ensureLight()
	local part = lightPart :: Part
	local light = spotLight :: SpotLight
	part.CFrame = camera.CFrame

	local now = os.clock()
	local visible = desiredOn and serverAlive
	light.Enabled = visible
	if visible then
		light.Brightness = PresentationConfig.Flashlight.Brightness * flickerMultiplier(now)
		updateAim(now, camera.CFrame.LookVector)
	else
		lastAimDirection = nil
	end
end

function Controller.Init(context: Context)
	remotes = context.Remotes :: { [string]: RemoteEvent }
	controllers = context.Controllers :: { [string]: any }
end

function Controller.Start()
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(connections, remotes.ActionResult.OnClientEvent:Connect(onActionResult))
	table.insert(connections, remotes.Feedback.OnClientEvent:Connect(onFeedback))
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == PresentationConfig.InputBindings.Flashlight then
				toggle()
			end
		end)
	)
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))

	-- Si el personaje muere o se recarga, la luz local sigue la camara; no hay estado propio que limpiar.
	table.insert(
		connections,
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			lastAimDirection = nil
		end)
	)

	DebugCommands.Register("parpadeo", function(args: { string })
		Controller.Flicker(tonumber(args[1]) or PresentationConfig.Flashlight.FlickerSeconds)
	end)
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
	if lightPart ~= nil then
		lightPart:Destroy()
		lightPart = nil
		spotLight = nil
	end
end

function Controller.IsOn(): boolean
	return desiredOn
end

return Controller
