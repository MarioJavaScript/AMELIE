--!strict
-- TODO: Implementar segun docs/specs/datos.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.LoadProfile(_userId: number): boolean
	return false
end

function Service.RecordRunStarted(_userId: number, _runId: string)
	return nil
end

function Service.RequestFlush(_userId: number, _reason: string)
	return nil
end

return Service
