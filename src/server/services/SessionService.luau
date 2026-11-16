--!strict
-- TODO: Implementar segun docs/specs/ciclo-partida.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.BeginRun() end

function Service.EndRun(_outcome: string)
	return nil
end

function Service.GetRunId(): string?
	return nil
end

return Service
