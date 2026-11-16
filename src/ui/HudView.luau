--!strict
-- Vista del HUD basico: barras de vida, estamina y bateria. No conoce el estado del juego: el controlador
-- le pasa fracciones y textos ya confirmados por el servidor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local HudView = {}

export type BarName = "Health" | "Stamina" | "Battery"

type Bar = { Fill: Frame, Label: TextLabel }

export type Hud = {
	Gui: ScreenGui,
	SetBar: (name: BarName, fraction: number, text: string, color: Color3) -> (),
	SetVisible: (visible: boolean) -> (),
	Destroy: () -> (),
}

local BAR_ORDER: { BarName } = { "Battery", "Stamina", "Health" }

local function createBar(parent: Frame, name: BarName, index: number): Bar
	local settings = PresentationConfig.Hud
	local back = Instance.new("Frame")
	back.Name = name
	back.Size = UDim2.fromOffset(settings.BarWidth, settings.BarHeight)
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position = UDim2.new(0, 0, 1, -(index - 1) * (settings.BarHeight + settings.BarGap))
	back.BackgroundColor3 = PresentationConfig.Colors.HudBarBack
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = settings.BarHeight - 3
	label.TextColor3 = PresentationConfig.Colors.HudText
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = back

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.Parent = label

	return { Fill = fill, Label = label }
end

function HudView.Create(playerGui: Instance): Hud
	local settings = PresentationConfig.Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false

	local container = Instance.new("Frame")
	container.Name = "Bars"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, settings.Margin, 1, -settings.Margin)
	container.Size = UDim2.fromOffset(settings.BarWidth, #BAR_ORDER * (settings.BarHeight + settings.BarGap))
	container.BackgroundTransparency = 1
	container.Parent = gui

	local bars: { [string]: Bar } = {}
	for index, name in BAR_ORDER do
		bars[name] = createBar(container, name, index)
	end
	gui.Parent = playerGui

	local hud: Hud = {
		Gui = gui,
		SetBar = function(name: BarName, fraction: number, text: string, color: Color3)
			local bar = bars[name]
			bar.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			bar.Fill.BackgroundColor3 = color
			bar.Label.Text = text
		end,
		SetVisible = function(visible: boolean)
			gui.Enabled = visible
		end,
		Destroy = function()
			gui:Destroy()
		end,
	}
	return hud
end

return HudView
