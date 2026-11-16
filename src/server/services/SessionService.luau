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

function Service.Init(_context: Context) end

-- Crea una run con un runId nuevo (ASCII alfanumerico y guion, <= 64 bytes: ver remotes.md) y lo devuelve.
function Service.BeginRun(): string
	local runId = "dev_" .. HttpService:GenerateGUID(false)
	currentRunId = runId
	return runId
end

function Service.EndRun(_outcome: string?)
	currentRunId = nil
end

function Service.GetRunId(): string?
	return currentRunId
end

local function ensureDevRun()
	if currentRunId == nil then
		Service.BeginRun()
	end
end

function Service.Start()
	if not RunService:IsStudio() then
		return
	end
	table.insert(connections, Players.PlayerAdded:Connect(ensureDevRun))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function()
			-- PlayerRemoving se emite antes de salir de la lista: el ultimo jugador deja 1.
			if #Players:GetPlayers() <= 1 then
				Service.EndRun("DevClosed")
			end
		end)
	)
	if #Players:GetPlayers() > 0 then
		ensureDevRun()
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
