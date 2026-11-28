--!strict
-- Nodos (arboles, rocas, arbustos), golpes, contenedores y loot (docs/specs/recoleccion-inventario.md).
-- Todo vive en registries del servidor; el cliente solo ve los atributos de los modelos y ContainerView.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Guard = require(script.Parent:WaitForChild("RemoteGuard"))
local Spatial = require(script.Parent:WaitForChild("Spatial"))

local Service = {}

export type Context = { [string]: unknown }
type Node = { id: string, kind: string, model: Model, hitbox: BasePart, hp: number, maxHp: number }
type Container = {
	id: string,
	model: Model,
	hitbox: BasePart,
	open: boolean,
	content: { { Item: string, Count: number } },
	noiseKind: string?,
	lots: { [number]: Lot },
}
type Lot = { id: string, container: Container, slot: number, itemId: string, count: number }

local nodes: { [string]: Node } = {}
local containers: { [string]: Container } = {}
local lots: { [string]: Lot } = {}
local hitReady: { [Player]: number } = {}
local residue: { [number]: { [string]: number } } = {}
local connections: { RBXScriptConnection } = {}
local counter = 0
local resources: any
local items: any
local nights: any
local network: any
local interactionConfig: any
local worldConfig: any
local eyeOffset = Vector3.zero
local players: any
local inventory: any
local stimulus: any
local interaction: any
local replication: any
local world: any

local function prefabPath(name: string): string
	return "ServerStorage/" .. worldConfig.PrefabsName .. "/" .. name
end

-- Valida el contrato de prefab (nodo o contenedor). Devuelve el modelo o el mensaje de error con el path.
local function checkPrefab(name: string, isNode: boolean): (Model?, string?)
	local folder = ServerStorage:FindFirstChild(worldConfig.PrefabsName)
	local prefab = if folder then folder:FindFirstChild(name) else nil
	local path = prefabPath(name)
	if not prefab or not prefab:IsA("Model") then
		return nil, "falta el prefab (Model) " .. path
	end
	local hitbox = prefab:FindFirstChild("Hitbox")
	if isNode and prefab:GetAttribute("NodeKind") ~= name then
		return nil, path .. " sin atributo NodeKind = " .. name
	elseif not prefab.PrimaryPart or prefab.PrimaryPart.Name ~= "Base" then
		return nil, path .. " sin PrimaryPart Base"
	elseif not hitbox or not hitbox:IsA("BasePart") or not hitbox.CanQuery then
		return nil, path .. " sin Part Hitbox con CanQuery"
	elseif prefab:FindFirstChildWhichIsA("LuaSourceContainer", true) then
		return nil, path .. " contiene Scripts"
	end
	return prefab, nil
end

local function markersOf(name: string, errors: { string }): { BasePart }
	local markers = Workspace:FindFirstChild(worldConfig.MarkersName)
	local folder = if markers then markers:FindFirstChild(name) else nil
	local list: { BasePart } = {}
	if not folder then
		table.insert(errors, "falta Workspace/" .. worldConfig.MarkersName .. "/" .. name)
		return list
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

type NodePlan = { marker: BasePart, kind: string }
type ContainerPlan = { marker: BasePart, content: { { Item: string, Count: number } }, noiseKind: string? }

-- Valida todo (prefabs, contrato, marcadores, LootTables) sin crear nada. Lanza un error con todos los problemas.
local function buildPlan(): ({ NodePlan }, { ContainerPlan }, { [string]: Model })
	local errors: { string } = {}
	local prefabs: { [string]: Model } = {}
	for kind in resources.Nodes do
		local prefab, message = checkPrefab(kind, true)
		if prefab then
			prefabs[kind] = prefab
		else
			table.insert(errors, message :: string)
		end
	end
	local containerPrefab, containerMessage = checkPrefab("Contenedor", false)
	if containerPrefab then
		prefabs.Contenedor = containerPrefab
	else
		table.insert(errors, containerMessage :: string)
	end
	local nodePlans: { NodePlan } = {}
	for _, marker in markersOf("ResourceSpawns", errors) do
		local kind = marker:GetAttribute("Kind")
		if typeof(kind) == "string" and resources.Nodes[kind] then
			table.insert(nodePlans, { marker = marker, kind = kind })
		else
			table.insert(errors, marker:GetFullName() .. " con atributo Kind sin entrada en ResourcesConfig.Nodes")
		end
	end
	local containerPlans: { ContainerPlan } = {}
	local perZone: { [string]: number } = {}
	for _, marker in markersOf("LootSpawns", errors) do
		local zone = marker:GetAttribute("ZoneId")
		local lootTable = if typeof(zone) == "string" then resources.LootTables[zone] else nil
		local index = tonumber(string.match(marker.Name, "_(%d+)$"))
		local content = if lootTable and index then lootTable.Containers[index] else nil
		if content then
			perZone[zone] = (perZone[zone] or 0) + 1
			table.insert(containerPlans, { marker = marker, content = content, noiseKind = lootTable.OpenNoiseKind })
		else
			table.insert(errors, marker:GetFullName() .. " sin entrada en ResourcesConfig.LootTables")
		end
	end
	for zone, lootTable in resources.LootTables do
		if (perZone[zone] or 0) ~= #lootTable.Containers then
			table.insert(
				errors,
				string.format(
					"LootTables.%s espera %d marcadores en Workspace/%s/LootSpawns y hay %d",
					zone,
					#lootTable.Containers,
					worldConfig.MarkersName,
					perZone[zone] or 0
				)
			)
		end
	end
	if #errors > 0 then
		error("ResourceService: la run no puede arrancar:\n - " .. table.concat(errors, "\n - "), 0)
	end
	return nodePlans, containerPlans, prefabs
end

-- Clona el prefab anclado en el marcador y le pone los atributos del servidor.
local function place(prefab: Model, marker: BasePart, parent: Folder, idPrefix: string, attributes: { [string]: any })
	local clone = prefab:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	clone:PivotTo(CFrame.new(marker.Position) * CFrame.Angles(0, math.rad(marker.Orientation.Y), 0))
	counter += 1
	local id = idPrefix .. counter
	for name, value in attributes do
		clone:SetAttribute(name, value)
	end
	clone:SetAttribute(if idPrefix == "R" then "ResourceId" else "ContainerId", id)
	clone.Parent = parent
	return clone, clone:FindFirstChild("Hitbox") :: BasePart, id
end

local function clear(folder: Folder)
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
end

local function nodePosition(model: Model): Vector3
	return model:GetPivot().Position
end

local function currentRoster(): number
	return math.clamp(#Players:GetPlayers(), 1, #nights.Scaling)
end

local function openContainer(container: Container)
	container.open = true
	container.model:SetAttribute("Open", true)
	for slot, entry in container.content do
		local lot: Lot = {
			id = container.id .. ":" .. slot,
			container = container,
			slot = slot,
			itemId = entry.Item,
			count = entry.Count,
		}
		container.lots[slot] = lot
		lots[lot.id] = lot
	end
	local position = nodePosition(container.model)
	if container.noiseKind then
		stimulus.EmitNoise(container.noiseKind, container.id, position)
	end
	replication.EmitFeedback("ContainerOpened", container.id, position, nil)
end

function Service.Init(context: Context)
	local configs = context.Configs :: any
	local services = context.Services :: any
	resources = configs.ResourcesConfig
	items = configs.ItemsConfig.Items
	nights = configs.NightsConfig
	network = configs.NetworkConfig
	interactionConfig = configs.InteractionConfig
	worldConfig = configs.WorldConfig
	eyeOffset = Vector3.new(0, configs.PlayerConfig.EyeOffsetStuds, 0)
	players = services.PlayerService
	inventory = services.InventoryService
	stimulus = services.StimulusService
	interaction = services.InteractionService
	replication = services.ReplicationService
	world = services.WorldService
end

function Service.Start()
	interaction.Register("SearchContainer", {
		Prepare = function(_player: Player, targetId: string)
			local container = containers[targetId]
			if not container then
				return "NotFound", nil
			end
			if container.open then
				return "InvalidState", nil
			end
			return "Ok",
				{
					hold = interactionConfig.SearchContainerHoldSeconds,
					key = "container:" .. container.id,
					model = container.model,
					hitbox = container.hitbox,
					cancelOnDamage = true,
				}
		end,
		Commit = function(_player: Player, targetId: string)
			local container = containers[targetId]
			if not container or container.open then
				return "InvalidState"
			end
			openContainer(container)
			return "Ok"
		end,
	})
	interaction.Register("PickupLoot", {
		Prepare = function(player: Player, targetId: string)
			local lot = lots[targetId]
			if not lot then
				return "NotFound", nil
			end
			if not inventory.CanApplyDelta(player.UserId, { [lot.itemId] = lot.count }) then
				return "InventoryFull", nil
			end
			return "Ok",
				{
					hold = interactionConfig.PickupLootHoldSeconds,
					key = "loot:" .. lot.id,
					model = lot.container.model,
					hitbox = lot.container.hitbox,
					cancelOnDamage = true,
				}
		end,
		Commit = function(player: Player, targetId: string)
			local lot = lots[targetId]
			if not lot then
				return "NotFound"
			end
			local ok, code =
				inventory.TryApplyDelta(player.UserId, { [lot.itemId] = lot.count }, "PickupLoot:" .. lot.id)
			if ok then
				lots[lot.id] = nil
				lot.container.lots[lot.slot] = nil
				return "Ok"
			end
			return code
		end,
	})
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			hitReady[player] = nil
			residue[player.UserId] = nil
		end)
	)
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

-- Valida todo antes de tocar nada (error con el path si falta algo) y luego reconstruye nodos y contenedores.
function Service.BeginRun(_runId: string)
	local nodePlans, containerPlans, prefabs = buildPlan()
	table.clear(nodes)
	table.clear(containers)
	table.clear(lots)
	table.clear(hitReady)
	table.clear(residue)
	counter = 0
	local nodeFolder = world.RuntimeFolder(worldConfig.ResourcesFolder)
	local containerFolder = world.RuntimeFolder(worldConfig.ContainersFolder)
	clear(nodeFolder)
	clear(containerFolder)
	for _, plan in nodePlans do
		local config = resources.Nodes[plan.kind]
		local model, hitbox, id = place(
			prefabs[plan.kind],
			plan.marker,
			nodeFolder,
			"R",
			{ HP = config.MaxHealth, MaxHP = config.MaxHealth, Active = true }
		)
		nodes[id] = {
			id = id,
			kind = plan.kind,
			model = model,
			hitbox = hitbox,
			hp = config.MaxHealth,
			maxHp = config.MaxHealth,
		}
	end
	for _, plan in containerPlans do
		local model, hitbox, id = place(prefabs.Contenedor, plan.marker, containerFolder, "C", { Open = false })
		containers[id] = {
			id = id,
			model = model,
			hitbox = hitbox,
			open = false,
			content = plan.content,
			noiseKind = plan.noiseKind,
			lots = {},
		}
	end
end

-- Comprobacion previa para SessionService: lanza el mismo error sin crear nada.
function Service.Validate()
	buildPlan()
end

Service.ResetForRun = Service.BeginRun

-- Golpe a un nodo. El llamador (ReplicationService) ya comprobo run, Alive, manos libres y sin interaccion activa.
-- Devuelve el ResultCode; rechazar no daña, no emite ruido ni consume cooldown de gameplay.
function Service.Hit(player: Player, targetId: string): string
	local node = nodes[targetId]
	if not node then
		return "NotFound"
	end
	local config = resources.Nodes[node.kind]
	local userId = player.UserId
	-- Herramienta derivada en servidor; en nodos HandOnly cualquier herramienta cuenta como mano vacia.
	local equipped = inventory.GetEquipped(userId)
	local tool = if equipped then items[equipped].Tool else nil
	local stats = resources.BareHand
	if tool and table.find(tool.ResourceKinds, node.kind) then
		stats = tool
	elseif equipped and not config.HandOnly then
		return "WrongTool"
	end
	local now = os.clock()
	if not Guard.CooldownOk(hitReady, player, now) then
		return "Cooldown"
	end
	local position = players.GetValidatedPosition(player)
	if not position then
		return "NotAlive"
	end
	local point = Spatial.ClosestPoint(node.hitbox, position)
	if (point - position).Magnitude > resources.HitRangeStuds then
		return "OutOfRange"
	end
	if not Spatial.HasLineOfSight(position + eyeOffset, point, node.model) then
		return "Blocked"
	end
	-- Escalado por roster con residuo por jugador y material para no perder decimales.
	local carried = residue[userId]
	if not carried then
		carried = {}
		residue[userId] = carried
	end
	local gross = stats.Yield * nights.Scaling[currentRoster()].ResourceYieldFactor + (carried[config.OutputItem] or 0)
	local amount = math.floor(gross + 1e-9)
	local reward = { [config.OutputItem] = amount }
	if amount > 0 and not inventory.CanApplyDelta(userId, reward) then
		return "InventoryFull"
	end
	-- Commit sin yield.
	Guard.CooldownArm(hitReady, player, stats.HitCooldownSeconds, now)
	if amount > 0 then
		inventory.TryApplyDelta(userId, reward, "Resource:" .. node.kind)
	end
	carried[config.OutputItem] = math.max(0, gross - amount)
	node.hp = math.max(0, node.hp - stats.Damage)
	node.model:SetAttribute("HP", node.hp)
	local nodeAt = nodePosition(node.model)
	stimulus.EmitNoise(config.NoiseKind, node.id, nodeAt)
	if node.hp > 0 then
		replication.EmitFeedback("ResourceHit", node.id, nodeAt, nil)
	else
		nodes[node.id] = nil
		node.model:SetAttribute("Active", false)
		replication.EmitFeedback("ResourceDepleted", node.id, nodeAt, nil)
		node.model:Destroy()
	end
	players.NotifySwing(player)
	return "Ok"
end

-- ContainerView de los contenedores a <= ContainerViewRangeStuds del jugador. Cerrados: sin contenido.
function Service.GetContainerViews(player: Player): { any }
	local position = players.GetValidatedPosition(player)
	local views = {}
	if not position then
		return views
	end
	local near: { { container: Container, distance: number } } = {}
	for _, container in containers do
		local distance = (container.hitbox.Position - position).Magnitude
		if distance <= network.ContainerViewRangeStuds then
			table.insert(near, { container = container, distance = distance })
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#near, network.MaxVisibleContainers) do
		local container = near[index].container
		local stacks = {}
		for slot = 1, #container.content do
			local lot = container.lots[slot]
			if lot and #stacks < network.MaxContainerStacks then
				table.insert(stacks, { slot = slot, itemId = lot.itemId, count = lot.count })
			end
		end
		table.insert(views, { id = container.id, kind = "LootContainer", open = container.open, stacks = stacks })
	end
	return views
end

return Service
