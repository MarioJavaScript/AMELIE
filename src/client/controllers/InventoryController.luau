--!strict
-- Inventario, equipar, usar consumibles y crafteo rapido. Todo se dibuja desde SelfView.inventory del snapshot:
-- el cliente nunca altera cantidades, solo pide EquipTool / BeginInteraction UseItem / CraftItem y espera al servidor.
-- Contrato leido: snapshot.self.inventory {slot,itemId,count}, self.equippedSlot, ItemsConfig.Items, RecipesConfig.Recipes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("types"))
local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))
local PresentationConfig = require(config:WaitForChild("PresentationConfig"))
local NetworkConfig = require(config:WaitForChild("NetworkConfig"))
-- Los configs no exportan tipo: se estrechan a la forma real declarada en ClientTypes (un cast por config).
local ItemsConfig = (require(config:WaitForChild("ItemsConfig")) :: unknown) :: ClientTypes.ItemsConfig
local RecipesConfig = (require(config:WaitForChild("RecipesConfig")) :: unknown) :: ClientTypes.RecipesConfig
local DebugCommands = require(script.Parent.Parent:WaitForChild("DebugCommands"))

local Controller = {}

export type Context = { [string]: unknown }
type Menu = { SetVisible: (boolean) -> (), IsVisible: () -> boolean }
type RecipeEntry = { id: string, recipe: ClientTypes.RecipeDef }

local SLOT_COUNT = ItemsConfig.InventorySlots

local controllers = {} :: ClientTypes.Controllers
local views = {} :: ClientTypes.Views
local unsubscribers: { () -> () } = {}
local inventoryView: ClientTypes.InventoryView? = nil
local craftView: ClientTypes.CraftView? = nil

local bySlot: { [number]: Types.Stack } = {}
local totals: { [string]: number } = {}
local equippedSlot = 0
-- Slot que el jugador acaba de pedir (para alternar sin esperar al snapshot); caduca a los 3 s.
local pendingSlot: number? = nil
local pendingExpires = 0
local equipToken = 0

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

local function sortedRecipes(): { RecipeEntry }
	local list: { RecipeEntry } = {}
	for _, recipe in RecipesConfig.Recipes do
		table.insert(list, { id = recipe.Id, recipe = recipe })
	end
	table.sort(list, function(a: RecipeEntry, b: RecipeEntry): boolean
		local orderA, orderB = a.recipe.Order, b.recipe.Order
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.id < b.id
	end)
	return list
end

local function renderInventory()
	local view = inventoryView
	if view == nil then
		return
	end
	local slots: { [number]: ClientTypes.SlotData } = {}
	for slot, stack in bySlot do
		local display = views.ItemDisplay.Get(stack.itemId)
		slots[slot] = {
			name = display.name,
			count = stack.count,
			color = display.color,
			letters = display.letters,
			equipped = slot == equippedSlot,
			hotkey = if slot <= #PresentationConfig.InputBindings.Hotbar then tostring(slot) else nil,
		}
	end
	view.SetSlots(slots)
end

local function renderCraft()
	local view = craftView
	if view == nil then
		return
	end
	local order: { string } = views.ItemDisplay.SortedIds()
	local rank: { [string]: number } = {}
	for index, id in order do
		rank[id] = index
	end
	local data: { ClientTypes.RecipeData } = {}
	for _, entry in sortedRecipes() do
		local recipe = entry.recipe
		local inputs: { { id: string, need: number } } = {}
		for itemId, need in recipe.Inputs do
			table.insert(inputs, { id = itemId, need = need })
		end
		table.sort(inputs, function(a: { id: string, need: number }, b: { id: string, need: number }): boolean
			return (rank[a.id] or math.huge) < (rank[b.id] or math.huge)
		end)
		local canCraft: { [number]: boolean } = {}
		for _, batch in PresentationConfig.Craft.Batches do
			canCraft[batch] = true
			for _, input in inputs do
				if (totals[input.id] or 0) < input.need * batch then
					canCraft[batch] = false
				end
			end
		end
		local shown: { ClientTypes.RecipeInput } = {}
		for _, input in inputs do
			table.insert(
				shown,
				{ name = views.ItemDisplay.Get(input.id).name, have = totals[input.id] or 0, need = input.need }
			)
		end
		local output = recipe.Output
		local display = views.ItemDisplay.Get(output.ItemId)
		table.insert(data, {
			recipeId = entry.id,
			outputName = display.name,
			outputCount = output.Count,
			color = display.color,
			letters = display.letters,
			inputs = shown,
			canCraft = canCraft,
		})
	end
	view.SetRecipes(data)
end

local function onSnapshot(snapshot: Types.Snapshot)
	table.clear(bySlot)
	table.clear(totals)
	for _, stack in snapshot.self.inventory do
		bySlot[stack.slot] = stack
		totals[stack.itemId] = (totals[stack.itemId] or 0) + stack.count
	end
	equippedSlot = snapshot.self.equippedSlot
	if pendingSlot ~= nil and (pendingSlot == equippedSlot or os.clock() >= pendingExpires) then
		pendingSlot = nil
	end
	if inventoryView ~= nil and craftView ~= nil and not isPlayablePhase(snapshot.phase) then
		inventoryView.SetVisible(false)
		craftView.SetVisible(false)
	end
	renderInventory()
	renderCraft()
end

function Controller.IsMenuOpen(): boolean
	return inventoryView ~= nil and craftView ~= nil and (inventoryView.IsVisible() or craftView.IsVisible())
end

local function toggleMenu(open: Menu, other: Menu)
	local snapshot = controllers.StateController.Get()
	local show = not open.IsVisible()
	if show and (snapshot == nil or not isPlayablePhase(snapshot.phase)) then
		return
	end
	other.SetVisible(false)
	open.SetVisible(show)
end

function Controller.ToggleInventory()
	if inventoryView ~= nil and craftView ~= nil then
		toggleMenu(inventoryView, craftView)
	end
end

function Controller.ToggleCraft()
	if inventoryView ~= nil and craftView ~= nil then
		toggleMenu(craftView, inventoryView)
	end
end

-- Cooldown visual del golpe: el de la herramienta equipada o el de mano vacia. La autoridad es el servidor.
function Controller.GetEquippedHitCooldown(): number
	local stack = bySlot[equippedSlot]
	local def = if stack ~= nil then views.ItemDisplay.Def(stack.itemId) else nil
	local tool = if def ~= nil then def.Tool else nil
	return if tool ~= nil and tool.HitCooldownSeconds ~= nil
		then tool.HitCooldownSeconds
		else PresentationConfig.Interaction.DefaultHitCooldownSeconds
end

local function equip(slot: number)
	local current = pendingSlot or equippedSlot
	local target = if current == slot then 0 else slot
	pendingSlot = target
	pendingExpires = os.clock() + NetworkConfig.PendingRequestTimeoutSeconds
	equipToken += 1
	local token = equipToken
	-- Agrupa cambios rapidos y envia solo el ultimo.
	task.delay(PresentationConfig.Interaction.EquipGroupSeconds, function()
		if token ~= equipToken then
			return
		end
		local state = controllers.StateController
		if target == equippedSlot then
			pendingSlot = nil
		elseif state.IsDebug() then
			local selfView = table.clone((state.Get() :: Types.Snapshot).self)
			selfView.equippedSlot = target
			state.DebugInject({ self = selfView })
		else
			controllers.InteractionController.Send("EquipTool", { slot = target }, "Equip")
		end
	end)
end

-- Tecla 1..9 o clic en un slot: herramienta -> equipar/desequipar; consumible -> usar (otra pulsacion cancela).
function Controller.ActivateSlot(slot: number)
	local stack = bySlot[slot]
	local def = if stack ~= nil then views.ItemDisplay.Def(stack.itemId) else nil
	if stack == nil or def == nil then
		return
	end
	local interaction = controllers.InteractionController
	if def.Equippable == true then
		equip(slot)
	elseif def.Use ~= nil then
		local current = interaction.GetActive()
		if current ~= nil and current.action == "UseItem" and current.targetId == stack.itemId then
			interaction.Cancel()
		else
			interaction.Begin("UseItem", stack.itemId)
		end
	end
end

function Controller.Craft(recipeId: string, count: number)
	local interaction = controllers.InteractionController
	if interaction.IsPending("Craft") then
		return
	end
	interaction.Send(
		"CraftItem",
		{ recipeId = recipeId, count = math.clamp(count, 1, RecipesConfig.MaxBatch) },
		"Craft"
	)
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
	views = context.Views :: ClientTypes.Views
end

function Controller.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	inventoryView = views.Inventory.Create(playerGui, SLOT_COUNT, Controller.ActivateSlot)
	craftView = views.Craft.Create(playerGui, Controller.Craft)
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))
	controllers.InteractionController.SubscribeResults(function(kind: string, ok: boolean, _code: string)
		if kind == "Equip" and not ok then
			pendingSlot = nil
		end
	end)

	-- Solo Studio: /inv [slotEquipado] llena el inventario con ejemplos tomados de ItemsConfig mientras no haya servidor.
	DebugCommands.Register("inv", function(args: { string })
		local state = controllers.StateController
		if state.Get() ~= nil and not state.IsDebug() then
			warn("/inv: ya hay snapshots reales del servidor")
			return
		end
		state.DebugInject({})
		local selfView = table.clone((state.Get() :: Types.Snapshot).self)
		local inventory: { Types.Stack } = {}
		for index, itemId in views.ItemDisplay.SortedIds() do
			if index > SLOT_COUNT then
				break
			end
			local maxStack = ItemsConfig.Items[itemId].MaxStack
			table.insert(inventory, { slot = index, itemId = itemId, count = math.max(1, maxStack // 2) })
		end
		selfView.inventory = inventory
		selfView.equippedSlot = tonumber(args[1]) or 0
		state.DebugInject({ self = selfView })
	end)
end

function Controller.Stop()
	for _, unsubscribe in unsubscribers do
		unsubscribe()
	end
	table.clear(unsubscribers)
	if inventoryView ~= nil then
		inventoryView.Destroy()
	end
	if craftView ~= nil then
		craftView.Destroy()
	end
	inventoryView, craftView = nil, nil
end

return Controller
