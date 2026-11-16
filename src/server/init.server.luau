--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local configFolder = shared:WaitForChild("config")
local configs: { [string]: unknown } = {}
for _, name in
	{
		"SessionConfig",
		"PlayerConfig",
		"ItemsConfig",
		"RecipesConfig",
		"ResourcesConfig",
		"StructuresConfig",
		"NightsConfig",
		"ObjectivesConfig",
		"StimuliConfig",
		"NetworkConfig",
		"InteractionConfig",
		"WorldConfig",
		"PresentationConfig",
		"DataConfig",
		"EnemiesConfig",
	}
do
	configs[name] = require(configFolder:WaitForChild(name))
end
local remotes = require(shared:WaitForChild("Remotes")).InitServer()
local services: { [string]: unknown } = {}
local context: { [string]: unknown } = { Configs = configs, Remotes = remotes, Services = services }
local folder = script:WaitForChild("services")
for _, name in
	{
		"WorldService",
		"DataService",
		"InventoryService",
		"StimulusService",
		"PlayerService",
		"ResourceService",
		"BuildingService",
		"ObjectiveService",
		"InteractionService",
		"ReplicationService",
		"DayNightService",
		"AIService",
		"SessionService",
	}
do
	services[name] = require(folder:WaitForChild(name))
end
for _, name in
	{
		"WorldService",
		"DataService",
		"InventoryService",
		"StimulusService",
		"PlayerService",
		"ResourceService",
		"BuildingService",
		"ObjectiveService",
		"InteractionService",
		"ReplicationService",
		"DayNightService",
		"AIService",
		"SessionService",
	}
do
	(services[name] :: any).Init(context)
end
for _, name in
	{
		"WorldService",
		"DataService",
		"InventoryService",
		"StimulusService",
		"PlayerService",
		"ResourceService",
		"BuildingService",
		"ObjectiveService",
		"InteractionService",
		"ReplicationService",
		"DayNightService",
		"AIService",
		"SessionService",
	}
do
	(services[name] :: any).Start()
end
