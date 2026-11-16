--!strict
-- TODO: Implementar segun docs/specs/jugador.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.GetValidatedPosition(_player: Player): Vector3?
	return nil
end

function Service.ApplyDamage(_player: Player, _amount: number)
	return nil
end

function Service.RespawnAtDawn(_player: Player)
	return nil
end

return Service
