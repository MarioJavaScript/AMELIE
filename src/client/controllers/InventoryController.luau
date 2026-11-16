--!strict
-- TODO: Implementar segun docs/specs/recoleccion-inventario.md.
local Controller = {}

export type Context = { [string]: unknown }

function Controller.Init(_context: Context) end

function Controller.Start() end

function Controller.Stop() end

return Controller
