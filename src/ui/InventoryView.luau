--!strict
-- Vista del inventario: rejilla de slots con icono greybox, nombre, cantidad y slot equipado resaltado.
-- Dibuja solo lo que le pasa el controlador (snapshot del servidor); un clic llama a onSlot(slot).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local InventoryView = {}

export type SlotData = {
	name: string,
	count: number,
	color: Color3,
	letters: string,
	equipped: boolean,
	hotkey: string?,
}

export type Inventory = {
	Gui: ScreenGui,
	SetSlots: (slots: { [number]: SlotData? }) -> (),
	SetVisible: (visible: boolean) -> (),
	IsVisible: () -> boolean,
	Destroy: () -> (),
}

type SlotUi = {
	Button: TextButton,
	Stroke: UIStroke,
	Icon: Frame,
	Letters: TextLabel,
	Name: TextLabel,
	Count: TextLabel,
	Hotkey: TextLabel,
	Tag: TextLabel,
}

local function newLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number, align: Enum.TextXAlignment)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = PresentationConfig.Colors.HudText
	label.TextXAlignment = align
	label.TextStrokeTransparency = 0.6
	label.Text = ""
	label.Parent = parent
	return label
end

local function createSlot(parent: Frame, index: number, onSlot: (number) -> ()): SlotUi
	local layout = PresentationConfig.Inventory
	local colors = PresentationConfig.Colors
	local column = (index - 1) % layout.Columns
	local row = (index - 1) // layout.Columns
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = UDim2.fromOffset(layout.SlotSize, layout.SlotSize)
	button.Position = UDim2.fromOffset(
		layout.Padding + column * (layout.SlotSize + layout.SlotGap),
		layout.Padding + 28 + row * (layout.SlotSize + layout.SlotGap)
	)
	button.BackgroundColor3 = colors.Slot
	button.BorderSizePixel = 0
	button.Parent = parent
	button.Activated:Connect(function()
		onSlot(index)
	end)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = colors.SlotEquipped
	stroke.Enabled = false
	stroke.Parent = button

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Size = UDim2.fromOffset(layout.SlotSize * 0.5, layout.SlotSize * 0.5)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.BorderSizePixel = 0
	icon.Parent = button
	local letters = newLabel(icon, UDim2.fromScale(1, 1), UDim2.new(), 18, Enum.TextXAlignment.Center)
	letters.Font = Enum.Font.GothamBold

	local full = UDim2.new(1, -6, 0, 14)
	local name = newLabel(button, full, UDim2.new(0, 3, 1, -18), 11, Enum.TextXAlignment.Center)
	local count = newLabel(button, UDim2.new(0.5, -4, 0, 14), UDim2.new(0.5, 0, 0, 2), 13, Enum.TextXAlignment.Right)
	local hotkey = newLabel(button, UDim2.new(0.5, -4, 0, 14), UDim2.fromOffset(4, 2), 11, Enum.TextXAlignment.Left)
	hotkey.TextColor3 = colors.TextDim
	local tag = newLabel(button, UDim2.new(1, 0, 0, 12), UDim2.new(0, 0, 1, -30), 9, Enum.TextXAlignment.Center)
	tag.TextColor3 = colors.SlotEquipped
	return {
		Button = button,
		Stroke = stroke,
		Icon = icon,
		Letters = letters,
		Name = name,
		Count = count,
		Hotkey = hotkey,
		Tag = tag,
	}
end

function InventoryView.Create(playerGui: Instance, slotCount: number, onSlot: (number) -> ()): Inventory
	local layout = PresentationConfig.Inventory
	local colors = PresentationConfig.Colors
	local rows = math.ceil(slotCount / layout.Columns)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Inventory"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false

	-- Un boton Modal visible libera el cursor mientras el menu esta abierto (primera persona bloquea el raton).
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.Modal = true
	modal.Text = ""
	modal.BackgroundTransparency = 1
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(
		layout.Padding * 2 + layout.Columns * layout.SlotSize + (layout.Columns - 1) * layout.SlotGap,
		layout.Padding * 2 + 28 + rows * layout.SlotSize + (rows - 1) * layout.SlotGap
	)
	panel.BackgroundColor3 = colors.Panel
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local title = newLabel(
		panel,
		UDim2.new(1, -layout.Padding * 2, 0, 24),
		UDim2.fromOffset(layout.Padding, 10),
		16,
		Enum.TextXAlignment.Left
	)
	title.Font = Enum.Font.GothamBold
	title.Text = layout.Title

	local slotUis: { SlotUi } = {}
	for index = 1, slotCount do
		slotUis[index] = createSlot(panel, index, onSlot)
	end
	gui.Parent = playerGui

	return {
		Gui = gui,
		SetSlots = function(slots: { [number]: SlotData? })
			for index, ui in slotUis do
				local data = slots[index]
				ui.Icon.Visible = data ~= nil
				ui.Name.Visible = data ~= nil
				ui.Count.Visible = data ~= nil
				ui.Stroke.Enabled = data ~= nil and data.equipped
				ui.Hotkey.Text = if data ~= nil and data.hotkey ~= nil then data.hotkey else ""
				ui.Tag.Text = if data ~= nil and data.equipped then layout.EquippedLabel else ""
				if data ~= nil then
					ui.Icon.BackgroundColor3 = data.color
					ui.Letters.Text = data.letters
					ui.Name.Text = data.name
					ui.Count.Text = if data.count > 1 then tostring(data.count) else ""
				end
			end
		end,
		SetVisible = function(visible: boolean)
			gui.Enabled = visible
		end,
		IsVisible = function(): boolean
			return gui.Enabled
		end,
		Destroy = function()
			gui:Destroy()
		end,
	}
end

return InventoryView
