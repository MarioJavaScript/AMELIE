--!strict
-- Modelos en mano (docs/specs/jugador.md, "Herramienta en la mano"). Solo visual: el servidor nunca lee su posicion.
local ServerStorage = game:GetService("ServerStorage")

local Module = {}

local worldConfig: any
local itemsConfig: any
local playerConfig: any
local flashlight: any

local SLOTS = {
	HeldRight = { hand = { "RightHand", "Right Arm" }, grip = "RightGripAttachment" },
	HeldLeft = { hand = { "LeftHand", "Left Arm" }, grip = "LeftGripAttachment" },
}

function Module.Init(configs: { [string]: any })
	worldConfig = configs.WorldConfig
	itemsConfig = configs.ItemsConfig.Items
	playerConfig = configs.PlayerConfig
	flashlight = configs.StimuliConfig.Flashlight
end

local function folder(): Instance?
	local prefabs = ServerStorage:FindFirstChild(worldConfig.PrefabsName)
	return if prefabs then prefabs:FindFirstChild(worldConfig.HeldPrefabsFolder) else nil
end

local function requiredNames(): { string }
	local names: { [string]: boolean } = { [playerConfig.FlashlightHeldModel] = true }
	for _, item in itemsConfig do
		if item.HeldModel then
			names[item.HeldModel] = true
		end
	end
	local list = {}
	for name in names do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

-- Devuelve todos los problemas de contrato de los prefabs en mano (lista vacia si todo esta bien).
function Module.Validate(): { string }
	local errors: { string } = {}
	local root = folder()
	local base = "ServerStorage/" .. worldConfig.PrefabsName .. "/" .. worldConfig.HeldPrefabsFolder
	for _, name in requiredNames() do
		local path = base .. "/" .. name
		local model = if root then root:FindFirstChild(name) else nil
		if not model or not model:IsA("Model") then
			table.insert(errors, "falta el prefab (Model) " .. path)
			continue
		end
		local handle = model.PrimaryPart
		if not handle or handle.Name ~= "Handle" then
			table.insert(errors, path .. " sin PrimaryPart Handle")
			continue
		end
		local grip = handle:FindFirstChild("Grip")
		if not grip or not grip:IsA("Attachment") then
			table.insert(errors, path .. " sin Attachment Grip en Handle")
		end
		if model:FindFirstChildWhichIsA("LuaSourceContainer", true) then
			table.insert(errors, path .. " contiene Scripts")
		end
		local welded: { [Instance]: boolean } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("WeldConstraint") then
				if descendant.Part0 then
					welded[descendant.Part0] = true
				end
				if descendant.Part1 then
					welded[descendant.Part1] = true
				end
			end
		end
		for _, descendant in model:GetDescendants() do
			if not descendant:IsA("BasePart") then
				continue
			end
			if
				descendant.Anchored
				or descendant.CanCollide
				or descendant.CanTouch
				or descendant.CanQuery
				or not descendant.Massless
			then
				table.insert(
					errors,
					path
						.. "/"
						.. descendant.Name
						.. " debe ser Anchored, CanCollide, CanTouch y CanQuery false y Massless"
				)
			end
			if descendant ~= handle and not welded[descendant] then
				table.insert(errors, path .. "/" .. descendant.Name .. " sin WeldConstraint al Handle")
			end
		end
		if name == playerConfig.FlashlightHeldModel then
			local beam = model:FindFirstChild("Beam", true)
			if not beam or not beam:IsA("SpotLight") then
				table.insert(errors, path .. " sin SpotLight Beam")
			end
		end
	end
	return errors
end

local function find(character: Model, names: { string }): Instance?
	for _, name in names do
		local found = character:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

local function mount(character: Model, slotName: string, modelName: string, itemId: string)
	local slot = SLOTS[slotName]
	local hand = find(character, slot.hand)
	local anchor = if hand then hand:FindFirstChild(slot.grip) else nil
	local root = folder()
	local prefab = if root then root:FindFirstChild(modelName) else nil
	if not anchor or not anchor:IsA("Attachment") or not prefab or not prefab:IsA("Model") then
		return
	end
	local model = prefab:Clone()
	local handle = model.PrimaryPart :: BasePart
	local grip = handle:FindFirstChild("Grip") :: Attachment
	model.Name = slotName
	model:SetAttribute("ItemId", itemId)
	local beam = model:FindFirstChild("Beam", true)
	if beam and beam:IsA("SpotLight") then
		beam.Range = flashlight.RangeStuds
		beam.Angle = flashlight.ConeDegrees
	end
	model:PivotTo(anchor.WorldCFrame * grip.CFrame:Inverse())
	local constraint = Instance.new("RigidConstraint")
	constraint.Attachment0 = grip
	constraint.Attachment1 = anchor
	constraint.Parent = handle
	model.Parent = character
end

-- Reconcilia un slot: solo reemplaza el modelo si cambia el item. wanted = nombre de modelo e id de item, o nil.
local function reconcile(character: Model, slotName: string, modelName: string?, itemId: string?)
	local current = character:FindFirstChild(slotName)
	if current and (itemId == nil or current:GetAttribute("ItemId") ~= itemId) then
		current:Destroy()
		current = nil
	end
	if not current and modelName and itemId then
		mount(character, slotName, modelName, itemId)
	end
end

-- right/left: ids de item a mostrar (nil = nada). El nombre del modelo sale de ItemsConfig o de FlashlightHeldModel.
function Module.Sync(character: Model, rightItem: string?, leftOn: boolean)
	local item = if rightItem then itemsConfig[rightItem] else nil
	reconcile(character, "HeldRight", if item then item.HeldModel else nil, rightItem)
	local lamp = playerConfig.FlashlightHeldModel
	reconcile(character, "HeldLeft", if leftOn then lamp else nil, if leftOn then lamp else nil)
end

function Module.Clear(character: Model?)
	if character then
		Module.Sync(character, nil, false)
	end
end

return Module
