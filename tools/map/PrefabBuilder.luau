--!strict
-- Script plano para execute_luau (Studio, modo Edit). Idempotente: reemplaza solo Arbol y Roca.
local ServerStorage = game:GetService("ServerStorage")

local prefabs = ServerStorage:FindFirstChild("Prefabs") or Instance.new("Folder")
prefabs.Name = "Prefabs"
prefabs.Parent = ServerStorage

local function part(
	model: Model,
	name: string,
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material,
	collide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide
	p.Parent = model
	return p
end

local function build(name: string, fill: (Model) -> ())
	local old = prefabs:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	-- Pivote en el suelo: marcador invisible en y = 0.
	local base = part(model, "Base", Vector3.new(1, 0.2, 1), Vector3.zero, Color3.new(), Enum.Material.Plastic, false)
	base.Transparency = 1
	base.CanQuery = false
	base.CanTouch = false
	model.PrimaryPart = base
	model:SetAttribute("NodeKind", name)
	fill(model)
	model.Parent = prefabs
end

build("Arbol", function(m)
	part(
		m,
		"Hitbox",
		Vector3.new(2, 12, 2),
		Vector3.new(0, 6, 0),
		Color3.fromRGB(110, 80, 50),
		Enum.Material.Wood,
		true
	)
	part(
		m,
		"Copa",
		Vector3.new(8, 8, 8),
		Vector3.new(0, 15, 0),
		Color3.fromRGB(90, 150, 70),
		Enum.Material.Grass,
		false
	)
end)

build("Roca", function(m)
	part(
		m,
		"Hitbox",
		Vector3.new(5, 4, 5),
		Vector3.new(0, 2, 0),
		Color3.fromRGB(125, 125, 130),
		Enum.Material.Slate,
		true
	)
	part(
		m,
		"Fragmento",
		Vector3.new(3, 2.5, 3),
		Vector3.new(2.5, 1.25, 1.5),
		Color3.fromRGB(105, 105, 110),
		Enum.Material.Slate,
		true
	)
end)
