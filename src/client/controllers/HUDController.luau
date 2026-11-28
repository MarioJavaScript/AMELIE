--!strict
-- HUD basico: vida, estamina y bateria. Solo muestra lo que manda el servidor; las barras se suavizan
-- hacia el ultimo valor confirmado y nunca extrapolan consumo (docs/specs/jugador.md, remotes.md).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("types"))
local PresentationConfig = require(Shared:WaitForChild("config"):WaitForChild("PresentationConfig"))
local ObjectivesConfig = require(Shared:WaitForChild("config"):WaitForChild("ObjectivesConfig"))
local DebugCommands = require(script.Parent.Parent:WaitForChild("DebugCommands"))

local ClientTypes = require(script.Parent.Parent:WaitForChild("ClientTypes"))

local Controller = {}

export type Context = { [string]: unknown }

type BarState = { shown: number, target: number, max: number }

local controllers = {} :: ClientTypes.Controllers
local views = {} :: ClientTypes.Views
local remotes: { [string]: RemoteEvent } = {}
local connections: { RBXScriptConnection } = {}
local unsubscribers: { () -> () } = {}
local hud: ClientTypes.HudView? = nil

local bars: { [ClientTypes.BarName]: BarState } = {
	Health = { shown = 0, target = 0, max = 0 },
	Stamina = { shown = 0, target = 0, max = 0 },
	Battery = { shown = 0, target = 0, max = 0 },
	Hunger = { shown = 0, target = 0, max = 0 },
}
local hasData = false

local function isPlayablePhase(phase: string): boolean
	return phase == "Day" or phase == "Dusk" or phase == "Night" or phase == "Dawn"
end

local function setTarget(name: ClientTypes.BarName, value: number, max: number)
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
	setTarget("Hunger", snapshot.self.hunger, snapshot.self.maxHunger)
	hasData = true
end

local function render(view: ClientTypes.HudView, name: ClientTypes.BarName, label: string, color: Color3)
	local bar = bars[name]
	local fraction = if bar.max > 0 then bar.shown / bar.max else 0
	view.SetBar(name, fraction, string.format("%s  %d / %d", label, math.round(bar.shown), math.round(bar.max)), color)
end

local function onRender(dt: number)
	local view = hud
	if view == nil or not hasData then
		return
	end
	local alpha = 1 - math.exp(-PresentationConfig.Hud.BarSmoothing * dt)
	for _, bar in bars do
		bar.shown += (bar.target - bar.shown) * alpha
	end
	local colors = PresentationConfig.Colors
	render(view, "Health", "VIDA", colors.Health)
	render(view, "Stamina", "ESTAMINA", colors.Stamina)
	render(view, "Hunger", "HAMBRE", colors.Hunger)
	local low = bars.Battery.target <= PresentationConfig.Flashlight.LowBatteryThreshold
	render(view, "Battery", "BATERIA", if low then colors.BatteryLow else colors.Battery)

	local interaction = controllers.InteractionController
	local current = interaction.GetActive()
	if current ~= nil then
		local fraction = (Workspace:GetServerTimeNow() - current.startedAt)
			/ math.max(current.endsAt - current.startedAt, 0.001)
		local label: string = (PresentationConfig.Hud.ActionLabels :: { [string]: string })[current.action]
			or PresentationConfig.Hud.DefaultActionLabel
		if current.action == "UseItem" then
			label ..= " " .. views.ItemDisplay.Get(current.targetId).name
		end
		view.SetProgress(fraction, label)
		view.SetPrompt(nil)
	else
		view.SetProgress(nil, nil)
		view.SetPrompt(interaction.GetPrompt())
	end
end

-- API para otros controllers (mensajes de resultado, destellos, marca de golpe).
function Controller.ShowMessage(text: string)
	if hud ~= nil then
		hud.ShowMessage(text)
	end
end

function Controller.Flash(color: Color3)
	if hud ~= nil then
		hud.Flash(color)
	end
end

function Controller.PulseCrosshair()
	if hud ~= nil then
		hud.PulseCrosshair()
	end
end

function Controller.Init(context: Context)
	controllers = context.Controllers :: ClientTypes.Controllers
	views = context.Views :: ClientTypes.Views
	remotes = context.Remotes :: { [string]: RemoteEvent }
end

function Controller.Start()
	hud = views.Hud.Create(Players.LocalPlayer:WaitForChild("PlayerGui"))
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(unsubscribers, controllers.StateController.Subscribe(onSnapshot))

	-- Solo Studio: /hud <vida> <estamina> <bateria> <hambre> inyecta valores mientras no haya servidor.
	DebugCommands.Register("hud", function(args: { string })
		local state = controllers.StateController
		if state.Get() ~= nil and not state.IsDebug() then
			warn("/hud: ya hay snapshots reales del servidor")
			return
		end
		state.DebugInject({})
		local selfView = table.clone((state.Get() :: Types.Snapshot).self)
		selfView.stamina = tonumber(args[2]) or selfView.stamina
		selfView.battery = tonumber(args[3]) or selfView.battery
		selfView.hunger = tonumber(args[4]) or selfView.hunger
		state.DebugInject({ self = selfView })
		state.DebugPatchSelfPlayer({ health = tonumber(args[1]) or 100 })
	end)

	-- Solo Studio: /puente on|off pide al servidor construir o romper el puente (el servidor decide y valida).
	DebugCommands.Register(ObjectivesConfig.Bridge.DebugCommand, function(args: { string })
		if args[1] ~= "on" and args[1] ~= "off" then
			warn("Uso: /" .. ObjectivesConfig.Bridge.DebugCommand .. " on|off")
			return
		end
		local request = controllers.StateController.NewRequest()
		local payload: Types.DebugBridge =
			{ requestId = request.requestId, runId = request.runId, enabled = args[1] == "on" }
		remotes.DebugBridge:FireServer(payload)
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
