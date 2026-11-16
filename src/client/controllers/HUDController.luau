--!strict
-- HUD basico: vida, estamina y bateria. Solo muestra lo que manda el servidor; las barras se suavizan
-- hacia el ultimo valor confirmado y nunca extrapolan consumo (docs/specs/jugador.md, remotes.md).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local PresentationConfig = require(Shared:WaitForChild("config"):WaitForChild("PresentationConfig"))
local DebugCommands = require(script.Parent.Parent:WaitForChild("DebugCommands"))

local Controller = {}

export type Context = { [string]: unknown }

type BarState = { shown: number, target: number, max: number }

local controllers: { [string]: any } = {}
local views: { [string]: any } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}
local hud: any = nil

local bars: { [string]: BarState } = {
	Health = { shown = 0, target = 0, max = 0 },
	Stamina = { shown = 0, target = 0, max = 0 },
	Battery = { shown = 0, target = 0, max = 0 },
}
local hasData = false

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

local function setTarget(name: string, value: number, max: number)
	local bar = bars[name]
	if not hasData then
		-- Primer dato: sin animacion desde cero.
		bar.shown = value
	end
	bar.target = value
	bar.max = max
end

local function onSnapshot(snapshot: Types.Snapshot)
	local view = controllers.StateController.GetSelfPlayer()
	local visible = isPlayablePhase(snapshot.phase) and (view == nil or view.life ~= "Spectating")
	if hud ~= nil then
		hud.SetVisible(visible)
	end
	if view ~= nil then
		setTarget("Health", view.health, view.maxHealth)
	else
		setTarget("Health", 0, 0)
	end
	setTarget("Stamina", snapshot.self.stamina, snapshot.self.maxStamina)
	setTarget("Battery", snapshot.self.battery, snapshot.self.maxBattery)
	hasData = true
end

local function render(name: string, label: string, color: Color3)
	local bar = bars[name]
	local fraction = if bar.max > 0 then bar.shown / bar.max else 0
	hud.SetBar(name, fraction, string.format("%s  %d / %d", label, math.round(bar.shown), math.round(bar.max)), color)
end

local function onRender(dt: number)
	if hud == nil or not hasData then
		return
	end
	local alpha = 1 - math.exp(-PresentationConfig.Hud.BarSmoothing * dt)
	for _, bar in bars do
		bar.shown += (bar.target - bar.shown) * alpha
	end
	local colors = PresentationConfig.Colors
	render("Health", "VIDA", colors.Health)
	render("Stamina", "ESTAMINA", colors.Stamina)
	local low = bars.Battery.target <= PresentationConfig.Flashlight.LowBatteryThreshold
	render("Battery", "BATERIA", if low then colors.BatteryLow else colors.Battery)
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: { [string]: any }
	views = context.Views :: { [string]: any }
end

function Controller.Start()
	hud = views.Hud.Create(Players.LocalPlayer:WaitForChild("PlayerGui"))
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))

	-- Solo Studio: /hud <vida> <estamina> <bateria> inyecta valores mientras no haya servidor.
	DebugCommands.Register("hud", function(args: { string })
		local state = controllers.StateController
		if state.Get() ~= nil and not state.IsDebug() then
			warn("/hud: ya hay snapshots reales del servidor")
			return
		end
		state.DebugInject({})
		local selfView = table.clone((state.Get() :: Types.Snapshot).self) :: any
		selfView.stamina = tonumber(args[2]) or selfView.stamina
		selfView.battery = tonumber(args[3]) or selfView.battery
		state.DebugInject({ self = selfView })
		state.DebugPatchSelfPlayer({ health = tonumber(args[1]) or 100 })
	end)
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
	if hud ~= nil then
		hud.Destroy()
		hud = nil
	end
end

return Controller
