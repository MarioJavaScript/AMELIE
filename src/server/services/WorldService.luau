--!strict
-- TODO: Implementar segun docs/specs/arquitectura.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.ValidateStudio(): boolean
	return false
end

function Service.BeginRun(_runId: string)
	return nil
end

function Service.Resolve(_entityId: string): Instance?
	return nil
end

return Service
