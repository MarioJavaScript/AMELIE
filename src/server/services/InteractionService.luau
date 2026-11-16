--!strict
-- TODO: Implementar segun docs/specs/remotes.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.Begin(_player: Player, _action: string, _targetId: string): string?
	return nil
end

function Service.Cancel(_player: Player, _interactionId: string)
	return nil
end

return Service
