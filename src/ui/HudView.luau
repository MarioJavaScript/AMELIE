--!strict
-- Vista del HUD basico: barras de vida, estamina y bateria. No conoce el estado del juego: el controlador
-- le pasa fracciones y textos ya confirmados por el servidor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local HudView = {}

export type BarName = "Health" | "Stamina" | "Battery" | "Hunger"

type Bar = { Fill: Frame, Label: TextLabel }

export type Hud = {
	Gui: ScreenGui,
	SetBar: (name: BarName, fraction: number, text: string, color: Color3) -> (),
	SetVisible: (visible: boolean) -> (),
	-- Prompt de contexto (nil lo oculta).
	SetPrompt: (text: string?) -> (),
	-- Barra de progreso de la interaccion en curso (nil la oculta).
	SetProgress: (fraction: number?, text: string?) -> (),
	ShowMessage: (text: string) -> (),
	Flash: (color: Color3) -> (),
	PulseCrosshair: () -> (),
	Destroy: () -> (),
}

local BAR_ORDER: { BarName } = { "Battery", "Stamina", "Hunger", "Health" }

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

	local colors = PresentationConfig.Colors
	local function centered(item: GuiObject, offsetY: number, size: UDim2)
		item.AnchorPoint = Vector2.new(0.5, 0.5)
		item.Position = UDim2.new(0.5, 0, 0.5, offsetY)
		item.Size = size
		item.BackgroundTransparency = 1
		item.Parent = gui
	end
	local function styleText(label: TextLabel)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 16
		label.TextColor3 = colors.HudText
		label.TextStrokeTransparency = 0.4
		label.Text = ""
	end

	local crosshair = Instance.new("Frame")
	centered(crosshair, 0, UDim2.fromOffset(settings.CrosshairSize, settings.CrosshairSize))
	crosshair.BackgroundTransparency = 0.3
	crosshair.BackgroundColor3 = colors.HudText
	crosshair.BorderSizePixel = 0

	local prompt = Instance.new("TextLabel")
	centered(prompt, settings.PromptOffsetY, UDim2.fromOffset(300, 24))
	styleText(prompt)
	prompt.Visible = false

	local progressBack = Instance.new("Frame")
	centered(
		progressBack,
		settings.PromptOffsetY + 30,
		UDim2.fromOffset(settings.ProgressWidth, settings.ProgressHeight)
	)
	progressBack.BackgroundTransparency = 0.35
	progressBack.BackgroundColor3 = colors.HudBarBack
	progressBack.BorderSizePixel = 0
	progressBack.Visible = false
	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = colors.Progress
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.Parent = progressBack
	local progressLabel = Instance.new("TextLabel")
	progressLabel.AnchorPoint = Vector2.new(0.5, 0)
	progressLabel.Position = UDim2.new(0.5, 0, 1, 2)
	progressLabel.Size = UDim2.fromOffset(settings.ProgressWidth, 18)
	progressLabel.BackgroundTransparency = 1
	styleText(progressLabel)
	progressLabel.TextSize = 13
	progressLabel.Parent = progressBack

	local message = Instance.new("TextLabel")
	centered(message, -settings.MessageOffsetY, UDim2.fromOffset(360, 24))
	styleText(message)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.Parent = gui

	local messageToken = 0
	local pulseToken = 0
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
		SetPrompt = function(text: string?)
			prompt.Visible = text ~= nil
			prompt.Text = text or ""
		end,
		SetProgress = function(fraction: number?, text: string?)
			progressBack.Visible = fraction ~= nil
			if fraction ~= nil then
				progressFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
				progressLabel.Text = text or ""
			end
		end,
		ShowMessage = function(text: string)
			messageToken += 1
			local token = messageToken
			message.Text = text
			task.delay(settings.MessageSeconds, function()
				if token == messageToken then
					message.Text = ""
				end
			end)
		end,
		Flash = function(color: Color3)
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = settings.FlashTransparency
			TweenService:Create(flash, TweenInfo.new(settings.FlashSeconds), { BackgroundTransparency = 1 }):Play()
		end,
		PulseCrosshair = function()
			pulseToken += 1
			local token = pulseToken
			crosshair.BackgroundColor3 = colors.SlotEquipped
			task.delay(settings.CrosshairPulseSeconds, function()
				if token == pulseToken then
					crosshair.BackgroundColor3 = colors.HudText
				end
			end)
		end,
		Destroy = function()
			gui:Destroy()
		end,
	}
	return hud
end

return HudView
