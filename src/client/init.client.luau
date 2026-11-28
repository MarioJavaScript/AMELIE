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
type Module = { Init: ({ [string]: unknown }) -> (), Start: () -> () }
local controllers: { [string]: Module } = {}
local context: { [string]: unknown } = { Remotes = remotes, Controllers = controllers, Views = views }
local folder = script:WaitForChild("controllers")
local order = {
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
	"FeedbackController",
	"HUDController",
	"SpectatorController",
}
for _, name in order do
	-- require devuelve el tipo del modulo; se estrecha al contrato comun Init/Start.
	controllers[name] = (require(folder:WaitForChild(name)) :: unknown) :: Module
end
for _, name in order do
	controllers[name].Init(context)
end
for _, name in order do
	controllers[name].Start()
end
remotes.RequestSnapshot:FireServer({ requestId = "bootstrap", runId = "" })
