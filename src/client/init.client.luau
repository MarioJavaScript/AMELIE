--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared", 10)
if not shared then
	warn("Shared no disponible")
	return
end
local remotesModule = require(shared:WaitForChild("Remotes", 10))
local remotes = remotesModule.GetClient(10)
if not remotes then
	warn("Remotes no disponibles")
	return
end
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local ui = playerGui:WaitForChild("UI", 10)
if not ui then
	warn("UI no disponible")
	return
end
local views = require(ui:WaitForChild("Views"))
local controllers: { [string]: unknown } = {}
local context: { [string]: unknown } = { Remotes = remotes, Controllers = controllers, Views = views }
local folder = script:WaitForChild("controllers")
for _, name in
	{
		"StateController",
		"InputController",
		"FirstPersonController",
		"MovementController",
		"FlashlightController",
		"InteractionController",
		"InventoryController",
		"BuildPreviewController",
		"EnvironmentController",
		"SoundController",
		"HUDController",
		"SpectatorController",
	}
do
	controllers[name] = require(folder:WaitForChild(name))
end
for _, name in
	{
		"StateController",
		"InputController",
		"FirstPersonController",
		"MovementController",
		"FlashlightController",
		"InteractionController",
		"InventoryController",
		"BuildPreviewController",
		"EnvironmentController",
		"SoundController",
		"HUDController",
		"SpectatorController",
	}
do
	(controllers[name] :: any).Init(context)
end
for _, name in
	{
		"StateController",
		"InputController",
		"FirstPersonController",
		"MovementController",
		"FlashlightController",
		"InteractionController",
		"InventoryController",
		"BuildPreviewController",
		"EnvironmentController",
		"SoundController",
		"HUDController",
		"SpectatorController",
	}
do
	(controllers[name] :: any).Start()
end
remotes.RequestSnapshot:FireServer({ requestId = "bootstrap", runId = "" })
