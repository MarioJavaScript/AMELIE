--!strict
-- Sesion de partida. Por ahora solo la run de desarrollo (docs/specs/ciclo-partida.md define el ciclo completo:
-- lobby, roster congelado, resultado). La run de desarrollo solo existe en Studio: arranca al entrar el primer
-- jugador y termina al salir el ultimo, sin lobby ni roster.
-- TODO: lobby, roster congelado, fases y resultado segun ciclo-partida.md.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Service = {}

export type Context = { [string]: unknown }

local connections: { RBXScriptConnection } = {}
local currentRunId: string? = nil
local world: any
local services: any

function Service.Init(context: Context)
	services = context.Services
	world = services.WorldService
end

-- Crea una run con un runId nuevo (ASCII alfanumerico y guion, <= 64 bytes: ver remotes.md) y lo devuelve.
function Service.BeginRun(): string
	-- Contenido invalido: la run no arranca (el error del servicio explica el path) y no se toca ningun estado.
	local problems = services.PlayerService.ValidateHeld()
	local okResources, resourcesError = pcall(services.ResourceService.Validate)
	if not okResources or #problems > 0 then
		local parts = {}
		if not okResources then
			table.insert(parts, tostring(resourcesError))
		end
		if #problems > 0 then
			table.insert(parts, "PlayerService: la run no puede arrancar:\n - " .. table.concat(problems, "\n - "))
		end
		error(table.concat(parts, "\n"), 0)
	end
	local runId = "dev_" .. HttpService:GenerateGUID(false)
	currentRunId = runId
	services.InteractionService.CancelAll("Cancelled")
	world.BeginRun(runId)
	services.InventoryService.ResetForRun()
	services.PlayerService.BeginRun(runId)
	services.ResourceService.BeginRun(runId)
	for _, player in Players:GetPlayers() do
		services.InventoryService.GiveInitialKit(player.UserId)
	end
	return runId
end

function Service.EndRun(_outcome: string?)
	services.InteractionService.CancelAll("Cancelled")
	services.PlayerService.EndRun()
	currentRunId = nil
end

function Service.GetRunId(): string?
	return currentRunId
end

local function onJoin(player: Player)
	if currentRunId == nil then
		Service.BeginRun()
	end
	services.InventoryService.GiveInitialKit(player.UserId)
end

function Service.Start()
	if not RunService:IsStudio() then
		return
	end
	table.insert(connections, Players.PlayerAdded:Connect(onJoin))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function()
			-- PlayerRemoving se emite antes de salir de la lista: el ultimo jugador deja 1.
			if #Players:GetPlayers() <= 1 then
				Service.EndRun("DevClosed")
			end
		end)
	)
	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
end

function Service.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	currentRunId = nil
end

return Service
