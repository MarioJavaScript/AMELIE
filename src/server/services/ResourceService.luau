--!strict
-- TODO: Implementar segun docs/specs/recoleccion-inventario.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.Hit(_player: Player, _targetId: string): boolean
	return false
end

function Service.ResetForRun(_runId: string)
	return nil
end

return Service
