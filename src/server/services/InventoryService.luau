--!strict
-- TODO: Implementar segun docs/specs/recoleccion-inventario.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.GetSnapshot(_player: Player): { [string]: unknown }?
	return nil
end

function Service.TryApplyDelta(_player: Player, _delta: { [string]: number }): boolean
	return false
end

return Service
