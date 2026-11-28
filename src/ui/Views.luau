--!strict
-- Registro de vistas de UI (docs/specs/arquitectura.md). Cada vista es un ModuleScript hermano.
return {
	Hud = require(script.Parent:WaitForChild("HudView")),
	Inventory = require(script.Parent:WaitForChild("InventoryView")),
	Craft = require(script.Parent:WaitForChild("CraftView")),
	ItemDisplay = require(script.Parent:WaitForChild("ItemDisplay")),
}
