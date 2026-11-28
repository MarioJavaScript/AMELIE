--!strict
-- Vista del menu de crafteo rapido: una fila por receta con ingredientes (tengo/necesito) y botones por lote.
-- Solo dibuja los datos que le pasa el controlador; los botones llaman a onCraft(recipeId, count).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local CraftView = {}

export type Input = { name: string, have: number, need: number }
export type RecipeData = {
	recipeId: string,
	outputName: string,
	outputCount: number,
	color: Color3,
	letters: string,
	inputs: { Input },
	-- Lote -> true si el inventario actual alcanza para ese lote.
	canCraft: { [number]: boolean },
}

export type Craft = {
	Gui: ScreenGui,
	SetRecipes: (recipes: { RecipeData }) -> (),
	SetVisible: (visible: boolean) -> (),
	IsVisible: () -> boolean,
	Destroy: () -> (),
}

type RowUi = { Frame: Frame, Inputs: TextLabel, Buttons: { [number]: TextButton } }

local function newLabel(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = PresentationConfig.Colors.HudText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function createRow(parent: Frame, index: number, data: RecipeData, onCraft: (string, number) -> ()): RowUi
	local layout = PresentationConfig.Craft
	local colors = PresentationConfig.Colors
	local frame = Instance.new("Frame")
	frame.Name = data.recipeId
	frame.Size = UDim2.new(1, -layout.Padding * 2, 0, layout.RowHeight)
	frame.Position =
		UDim2.fromOffset(layout.Padding, layout.Padding + 28 + (index - 1) * (layout.RowHeight + layout.RowGap))
	frame.BackgroundColor3 = colors.Slot
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local icon = Instance.new("Frame")
	icon.Size = UDim2.fromOffset(layout.RowHeight - 24, layout.RowHeight - 24)
	icon.Position = UDim2.fromOffset(10, 12)
	icon.BackgroundColor3 = data.color
	icon.BorderSizePixel = 0
	icon.Parent = frame
	local letters = newLabel(icon, UDim2.fromScale(1, 1), UDim2.new(), 16)
	letters.TextXAlignment = Enum.TextXAlignment.Center
	letters.Text = data.letters

	local textX = layout.RowHeight
	local title = newLabel(frame, UDim2.new(1, -textX - 130, 0, 20), UDim2.fromOffset(textX, 8), 14)
	title.Font = Enum.Font.GothamBold
	title.Text = if data.outputCount > 1
		then string.format("%s x%d", data.outputName, data.outputCount)
		else data.outputName
	local inputs =
		newLabel(frame, UDim2.new(1, -textX - 130, 0, layout.RowHeight - 32), UDim2.fromOffset(textX, 30), 12)
	inputs.TextYAlignment = Enum.TextYAlignment.Top

	local buttons: { [number]: TextButton } = {}
	for position, batch in layout.Batches do
		local button = Instance.new("TextButton")
		button.Name = "Batch" .. batch
		button.Size = UDim2.fromOffset(52, 30)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10 - (#layout.Batches - position) * 58, 0.5, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = colors.HudText
		button.Text = "x" .. batch
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Parent = frame
		button.Activated:Connect(function()
			if button:GetAttribute("Enabled") == true then
				onCraft(data.recipeId, batch)
			end
		end)
		buttons[batch] = button
	end
	return { Frame = frame, Inputs = inputs, Buttons = buttons }
end

function CraftView.Create(playerGui: Instance, onCraft: (string, number) -> ()): Craft
	local layout = PresentationConfig.Craft
	local colors = PresentationConfig.Colors
	local gui = Instance.new("ScreenGui")
	gui.Name = "Craft"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false

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
	panel.BackgroundColor3 = colors.Panel
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local title = newLabel(panel, UDim2.new(1, -layout.Padding * 2, 0, 24), UDim2.fromOffset(layout.Padding, 10), 16)
	title.Font = Enum.Font.GothamBold
	title.Text = layout.Title
	gui.Parent = playerGui

	local rows: { [string]: RowUi } = {}
	local built = 0

	local function setRecipes(recipes: { RecipeData })
		if built ~= #recipes then
			for _, row in rows do
				row.Frame:Destroy()
			end
			table.clear(rows)
			for index, data in recipes do
				rows[data.recipeId] = createRow(panel, index, data, onCraft)
			end
			built = #recipes
			panel.Size = UDim2.fromOffset(
				layout.Width,
				layout.Padding * 2 + 28 + built * layout.RowHeight + math.max(built - 1, 0) * layout.RowGap
			)
		end
		for _, data in recipes do
			local row = rows[data.recipeId]
			local parts: { string } = {}
			for _, input in data.inputs do
				local color = if input.have >= input.need then colors.Good else colors.Bad
				table.insert(
					parts,
					string.format(
						'<font color="#%s">%s %d/%d</font>',
						color:ToHex(),
						input.name,
						input.have,
						input.need
					)
				)
			end
			row.Inputs.Text = table.concat(parts, "\n")
			for batch, button in row.Buttons do
				local enabled = data.canCraft[batch] == true
				button:SetAttribute("Enabled", enabled)
				button.BackgroundColor3 = if enabled then colors.Button else colors.ButtonDisabled
				button.TextColor3 = if enabled then colors.HudText else colors.TextDim
			end
		end
	end

	return {
		Gui = gui,
		SetRecipes = setRecipes,
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

return CraftView
