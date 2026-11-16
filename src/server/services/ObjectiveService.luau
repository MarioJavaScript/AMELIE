--!strict
-- TODO: Implementar segun docs/specs/objetivos.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.GetProgress(): number
	return 0
end

function Service.ApplyRadioHit(_enemyId: string)
	return nil
end

function Service.ResetForRun(_runId: string)
	return nil
end

return Service
