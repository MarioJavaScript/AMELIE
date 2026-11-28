--!strict
-- Script plano para execute_luau (Studio, modo Edit). Idempotente: reemplaza solo Arbol, Roca, Arbusto y Contenedor.
-- Contrato (recoleccion-inventario.md): Model con PrimaryPart Base; Hitbox con CanQuery = true y CanTouch = false;
-- el resto de partes con CanQuery = false y CanTouch = false.
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
	collide: boolean,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = name == "Hitbox"
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function build(name: string, attrs: { [string]: string }, fill: (Model) -> ())
	local old = prefabs:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	-- Pivote en el suelo: marcador invisible en y = 0.
	local base = part(model, "Base", Vector3.new(1, 0.2, 1), Vector3.zero, Color3.new(), Enum.Material.Plastic, false)
	base.Transparency = 1
	model.PrimaryPart = base
	model:SetAttribute("NodeKind", name)
	for k, v in attrs do
		model:SetAttribute(k, v)
	end
	fill(model)
	model.Parent = prefabs
end

build("Arbol", {}, function(m)
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

build("Roca", {}, function(m)
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
		false
	)
end)

build("Arbusto", {}, function(m)
	local hit = part(
		m,
		"Hitbox",
		Vector3.new(4, 3, 4),
		Vector3.new(0, 1.5, 0),
		Color3.fromRGB(30, 62, 34),
		Enum.Material.Grass,
		false
	)
	hit.Transparency = 1
	local leaf, leaf2 = Color3.fromRGB(30, 62, 34), Color3.fromRGB(38, 76, 40)
	local ball = Enum.PartType.Ball
	part(m, "Hoja", Vector3.new(3.6, 2.8, 3.6), Vector3.new(0, 1.4, 0), leaf, Enum.Material.Grass, false, ball)
	part(m, "Hoja", Vector3.new(2.6, 2.2, 2.6), Vector3.new(1.1, 1.1, 0.8), leaf2, Enum.Material.Grass, false, ball)
	part(m, "Hoja", Vector3.new(2.4, 2, 2.4), Vector3.new(-1.1, 1, -0.7), leaf2, Enum.Material.Grass, false, ball)
	local berry = Color3.fromRGB(190, 30, 40)
	for i, p in
		{
			Vector3.new(1.2, 2.2, 1.2),
			Vector3.new(-1, 2, 1.2),
			Vector3.new(0.2, 2.7, -0.4),
			Vector3.new(1.8, 1.4, -0.6),
			Vector3.new(-1.6, 1.3, 0.2),
			Vector3.new(-0.4, 1.2, 1.8),
			Vector3.new(0.6, 1.1, -1.8),
		}
	do
		part(m, "Baya" .. i, Vector3.new(0.4, 0.4, 0.4), p, berry, Enum.Material.SmoothPlastic, false, ball)
	end
end)

build("Contenedor", { ContainerKind = "Caja" }, function(m)
	part(
		m,
		"Hitbox",
		Vector3.new(3, 2, 2),
		Vector3.new(0, 1, 0),
		Color3.fromRGB(120, 124, 130),
		Enum.Material.Metal,
		true
	)
	-- Detalles visuales: tapa y franjas.
	local dark = Color3.fromRGB(70, 74, 80)
	part(m, "Tapa", Vector3.new(3.2, 0.3, 2.2), Vector3.new(0, 2.05, 0), dark, Enum.Material.Metal, false)
	for _, x in { -1.2, 1.2 } do
		part(m, "Franja", Vector3.new(0.3, 2.05, 2.1), Vector3.new(x, 1, 0), dark, Enum.Material.Metal, false)
	end
end)
