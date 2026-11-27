--!strict
-- Mundo: estado del puente (docs/specs/mapa.md 2.2). El resto sigue pendiente segun docs/specs/arquitectura.md.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Service = {}

export type Context = { [string]: unknown }

local bridge: any

local function find(root: Instance, path: string): Instance?
	local current: Instance? = root
	for _, name in string.split(path, "/") do
		current = if current then current:FindFirstChild(name) else nil
	end
	return current
end

function Service.Init(context: Context)
	bridge = ((context.Configs :: any).ObjectivesConfig).Bridge
end

function Service.Start() end

function Service.Stop() end

function Service.ValidateStudio(): boolean
	return RunService:IsStudio()
end

-- Idempotente: deja el puente construido (clona la variante) o roto (destruye Construido). Devuelve false sin
-- tocar nada si falta el folder del puente o, al construir, la variante.
function Service.setBridgeBuilt(built: boolean): boolean
	local folder = find(Workspace, bridge.MapPath)
	if not folder then
		warn("WorldService: falta Workspace/" .. bridge.MapPath)
		return false
	end
	local existing = folder:FindFirstChild(bridge.BuiltChildName)
	if built then
		if existing then
			folder:SetAttribute(bridge.BuiltAttribute, true)
			return true
		end
		local source = find(ServerStorage, bridge.BuiltVariantPath)
		if not source then
			warn("WorldService: falta ServerStorage/" .. bridge.BuiltVariantPath .. "; no se crea nada")
			return false
		end
		local clone = source:Clone()
		clone.Name = bridge.BuiltChildName
		clone.Parent = folder
	elseif existing then
		existing:Destroy()
	end
	folder:SetAttribute(bridge.BuiltAttribute, built)
	return true
end

function Service.IsBridgeBuilt(): boolean
	local folder = find(Workspace, bridge.MapPath)
	return folder ~= nil and folder:GetAttribute(bridge.BuiltAttribute) == true
end

-- Cada run empieza con el puente roto.
function Service.BeginRun(_runId: string)
	Service.setBridgeBuilt(false)
end

function Service.Resolve(_entityId: string): Instance?
	return nil
end

return Service
