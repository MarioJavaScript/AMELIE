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

-- Modelos en mano (jugador.md, "Herramienta en la mano"). Idempotente: reemplaza solo Prefabs/Held.
-- Marco local: la herramienta apunta a -Z (LookVector del Grip) y su arriba es +Y; Grip = punto donde agarra la mano.
local held = prefabs:FindFirstChild("Held")
if held then
	held:Destroy()
end
held = Instance.new("Folder")
held.Name = "Held"
held.Parent = prefabs

local ball, cylinder = Enum.PartType.Ball, Enum.PartType.Cylinder
local R90 = math.pi / 2

-- Parte suelta (sin anclar, sin colision, sin masa). cf es relativo al Handle (marco local de la herramienta).
local function heldPart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = model
	local handle = model.PrimaryPart
	if handle then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	return p
end

-- handleCf orienta el Handle en el marco local; gripAt es la posicion del Grip en ese mismo marco.
local function buildHeld(
	name: string,
	handleSize: Vector3,
	handleCf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	gripAt: Vector3,
	fill: (Model, CFrame) -> ()
)
	local model = Instance.new("Model")
	model.Name = name
	local handle = heldPart(model, "Handle", handleSize, handleCf, color, material, shape)
	model.PrimaryPart = handle
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = handleCf:Inverse() * CFrame.new(gripAt)
	grip.Parent = handle
	fill(model, handleCf)
	model.Parent = held
end

local wood, steel = Color3.fromRGB(120, 85, 50), Color3.fromRGB(150, 155, 160)
local none = function(_m: Model, _cf: CFrame) end
local look = CFrame.new

buildHeld(
	"Hacha",
	Vector3.new(0.25, 0.25, 3),
	CFrame.new(),
	wood,
	Enum.Material.Wood,
	nil,
	Vector3.new(0, 0, 0.9),
	function(m, cf)
		heldPart(m, "Cabeza", Vector3.new(0.2, 1, 0.8), cf * look(0, 0.3, -1.25), steel, Enum.Material.Metal, nil)
	end
)

buildHeld(
	"Pico",
	Vector3.new(0.25, 0.25, 3),
	CFrame.new(),
	wood,
	Enum.Material.Wood,
	nil,
	Vector3.new(0, 0, 0.9),
	function(m, cf)
		heldPart(m, "Cabeza", Vector3.new(1.8, 0.25, 0.3), cf * look(0, 0, -1.4), steel, Enum.Material.Metal, nil)
	end
)

-- Cilindros: el eje largo de Roblox es X; se gira para que quede vertical (marco local +Y).
local upright = CFrame.Angles(0, 0, R90)

buildHeld(
	"Venda",
	Vector3.new(0.7, 0.9, 0.9),
	upright,
	Color3.fromRGB(235, 235, 230),
	Enum.Material.Fabric,
	cylinder,
	Vector3.zero,
	none
)

buildHeld(
	"Botiquin",
	Vector3.new(1, 0.8, 0.45),
	CFrame.new(),
	Color3.fromRGB(190, 35, 35),
	Enum.Material.Plastic,
	nil,
	Vector3.zero,
	function(m, cf)
		heldPart(
			m,
			"Cruz",
			Vector3.new(0.5, 0.3, 0.5),
			cf * look(0, 0, -0.2),
			Color3.fromRGB(240, 240, 240),
			Enum.Material.Plastic,
			nil
		)
	end
)

buildHeld(
	"Lata",
	Vector3.new(1, 0.6, 0.6),
	upright,
	Color3.fromRGB(170, 175, 180),
	Enum.Material.Metal,
	cylinder,
	Vector3.zero,
	function(m, cf)
		heldPart(
			m,
			"Etiqueta",
			Vector3.new(0.6, 0.62, 0.62),
			cf,
			Color3.fromRGB(190, 60, 40),
			Enum.Material.Plastic,
			cylinder
		)
	end
)

buildHeld(
	"Baya",
	Vector3.new(0.35, 0.35, 0.35),
	CFrame.new(),
	Color3.fromRGB(190, 30, 40),
	Enum.Material.SmoothPlastic,
	ball,
	Vector3.zero,
	function(m, cf)
		for i, offset in { Vector3.new(0.3, 0.1, 0), Vector3.new(-0.1, 0.25, 0.2), Vector3.new(0.05, -0.2, -0.25) } do
			heldPart(
				m,
				"Baya" .. i,
				Vector3.new(0.35, 0.35, 0.35),
				cf * look(offset),
				Color3.fromRGB(190, 30, 40),
				Enum.Material.SmoothPlastic,
				ball
			)
		end
	end
)

buildHeld(
	"Pila",
	Vector3.new(0.8, 0.4, 0.4),
	upright,
	Color3.fromRGB(60, 60, 65),
	Enum.Material.Metal,
	cylinder,
	Vector3.zero,
	function(m, cf)
		heldPart(
			m,
			"Polo",
			Vector3.new(0.15, 0.2, 0.2),
			cf * look(0.45, 0, 0),
			Color3.fromRGB(200, 170, 60),
			Enum.Material.Metal,
			cylinder
		)
	end
)

-- Linterna: cuerpo cilindrico con el eje largo en Z; Lens en el frente (-Z) con el SpotLight Beam.
buildHeld(
	"Linterna",
	Vector3.new(1.2, 0.4, 0.4),
	CFrame.Angles(0, R90, 0),
	Color3.fromRGB(45, 45, 50),
	Enum.Material.Metal,
	cylinder,
	Vector3.zero,
	function(m, cf)
		local lens = heldPart(
			m,
			"Lens",
			Vector3.new(0.15, 0.5, 0.5),
			cf * look(0.65, 0, 0),
			Color3.fromRGB(255, 240, 190),
			Enum.Material.Neon,
			cylinder
		)
		local beam = Instance.new("SpotLight")
		beam.Name = "Beam"
		beam.Face = Enum.NormalId.Right
		beam.Brightness = 2
		beam.Range = 60
		beam.Angle = 50
		beam.Parent = lens
	end
)
