--!strict
-- TODO: Implementar segun docs/specs/construccion.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.Place(_player: Player, _placement: unknown): boolean
	return false
end

function Service.Repair(_player: Player, _structureId: string): boolean
	return false
end

return Service
