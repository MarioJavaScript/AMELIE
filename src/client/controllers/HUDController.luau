--!strict
-- TODO: Implementar segun docs/specs/jugador.md.
local Controller = {}

export type Context = { [string]: unknown }

function Controller.Init(_context: Context) end

function Controller.Start() end

function Controller.Stop() end

return Controller
