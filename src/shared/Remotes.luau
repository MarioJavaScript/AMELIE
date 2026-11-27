--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"RequestSnapshot",
	"SetReady",
	"SetMovementMode",
	"SetFlashlight",
	"SetFlashlightAim",
	"EquipTool",
	"HitResource",
	"CraftItem",
	"PlaceStructure",
	"DropObjective",
	"BeginInteraction",
	"CancelInteraction",
	"Shout",
	"DebugBridge",
	"StateSnapshot",
	"ActionResult",
	"InteractionState",
	"Feedback",
}

export type RemoteMap = { [string]: RemoteEvent }
local Remotes = {}

function Remotes.InitServer(): RemoteMap
	assert(RunService:IsServer(), "InitServer solo en servidor")
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	assert(folder:IsA("Folder"), "ReplicatedStorage/Remotes debe ser Folder")
	local result: RemoteMap = {}
	for _, name in NAMES do
		local event = folder:FindFirstChild(name)
		if event == nil then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
		assert(event:IsA("RemoteEvent"), name .. " debe ser RemoteEvent")
		result[name] = event
	end
	return result
end

function Remotes.GetClient(timeoutSeconds: number): RemoteMap?
	assert(RunService:IsClient(), "GetClient solo en cliente")
	local folder = ReplicatedStorage:WaitForChild("Remotes", timeoutSeconds)
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local result: RemoteMap = {}
	for _, name in NAMES do
		local event = folder:WaitForChild(name, timeoutSeconds)
		if not event or not event:IsA("RemoteEvent") then
			return nil
		end
		result[name] = event
	end
	return result
end

return Remotes
