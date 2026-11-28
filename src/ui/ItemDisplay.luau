--!strict
-- Presentacion de items desde ItemsConfig + PresentationConfig (nombre, icono greybox). Sin listas escritas a mano.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
local PresentationConfig = require(config:WaitForChild("PresentationConfig"))

local ItemDisplay = {}

export type ItemDef = {
	Id: string,
	DisplayName: string,
	Kind: string,
	MaxStack: number,
	Equippable: boolean,
	IconKey: string,
	Order: number,
	Tool: { ResourceKinds: { string }, Damage: number, Yield: number, HitCooldownSeconds: number }?,
	Use: { HoldSeconds: number, Health: number?, Hunger: number?, Battery: number?, CancelOnDamage: boolean }?,
}

-- ItemsConfig no exporta tipo: se estrecha aqui, una sola vez, a la forma real de ItemsConfig.luau.
local Items = ((require(config:WaitForChild("ItemsConfig")) :: unknown) :: { Items: { [string]: ItemDef } }).Items

export type Display = { name: string, color: Color3, letters: string, kind: string }

function ItemDisplay.Def(itemId: string): ItemDef?
	return Items[itemId]
end

function ItemDisplay.Get(itemId: string): Display
	local def = Items[itemId]
	local name = if def ~= nil then def.DisplayName else itemId
	local kind = if def ~= nil then def.Kind else ""
	local icons = PresentationConfig.Icons :: { [string]: { Color: Color3, Letters: string? } }
	local icon = icons[if def ~= nil then def.IconKey else itemId]
	local kindColors: { [string]: Color3 } = PresentationConfig.IconKindColors
	return {
		name = name,
		kind = kind,
		color = if icon ~= nil then icon.Color else (kindColors[kind] or PresentationConfig.IconDefaultColor),
		letters = if icon ~= nil and icon.Letters ~= nil then icon.Letters else string.sub(name, 1, 2),
	}
end

-- ItemIds ordenados por Order y luego por nombre.
function ItemDisplay.SortedIds(): { string }
	local ids: { string } = {}
	for id in Items do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local orderA, orderB = Items[a].Order, Items[b].Order
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a < b
	end)
	return ids
end

return ItemDisplay
