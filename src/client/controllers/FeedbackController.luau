--!strict
-- Feedback cosmetico local: sacudida y particulas en nodos golpeados, destellos al usar items. Recibe el remote
-- Feedback (solo hechos aceptados por el servidor) y no cambia nada jugable.
-- Cues atendidos: ResourceHit, ResourceDepleted, ContainerOpened, ItemUsed. sourceId de nodos = ResourceId.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))

local Controller = {}

export type Context = { [string]: unknown }

local controllers = {} :: ClientTypes.Controllers
local remotes: { [string]: RemoteEvent } = {}
local connections: { RBXScriptConnection } = {}
local shaking: { [Instance]: boolean } = {}
local lastFx: { [Instance]: number } = setmetatable({} :: { [Instance]: number }, { __mode = "k" })

local function resourcesFolder(): Instance?
	local runtime = Workspace:FindFirstChild("Runtime")
	return if runtime ~= nil then runtime:FindFirstChild("Resources") else nil
end

local function findNode(resourceId: string): Model?
	local folder = resourcesFolder()
	if folder == nil then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("ResourceId") == resourceId then
			return child
		end
	end
	return nil
end

local function burst(position: Vector3, color: Color3, count: number)
	local settings = PresentationConfig.Feedback
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(settings.ParticleLifetimeSeconds * 0.6, settings.ParticleLifetimeSeconds)
	emitter.Speed = NumberRange.new(settings.ParticleSpeed * 0.5, settings.ParticleSpeed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -settings.ParticleGravity, 0)
	emitter.Size = NumberSequence.new(settings.ParticleSize)
	emitter.Parent = part
	part.Parent = Workspace
	emitter:Emit(count)
	Debris:AddItem(part, settings.ParticleLifetimeSeconds + 0.5)
end

local function shake(model: Model)
	if shaking[model] then
		return
	end
	shaking[model] = true
	local settings = PresentationConfig.Feedback
	local origin = model:GetPivot()
	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local fraction = (os.clock() - startedAt) / settings.ShakeSeconds
		if model.Parent == nil or fraction >= 1 then
			if model.Parent ~= nil then
				model:PivotTo(origin)
			end
			shaking[model] = nil
			if connection ~= nil then
				connection:Disconnect()
			end
			return
		end
		local amplitude = settings.ShakeStuds * (1 - fraction)
		model:PivotTo(
			origin + Vector3.new((math.random() - 0.5) * 2 * amplitude, 0, (math.random() - 0.5) * 2 * amplitude)
		)
	end)
end

local function nodeColor(model: Instance?): Color3
	local colors: { [string]: Color3 } = PresentationConfig.Feedback.NodeColors
	local kind = if model ~= nil then model:GetAttribute("NodeKind") else nil
	return if typeof(kind) == "string" and colors[kind] ~= nil
		then colors[kind]
		else PresentationConfig.Feedback.DefaultParticleColor
end

-- Golpe confirmado (ActionResult ok o cue ResourceHit): sacudida y particulas, una vez por ventana por nodo.
local function hitFx(model: Model?, position: Vector3?)
	local settings = PresentationConfig.Feedback
	local now = os.clock()
	local key: Instance? = model
	if key ~= nil then
		if now - (lastFx[key] or 0) < settings.NodeFxDebounceSeconds then
			return
		end
		lastFx[key] = now
		shake(model :: Model)
		controllers.HUDController.PulseCrosshair()
	end
	local at = position or (if model ~= nil then model:GetPivot().Position else nil)
	if at ~= nil then
		burst(at, nodeColor(model), settings.HitParticles)
	end
end

function Controller.HitConfirmed(node: Instance)
	if node:IsA("Model") and node.Parent ~= nil then
		hitFx(node, nil)
	end
end

local function onFeedback(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local cue = payload :: { [string]: unknown }
	local snapshot = controllers.StateController.Get()
	if snapshot ~= nil and cue.runId ~= snapshot.runId then
		return
	end
	local position: Vector3? = if typeof(cue.position) == "Vector3" then cue.position else nil
	local settings = PresentationConfig.Feedback
	if cue.cueId == "ResourceHit" and typeof(cue.sourceId) == "string" then
		hitFx(findNode(cue.sourceId), position)
	elseif cue.cueId == "ResourceDepleted" and position ~= nil then
		local node = if typeof(cue.sourceId) == "string" then findNode(cue.sourceId) else nil
		burst(position, nodeColor(node), settings.DepletedParticles)
	elseif cue.cueId == "ContainerOpened" and position ~= nil then
		burst(position, settings.ContainerColor, settings.ContainerParticles)
	elseif cue.cueId == "ItemUsed" then
		controllers.HUDController.Flash(PresentationConfig.Colors.ItemUsedFlash)
	end
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
	remotes = context.Remotes :: { [string]: RemoteEvent }
end

function Controller.Start()
	table.insert(connections, remotes.Feedback.OnClientEvent:Connect(onFeedback))
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return Controller
