--!strict
-- TODO: Implementar segun docs/specs/remotes.md.
local Service = {}

export type Context = { [string]: unknown }

function Service.Init(_context: Context) end

function Service.Start() end

function Service.Stop() end

function Service.PublishSnapshot(_player: Player)
	return nil
end

function Service.BindRemotes() end

return Service
