--!strict
-- TODO: Implementar segun docs/specs/estimulos.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.EmitNoise(_kind: string, _sourceId: string, _position: Vector3)
	return nil
end

function Service.IsProtectedFromMain(_position: Vector3): boolean
	return false
end

return Service
