--!strict
-- Tipos locales del cliente: contratos entre controllers, vistas de UI y formas de ItemsConfig / RecipesConfig
-- (los configs no exportan tipo). Solo tipos; no ejecuta logica. Las vistas viven en otro arbol (PlayerGui),
-- por eso sus interfaces se reflejan aqui en vez de importarse.
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("types"))

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
export type ItemsConfig = { InventorySlots: number, Items: { [string]: ItemDef } }
export type RecipeDef = {
	Id: string,
	Inputs: { [string]: number },
	Output: { ItemId: string, Count: number },
	Order: number,
}
export type RecipesConfig = { MaxBatch: number, CraftCooldownSeconds: number, Recipes: { [string]: RecipeDef } }

export type Display = { name: string, color: Color3, letters: string, kind: string }
export type BarName = "Health" | "Stamina" | "Battery" | "Hunger"
export type SlotData = {
	name: string,
	count: number,
	color: Color3,
	letters: string,
	equipped: boolean,
	hotkey: string?,
}
export type RecipeInput = { name: string, have: number, need: number }
export type RecipeData = {
	recipeId: string,
	outputName: string,
	outputCount: number,
	color: Color3,
	letters: string,
	inputs: { RecipeInput },
	canCraft: { [number]: boolean },
}

export type HudView = {
	SetBar: (name: BarName, fraction: number, text: string, color: Color3) -> (),
	SetVisible: (visible: boolean) -> (),
	SetPrompt: (text: string?) -> (),
	SetProgress: (fraction: number?, text: string?) -> (),
	ShowMessage: (text: string) -> (),
	Flash: (color: Color3) -> (),
	PulseCrosshair: () -> (),
	Destroy: () -> (),
}
export type InventoryView = {
	SetSlots: ({ [number]: SlotData? }) -> (),
	SetVisible: (visible: boolean) -> (),
	IsVisible: () -> boolean,
	Destroy: () -> (),
}
export type CraftView = {
	SetRecipes: ({ RecipeData }) -> (),
	SetVisible: (visible: boolean) -> (),
	IsVisible: () -> boolean,
	Destroy: () -> (),
}
export type Views = {
	Hud: { Create: (playerGui: Instance) -> HudView },
	Inventory: { Create: (playerGui: Instance, slotCount: number, onSlot: (number) -> ()) -> InventoryView },
	Craft: { Create: (playerGui: Instance, onCraft: (string, number) -> ()) -> CraftView },
	ItemDisplay: { Def: (itemId: string) -> ItemDef?, Get: (itemId: string) -> Display, SortedIds: () -> { string } },
}

export type ActiveInteraction = {
	id: string,
	action: Types.InteractionAction,
	targetId: string,
	startedAt: number,
	endsAt: number,
	seenAt: number,
}
export type StateController = {
	Get: () -> Types.Snapshot?,
	GetSelfPlayer: () -> Types.PlayerView?,
	Subscribe: (listener: (Types.Snapshot) -> ()) -> () -> (),
	NewRequest: () -> Types.Req,
	DebugInject: (patch: { [string]: unknown }) -> (),
	DebugPatchSelfPlayer: (patch: { [string]: unknown }) -> (),
	IsDebug: () -> boolean,
}
export type InteractionController = {
	IsPending: (kind: string) -> boolean,
	Send: (remoteName: string, fields: { [string]: unknown }, kind: string, target: Instance?) -> string,
	SubscribeResults: (listener: (kind: string, ok: boolean, code: string) -> ()) -> (),
	GetActive: () -> ActiveInteraction?,
	GetPrompt: () -> string?,
	Begin: (action: Types.InteractionAction, targetId: string) -> (),
	Cancel: () -> (),
	Hit: () -> (),
	InteractPressed: () -> (),
	InteractReleased: () -> (),
}
export type InventoryController = {
	IsMenuOpen: () -> boolean,
	ToggleInventory: () -> (),
	ToggleCraft: () -> (),
	GetEquippedHitCooldown: () -> number,
	ActivateSlot: (slot: number) -> (),
	Craft: (recipeId: string, count: number) -> (),
}
export type HUDController = {
	ShowMessage: (text: string) -> (),
	Flash: (color: Color3) -> (),
	PulseCrosshair: () -> (),
}
export type FeedbackController = { HitConfirmed: (node: Instance) -> () }
export type MovementController = { IsCrouching: () -> boolean, GetMode: () -> "Walk" | "Sprint" | "Crouch" }
export type Controllers = {
	StateController: StateController,
	InteractionController: InteractionController,
	InventoryController: InventoryController,
	HUDController: HUDController,
	FeedbackController: FeedbackController,
	MovementController: MovementController,
}

return {}
