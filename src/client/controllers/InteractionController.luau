--!strict
-- Golpes a nodos, interaccion con contenedores y registro de solicitudes pendientes. Todo lo decide el servidor:
-- aqui solo se apunta, se envia la solicitud y se muestra el resultado (ActionResult / InteractionState).
-- Contrato leido: atributos ResourceId y Active (nodos en Workspace/Runtime/Resources), ContainerId y Open
-- (Workspace/Runtime/Containers, Part Hitbox), snapshot.containers y snapshot.self.interaction.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("types"))
local PresentationConfig = require(config:WaitForChild("PresentationConfig"))
local NetworkConfig = require(config:WaitForChild("NetworkConfig"))

local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))

local Controller = {}

export type Context = { [string]: unknown }
export type Active = ClientTypes.ActiveInteraction
type Pending = { kind: string, expiresAt: number, target: Instance? }
type ResultListener = (kind: string, ok: boolean, code: string) -> ()

local controllers = {} :: ClientTypes.Controllers
local views = {} :: ClientTypes.Views
local remotes: { [string]: RemoteEvent } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}

local pending: { [string]: Pending } = {}
local finished: { [string]: boolean } = {}
local resultListeners: { ResultListener } = {}
local active: Active? = nil
local lastRunId = ""
local readyAt = 0
local interactDown = false
local wantCancel = false
local cancelRequestedId: string? = nil
local promptText: string? = nil
local promptElapsed = 0

local function showMessage(code: string)
	local text = (PresentationConfig.ResultMessages :: { [string]: string })[code]
	if text ~= nil then
		controllers.HUDController.ShowMessage(text)
	end
end

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

local function canAct(): boolean
	local snapshot = controllers.StateController.Get()
	if snapshot == nil or not isPlayablePhase(snapshot.phase) then
		return false
	end
	local me = controllers.StateController.GetSelfPlayer()
	return me == nil or me.life == "Alive"
end

local function castFromCamera(range: number): RaycastResult?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	return Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * range, params)
end

local function ancestorWith(instance: Instance, attribute: string): Model?
	local node: Instance? = instance
	while node ~= nil and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute(attribute) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Distancia desde el punto al punto mas cercano de la Hitbox del modelo.
local function distanceToHitbox(model: Model, point: Vector3): number?
	local hitbox = model:FindFirstChild("Hitbox")
	if hitbox == nil or not hitbox:IsA("BasePart") then
		return nil
	end
	local half = hitbox.Size / 2
	local rel = hitbox.CFrame:PointToObjectSpace(point)
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return (hitbox.CFrame:PointToWorldSpace(clamped) - point).Magnitude
end

local function findContainer(): Model?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local runtime = Workspace:FindFirstChild("Runtime")
	local folder = if runtime ~= nil then runtime:FindFirstChild("Containers") else nil
	if root == nil or not root:IsA("BasePart") or folder == nil then
		return nil
	end
	local settings = PresentationConfig.Interaction
	local result = castFromCamera(settings.AimRayStuds)
	if result ~= nil then
		local aimed = ancestorWith(result.Instance, "ContainerId")
		local distance = if aimed ~= nil then distanceToHitbox(aimed, root.Position) else nil
		if aimed ~= nil and distance ~= nil and distance <= settings.InteractRangeStuds then
			return aimed
		end
	end
	local best: Model? = nil
	local bestDistance = settings.InteractRangeStuds
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("ContainerId") ~= nil then
			local distance = distanceToHitbox(child, root.Position)
			if distance ~= nil and distance <= bestDistance then
				best, bestDistance = child, distance
			end
		end
	end
	return best
end

-- Accion, targetId y texto del prompt para un contenedor, o nil si no hay nada que hacer.
local function resolve(model: Model): (Types.InteractionAction?, string?, string?)
	local id = model:GetAttribute("ContainerId")
	if typeof(id) ~= "string" then
		return nil, nil, nil
	end
	local settings = PresentationConfig.Interaction
	local key = PresentationConfig.InputBindings.Interact.Name
	if model:GetAttribute("Open") ~= true then
		return "SearchContainer", id, string.format(settings.SearchPrompt, key)
	end
	local snapshot = controllers.StateController.Get()
	if snapshot == nil then
		return nil, nil, nil
	end
	for _, view in snapshot.containers do
		if view.id == id then
			local first = nil
			for _, stack in view.stacks do
				if first == nil or stack.slot < first.slot then
					first = stack
				end
			end
			if first == nil then
				return nil, nil, nil
			end
			local name = views.ItemDisplay.Get(first.itemId).name
			local text = string.format(settings.PickupPrompt, key, name, first.count)
			return "PickupLoot", string.format("%s:%d", id, first.slot), text
		end
	end
	return nil, nil, nil
end

local function updatePrompt()
	promptText = nil
	if active ~= nil or controllers.InventoryController.IsMenuOpen() or not canAct() then
		return
	end
	local model = findContainer()
	if model ~= nil then
		local _, _, text = resolve(model)
		promptText = text
	end
end

local function prune(now: number)
	for id, entry in pending do
		if now >= entry.expiresAt then
			pending[id] = nil
		end
	end
end

function Controller.IsPending(kind: string): boolean
	prune(os.clock())
	for _, entry in pending do
		if entry.kind == kind then
			return true
		end
	end
	return false
end

-- Envia una solicitud C->S con requestId/runId y la registra como pendiente (caduca a los 3 s).
function Controller.Send(remoteName: string, fields: { [string]: unknown }, kind: string, target: Instance?): string
	local request = controllers.StateController.NewRequest()
	local payload: { [string]: unknown } = { requestId = request.requestId, runId = request.runId }
	for key, value in fields do
		payload[key] = value
	end
	pending[request.requestId] = {
		kind = kind,
		expiresAt = os.clock() + NetworkConfig.PendingRequestTimeoutSeconds,
		target = target,
	}
	remotes[remoteName]:FireServer(payload)
	return request.requestId
end

function Controller.SubscribeResults(listener: ResultListener)
	table.insert(resultListeners, listener)
end

function Controller.GetActive(): Active?
	return active
end

function Controller.GetPrompt(): string?
	return promptText
end

function Controller.Begin(action: Types.InteractionAction, targetId: string)
	if active ~= nil or Controller.IsPending("Begin") then
		return
	end
	Controller.Send("BeginInteraction", { action = action, targetId = targetId }, "Begin")
end

function Controller.Cancel()
	local current = active
	if current ~= nil and cancelRequestedId ~= current.id then
		cancelRequestedId = current.id
		Controller.Send("CancelInteraction", { interactionId = current.id }, "Cancel")
	end
end

function Controller.Hit()
	local now = os.clock()
	if now < readyAt or active ~= nil or not canAct() then
		return
	end
	local result = castFromCamera(PresentationConfig.Interaction.HitRangeStuds)
	local node = if result ~= nil then ancestorWith(result.Instance, "ResourceId") else nil
	if node == nil or node:GetAttribute("Active") ~= true then
		return
	end
	local id = node:GetAttribute("ResourceId")
	if typeof(id) ~= "string" then
		return
	end
	readyAt = now + controllers.InventoryController.GetEquippedHitCooldown()
	Controller.Send("HitResource", { targetId = id }, "Hit", node)
end

-- Soltar la tecla cancela una accion de mantener solo si queda bastante hold (un tap en un recoger corto no cancela).
local function cancelIfHeldAction()
	local current = active
	local settings = PresentationConfig.Interaction
	if
		current ~= nil
		and (settings.HoldKeyActions :: { [string]: boolean })[current.action] == true
		and current.endsAt - Workspace:GetServerTimeNow() > settings.ReleaseCancelMinRemainingSeconds
	then
		Controller.Cancel()
	end
end

function Controller.InteractPressed()
	interactDown = true
	wantCancel = false
	if active ~= nil then
		Controller.Cancel()
		return
	end
	if not canAct() or Controller.IsPending("Begin") then
		return
	end
	local model = findContainer()
	if model ~= nil then
		local action, targetId = resolve(model)
		if action ~= nil and targetId ~= nil then
			Controller.Begin(action, targetId)
		end
	end
end

function Controller.InteractReleased()
	interactDown = false
	if active ~= nil then
		cancelIfHeldAction()
	elseif Controller.IsPending("Begin") then
		wantCancel = true
	end
end

local function adopt(id: string, action: Types.InteractionAction, targetId: string, startedAt: number, endsAt: number)
	if finished[id] then
		return
	end
	local current = active
	if current ~= nil and current.id == id then
		current.endsAt = endsAt
		return
	end
	active =
		{ id = id, action = action, targetId = targetId, startedAt = startedAt, endsAt = endsAt, seenAt = os.clock() }
	if wantCancel and not interactDown then
		wantCancel = false
		cancelIfHeldAction()
	end
end

local function onSnapshot(snapshot: Types.Snapshot)
	if snapshot.runId ~= lastRunId then
		lastRunId = snapshot.runId
		table.clear(pending)
		table.clear(finished)
		active = nil
		wantCancel = false
	end
	local info = snapshot.self.interaction
	if info ~= nil then
		adopt(info.id, info.action, info.targetId, info.startedAt, info.endsAt)
	elseif active ~= nil and os.clock() - active.seenAt > PresentationConfig.Interaction.SnapshotClearGraceSeconds then
		active = nil
	end
end

local function onActionResult(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local result = payload :: { [string]: unknown }
	local requestId = result.requestId
	local entry = if typeof(requestId) == "string" then pending[requestId] else nil
	if entry == nil then
		return
	end
	pending[requestId :: string] = nil
	local ok = result.ok == true
	local code = if typeof(result.code) == "string" then result.code else "InternalError"
	if not ok then
		showMessage(code)
	elseif entry.kind == "Hit" and entry.target ~= nil then
		controllers.FeedbackController.HitConfirmed(entry.target)
	end
	for _, listener in resultListeners do
		listener(entry.kind, ok, code)
	end
end

local function onInteractionState(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local info = payload :: { [string]: unknown }
	local id, state = info.interactionId, info.state
	if typeof(id) ~= "string" or typeof(state) ~= "string" then
		return
	end
	if state == "Started" then
		local action, targetId, startedAt, endsAt = info.action, info.targetId, info.startedAt, info.endsAt
		if
			typeof(action) == "string"
			and typeof(targetId) == "string"
			and typeof(startedAt) == "number"
			and typeof(endsAt) == "number"
		then
			-- Un solo estrechamiento: el servidor solo envia acciones de Types.InteractionAction.
			adopt(id, action :: Types.InteractionAction, targetId, startedAt, endsAt)
		end
		return
	end
	finished[id] = true
	if active ~= nil and active.id == id then
		active = nil
	end
	if state == "Cancelled" and cancelRequestedId ~= id then
		local code = info.code
		showMessage(if typeof(code) == "string" then code else "Cancelled")
	end
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
	views = context.Views :: ClientTypes.Views
	remotes = context.Remotes :: { [string]: RemoteEvent }
end

function Controller.Start()
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))
	table.insert(connections, remotes.ActionResult.OnClientEvent:Connect(onActionResult))
	table.insert(connections, remotes.InteractionState.OnClientEvent:Connect(onInteractionState))
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			promptElapsed += dt
			if promptElapsed >= PresentationConfig.Interaction.PromptRefreshSeconds then
				promptElapsed = 0
				prune(os.clock())
				updatePrompt()
			end
		end)
	)
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
	table.clear(pending)
	active = nil
	promptText = nil
end

return Controller
