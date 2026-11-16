--!strict
-- Registro de vistas de UI (docs/specs/arquitectura.md). Cada vista es un ModuleScript hermano.
return {
	Hud = require(script.Parent:WaitForChild("HudView")),
}
