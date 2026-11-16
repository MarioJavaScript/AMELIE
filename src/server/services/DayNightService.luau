--!strict
-- TODO: Implementar segun docs/specs/ciclo-partida.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.BeginRun(_runId: string)
	return nil
end

function Service.GetPhase(): string
	return "Lobby"
end

return Service
