--!strict
-- Entrada de gameplay (recoleccion, interaccion, inventario). Solo traduce teclas a llamadas de los controllers;
-- cada accion se valida y se decide en el servidor. Teclas en PresentationConfig.InputBindings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))

local Controller = {}

export type Context = { [string]: unknown }

local controllers = {} :: ClientTypes.Controllers
local connections: { RBXScriptConnection } = {}
local hitHeld = false

local function menuOpen(): boolean
	return controllers.InventoryController.IsMenuOpen()
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local bindings = PresentationConfig.InputBindings
	if input.UserInputType == bindings.Hit then
		hitHeld = true
	elseif input.KeyCode == bindings.Interact then
		if not menuOpen() then
			controllers.InteractionController.InteractPressed()
		end
	elseif input.KeyCode == bindings.Inventory then
		controllers.InventoryController.ToggleInventory()
	elseif input.KeyCode == bindings.Craft then
		controllers.InventoryController.ToggleCraft()
	else
		local slot = table.find(bindings.Hotbar, input.KeyCode)
		if slot ~= nil then
			controllers.InventoryController.ActivateSlot(slot)
		end
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	local bindings = PresentationConfig.InputBindings
	if input.UserInputType == bindings.Hit then
		hitHeld = false
	elseif input.KeyCode == bindings.Interact then
		controllers.InteractionController.InteractReleased()
	end
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
end

function Controller.Start()
	-- Sin Backpack de Roblox (docs/specs/remotes.md, autoridad fisica) y sin lista de jugadores: Tab es del inventario.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			hitHeld = false
			controllers.InteractionController.InteractReleased()
		end)
	)
	-- Mantener el clic repite el golpe; el cooldown lo aplica InteractionController.Hit (y el servidor).
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			if hitHeld and not menuOpen() then
				controllers.InteractionController.Hit()
			end
		end)
	)
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	hitHeld = false
end

return Controller
