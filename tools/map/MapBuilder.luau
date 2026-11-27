--!strict
--[[
	MapBuilder: construye el mapa greybox segun docs/specs/mapa.md.
	Uso: pegar este archivo completo como source en execute_luau (Studio, modo Edit, nunca Play).
	No hace require de nada: los datos de layout estan en las tablas del principio.

	SECTION:
		"All" | "Terreno" | "Caminos" | "Base" | "Gasolinera" | "Torre" | "Pantano" | "Mina" | "Bosque" | "Marcadores"
	"All" y "Terreno" limpian Terrain, Workspace.Map y Workspace.Markers. Las demas solo limpian su carpeta
	(Marcadores es dueña de Workspace.Markers, Map/Zones y Map/Limites). Nunca toca Runtime, Lighting ni ServerStorage.
	Orden recomendado si se ejecutan sueltas: Terreno, Caminos, Base, Gasolinera, Torre, Pantano, Mina, Bosque, Marcadores.
]]

local SECTION = "All"

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Terrain = Workspace.Terrain
local Mat = Enum.Material
local v3, v2 = Vector3.new, Vector2.new
-- FillBlock/FillBall dejan la superficie 2 studs por encima del borde nominal (celdas de 4): se compensa aqui.
local TERRAIN_DY = -2
local function fillBlock(cf: CFrame, size: Vector3, mat: Enum.Material)
	Terrain:FillBlock(cf + v3(0, TERRAIN_DY, 0), size, mat)
end
local function fillBall(c: Vector3, r: number, mat: Enum.Material)
	Terrain:FillBall(c + v3(0, TERRAIN_DY, 0), r, mat)
end

--------------------------------------------------------------------------------------------------
-- DATOS (mapa.md). Los Vector2 son (X, Z).
--------------------------------------------------------------------------------------------------

local BASE_SEED = 20261127
local SECTIONS = { "Terreno", "Caminos", "Base", "Gasolinera", "Torre", "Pantano", "Mina", "Bosque", "Marcadores" }
local PLAY_LIMIT = 756

local C = {
	Grey = BrickColor.new("Medium stone grey").Color,
	Dark = BrickColor.new("Dark stone grey").Color,
	Brown = BrickColor.new("Brown").Color,
	Black = Color3.fromRGB(28, 28, 32),
	Green = Color3.fromRGB(74, 96, 66),
	Forest = Color3.fromRGB(34, 52, 38),
	Bark = Color3.fromRGB(60, 46, 38),
}

type Rect = { x0: number, z0: number, x1: number, z1: number }
type Gap = { number } -- { desde, hasta, y0, y1 } medidos a lo largo del muro
type Road = { id: string, w: number, mat: Enum.Material, pts: { Vector2 } }

local function rect(cx: number, cz: number, w: number, d: number): Rect
	return { x0 = cx - w / 2, z0 = cz - d / 2, x1 = cx + w / 2, z1 = cz + d / 2 }
end

local function inRect(p: Vector2, r: Rect, pad: number?): boolean
	local g = pad or 0
	return p.X >= r.x0 - g and p.X <= r.x1 + g and p.Y >= r.z0 - g and p.Y <= r.z1 + g
end

local ZONES = {
	{ id = "Base", anchor = v2(0, 0), expected = 0, pos = v3(0, 10, 0), size = v3(100, 40, 100) },
	{ id = "Gasolinera", anchor = v2(150, 0), expected = 150, pos = v3(155, 15, 5), size = v3(110, 40, 120) },
	{ id = "Torre", anchor = v2(0, -300), expected = 300, pos = v3(0, 50, -300), size = v3(200, 120, 200) },
	{ id = "Pantano", anchor = v2(-320, 320), expected = 452, pos = v3(-320, 15, 320), size = v3(240, 40, 240) },
	{ id = "Mina", anchor = v2(400, -440), expected = 595, pos = v3(405, 15, -545), size = v3(130, 40, 250) },
}

local ROADS: { Road } = {
	{ id = "SenderoGasolinera", w = 8, mat = Mat.Ground, pts = { v2(44, 0), v2(120, 0), v2(172, 0) } },
	{ id = "Carretera", w = 16, mat = Mat.Asphalt, pts = { v2(180, -226), v2(180, 200) } },
	{ id = "Cortafuegos", w = 6, mat = Mat.Ground, pts = { v2(0, -48), v2(0, -180) } },
	{ id = "SubidaTorre", w = 6, mat = Mat.Ground, pts = { v2(0, -180), v2(0, -292) } },
	{
		id = "SenderoPantano",
		w = 6,
		mat = Mat.Ground,
		pts = { v2(-36, 36), v2(-120, 90), v2(-180, 190), v2(-236, 236) },
	},
	{ id = "Cresta", w = 6, mat = Mat.Ground, pts = { v2(60, -300), v2(250, -380), v2(400, -440) } },
	{
		id = "AtajoMina",
		w = 6,
		mat = Mat.Ground,
		pts = { v2(180, -220), v2(215, -262), v2(260, -340), v2(330, -415) },
	},
}
-- Caminos sobre los que se reparten los arboles/rocas de bosque (los pasillos sin arboles quedan fuera).
local FOREST_ROAD_IDS =
	{ SenderoGasolinera = true, Carretera = true, SenderoPantano = true, Cresta = true, AtajoMina = true }

local STREAM: { Vector2 } = { v2(470, -445), v2(300, -330), v2(100, -170), v2(-80, -120), v2(-220, 60), v2(-300, 250) }
local STREAM_WIDTH = 10

local HILL = { c = v3(0, -160, -300), r = 200 }
local BASIN = rect(-320, 320, 200, 200)
local ISLETS = {
	{ pos = v2(-240, 330), r = 10 },
	{ pos = v2(-285, 318), r = 9 },
	{ pos = v2(-365, 315), r = 12 },
	{ pos = v2(-340, 380), r = 10 },
	{ pos = v2(-405, 305), r = 8 },
	{ pos = v2(-268, 372), r = 12 },
}
local MOUNTAINS = {
	{ c = v3(400, -127, -797), r = 377, mat = Mat.Rock },
	{ c = v3(0, -300, -950), r = 400, mat = Mat.Rock },
	{ c = v3(950, -300, 0), r = 400, mat = Mat.Rock },
	{ c = v3(0, -300, 950), r = 400, mat = Mat.Rock },
	{ c = v3(-950, -300, 0), r = 400, mat = Mat.Rock },
	{ c = v3(-720, -250, -720), r = 380, mat = Mat.Slate },
	{ c = v3(720, -250, 720), r = 380, mat = Mat.Slate },
	{ c = v3(-720, -250, 720), r = 380, mat = Mat.Slate },
}
local RUBBLE = {
	{ c = v3(180, 2, 208), r = 14 },
	{ c = v3(166, 0, 212), r = 10 },
	{ c = v3(194, 0, 212), r = 10 },
	{ c = v3(180, 0, 222), r = 10 },
	{ c = v3(172, 0, 224), r = 8 },
}
-- Excavacion de la mina (2.4). Tunel A alargado a 80 de largo para enlazar con la galeria (la spec dejaba 5 de roca).
-- Ancho de gateras y nicho 8 (no 6): el terreno usa celdas de 4 y un hueco de 6 queda con ribs parciales sin suelo.
local EXCAVATIONS = {
	{ c = v3(400, 6, -465), s = v3(12, 12, 80) },
	{ c = v3(408, 4, -472), s = v3(8, 8, 8) },
	{ c = v3(400, 7, -520), s = v3(40, 14, 30) },
	{ c = v3(360, 5, -520), s = v3(40, 10, 10) },
	{ c = v3(340, 5, -555), s = v3(10, 10, 60) },
	{ c = v3(340, 10, -600), s = v3(30, 20, 30) },
	{ c = v3(340, 35, -600), s = v3(8, 30, 8) },
	{ c = v3(400, 6, -577), s = v3(12, 12, 84) },
	{ c = v3(420, 9, -640), s = v3(50, 18, 40) },
	{ c = v3(367.5, 4, -600), s = v3(25, 8, 8) },
	{ c = v3(380, 4, -620), s = v3(8, 8, 40) },
	{ c = v3(387.5, 4, -640), s = v3(15, 8, 8) },
}
local MINE_FRAMES = {
	{ axis = "Z", c = 400, from = -455, to = -503, step = -12, w = 12, h = 12 },
	{ axis = "Z", c = 400, from = -541, to = -613, step = -12, w = 12, h = 12 },
	{ axis = "X", c = -520, from = 372, to = 348, step = -12, w = 10, h = 10 },
	{ axis = "Z", c = 340, from = -531, to = -579, step = -12, w = 10, h = 10 },
}

local CABINS = {
	{ id = "C1", pos = v2(-270, 280), tilt = 4 },
	{ id = "C2", pos = v2(-330, 290), tilt = 6 },
	{ id = "C3", pos = v2(-300, 350), tilt = 5 },
	{ id = "C4", pos = v2(-380, 350), tilt = 8 },
}
-- Pasarelas (2.3). El primer punto es la orilla (-222, 222): el sendero acaba en (-236, 236), ya dentro del agua.
local WALKWAY: { Vector2 } = {
	v2(-222, 222),
	v2(-260, 264),
	v2(-270, 280),
	v2(-300, 284),
	v2(-330, 290),
	v2(-310, 320),
	v2(-300, 350),
}

local CARS = { v3(172, 0, 11), v3(184, 0, -40), v3(176, 0, 60), v3(185, 0, 120) }

-- Marcadores (secciones 3, 4.6, 5, 8)
local PIECES = {
	{ id = "Bateria", pts = { v3(130, 0, -14), v3(138, 0, 26), v3(184, 0, -47) } },
	{ id = "Antena", pts = { v3(0, 80, -300), v3(0, 60, -300), v3(18, 40, -292) } },
	{ id = "Transceptor", pts = { v3(-332, 1, 292), v3(-302, 1, 352), v3(-382, 1, 352) } },
	{ id = "Cristal", pts = { v3(412, 0, -528), v3(336, 0, -606), v3(440, 0, -652) } },
}
local LOOT = {
	{ zone = "Base", pts = { v3(6, 0, -4) } },
	{ zone = "Gasolinera", pts = { v3(146, 0, -6), v3(134, 0, 18), v3(172, 0, 4) } },
	{ zone = "Torre", pts = { v3(4, 80, -304), v3(20, 40, -290), v3(-6, 40, -296) } },
	{ zone = "Pantano", pts = { v3(-272, 1, 282), v3(-298, 1, 348), v3(-350, 0, 260) } },
	{ zone = "Mina", pts = { v3(406, 0, -470), v3(388, 0, -512), v3(348, 0, -592) } },
}
local HIDEOUTS = {
	{ id = "Gasolinera_Almacen", pos = v3(130, 0, -14) },
	{ id = "Gasolinera_Taller", pos = v3(140, 0, 22) },
	{ id = "Matorral_Este", pos = v3(70, 0, -60) },
	{ id = "Matorral_Oeste", pos = v3(-80, 0, 60) },
	{ id = "Matorral_Arroyo", pos = v3(150, 0, -150) },
	{ id = "Torre_Caseta", pos = v3(18, 40, -292) },
	{ id = "Pantano_C3", pos = v3(-300, 1, 350) },
	{ id = "Mina_Nicho", pos = v3(406, 0, -470) },
}
local ENEMIES = {
	{ id = "CriaturaPrincipal_01", kind = "CriaturaPrincipal", pos = v3(420, 0, -645) },
	{ id = "AcechadorMenor_01", kind = "AcechadorMenor", pos = v3(-400, -3, 380) },
	{ id = "AcechadorMenor_02", kind = "AcechadorMenor", pos = v3(-260, -3, 390) },
	{ id = "AcechadorMenor_03", kind = "AcechadorMenor", pos = v3(-390, -3, 250) },
}
local NEST = { pos = v3(420, 9, -640), size = v3(50, 18, 40) }
type Patrol = { id: string, fromY: number?, pts: { Vector2 } }
local PATROLS: { Patrol } = {
	{
		id = "Bosque",
		pts = { v2(0, -125), v2(110, -90), v2(120, 70), v2(40, 140), v2(-90, 130), v2(-150, 10), v2(-110, -100) },
	},
	{
		id = "Exterior",
		pts = { v2(0, -200), v2(60, -300), v2(215, -262), v2(190, 100), v2(-200, 200), v2(-200, -60), v2(-60, -150) },
	},
	{ id = "Mina", fromY = 6, pts = { v2(400, -450), v2(400, -520), v2(340, -600), v2(380, -620), v2(420, -640) } },
	{
		id = "Pantano",
		pts = { v2(-260, 260), v2(-250, 340), v2(-320, 400), v2(-400, 360), v2(-400, 280), v2(-330, 240) },
	},
}
local NOBUILD = {
	{ id = "Caseta", pos = v3(0, 5, 0), size = v3(24, 12, 20) },
	{ id = "PuertaCaseta", pos = v3(0, 5, 12), size = v3(8, 12, 12) },
	{ id = "Fogata", pos = v3(0, 5, 18), size = v3(12, 12, 12) },
	{ id = "BaseSpawn", pos = v3(-8, 5, 18), size = v3(16, 12, 16) },
}
local BUILD_ZONE = { pos = v3(0, 0, 0), size = v3(96, 8, 96) }
local WATER_BOX = { pos = v3(-320, -1.5, 320), size = v3(200, 4, 200) }

-- Recursos (6): lo que se reparte y como. Total 68 Arbol / 42 Roca.
type ResEntry = { zone: string, kind: string, n: number, s: string, rock: boolean? }
local RES_PLAN: { ResEntry } = {
	{ zone = "Base", kind = "Arbol", n = 16, s = "BaseRing" },
	{ zone = "Base", kind = "Roca", n = 6, s = "BaseRing" },
	{ zone = "Bosque", kind = "Arbol", n = 36, s = "BosqueRoad" },
	{ zone = "Bosque", kind = "Roca", n = 10, s = "BosqueRoad" },
	{ zone = "Gasolinera", kind = "Arbol", n = 4, s = "GasBox" },
	{ zone = "Gasolinera", kind = "Roca", n = 6, s = "Derrumbe", rock = true },
	{ zone = "Torre", kind = "Arbol", n = 4, s = "TorrePie" },
	{ zone = "Torre", kind = "Roca", n = 8, s = "Afloramiento", rock = true },
	{ zone = "Pantano", kind = "Arbol", n = 8, s = "Pantano" },
	{ zone = "Pantano", kind = "Roca", n = 2, s = "Pantano" },
	{ zone = "Mina", kind = "Roca", n = 4, s = "MinaEntrada" },
	{ zone = "Mina", kind = "Roca", n = 6, s = "MinaInterior" },
}
local MINA_ROCKS: { Vector2 } =
	{ v2(415, -513), v2(404, -533), v2(392, -526), v2(330, -590), v2(342, -600), v2(350, -610) }

local EXPECTED = {
	{ "MapZone", 5 },
	{ "PieceSpawn", 12 },
	{ "ResourceSpawn", 110 },
	{ "LootSpawn", 13 },
	{ "EnemySpawn", 4 },
	{ "Nest", 1 },
	{ "WaterZone", 6 },
	{ "BuildZone", 1 },
	{ "NoBuildZone", 4 },
	{ "PatrolPoint", 25 },
	{ "Hideout", 8 },
}

-- Zonas donde no se pone ningun nodo de recurso: edificios, NoBuildZones y BuildZone.
local BLOCKED: { Rect } = {
	rect(140, -10, 32, 22),
	rect(140, 22, 18, 18),
	rect(166, 10, 28, 20),
	rect(0, -306, 20, 40),
	rect(18, -292, 12, 12),
	rect(-350, 260, 8, 14),
	rect(0, 0, 96, 96),
}
for _, n in NOBUILD do
	table.insert(BLOCKED, rect(n.pos.X, n.pos.Z, n.size.X, n.size.Z))
end
for _, c in CABINS do
	table.insert(BLOCKED, rect(c.pos.X, c.pos.Y, 16, 14))
end

--------------------------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------------------------

local function rngFor(section: string): Random
	return Random.new(BASE_SEED + (table.find(SECTIONS, section) :: number))
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function fresh(parent: Instance, name: string): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	return folder(parent, name)
end

local function part(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.Plastic
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, base: Vector3, h: number, d: number, color: Color3): Part
	local p =
		part(parent, name, CFrame.new(base + v3(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), v3(h, d, d), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function beam(parent: Instance, a: Vector3, b: Vector3, th: number, color: Color3): Part
	return part(parent, "Riostra", CFrame.lookAt((a + b) / 2, b), v3(th, th, (b - a).Magnitude), color)
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Muro de a a b (XZ) con huecos {desde, hasta, y0, y1}. Los extremos se alargan medio grosor para cerrar esquinas.
local function wall(
	parent: Instance,
	name: string,
	a: Vector2,
	b: Vector2,
	y0: number,
	h: number,
	th: number,
	gaps: { Gap }?,
	color: Color3
)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local function seg(t0: number, t1: number, ya: number, yb: number)
		if t1 - t0 < 0.01 or yb - ya < 0.01 then
			return
		end
		local c = a + dir * ((t0 + t1) / 2)
		local pos = v3(c.X, y0 + (ya + yb) / 2, c.Y)
		part(parent, name, CFrame.lookAt(pos, pos + v3(dir.X, 0, dir.Y)), v3(th, yb - ya, t1 - t0), color)
	end
	local sorted: { Gap } = if gaps then table.clone(gaps) else {}
	table.sort(sorted, function(g1, g2)
		return g1[1] < g2[1]
	end)
	local t = -th / 2
	for _, g in sorted do
		seg(t, g[1], 0, h)
		seg(g[1], g[2], 0, g[3])
		seg(g[1], g[2], g[4], h)
		t = g[2]
	end
	seg(t, len + th / 2, 0, h)
end

type Opts = { gaps: { [string]: { Gap } }?, roof: boolean?, floor: number?, th: number?, color: Color3? }

-- Edificio rectangular (centro cx,cz; ancho X w, fondo Z d; base en gy). Gaps por lado N/S/E/W; N y S miden desde
-- el oeste, E y W desde el norte.
local function building(
	parent: Instance,
	name: string,
	cx: number,
	gy: number,
	cz: number,
	w: number,
	d: number,
	h: number,
	o: Opts?
): Model
	local opt: Opts = o or {}
	local th = opt.th or 1
	local col = opt.color or C.Grey
	local gaps = opt.gaps or {}
	local m = model(parent, name)
	local x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2
	wall(m, "Muro_N", v2(x0, z0), v2(x1, z0), gy, h, th, gaps.N, col)
	wall(m, "Muro_S", v2(x0, z1), v2(x1, z1), gy, h, th, gaps.S, col)
	wall(m, "Muro_O", v2(x0, z0), v2(x0, z1), gy, h, th, gaps.W, col)
	wall(m, "Muro_E", v2(x1, z0), v2(x1, z1), gy, h, th, gaps.E, col)
	if opt.floor then
		part(m, "Piso", CFrame.new(cx, gy - opt.floor / 2, cz), v3(w, opt.floor, d), col)
	end
	if opt.roof then
		part(m, "Techo", CFrame.new(cx, gy + h + 0.5, cz), v3(w + th, 1, d + th), C.Dark)
	end
	return m
end

local function truss(parent: Instance, pos: Vector3, h: number)
	local t = Instance.new("TrussPart")
	t.Name = "Escalera"
	t.Anchored = true
	t.Size = v3(2, h, 2)
	t.CFrame = CFrame.new(pos)
	t.Color = C.Brown
	t.Parent = parent
end

-- Geometria 2D
local function segDist(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function polyDist(p: Vector2, pts: { Vector2 }): number
	local best = math.huge
	for i = 1, #pts - 1 do
		best = math.min(best, segDist(p, pts[i], pts[i + 1]))
	end
	return best
end

local function nearRoad(p: Vector2, base: number): boolean
	for _, r in ROADS do
		if polyDist(p, r.pts) < math.max(base, r.w / 2 + 2) then
			return true
		end
	end
	return false
end

local function zoneOf(x: number, z: number): string
	for _, zn in ZONES do
		if math.abs(x - zn.pos.X) <= zn.size.X / 2 and math.abs(z - zn.pos.Z) <= zn.size.Z / 2 then
			return zn.id
		end
	end
	return "Bosque"
end

local function hillY(x: number, z: number): number
	return HILL.c.Y + math.sqrt(math.max(HILL.r ^ 2 - x ^ 2 - (z - HILL.c.Z) ^ 2, 0))
end

-- Raycasts
local terrainParamsCache: { [boolean]: RaycastParams } = {}
local function terrainParams(ignoreWater: boolean): RaycastParams
	local p = terrainParamsCache[ignoreWater]
	if not p then
		p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		p.FilterDescendantsInstances = { Terrain }
		p.IgnoreWater = ignoreWater
		terrainParamsCache[ignoreWater] = p
	end
	return p :: RaycastParams
end

-- Terrain + Map sin Bosque/Limites/Zones (para marcadores sobre edificios, pasarelas, etc.)
local function worldParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.IgnoreWater = true
	local list: { Instance } = { Terrain }
	local map = Workspace:FindFirstChild("Map")
	if map then
		for _, c in map:GetChildren() do
			if c.Name ~= "Bosque" and c.Name ~= "Limites" and c.Name ~= "Zones" then
				table.insert(list, c)
			end
		end
	end
	p.FilterDescendantsInstances = list
	return p
end

local function cast(x: number, z: number, fromY: number?, params: RaycastParams): RaycastResult?
	local y = fromY or 400
	return Workspace:Raycast(v3(x, y, z), v3(0, -(y + 100), 0), params)
end

-- Marcadores
local function mk(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	tag: string?,
	attrs: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p:SetAttribute("ZoneId", zoneOf(cf.Position.X, cf.Position.Z))
	for k, v in attrs or {} do
		p:SetAttribute(k, v)
	end
	if tag then
		CollectionService:AddTag(p, tag)
	end
	p.Parent = parent
	return p
end

-- Marcador puntual de 2 x 1 x 2 con la cara inferior en ground.
local function spot(parent: Instance, name: string, ground: Vector3, tag: string?, attrs: { [string]: any }?): Part
	return mk(parent, name, CFrame.new(ground + v3(0, 0.5, 0)), v3(2, 1, 2), tag, attrs)
end

--------------------------------------------------------------------------------------------------
-- PLAN DE RECURSOS (6). Determinista; solo consulta Terrain. Lo usan Bosque, Pantano y Marcadores.
--------------------------------------------------------------------------------------------------

type Node = { kind: string, zone: string, pos: Vector3 }

local function outcrops(): { Vector2 }
	local rng = rngFor("Terreno")
	local out: { Vector2 } = {}
	local tries = 0
	while #out < 8 and tries < 1000 do
		tries += 1
		local ang, dist = rng:NextNumber(0, math.pi * 2), rng:NextNumber(35, 105)
		local p = v2(math.cos(ang) * dist, -300 + math.sin(ang) * dist)
		local ok = not (math.abs(p.X) < 14 and p.Y > -300) and (p - v2(18, -292)).Magnitude > 16
		for _, q in out do
			ok = ok and (p - q).Magnitude >= 20
		end
		if ok then
			table.insert(out, p)
		end
	end
	return out
end

local function polar(rng: Random, center: Vector2, r0: number, r1: number): Vector2
	local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(r0, r1)
	return center + v2(math.cos(a) * r, math.sin(a) * r)
end

local forestRoads: { Road } = {}
for _, r in ROADS do
	if FOREST_ROAD_IDS[r.id] then
		table.insert(forestRoads, r)
	end
end

local SAMPLERS: { [string]: (Random, number) -> (Vector2, number?) } = {
	BaseRing = function(rng)
		return polar(rng, v2(0, 0), 56, 96)
	end,
	BosqueRoad = function(rng)
		local r = forestRoads[rng:NextInteger(1, #forestRoads)]
		local i = rng:NextInteger(1, #r.pts - 1)
		local a, b = r.pts[i], r.pts[i + 1]
		local n = (b - a).Unit
		local off = rng:NextNumber(math.max(8, r.w / 2 + 2), 20) * (if rng:NextNumber() < 0.5 then -1 else 1)
		return a:Lerp(b, rng:NextNumber()) + v2(-n.Y, n.X) * off
	end,
	GasBox = function(rng)
		return v2(rng:NextNumber(102, 208), rng:NextNumber(-53, 63))
	end,
	Derrumbe = function(rng)
		return v2(rng:NextNumber(158, 202), rng:NextNumber(204, 230))
	end,
	TorrePie = function(rng)
		return polar(rng, v2(0, -300), 95, 118)
	end,
	Afloramiento = function(_, placed)
		return outcrops()[placed + 1] or v2(0, 0)
	end,
	Pantano = function(rng)
		return v2(rng:NextNumber(-440, -200), rng:NextNumber(200, 440))
	end,
	MinaEntrada = function(rng)
		return v2(400 + rng:NextNumber(14, 28) * (if rng:NextNumber() < 0.5 then -1 else 1), rng:NextNumber(-432, -416))
	end,
	MinaInterior = function(_, placed)
		return MINA_ROCKS[placed + 1] or v2(0, 0), 0
	end,
}

local planCache: { Node }? = nil

local function avoidPoints(): { Vector2 }
	local out: { Vector2 } = { v2(0, 18), v2(-8, 18) }
	local function add(pos: Vector3)
		table.insert(out, v2(pos.X, pos.Z))
	end
	for _, g in PIECES do
		for _, p in g.pts do
			add(p)
		end
	end
	for _, g in LOOT do
		for _, p in g.pts do
			add(p)
		end
	end
	for _, e in ENEMIES do
		add(e.pos)
	end
	return out
end

local function nodeAt(e: ResEntry, p: Vector2, fixedY: number?, out: { Node }, avoid: { Vector2 }): Vector3?
	if math.abs(p.X) > PLAY_LIMIT or math.abs(p.Y) > PLAY_LIMIT then
		return nil
	end
	if nearRoad(p, 6) or polyDist(p, STREAM) < 7 then
		return nil
	end
	if e.kind == "Arbol" and math.abs(p.X) < 12 and p.Y < -48 and p.Y > -180 then
		return nil
	end
	if e.zone == "Bosque" and zoneOf(p.X, p.Y) ~= "Bosque" then
		return nil
	end
	for _, r in BLOCKED do
		if inRect(p, r) then
			return nil
		end
	end
	for _, a in avoid do
		if (a - p).Magnitude < 4 then
			return nil
		end
	end
	for _, n in out do
		if (v2(n.pos.X, n.pos.Z) - p).Magnitude < 8 then
			return nil
		end
	end
	if fixedY then
		return v3(p.X, fixedY, p.Y)
	end
	local hit = cast(p.X, p.Y, nil, terrainParams(false))
	if not hit or hit.Material == Mat.Water then
		return nil
	end
	local m = hit.Material
	if e.rock and m ~= Mat.Rock then
		return nil
	end
	if e.kind == "Arbol" and (m == Mat.Rock or m == Mat.Slate) then
		return nil
	end
	if e.zone ~= "Torre" and hit.Position.Y > 20 then
		return nil
	end
	return hit.Position
end

local function planResources(): { Node }
	if planCache then
		return planCache
	end
	local out: { Node } = {}
	local avoid = avoidPoints()
	for i, e in RES_PLAN do
		local rng = Random.new(BASE_SEED + 100 + i)
		local placed, tries = 0, 0
		while placed < e.n and tries < 6000 do
			tries += 1
			local p, fy = SAMPLERS[e.s](rng, placed)
			local pos = nodeAt(e, p, fy, out, avoid)
			if pos then
				table.insert(out, { kind = e.kind, zone = e.zone, pos = pos })
				placed += 1
			end
		end
		if placed < e.n then
			warn(string.format("Recursos: %s %s %s solo %d/%d", e.zone, e.kind, e.s, placed, e.n))
		end
	end
	planCache = out
	return out
end

local function nearNode(p: Vector2, dist: number): boolean
	for _, n in planResources() do
		if (v2(n.pos.X, n.pos.Z) - p).Magnitude < dist then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------------------------
-- SECCIONES
--------------------------------------------------------------------------------------------------

local function carve(a: Vector2, b: Vector2, width: number)
	local a3, b3 = v3(a.X, 0, a.Y), v3(b.X, 0, b.Y)
	local cf = CFrame.lookAt((a3 + b3) / 2, b3)
	local len = (b3 - a3).Magnitude + 10
	fillBlock(cf * CFrame.new(0, 1, 0), v3(width, 8, len), Mat.Air)
	fillBlock(cf * CFrame.new(0, -5, 0), v3(width, 4, len), Mat.Mud)
	fillBlock(cf * CFrame.new(0, -1, 0), v3(width, 4, len), Mat.Water)
end

local function terreno(_map: Folder)
	for x = -800, 600, 200 do
		for z = -800, 600, 200 do
			fillBlock(CFrame.new(x + 100, -8, z + 100), v3(200, 16, 200), Mat.Grass)
			task.wait()
		end
	end
	fillBall(HILL.c, HILL.r, Mat.Grass)
	task.wait()
	for _, b in MOUNTAINS do
		fillBall(b.c, b.r, b.mat)
		task.wait()
	end
	for _, o in outcrops() do
		fillBall(v3(o.X, hillY(o.X, o.Y) - 2, o.Y), 7, Mat.Rock)
	end
	for _, b in RUBBLE do
		fillBall(b.c, b.r, Mat.Rock)
	end
	task.wait()
	for i = 1, #STREAM - 1 do
		carve(STREAM[i], STREAM[i + 1], STREAM_WIDTH)
	end
	local bc = v3((BASIN.x0 + BASIN.x1) / 2, 0, (BASIN.z0 + BASIN.z1) / 2)
	fillBlock(CFrame.new(bc + v3(0, 1, 0)), v3(200, 8, 200), Mat.Air)
	fillBlock(CFrame.new(bc + v3(0, -5, 0)), v3(200, 4, 200), Mat.Mud)
	fillBlock(CFrame.new(bc + v3(0, -1, 0)), v3(200, 4, 200), Mat.Water)
	for _, isl in ISLETS do
		local inner = isl.r - 4
		fillBall(v3(isl.pos.X, 1.5 - isl.r, isl.pos.Y), isl.r, Mat.Mud)
		fillBall(v3(isl.pos.X, 2.5 - inner, isl.pos.Y), inner, Mat.LeafyGrass)
	end
	task.wait()
	for _, e in EXCAVATIONS do
		-- El aire se queda corto (celdas de 4): ensanchar 2 por lado y subir el techo 4 deja el hueco util que pide la spec.
		fillBlock(CFrame.new(e.c + v3(0, 2, 0)), e.s + v3(4, 4, 4), Mat.Air)
	end
end

local function caminos(map: Folder)
	local params = terrainParams(true)
	for _, r in ROADS do
		local h = r.w / 2
		for i = 1, #r.pts - 1 do
			local a, b = r.pts[i], r.pts[i + 1]
			local n = math.ceil((b - a).Magnitude / h)
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				local hit = cast(p.X, p.Y, nil, params)
				if hit then
					local y = hit.Position.Y
					local region = Region3.new(v3(p.X - h, y - 10, p.Y - h), v3(p.X + h, y + 4, p.Y + h))
						:ExpandToGrid(4)
					Terrain:ReplaceMaterial(region, 4, Mat.Grass, r.mat)
				end
			end
		end
		task.wait()
	end
	local f = fresh(map, "Caminos")
	part(f, "PuenteCortafuegos", CFrame.new(0, 0.5, -142), v3(6, 1, 16), C.Brown)
	local dir = (STREAM[3] - STREAM[2]).Unit
	local pos = v3(215, 1.5, -262)
	part(f, "TroncoArroyo", CFrame.lookAt(pos, pos + v3(-dir.Y, 0, dir.X)), v3(3, 3, 18), C.Bark)
end

local function base(map: Folder)
	local f = fresh(map, "Base")
	local caseta = building(f, "Caseta", 0, 0, 0, 16, 12, 10, {
		roof = true,
		gaps = {
			S = { { 6, 10, 0, 7 } },
			N = { { 2, 6, 4, 8 }, { 10, 14, 4, 8 } },
			E = { { 4, 8, 4, 8 } },
			W = { { 4, 8, 4, 8 } },
		},
	})
	part(caseta, "Mesa", CFrame.new(0, 1.5, -4), v3(6, 3, 2), C.Brown)
	local radio = model(f, "Radio")
	radio:SetAttribute("InteractableId", "radio")
	radio.PrimaryPart = part(radio, "Cuerpo", CFrame.new(0, 4, -4), v3(4, 2, 2), C.Dark)
	for i, id in { "Bateria", "Antena", "Transceptor", "Cristal" } do
		part(radio, "Socket_" .. id, CFrame.new(-1.5 + (i - 1), 4, -2.85), v3(0.8, 0.8, 0.3), C.Black)
	end
	part(f, "Estante", CFrame.new(6, 2.5, -4), v3(2, 5, 4), C.Brown)
end

local function gasolinera(map: Folder)
	local f = fresh(map, "Gasolinera")
	local tienda = building(f, "Tienda", 140, 0, -10, 28, 18, 10, { roof = true, gaps = { E = { { 7, 11, 0, 7 } } } })
	wall(tienda, "Tabique", v2(134, -19), v2(134, -1), 0, 10, 0.8, { { 3, 7, 0, 7 } }, C.Grey)
	part(tienda, "Mostrador", CFrame.new(150, 1.5, -6), v3(2, 3, 8), C.Dark)
	for i, x in { 136, 140, 144 } do
		part(tienda, "Estanteria_" .. i, CFrame.new(x, 3, -10), v3(2, 6, 8), C.Dark)
	end
	local taller = building(f, "Taller", 140, 0, 22, 14, 14, 10, { roof = true, gaps = { E = { { 3, 11, 0, 7 } } } })
	part(taller, "Banco", CFrame.new(134.5, 1.5, 24), v3(2, 3, 6), C.Brown)
	local mq = model(f, "Marquesina")
	part(mq, "Techo", CFrame.new(166, 12, 10), v3(24, 1, 16), C.Dark)
	for i, c in { v2(156, 4), v2(176, 4), v2(156, 16), v2(176, 16) } do
		part(mq, "Columna_" .. i, CFrame.new(c.X, 5.75, c.Y), v3(1.5, 11.5, 1.5), C.Grey)
	end
	for i, z in { 6, 14 } do
		part(mq, "Surtidor_" .. i, CFrame.new(166, 2.5, z), v3(2, 5, 1.5), C.Black)
	end
	local coches = model(f, "Coches")
	for i, p in CARS do
		part(coches, "Coche_" .. i, CFrame.new(p.X, 1.75, p.Z), v3(6, 3.5, 12), C.Black)
		part(coches, "Cabina_" .. i, CFrame.new(p.X, 4.25, p.Z), v3(5, 1.5, 6), C.Black)
	end
	local puente = model(f, "PuenteCaido")
	part(puente, "Losa_1", CFrame.new(180, -1, -230) * CFrame.Angles(math.rad(-20), 0, 0), v3(16, 1, 10), C.Grey)
	part(puente, "Losa_2", CFrame.new(180, -2.5, -240) * CFrame.Angles(math.rad(20), 0, 0), v3(16, 1, 10), C.Grey)
end

local function torre(map: Folder)
	local f = fresh(map, "Torre")
	local m = model(f, "Torre")
	local corners = { v2(-5, -305), v2(5, -305), v2(5, -295), v2(-5, -295) }
	for i, c in corners do
		local n = corners[i % 4 + 1]
		part(m, "Pata", CFrame.new(c.X, 58.5, c.Y), v3(1.5, 43, 1.5), C.Dark)
		for _, y in { 40, 60 } do
			beam(m, v3(c.X, y, c.Y), v3(n.X, y + 20, n.Y), 0.5, C.Dark)
			beam(m, v3(n.X, y, n.Y), v3(c.X, y + 20, c.Y), 0.5, C.Dark)
		end
		beam(m, v3(c.X, 60, c.Y), v3(n.X, 60, n.Y), 0.6, C.Dark)
	end
	-- Descanso (suelo en Y 60) y cabina (suelo en Y 80), con hueco de 4 al norte para soltar la Antena
	part(m, "Descanso", CFrame.new(0, 59.5, -300), v3(8, 1, 8), C.Grey)
	building(m, "BarandillaDescanso", 0, 60, -300, 8, 8, 3, {
		th = 0.4,
		color = C.Dark,
		gaps = { N = { { 2, 6, 0, 3 } }, S = { { 2, 6, 0, 3 } } },
	})
	part(m, "CabinaSuelo_N", CFrame.new(0, 79.5, -301.75), v3(14, 1, 10.5), C.Grey)
	part(m, "CabinaSuelo_O", CFrame.new(-4.25, 79.5, -294.75), v3(5.5, 1, 3.5), C.Grey)
	part(m, "CabinaSuelo_E", CFrame.new(4.25, 79.5, -294.75), v3(5.5, 1, 3.5), C.Grey)
	building(m, "BarandillaCabina", 0, 80, -300, 14, 14, 3, {
		th = 0.4,
		color = C.Dark,
		gaps = { N = { { 5, 9, 0, 3 } }, S = { { 5.5, 8.5, 0, 3 } } },
	})
	for i, c in { v2(-6.75, -306.75), v2(6.75, -306.75), v2(6.75, -293.25), v2(-6.75, -293.25) } do
		part(m, "PosteCabina_" .. i, CFrame.new(c.X, 84.25, c.Y), v3(0.5, 8.5, 0.5), C.Dark)
	end
	part(m, "TechoCabina", CFrame.new(0, 89, -300), v3(14.5, 1, 14.5), C.Dark)
	truss(m, v3(0, 51, -293.5), 22)
	truss(m, v3(0, 71, -293.5), 22)
	building(
		f,
		"CasetaHerramientas",
		18,
		40,
		-292,
		8,
		8,
		7,
		{ roof = true, floor = 2, gaps = { S = { { 2, 6, 0, 6 } } } }
	)
end

local function pantano(map: Folder)
	local f = fresh(map, "Pantano")
	local rng = rngFor("Pantano")
	local cabanas = folder(f, "Cabanas")
	for _, c in CABINS do
		local m = building(cabanas, c.id, c.pos.X, 1, c.pos.Y, 12, 10, 8, {
			roof = true,
			floor = 1,
			color = C.Brown,
			gaps = { N = { { 4, 8, 0, 7 } }, E = { { 3, 7, 3, 6 } }, W = { { 3, 7, 3, 6 } } },
		})
		local center = CFrame.new(c.pos.X, 1, c.pos.Y)
		m:PivotTo(center * CFrame.Angles(0, 0, math.rad(c.tilt)) * center:Inverse() * m:GetPivot())
	end
	local pas = folder(f, "Pasarelas")
	for i = 1, #WALKWAY - 1 do
		local a, b = WALKWAY[i], WALKWAY[i + 1]
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		part(pas, "Tablon", CFrame.lookAt(v3(mid.X, 0.7, mid.Y), v3(b.X, 0.7, b.Y)), v3(4, 0.5, len + 2), C.Brown)
		for k = 0, math.floor(len / 8) do
			local p = a:Lerp(b, math.min(k * 8 / len, 1))
			part(pas, "Poste", CFrame.new(p.X, -1.8, p.Y), v3(0.6, 5, 0.6), C.Bark)
		end
	end
	part(f, "Bote", CFrame.new(-350, 0, 260) * CFrame.Angles(0, math.rad(20), math.rad(12)), v3(4, 2, 10), C.Brown)
	-- 30 arboles muertos: 12 en islotes y 18 en orillas
	local dead = folder(f, "ArbolesMuertos")
	local placed: { Vector2 } = {}
	local tries = 0
	while #placed < 30 and tries < 4000 do
		tries += 1
		local p: Vector2
		if #placed < 12 then
			local isl = ISLETS[#placed % #ISLETS + 1]
			p = polar(rng, isl.pos, 0, isl.r * 0.6)
		else
			p = v2(rng:NextNumber(-440, -200), rng:NextNumber(200, 440))
		end
		local ok = not nearNode(p, 4)
		for _, r in BLOCKED do
			ok = ok and not inRect(p, r)
		end
		for _, q in placed do
			ok = ok and (p - q).Magnitude >= 5
		end
		local hit = if ok then cast(p.X, p.Y, nil, terrainParams(false)) else nil
		if hit and hit.Material ~= Mat.Water then
			table.insert(placed, p)
			local m = model(dead, string.format("ArbolMuerto_%02d", #placed))
			local h = rng:NextNumber(8, 14)
			cylinder(m, "Tronco", hit.Position - v3(0, 0.5, 0), h + 0.5, 1.4, C.Bark)
			part(
				m,
				"Rama",
				CFrame.new(hit.Position + v3(0.9, h - 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(40)),
				v3(0.5, 4, 0.5),
				C.Bark
			)
		end
	end
end

local function mina(map: Folder)
	local f = fresh(map, "Mina")
	local sup = folder(f, "Soportes")
	for _, e in MINE_FRAMES do
		local hw = e.w / 2 - 0.4
		for t = e.from, e.to, e.step do
			local function at(off: number, y: number): Vector3
				return if e.axis == "Z" then v3(e.c + off, y, t) else v3(t, y, e.c + off)
			end
			part(sup, "Poste", CFrame.new(at(-hw, (e.h - 0.5) / 2)), v3(0.8, e.h - 0.5, 0.8), C.Brown)
			part(sup, "Poste", CFrame.new(at(hw, (e.h - 0.5) / 2)), v3(0.8, e.h - 0.5, 0.8), C.Brown)
			local bsize = if e.axis == "Z" then v3(e.w, 0.8, 0.8) else v3(0.8, 0.8, e.w)
			part(sup, "Viga", CFrame.new(at(0, e.h - 0.4)), bsize, C.Brown)
		end
	end
	local portal = model(f, "Portal")
	part(portal, "Poste_O", CFrame.new(393.2, 7, -444), v3(1.5, 14, 1.5), C.Brown)
	part(portal, "Poste_E", CFrame.new(406.8, 7, -444), v3(1.5, 14, 1.5), C.Brown)
	part(portal, "Dintel", CFrame.new(400, 14.25, -444), v3(16, 1.5, 1.5), C.Brown)
	local rieles = folder(f, "Rieles")
	for _, x in { 396.5, 399.5 } do
		part(rieles, "Riel", CFrame.new(x, 0.5, -501.5), v3(0.4, 0.4, 63), C.Dark)
	end
	for z = -472, -532, -3 do
		part(rieles, "Traviesa", CFrame.new(398, 0.15, z), v3(4, 0.3, 0.6), C.Bark)
	end
	local vag = model(f, "Vagoneta")
	part(vag, "Caja", CFrame.new(398, 1.5, -518), v3(4, 2, 5), C.Dark)
	for _, dx in { -2.1, 2.1 } do
		for _, dz in { -1.6, 1.6 } do
			local w = part(vag, "Rueda", CFrame.new(398 + dx, 0.6, -518 + dz), v3(0.4, 1.2, 1.2), C.Black)
			w.Shape = Enum.PartType.Cylinder
		end
	end
end

-- Variantes de arbol decorativo (solo Parts dentro de Map/Bosque, no son prefabs). Cada copa: tamano, altura del centro
-- sobre el suelo y color; el tronco es { alto, grosor }. Todo se multiplica por la escala del arbol.
type Crown = { size: Vector3, y: number }
type TreeVariant = { trunk: number, color: Color3, crowns: { Crown } }
local FOREST_JITTER = 8
local TREE_VARIANTS: { TreeVariant } = {
	{ trunk = 25, color = C.Forest, crowns = { { size = v3(7, 18, 7), y = 25 } } }, -- alto y estrecho
	{ trunk = 19, color = Color3.fromRGB(26, 62, 34), crowns = { { size = v3(15, 10, 15), y = 21 } } }, -- copa ancha
	{
		trunk = 24,
		color = Color3.fromRGB(48, 64, 54),
		crowns = { { size = v3(12, 8, 12), y = 17 }, { size = v3(8, 8, 8), y = 26 } },
	}, -- dos niveles, tono gris
}
local TREE_SCALE_MIN, TREE_SCALE_MAX = 0.8, 1.3

local function bosque(map: Folder)
	local f = fresh(map, "Bosque")
	local trees = folder(f, "Arboles")
	local bushes = folder(f, "Matorrales")
	local rng = rngFor("Bosque")
	local cand: { Vector2 } = {}
	for gx = -PLAY_LIMIT, PLAY_LIMIT, 18 do
		for gz = -PLAY_LIMIT, PLAY_LIMIT, 18 do
			local x, z, roll =
				gx + rng:NextNumber(-FOREST_JITTER, FOREST_JITTER),
				gz + rng:NextNumber(-FOREST_JITTER, FOREST_JITTER),
				rng:NextNumber()
			local p = v2(x, z)
			local near = math.huge
			for _, r in ROADS do
				near = math.min(near, polyDist(p, r.pts))
			end
			for _, zn in ZONES do
				local dx = math.max(math.abs(x - zn.pos.X) - zn.size.X / 2, 0)
				local dz = math.max(math.abs(z - zn.pos.Z) - zn.size.Z / 2, 0)
				near = math.min(near, math.sqrt(dx * dx + dz * dz))
			end
			local clear = p.Magnitude < 60
				or (math.abs(x) < 12 and z > -180 and z < -48)
				or nearRoad(p, 10)
				or polyDist(p, STREAM) < STREAM_WIDTH / 2 + 4
				or inRect(p, BASIN, 4)
				or zoneOf(x, z) ~= "Bosque"
				or roll >= (if near < 150 then 0.55 else 0.15)
				or nearNode(p, 8)
			if not clear then
				table.insert(cand, p)
			end
		end
	end
	for i = #cand, 2, -1 do
		local j = rng:NextInteger(1, i)
		cand[i], cand[j] = cand[j], cand[i]
	end
	local count = 0
	for _, p in cand do
		if count >= 2500 then
			break
		end
		local hit = cast(p.X, p.Y, nil, terrainParams(false))
		if
			hit
			and hit.Material ~= Mat.Water
			and hit.Material ~= Mat.Rock
			and hit.Material ~= Mat.Slate
			and hit.Position.Y <= 20
		then
			count += 1
			local m = model(trees, "Arbol_" .. count)
			local var = TREE_VARIANTS[rng:NextInteger(1, #TREE_VARIANTS)]
			local sc, yaw = rng:NextNumber(TREE_SCALE_MIN, TREE_SCALE_MAX), rng:NextNumber(0, math.pi * 2)
			cylinder(m, "Tronco", hit.Position - v3(0, 1, 0), var.trunk * sc, 2.5 * sc, C.Bark)
			for i, c in var.crowns do
				part(
					m,
					"Copa_" .. i,
					CFrame.new(hit.Position + v3(0, c.y * sc, 0)) * CFrame.Angles(0, yaw, 0),
					c.size * sc,
					var.color
				).CanCollide =
					false
			end
			if count % 200 == 0 then
				task.wait()
			end
		end
	end
	for _, h in HIDEOUTS do
		if string.sub(h.id, 1, 8) == "Matorral" then
			local m = model(bushes, h.id)
			for i = 1, 6 do
				local p = polar(rng, v2(h.pos.X, h.pos.Z), 0, 5)
				local hit = cast(p.X, p.Y, nil, terrainParams(true))
				local r = rng:NextNumber(6, 8)
				local ball = part(
					m,
					"Bola_" .. i,
					CFrame.new(p.X, (if hit then hit.Position.Y else 0) + r * 0.5, p.Y),
					v3(r, r, r),
					C.Green
				)
				ball.Shape = Enum.PartType.Ball
				ball.CanCollide = false
			end
		end
	end
end

local function marcadores(map: Folder)
	-- Volumenes de zona y muros limite (Map)
	local zones = fresh(map, "Zones")
	for _, z in ZONES do
		mk(zones, z.id, CFrame.new(z.pos), z.size, "MapZone", { ZoneId = z.id })
	end
	local lim = fresh(map, "Limites")
	local walls: { { id: string, pos: Vector3, size: Vector3 } } = {
		{ id = "N", pos = v3(0, 150, -762), size = v3(1528, 300, 4) },
		{ id = "S", pos = v3(0, 150, 762), size = v3(1528, 300, 4) },
		{ id = "E", pos = v3(762, 150, 0), size = v3(4, 300, 1528) },
		{ id = "O", pos = v3(-762, 150, 0), size = v3(4, 300, 1528) },
	}
	for _, w in walls do
		mk(lim, "Muro_" .. w.id, CFrame.new(w.pos), w.size, nil, nil).CanCollide = true
	end

	local root = fresh(Workspace, "Markers")
	spot(root, "BaseSpawn", v3(-8, 0, 18)).Size = v3(8, 1, 8)
	mk(root, "RadioSocket", CFrame.new(0, 3.5, -4), v3(4, 2, 2), nil, nil)
	mk(root, "CampfireSocket", CFrame.new(0, 0.5, 18), v3(4, 1, 4), nil, nil)

	local obj = folder(root, "ObjectiveSpawns")
	for _, g in PIECES do
		local gf = folder(obj, g.id)
		for i, p in g.pts do
			spot(gf, string.format("%02d", i), p, "PieceSpawn", { PieceId = g.id })
		end
	end

	local res = folder(root, "ResourceSpawns")
	local counters: { [string]: number } = { Arbol = 0, Roca = 0 }
	for _, n in planResources() do
		counters[n.kind] += 1
		spot(
			res,
			string.format("%s_%03d", n.kind, counters[n.kind]),
			n.pos,
			"ResourceSpawn",
			{ Kind = n.kind, ZoneId = n.zone }
		)
	end

	local loot = folder(root, "LootSpawns")
	for _, g in LOOT do
		for i, p in g.pts do
			spot(loot, string.format("%s_%02d", g.zone, i), p, "LootSpawn", { ZoneId = g.zone })
		end
	end

	local en = folder(root, "EnemySpawns")
	for _, e in ENEMIES do
		spot(en, e.id, e.pos, "EnemySpawn", { EnemyKind = e.kind })
	end
	mk(root, "Nest", CFrame.new(NEST.pos), NEST.size, "Nest", nil)

	local water = folder(root, "WaterZones")
	mk(water, "Pantano", CFrame.new(WATER_BOX.pos), WATER_BOX.size, "WaterZone", nil)
	for i = 1, #STREAM - 1 do
		local a, b = STREAM[i], STREAM[i + 1]
		local mid, len = (a + b) / 2, (b - a).Magnitude
		local c = v3(mid.X, -1.5, mid.Y)
		mk(water, "Arroyo_" .. i, CFrame.lookAt(c, c + v3(b.X - a.X, 0, b.Y - a.Y)), v3(12, 4, len), "WaterZone", nil)
	end

	mk(folder(root, "BuildZones"), "Base", CFrame.new(BUILD_ZONE.pos), BUILD_ZONE.size, "BuildZone", nil)
	local nb = folder(root, "NoBuildZones")
	for _, n in NOBUILD do
		mk(nb, n.id, CFrame.new(n.pos), n.size, "NoBuildZone", nil)
	end

	local pat = folder(root, "PatrolPoints")
	local params = worldParams()
	for _, r in PATROLS do
		local rf = folder(pat, r.id)
		for i, p in r.pts do
			local hit = cast(p.X, p.Y, r.fromY, params)
			spot(
				rf,
				string.format("%02d", i),
				v3(p.X, if hit then hit.Position.Y else 0, p.Y),
				"PatrolPoint",
				{ RouteId = r.id, Order = i }
			)
		end
	end

	local hid = folder(root, "Hideouts")
	for _, h in HIDEOUTS do
		spot(hid, h.id, h.pos, "Hideout", nil)
	end
end

--------------------------------------------------------------------------------------------------
-- VERIFICACION Y RESUMEN
--------------------------------------------------------------------------------------------------

local function summary(strict: boolean)
	print("--- MapBuilder: resumen ---")
	local counts: { [string]: number } = {}
	for _, e in EXPECTED do
		local n = #CollectionService:GetTagged(e[1] :: string)
		counts[e[1] :: string] = n
		print(string.format("%-14s %d (esperado %d)", e[1], n, e[2]))
		if strict and n ~= e[2] then
			warn(string.format("Conteo no cuadra: %s = %d, esperado %d", e[1], n, e[2]))
		end
	end
	local kinds: { [string]: number } = { Arbol = 0, Roca = 0 }
	for _, inst in CollectionService:GetTagged("ResourceSpawn") do
		local k = inst:GetAttribute("Kind")
		if type(k) == "string" and kinds[k] then
			kinds[k] += 1
		end
	end
	print(string.format("ResourceSpawn: Arbol %d (68), Roca %d (42)", kinds.Arbol, kinds.Roca))
	if strict and (kinds.Arbol ~= 68 or kinds.Roca ~= 42) then
		warn("ResourceSpawn Arbol/Roca no cuadra con 68/42")
	end
	local routes: { [string]: number } = {}
	for _, inst in CollectionService:GetTagged("PatrolPoint") do
		local id = inst:GetAttribute("RouteId")
		if type(id) == "string" then
			routes[id] = (routes[id] or 0) + 1
		end
	end
	for _, r in PATROLS do
		print(string.format("PatrolPoint %s: %d", r.id, routes[r.id] or 0))
	end
	for _, z in ZONES do
		local d = z.anchor.Magnitude
		print(string.format("Zona %s: %.0f studs a la base (spec %d)", z.id, d, z.expected))
		if strict and math.abs(d - z.expected) > z.expected * 0.1 then
			warn("Distancia fuera del 10 por ciento: " .. z.id)
		end
	end
	-- Ningun marcador a mas de 2 studs de su superficie
	local params = worldParams()
	for _, tag in { "PieceSpawn", "LootSpawn", "ResourceSpawn", "Hideout", "EnemySpawn", "PatrolPoint" } do
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") then
				local baseY = inst.Position.Y - inst.Size.Y / 2
				local hit = cast(inst.Position.X, inst.Position.Z, baseY + 1.5, params)
				if not hit or hit.Position.Y < baseY - 2 or hit.Position.Y > baseY + 1.5 then
					warn(string.format("Marcador fuera de superficie: %s (%s)", inst:GetFullName(), tag))
				end
			end
		end
	end
end

--------------------------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------------------------

-- Borra el Baseplate de la plantilla y deja un unico SpawnLocation invisible sobre BaseSpawn (tras crear marcadores).
local function removeBaseplate()
	local bp = Workspace:FindFirstChild("Baseplate")
	if bp then
		bp:Destroy()
	end
end

local function setupSpawn()
	local marker = (Workspace:FindFirstChild("Markers") :: Instance):FindFirstChild("BaseSpawn") :: BasePart
	local spawns: { SpawnLocation } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			table.insert(spawns, d)
		end
	end
	local sp = table.remove(spawns, 1) or Instance.new("SpawnLocation")
	for _, extra in spawns do
		extra:Destroy()
	end
	for _, c in sp:GetChildren() do
		if c:IsA("Decal") or c:IsA("Texture") then
			c:Destroy()
		end
	end
	sp.Name = "SpawnLocation"
	sp.Anchored = true
	sp.CanCollide = false
	sp.Transparency = 1
	sp.Neutral = true
	sp.Size = marker.Size
	sp.CFrame = marker.CFrame
	sp.Parent = Workspace
end

local RUNNERS: { [string]: (Folder) -> () } = {
	Terreno = terreno,
	Caminos = caminos,
	Base = base,
	Gasolinera = gasolinera,
	Torre = torre,
	Pantano = pantano,
	Mina = mina,
	Bosque = bosque,
	Marcadores = marcadores,
}

assert(SECTION == "All" or RUNNERS[SECTION] ~= nil, "SECTION invalida: " .. SECTION)
local t0 = os.clock()
removeBaseplate()
if SECTION == "All" or SECTION == "Terreno" then
	Terrain:Clear()
	for _, n in { "Map", "Markers" } do
		local old = Workspace:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
end
local mapFolder = Workspace:FindFirstChild("Map")
if not (mapFolder and mapFolder:IsA("Folder")) then
	mapFolder = folder(Workspace, "Map")
end
for _, s in SECTIONS do
	if SECTION == "All" or SECTION == s then
		RUNNERS[s](mapFolder :: Folder)
		if s == "Marcadores" then
			setupSpawn()
		end
		print(string.format("MapBuilder: %s lista (%.1fs)", s, os.clock() - t0))
		task.wait()
	end
end
if SECTION == "All" or SECTION == "Marcadores" then
	summary(true)
end
print(string.format("MapBuilder: %s terminado en %.1fs", SECTION, os.clock() - t0))
