--!strict
-- Unico escritor de cantidades (docs/specs/recoleccion-inventario.md). Todo es config-driven: items y recetas se
-- recorren desde ItemsConfig/RecipesConfig. Las operaciones son sincronas, sin yield, y atomicas sobre una copia.
local Players = game:GetService("Players")
local Guard = require(script.Parent:WaitForChild("RemoteGuard"))

local Service = {}

export type Context = { [string]: unknown }
type Slot = { itemId: string, count: number }
type Inventory = {
	slots: { [number]: Slot },
	equipped: number,
	equippedItem: string?,
	revision: number,
	lastReason: string,
	kit: boolean,
}

local items: any
local recipes: any
local playerConfig: any
local slotCount = 12
local orderedIds: { string } = {}
local inventories: { [number]: Inventory } = {}
local craftReady: { [number]: number } = {}
local connections: { RBXScriptConnection } = {}

local function inventoryOf(userId: number): Inventory
	local inventory = inventories[userId]
	if not inventory then
		inventory = { slots = {}, equipped = 0, equippedItem = nil, revision = 0, lastReason = "", kit = false }
		inventories[userId] = inventory
	end
	return inventory
end

local function isInteger(value: unknown): boolean
	return typeof(value) == "number"
		and value == value
		and math.abs(value :: number) ~= math.huge
		and (value :: number) % 1 == 0
end

-- Simula `delta` sobre una copia: primero salidas (liberan huecos), luego entradas. Devuelve la copia o el codigo.
local function simulate(slots: { [number]: Slot }, delta: { [string]: number }): ({ [number]: Slot }?, string)
	for itemId, amount in delta do
		if items[itemId] == nil or not isInteger(amount) then
			return nil, "InvalidPayload"
		end
	end
	local copy: { [number]: Slot } = {}
	for index, slot in slots do
		copy[index] = { itemId = slot.itemId, count = slot.count }
	end
	for _, itemId in orderedIds do
		local amount = delta[itemId]
		if amount and amount < 0 then
			local need = -amount
			for index = slotCount, 1, -1 do
				local slot = copy[index]
				if need > 0 and slot and slot.itemId == itemId then
					local take = math.min(need, slot.count)
					slot.count -= take
					need -= take
					if slot.count == 0 then
						copy[index] = nil
					end
				end
			end
			if need > 0 then
				return nil, "InsufficientItems"
			end
		end
	end
	for _, itemId in orderedIds do
		local amount = delta[itemId]
		if amount and amount > 0 then
			local maxStack = items[itemId].MaxStack
			local left = amount
			for index = 1, slotCount do
				local slot = copy[index]
				if left > 0 and slot and slot.itemId == itemId and slot.count < maxStack then
					local put = math.min(left, maxStack - slot.count)
					slot.count += put
					left -= put
				end
			end
			for index = 1, slotCount do
				if left > 0 and copy[index] == nil then
					local put = math.min(left, maxStack)
					copy[index] = { itemId = itemId, count = put }
					left -= put
				end
			end
			if left > 0 then
				return nil, "InventoryFull"
			end
		end
	end
	return copy, "Ok"
end

function Service.Init(context: Context)
	local configs = context.Configs :: any
	items = configs.ItemsConfig.Items
	recipes = configs.RecipesConfig
	playerConfig = configs.PlayerConfig
	slotCount = configs.ItemsConfig.InventorySlots
	for itemId in items do
		table.insert(orderedIds, itemId)
	end
	table.sort(orderedIds, function(a, b)
		return items[a].Order < items[b].Order
	end)
end

function Service.Start()
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			-- TODO: mochila al desconectar (ciclo de muerte); por ahora el inventario se descarta.
			inventories[player.UserId] = nil
			craftReady[player.UserId] = nil
		end)
	)
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function Service.CanApplyDelta(userId: number, delta: { [string]: number }): boolean
	return (simulate(inventoryOf(userId).slots, delta)) ~= nil
end

-- delta: positivos entran, negativos salen. Todo o nada; desequipa si el slot equipado cambia de contenido.
function Service.TryApplyDelta(userId: number, delta: { [string]: number }, reason: string): (boolean, string)
	local inventory = inventoryOf(userId)
	local copy, code = simulate(inventory.slots, delta)
	if not copy then
		return false, code
	end
	inventory.slots = copy
	inventory.revision += 1
	inventory.lastReason = reason
	local equipped = copy[inventory.equipped]
	if inventory.equipped ~= 0 and (not equipped or equipped.itemId ~= inventory.equippedItem) then
		inventory.equipped = 0
		inventory.equippedItem = nil
	end
	return true, "Ok"
end

function Service.GetSnapshot(userId: number): { { slot: number, itemId: string, count: number } }
	local inventory = inventories[userId]
	local list = {}
	if inventory then
		for index = 1, slotCount do
			local slot = inventory.slots[index]
			if slot then
				table.insert(list, { slot = index, itemId = slot.itemId, count = slot.count })
			end
		end
	end
	return list
end

function Service.Count(userId: number, itemId: string): number
	local inventory = inventories[userId]
	local total = 0
	if inventory then
		for _, slot in inventory.slots do
			if slot.itemId == itemId then
				total += slot.count
			end
		end
	end
	return total
end

function Service.GetEquipped(userId: number): string?
	local inventory = inventories[userId]
	return if inventory then inventory.equippedItem else nil
end

function Service.GetEquippedSlot(userId: number): number
	local inventory = inventories[userId]
	return if inventory then inventory.equipped else 0
end

function Service.GetRevision(userId: number): number
	local inventory = inventories[userId]
	return if inventory then inventory.revision else 0
end

function Service.Equip(userId: number, slot: number): string
	local inventory = inventoryOf(userId)
	if slot == 0 then
		inventory.equipped = 0
		inventory.equippedItem = nil
	else
		if not (isInteger(slot) and slot >= 1 and slot <= slotCount) then
			return "InvalidPayload"
		end
		local stack = inventory.slots[slot]
		if not stack then
			return "NotFound"
		end
		if not items[stack.itemId].Equippable then
			return "InvalidState"
		end
		inventory.equipped = slot
		inventory.equippedItem = stack.itemId
	end
	inventory.revision += 1
	return "Ok"
end

function Service.Craft(userId: number, recipeId: string, count: number): string
	local recipe = recipes.Recipes[recipeId]
	if not recipe then
		return "NotFound"
	end
	if not (isInteger(count) and count >= 1 and count <= recipes.MaxBatch) then
		return "InvalidPayload"
	end
	local now = os.clock()
	if not Guard.CooldownOk(craftReady, userId, now) then
		return "Cooldown"
	end
	local delta: { [string]: number } = {}
	for itemId, amount in recipe.Inputs do
		delta[itemId] = -amount * count
	end
	delta[recipe.Output.ItemId] = (delta[recipe.Output.ItemId] or 0) + recipe.Output.Count * count
	local ok, code = Service.TryApplyDelta(userId, delta, "Craft:" .. recipeId)
	if ok then
		Guard.CooldownArm(craftReady, userId, recipes.CraftCooldownSeconds, now)
	end
	return code
end

function Service.GiveInitialKit(userId: number)
	local inventory = inventoryOf(userId)
	if not inventory.kit then
		inventory.kit = true
		Service.TryApplyDelta(userId, playerConfig.InitialItems, "InitialKit")
	end
end

-- Vacia el inventario y devuelve los stacks (para la mochila).
function Service.TakeAll(userId: number): { { slot: number, itemId: string, count: number } }
	local list = Service.GetSnapshot(userId)
	local inventory = inventoryOf(userId)
	inventory.slots = {}
	inventory.equipped = 0
	inventory.equippedItem = nil
	inventory.revision += 1
	inventory.lastReason = "TakeAll"
	return list
end

function Service.ResetForRun()
	table.clear(inventories)
	table.clear(craftReady)
end

return Service
