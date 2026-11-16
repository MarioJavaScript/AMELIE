--!strict
-- Presets de Lighting, Atmosphere y ColorCorrection por fase y noche (docs/specs/ciclo-partida.md).
-- La fase y la noche salen del snapshot del servidor; los valores viven en PresentationConfig.
-- Requiere Lighting.Technology = Future, que solo se puede fijar en Studio (no por script).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local Config = Shared:WaitForChild("config")
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))
local DebugCommands = require(script.Parent.Parent:WaitForChild("DebugCommands"))

local Controller = {}

export type Context = { [string]: unknown }

type Values = { [string]: { [string]: any } }

local CLOCK_HOURS = 24
local DEBUG_PHASES: { Types.Phase } = { "Day", "Dusk", "Night", "Dawn" }
local PHASE_ALIASES: { [string]: Types.Phase } = {
	dia = "Day",
	atardecer = "Dusk",
	noche = "Night",
	amanecer = "Dawn",
}

local controllers: { [string]: any } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}

local instances: { [string]: Instance } = {}
local currentKey: string? = nil
local fromValues: Values = {}
local toValues: Values = {}
local elapsed = 0
local duration = 0
local transitioning = false

local serverPhase: Types.Phase = "Lobby"
local serverNight = 1
local debugPhase: Types.Phase? = nil
local debugNight = 1
local technologyWarned = false

local function ensureInstances()
	instances.Lighting = Lighting
	local atmosphere = instances.Atmosphere
	if atmosphere == nil or atmosphere.Parent ~= Lighting then
		local found = Lighting:FindFirstChildOfClass("Atmosphere")
		if found == nil then
			found = Instance.new("Atmosphere")
			found.Parent = Lighting
		end
		instances.Atmosphere = found
	end
	local correction = instances.ColorCorrection
	if correction == nil or correction.Parent ~= Lighting then
		local found = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if found == nil then
			found = Instance.new("ColorCorrectionEffect")
			found.Parent = Lighting
		end
		instances.ColorCorrection = found
	end
end

local function warnTechnology()
	if technologyWarned then
		return
	end
	technologyWarned = true
	local required = PresentationConfig.Lighting.RequiredTechnology
	if Lighting.Technology.Name ~= required then
		warn(
			"EnvironmentController: Lighting.Technology es "
				.. Lighting.Technology.Name
				.. " y debe ser "
				.. required
				.. ". Cambialo en Studio (Lighting > Technology); no se puede fijar por script."
		)
	end
end

-- Preset base mezclado con el override de la noche (solo la fase Night usa NightOverrides).
local function resolve(presetName: string, night: number): Values
	local presets = PresentationConfig.LightingPresets :: any
	local result: Values = {}
	for group, props in presets[presetName] do
		if typeof(props) == "table" then
			result[group] = table.clone(props)
		end
	end
	if presetName == "Night" then
		local overrides = PresentationConfig.NightOverrides :: any
		local override = overrides[math.clamp(night, 1, #overrides)]
		for group, props in override do
			local target = result[group]
			if target == nil then
				target = {}
				result[group] = target
			end
			for prop, value in props do
				target[prop] = value
			end
		end
	end
	return result
end

local function readCurrent(target: Values): Values
	local snapshot: Values = {}
	for group, props in target do
		local instance = instances[group] :: any
		local values: { [string]: any } = {}
		for prop in props do
			values[prop] = instance[prop]
		end
		snapshot[group] = values
	end
	return snapshot
end

local function lerpValue(prop: string, from: any, to: any, alpha: number): any
	if prop == "ClockTime" then
		-- La hora avanza hacia adelante (atardecer 18.3 -> noche 0 pasa por 24), por el camino corto.
		local delta = (to - from) % CLOCK_HOURS
		if delta > CLOCK_HOURS / 2 then
			delta -= CLOCK_HOURS
		end
		return (from + delta * alpha) % CLOCK_HOURS
	end
	if typeof(from) == "number" then
		return from + (to - from) * alpha
	end
	if typeof(from) == "Color3" then
		return (from :: Color3):Lerp(to :: Color3, alpha)
	end
	return to
end

local function apply(from: Values, to: Values, alpha: number)
	for group, props in to do
		local instance = instances[group] :: any
		local source = from[group]
		for prop, target in props do
			local start = if source ~= nil and source[prop] ~= nil then source[prop] else target
			instance[prop] = lerpValue(prop, start, target, alpha)
		end
	end
end

local function setTarget(presetName: string, night: number, instant: boolean)
	local key = if presetName == "Night" then presetName .. tostring(night) else presetName
	if key == currentKey then
		return
	end
	currentKey = key
	ensureInstances()
	warnTechnology()

	local presets = PresentationConfig.LightingPresets :: any
	toValues = resolve(presetName, night)
	fromValues = readCurrent(toValues)
	elapsed = 0
	duration = if instant then 0 else presets[presetName].TransitionSeconds
	if duration <= 0 then
		apply(fromValues, toValues, 1)
		transitioning = false
	else
		transitioning = true
	end
end

local function currentPhase(): (Types.Phase, number)
	if debugPhase ~= nil then
		return debugPhase, debugNight
	end
	return serverPhase, serverNight
end

local function refresh(instant: boolean)
	local phase, night = currentPhase()
	local mapping = PresentationConfig.Lighting.PhasePreset :: any
	setTarget(mapping[phase] or "Day", night, instant)
end

local function onSnapshot(snapshot: Types.Snapshot)
	serverPhase = snapshot.phase
	serverNight = snapshot.night
	refresh(false)
end

local function onRender(dt: number)
	if not transitioning then
		return
	end
	elapsed += dt
	local alpha = math.clamp(elapsed / duration, 0, 1)
	-- Smoothstep para que el cambio arranque y termine suave.
	apply(fromValues, toValues, alpha * alpha * (3 - 2 * alpha))
	if alpha >= 1 then
		transitioning = false
	end
end

-- Solo para pruebas en Studio: fuerza fase y noche ignorando el servidor. phase nil vuelve al servidor.
function Controller.SetDebugPhase(phase: Types.Phase?, night: number?)
	if not RunService:IsStudio() then
		return
	end
	debugPhase = phase
	if night ~= nil then
		debugNight = math.clamp(math.floor(night), 1, #(PresentationConfig.NightOverrides :: any))
	end
	local phaseName, nightNumber = currentPhase()
	print(
		string.format(
			"EnvironmentController debug: fase %s, noche %d%s",
			phaseName,
			nightNumber,
			if debugPhase == nil then " (servidor)" else ""
		)
	)
	refresh(false)
end

local function cyclePhase()
	local index = if debugPhase == nil then 0 else table.find(DEBUG_PHASES, debugPhase) or 0
	Controller.SetDebugPhase(DEBUG_PHASES[index + 1], nil)
end

local function cycleNight()
	local count = #(PresentationConfig.NightOverrides :: any)
	Controller.SetDebugPhase(debugPhase or "Night", debugNight % count + 1)
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: { [string]: any }
end

function Controller.Start()
	-- Estado inicial (Lobby) sin transicion hasta que llegue el primer snapshot.
	refresh(true)
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))

	if RunService:IsStudio() then
		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
				if processed then
					return
				end
				if input.KeyCode == PresentationConfig.InputBindings.DebugCyclePhase then
					cyclePhase()
				elseif input.KeyCode == PresentationConfig.InputBindings.DebugCycleNight then
					cycleNight()
				end
			end)
		)
		DebugCommands.Register("fase", function(args: { string })
			local name = string.lower(args[1] or "")
			local night = tonumber(args[2])
			if name == "auto" then
				Controller.SetDebugPhase(nil, night)
			elseif PHASE_ALIASES[name] ~= nil then
				Controller.SetDebugPhase(PHASE_ALIASES[name], night)
			else
				warn("Uso: /fase <auto|dia|atardecer|noche|amanecer> [noche 1-5]")
			end
		end)
	end
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, unsubscribe in unsubscribers do
		unsubscribe()
	end
	table.clear(unsubscribers)
end

return Controller
