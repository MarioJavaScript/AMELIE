--!strict
--[[
	MapBuilder: construye el mapa greybox en dos actos segun docs/specs/mapa.md (revision 2).
	Uso: pegar este archivo completo como source en execute_luau (Studio, modo Edit, nunca Play).
	No hace require de nada: los datos de layout estan en las tablas del principio.

	SECTION:
		"All" | "Terreno" | "Caminos" | "Base" | "Ciudad" | "Torre" | "Mina" | "Rio" | "Puente" | "Industrial"
		| "Complejo" | "BosqueAnomalo" | "Bosque" | "Marcadores"
		"PuenteOn" | "PuenteOff": alterna la variante del puente en Edit (misma logica que el comando de debug).
		"TerrenoA" (suelo, montanas, loma) y "TerrenoB" (garganta, mina, sotanos) son las dos pasadas de "Terreno".
	"All", "Terreno" y "TerrenoA" limpian Terrain, Workspace.Map, Workspace.Markers y ServerStorage.MapVariants.
	Las demas solo limpian su carpeta (Marcadores es dueña de Workspace.Markers, Map/Zones y Map/Limites; Puente de
	ServerStorage.MapVariants). Nunca toca Runtime, Lighting ni ServerStorage.Prefabs.
	Orden recomendado si se ejecutan sueltas: Terreno, Caminos, Base, Ciudad, Torre, Mina, Rio, Puente, Industrial,
	Complejo, BosqueAnomalo, Bosque, Marcadores.
]]

local SECTION = "All"

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
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
local function fillWedge(cf: CFrame, size: Vector3, mat: Enum.Material)
	Terrain:FillWedge(cf + v3(0, TERRAIN_DY, 0), size, mat)
end
-- Hueco de aire entre y0 (suelo) y y1 (techo). El aire sale corto con celdas de 4: se ensancha 2 por lado en XZ y el
-- techo queda en y1 (hay que pasar y1 ya con el margen). Huecos de menos de 8 de ancho quedan sin suelo.
local function hollow(cx: number, cz: number, sx: number, sz: number, y0: number, y1: number)
	local h = y1 - y0 - 4
	fillBlock(CFrame.new(cx, y0 + h / 2 + 2, cz), v3(sx + 4, h + 4, sz + 4), Mat.Air)
end

--------------------------------------------------------------------------------------------------
-- DATOS (mapa.md). Los Vector2 son (X, Z).
--------------------------------------------------------------------------------------------------

local BASE_SEED = 20261127
local SECTIONS = {
	"Terreno",
	"Caminos",
	"Base",
	"Ciudad",
	"Torre",
	"Mina",
	"Rio",
	"Puente",
	"Industrial",
	"Complejo",
	"BosqueAnomalo",
	"Bosque",
	"Marcadores",
}
local PLAY = { x0 = -600, x1 = 600, z0 = -760, z1 = 360 }

local C = {
	Grey = BrickColor.new("Medium stone grey").Color,
	Dark = BrickColor.new("Dark stone grey").Color,
	Brown = BrickColor.new("Brown").Color,
	Black = Color3.fromRGB(28, 28, 32),
	Green = Color3.fromRGB(74, 96, 66),
	Forest = Color3.fromRGB(34, 52, 38),
	Bark = Color3.fromRGB(60, 46, 38),
	Violet = Color3.fromRGB(92, 84, 108),
	Teal = Color3.fromRGB(56, 92, 98),
	Dry = Color3.fromRGB(112, 106, 120),
	Neon = Color3.fromRGB(70, 235, 215),
	Crystal = Color3.fromRGB(196, 218, 232),
	Canvas = Color3.fromRGB(104, 112, 92),
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
	{ id = "Ciudad", anchor = v2(300, 0), expected = 300, pos = v3(300, 15, 0), size = v3(220, 50, 200) },
	{ id = "Torre", anchor = v2(-120, -150), expected = 192, pos = v3(-120, 30, -150), size = v3(120, 80, 120) },
	{ id = "Mina", anchor = v2(-380, -40), expected = 382, pos = v3(-480, 15, -30), size = v3(250, 40, 150) },
	{ id = "Industrial", anchor = v2(280, -450), expected = 530, pos = v3(280, 20, -450), size = v3(240, 60, 200) },
	{ id = "BosqueAnomalo", anchor = v2(0, -560), expected = 560, pos = v3(0, 20, -560), size = v3(300, 60, 300) },
	{ id = "Complejo", anchor = v2(-300, -580), expected = 652, pos = v3(-300, 5, -580), size = v3(160, 90, 160) },
}

local ROADS: { Road } = {
	{ id = "Cortafuegos", w = 6, mat = Mat.Ground, pts = { v2(0, -48), v2(0, -220) } },
	{ id = "SenderoCiudad", w = 8, mat = Mat.Ground, pts = { v2(44, 0), v2(150, -20), v2(240, -40) } },
	{
		id = "Carretera",
		w = 16,
		mat = Mat.Asphalt,
		pts = { v2(262, 110), v2(262, -80), v2(150, -170), v2(30, -212), v2(0, -220) },
	},
	{ id = "CalleTransversal", w = 12, mat = Mat.Asphalt, pts = { v2(262, 15), v2(400, 15) } },
	{
		id = "SenderoMina",
		w = 6,
		mat = Mat.Ground,
		pts = { v2(-44, 10), v2(-160, -10), v2(-300, -40), v2(-364, -40) },
	},
	{ id = "SubidaTorre", w = 6, mat = Mat.Ground, pts = { v2(-40, -110), v2(-104, -142) } },
	{
		id = "CarreteraNorte",
		w = 16,
		mat = Mat.Asphalt,
		pts = { v2(0, -304), v2(0, -370), v2(120, -400), v2(165, -430) },
	},
	{
		id = "SenderoAnomalo",
		w = 6,
		mat = Mat.Ground,
		pts = { v2(0, -370), v2(-40, -460), v2(-120, -540), v2(-230, -580) },
	},
	{
		id = "PistaServicio",
		w = 8,
		mat = Mat.Ground,
		pts = { v2(280, -550), v2(200, -630), v2(40, -670), v2(-120, -650), v2(-230, -600) },
	},
}
-- Caminos del territorio inicial sobre los que se reparte el bosque recolectable.
local FOREST_ROAD_IDS = { SenderoCiudad = true, Carretera = true, SenderoMina = true, SubidaTorre = true }

local RIVER: { Vector2 } =
	{ v2(-470, -265), v2(-300, -245), v2(-120, -270), v2(0, -262), v2(150, -250), v2(380, -285), v2(720, -260) }
local GORGE_CLEAR = 46 -- distancia al eje del rio a partir de la cual ya no hay garganta

local HILL = { c = v3(-120, -100, -150), r = 120 }
local MOUNTAINS = {
	{ c = v3(-737, -127, -40), r = 377, mat = Mat.Rock },
	{ c = v3(0, -300, -1010), r = 400, mat = Mat.Rock },
	{ c = v3(820, -300, 0), r = 400, mat = Mat.Rock },
	{ c = v3(0, -300, 640), r = 400, mat = Mat.Rock },
	{ c = v3(600, -250, -760), r = 330, mat = Mat.Slate },
	{ c = v3(600, -250, 360), r = 330, mat = Mat.Slate },
	{ c = v3(-640, -250, -760), r = 330, mat = Mat.Slate },
	{ c = v3(-600, -250, 360), r = 330, mat = Mat.Slate },
}
local MOUNDS: { Vector2 } = { v2(320, 80), v2(380, -30), v2(390, 70) }

-- Excavaciones de la mina (3.3): { centro, tamano }. Ancho de gateras y nicho 8: con celdas de 4 un hueco de 6 queda
-- con partes sin suelo.
local MINE: { { Vector3 } } = {
	{ v3(-402, 6, -40), v3(76, 12, 12) },
	{ v3(-412, 4, -48), v3(8, 8, 8) },
	{ v3(-460, 7, -40), v3(32, 14, 40) },
	{ v3(-460, 5, 0), v3(12, 10, 40) },
	{ v3(-496, 5, 20), v3(60, 10, 12) },
	{ v3(-540, 10, 20), v3(32, 20, 32) },
	{ v3(-540, 35, 20), v3(8, 30, 8) },
	{ v3(-518, 6, -40), v3(84, 12, 12) },
	{ v3(-580, 9, -60), v3(40, 18, 52) },
	{ v3(-540, 4, -8), v3(8, 8, 24) },
	{ v3(-560, 4, -20), v3(40, 8, 8) },
	{ v3(-580, 4, -28), v3(8, 8, 16) },
}
type Frame = { axis: string, c: number, from: number, to: number, step: number, w: number, h: number }
local MINE_FRAMES: { Frame } = {
	{ axis = "X", c = -40, from = -376, to = -436, step = -12, w = 12, h = 12 },
	{ axis = "X", c = -40, from = -488, to = -548, step = -12, w = 12, h = 12 },
	{ axis = "Z", c = -460, from = -8, to = 16, step = 12, w = 12, h = 10 },
	{ axis = "X", c = 20, from = -484, to = -516, step = -12, w = 12, h = 10 },
}

local CARS: { { number } } = {
	{ 252, -30, 0 },
	{ 258, 10, 8 },
	{ 266, 48, -6 },
	{ 258, 86, 4 },
	{ 266, -12, 180 },
	{ 258, -58, -4 },
	{ 262, -98, 0 },
	{ 214, -126, 38 },
}

-- Marcadores (secciones 4, 5.5, 6, 8, 10)
local PIECES = {
	{ id = "Bateria", pts = { v3(210, 0, -54), v3(218, 0, -14), v3(264, 0, -88) } },
	{ id = "Cristal", pts = { v3(-468, 0, -52), v3(-546, 0, 24), v3(-592, 0, -80) } },
	{ id = "Antena", pts = { v3(300, 24, -470), v3(220, 16, -500), v3(236, 0, -412) } },
	{ id = "Transceptor", pts = { v3(-306, 0, -576), v3(-320, -18, -596), v3(-296, -40, -626) } },
}
local LOOT = {
	{ zone = "Base", pts = { v3(6, 0, -4) } },
	{ zone = "Ciudad", pts = { v3(226, 0, -46), v3(214, 0, -22), v3(252, 0, -36) } },
	{ zone = "Mina", pts = { v3(-410, 0, -46), v3(-452, 0, -28), v3(-532, 0, 12) } },
	{ zone = "Industrial", pts = { v3(216, 0, -496), v3(290, 0, -480), v3(360, 0, -420) } },
	{ zone = "Complejo", pts = { v3(-226, 0, -560), v3(-286, 0, -570), v3(-300, -18, -610) } },
}
local HIDEOUTS = {
	{ id = "Ciudad_Almacen", pos = v3(210, 0, -54) },
	{ id = "Ciudad_Taller", pos = v3(220, 0, -18) },
	{ id = "Matorral_Este", pos = v3(70, 0, -60) },
	{ id = "Matorral_Oeste", pos = v3(-80, 0, 60) },
	{ id = "Torre_Caseta", pos = v3(-104, 20, -142) },
	{ id = "Mina_Nicho", pos = v3(-410, 0, -46) },
	{ id = "Industrial_Oficinas", pos = v3(216, 0, -500) },
	{ id = "Complejo_Garita", pos = v3(-226, 0, -560) },
	{ id = "Complejo_Generadores", pos = v3(-340, 0, -530) },
}
local ENEMIES = {
	{ id = "CriaturaPrincipal_01", kind = "CriaturaPrincipal", pos = v3(-310, -40, -645) },
	{ id = "AcechadorMenor_01", kind = "AcechadorMenor", pos = v3(-40, 0, -640) },
	{ id = "AcechadorMenor_02", kind = "AcechadorMenor", pos = v3(60, 0, -600) },
	{ id = "AcechadorMenor_03", kind = "AcechadorMenor", pos = v3(-100, 0, -560) },
}
local NEST = { pos = v3(-310, -31, -640), size = v3(50, 18, 40) }
type Patrol = { id: string, ys: { number }?, pts: { Vector2 } }
local PATROLS: { Patrol } = {
	{
		id = "Bosque",
		pts = { v2(0, -125), v2(110, -90), v2(120, 70), v2(40, 140), v2(-90, 130), v2(-150, 10), v2(-110, -100) },
	},
	{
		id = "Exterior",
		pts = { v2(0, -200), v2(180, -160), v2(262, -40), v2(200, 110), v2(-120, 130), v2(-300, -20), v2(-200, -200) },
	},
	{
		id = "Mina",
		ys = { 0, 0, 0, 0, 0 },
		pts = { v2(-390, -40), v2(-460, -40), v2(-540, 20), v2(-560, -20), v2(-580, -60) },
	},
	{
		id = "Complejo",
		ys = { -40, -40, -18, 0 },
		pts = { v2(-310, -645), v2(-300, -650), v2(-300, -600), v2(-300, -585), v2(-230, -580), v2(-120, -540) },
	},
	{
		id = "BosqueAnomalo",
		pts = { v2(0, -440), v2(90, -500), v2(100, -620), v2(0, -680), v2(-110, -640), v2(-120, -500) },
	},
}
local NOBUILD = {
	{ id = "Caseta", pos = v3(0, 5, 0), size = v3(24, 12, 20) },
	{ id = "PuertaCaseta", pos = v3(0, 5, 12), size = v3(8, 12, 12) },
	{ id = "Fogata", pos = v3(0, 5, 18), size = v3(12, 12, 12) },
	{ id = "BaseSpawn", pos = v3(-8, 5, 18), size = v3(16, 12, 16) },
}
local BUILD_ZONE = { pos = v3(0, 0, 0), size = v3(96, 8, 96) }
type Anomaly = {
	id: string,
	pos: Vector3,
	size: Vector3,
	i: number,
	fog: boolean,
	em: boolean,
	audio: boolean,
	prop: boolean,
}
local ANOMALIES: { Anomaly } = {
	{
		id = "BosqueAnomalo",
		pos = v3(0, 20, -560),
		size = v3(300, 60, 300),
		i = 1,
		fog = true,
		em = true,
		audio = true,
		prop = false,
	},
	{
		id = "Complejo",
		pos = v3(-300, 5, -580),
		size = v3(160, 90, 160),
		i = 0.8,
		fog = false,
		em = true,
		audio = true,
		prop = false,
	},
	{
		id = "PuenteNorte",
		pos = v3(0, 10, -330),
		size = v3(120, 40, 60),
		i = 0.3,
		fog = true,
		em = false,
		audio = true,
		prop = true,
	},
	{
		id = "PuenteSur",
		pos = v3(0, 10, -200),
		size = v3(120, 40, 60),
		i = 0,
		fog = true,
		em = false,
		audio = true,
		prop = true,
	},
}
local CROSSINGS = {
	{ id = "Oeste", sur = v2(-230, -232), norte = v2(-230, -298) },
	{ id = "Centro", sur = v2(90, -226), norte = v2(90, -292) },
	{ id = "Este", sur = v2(300, -245), norte = v2(300, -310) },
}
type Lore = { id: string, act: number, zone: string, pos: Vector3 }
local LORE: { Lore } = {
	{ id = "A1-01", act = 1, zone = "Ciudad", pos = v3(262, 0, -60) },
	{ id = "A1-02", act = 1, zone = "Ciudad", pos = v3(234, 0, -40) },
	{ id = "A1-03", act = 1, zone = "Bosque", pos = v3(0, 0, -205) },
	{ id = "A1-04", act = 1, zone = "Mina", pos = v3(-350, 0, -10) },
	{ id = "A1-05", act = 1, zone = "Torre", pos = v3(-104, 20, -142) },
	{ id = "A2-01", act = 2, zone = "Industrial", pos = v3(360, 0, -420) },
	{ id = "A2-02", act = 2, zone = "Industrial", pos = v3(330, 0, -560) },
	{ id = "A2-03", act = 2, zone = "BosqueAnomalo", pos = v3(0, 0, -520) },
	{ id = "A2-04", act = 2, zone = "BosqueAnomalo", pos = v3(70, 0, -480) },
	{ id = "A2-05", act = 2, zone = "BosqueAnomalo", pos = v3(-40, 0, -460) },
	{ id = "A2-06", act = 2, zone = "Complejo", pos = v3(-320, 0, -580) },
	{ id = "A2-07", act = 2, zone = "Complejo", pos = v3(-306, 0, -576) },
	{ id = "A2-08", act = 2, zone = "Complejo", pos = v3(-300, -18, -610) },
}
local SENSORS: { Vector2 } = { v2(-60, -470), v2(70, -480), v2(60, -640), v2(-80, -630) }
local CAMP = v2(0, -520)

-- Recursos (7): lo que se reparte y como. Total 68 Arbol / 42 Roca.
type ResEntry = { zone: string, kind: string, n: number, s: string, rock: boolean? }
local RES_PLAN: { ResEntry } = {
	{ zone = "Base", kind = "Arbol", n = 16, s = "BaseRing" },
	{ zone = "Base", kind = "Roca", n = 6, s = "BaseRing" },
	{ zone = "Bosque", kind = "Arbol", n = 30, s = "BosqueRoad" },
	{ zone = "Bosque", kind = "Roca", n = 6, s = "BosqueRoad" },
	{ zone = "Ciudad", kind = "Arbol", n = 4, s = "CiudadBox" },
	{ zone = "Ciudad", kind = "Roca", n = 6, s = "Escombros", rock = true },
	{ zone = "Torre", kind = "Arbol", n = 4, s = "TorrePie" },
	{ zone = "Torre", kind = "Roca", n = 4, s = "Afloramiento", rock = true },
	{ zone = "Mina", kind = "Roca", n = 4, s = "MinaEntrada" },
	{ zone = "Mina", kind = "Roca", n = 8, s = "MinaInterior" },
	{ zone = "Industrial", kind = "Arbol", n = 2, s = "Industrial" },
	{ zone = "Industrial", kind = "Roca", n = 4, s = "Industrial" },
	{ zone = "BosqueAnomalo", kind = "Arbol", n = 12, s = "SenderoAnomalo" },
	{ zone = "BosqueAnomalo", kind = "Roca", n = 2, s = "SenderoAnomalo" },
	{ zone = "Complejo", kind = "Roca", n = 2, s = "Complejo" },
}
local ZONE_STRICT = { Bosque = true, Ciudad = true, Industrial = true, BosqueAnomalo = true, Complejo = true }
local MINA_ROCKS: { Vector2 } = {
	v2(-470, -32),
	v2(-448, -52),
	v2(-552, 30),
	v2(-528, 28),
	v2(-570, -52),
	v2(-590, -62),
	v2(-572, -76),
	v2(-594, -42),
}

local EXPECTED = {
	{ "MapZone", 7 },
	{ "PieceSpawn", 12 },
	{ "ResourceSpawn", 110 },
	{ "LootSpawn", 13 },
	{ "EnemySpawn", 4 },
	{ "Nest", 1 },
	{ "WaterZone", 6 },
	{ "BuildZone", 1 },
	{ "NoBuildZone", 4 },
	{ "PatrolPoint", 31 },
	{ "Hideout", 9 },
	{ "BridgeSite", 1 },
	{ "BridgeEnd", 2 },
	{ "CreatureCrossing", 6 },
	{ "AnomalyZone", 4 },
	{ "LorePoint", 13 },
}

-- Zonas donde no se pone ningun nodo de recurso ni arbol: edificios, NoBuildZones y BuildZone.
local BLOCKED: { Rect } = {
	rect(0, 0, 96, 96),
	rect(220, -50, 28, 18),
	rect(220, -18, 14, 14),
	rect(246, -30, 24, 16),
	rect(300, -60, 30, 24),
	rect(300, -10, 24, 30),
	rect(300, 45, 30, 24),
	rect(350, -60, 26, 26),
	rect(355, -10, 30, 30),
	rect(350, 55, 24, 24),
	rect(-120, -150, 16, 16),
	rect(-104, -142, 12, 12),
	rect(-350, -10, 18, 18),
	rect(0, -262, 30, 100),
	rect(0, -205, 40, 24),
	rect(300, -470, 64, 44),
	rect(220, -500, 28, 24),
	rect(230, -410, 44, 28),
	rect(300, -435, 52, 32),
	rect(360, -420, 62, 70),
	rect(340, -520, 8, 8),
	rect(-300, -580, 44, 34),
	rect(-340, -530, 20, 16),
	rect(-226, -560, 10, 10),
	rect(-260, -630, 14, 14),
	rect(-350, -630, 12, 12),
	rect(-290, -606, 14, 38),
	rect(CAMP.X, CAMP.Y, 34, 34),
	rect(-60, -480, 12, 18),
}
for _, n in NOBUILD do
	table.insert(BLOCKED, rect(n.pos.X, n.pos.Z, n.size.X, n.size.Z))
end
for _, s in SENSORS do
	table.insert(BLOCKED, rect(s.X, s.Y, 6, 6))
end

--------------------------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------------------------

local function rngFor(section: string): Random
	return Random.new(BASE_SEED + (table.find(SECTIONS, section) or 1))
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

local function box(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: Color3,
	material: Enum.Material?
): Part
	return part(parent, name, CFrame.new(x, y, z), v3(sx, sy, sz), color, material)
end

local function ball(
	parent: Instance,
	name: string,
	pos: Vector3,
	d: number,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(parent, name, CFrame.new(pos), v3(d, d, d), color, material)
	p.Shape = Enum.PartType.Ball
	p.CanCollide = false
	return p
end

local function cylinder(parent: Instance, name: string, base: Vector3, h: number, d: number, color: Color3): Part
	local p =
		part(parent, name, CFrame.new(base + v3(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), v3(h, d, d), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Cilindro inclinado: de base a base + dir * len (dir unitario).
local function tiltedCyl(
	parent: Instance,
	name: string,
	base: Vector3,
	dir: Vector3,
	len: number,
	d: number,
	color: Color3
): Part
	local cf = CFrame.lookAt(base + dir * (len / 2), base + dir * len) * CFrame.Angles(0, math.pi / 2, 0)
	local p = part(parent, name, cf, v3(len, d, d), color)
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

-- Losa horizontal (cara superior en top, grosor th) con un hueco rectangular opcional.
local function slab(parent: Instance, name: string, r: Rect, top: number, th: number, color: Color3, hole: Rect?)
	local function piece(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 > 0.01 and z1 - z0 > 0.01 then
			box(parent, name, (x0 + x1) / 2, top - th / 2, (z0 + z1) / 2, x1 - x0, th, z1 - z0, color)
		end
	end
	if not hole then
		piece(r.x0, r.x1, r.z0, r.z1)
		return
	end
	piece(r.x0, hole.x0, r.z0, r.z1)
	piece(hole.x1, r.x1, r.z0, r.z1)
	piece(hole.x0, hole.x1, r.z0, hole.z0)
	piece(hole.x0, hole.x1, hole.z1, r.z1)
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

local function car(parent: Instance, name: string, x: number, z: number, yaw: number, color: Color3?)
	local m = model(parent, name)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local col = color or C.Black
	part(m, "Carroceria", cf * CFrame.new(0, 1.75, 0), v3(6, 3.5, 12), col)
	part(m, "Cabina", cf * CFrame.new(0, 4.25, -0.5), v3(5, 1.5, 6), col)
end

local function barricada(parent: Instance, x: number, z: number, yaw: number)
	local m = model(parent, "Barricada")
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, dx in { -6.5, 6.5 } do
		part(m, "Bloque", cf * CFrame.new(dx, 1.25, 0), v3(6, 2.5, 1.5), C.Grey, Mat.Concrete)
	end
	for i = 1, 5 do
		part(m, "Saco", cf * CFrame.new(-8 + i * 2.6, 0.6, 2.2), v3(2.2, 1.2, 1.6), C.Bark)
	end
end

local function tent(parent: Instance, x: number, z: number, yaw: number)
	local m = model(parent, "Tienda")
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, s in { -1, 1 } do
		part(
			m,
			"Panel",
			cf * CFrame.new(s * 1.7, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-s * 40)),
			v3(0.3, 4.4, 7),
			C.Canvas
		)
	end
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
	return HILL.c.Y + math.sqrt(math.max(HILL.r ^ 2 - (x - HILL.c.X) ^ 2 - (z - HILL.c.Z) ^ 2, 0))
end

local function polar(rng: Random, center: Vector2, r0: number, r1: number): Vector2
	local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(r0, r1)
	return center + v2(math.cos(a) * r, math.sin(a) * r)
end

-- Afloramientos de roca sobre la loma de la torre (terreno y rocas recolectables).
local function outcrops(): { Vector2 }
	local rng = rngFor("Terreno")
	local hc = v2(HILL.c.X, HILL.c.Z)
	local out: { Vector2 } = {}
	local tries = 0
	while #out < 6 and tries < 1000 do
		tries += 1
		local p = polar(rng, hc, 30, 48)
		local ok = not nearRoad(p, 8) and (p - v2(-104, -142)).Magnitude > 14
		for _, q in out do
			ok = ok and (p - q).Magnitude >= 20
		end
		if ok then
			table.insert(out, p)
		end
	end
	return out
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

-- Terrain + Map sin Bosque/Limites/Zones (para marcadores sobre edificios, suelos de sotano, etc.)
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
-- Los marcadores de estos tags se ajustan a la superficie real (suelos de mina, azoteas) si estan a menos de 3.
local SNAP_TAGS =
	{ PieceSpawn = true, ResourceSpawn = true, LootSpawn = true, EnemySpawn = true, Hideout = true, LorePoint = true }
local snapParams: RaycastParams? = nil
local function spot(parent: Instance, name: string, ground: Vector3, tag: string?, attrs: { [string]: any }?): Part
	local g = ground
	if tag and SNAP_TAGS[tag] and snapParams then
		local hit = cast(g.X, g.Z, g.Y + 6, snapParams :: RaycastParams)
		if hit and math.abs(hit.Position.Y - g.Y) <= 3 then
			g = v3(g.X, hit.Position.Y, g.Z)
		end
	end
	return mk(parent, name, CFrame.new(g + v3(0, 0.5, 0)), v3(2, 1, 2), tag, attrs)
end

--------------------------------------------------------------------------------------------------
-- PLAN DE RECURSOS (7). Determinista; solo consulta Terrain. Lo usan los arboles y Marcadores.
--------------------------------------------------------------------------------------------------

type Node = { kind: string, zone: string, pos: Vector3 }

local forestRoads: { Road } = {}
for _, r in ROADS do
	if FOREST_ROAD_IDS[r.id] then
		table.insert(forestRoads, r)
	end
end
local ROAD_BY_ID: { [string]: Road } = {}
for _, r in ROADS do
	ROAD_BY_ID[r.id] = r
end

local function alongRoad(rng: Random, r: Road, o0: number, o1: number): Vector2
	local i = rng:NextInteger(1, #r.pts - 1)
	local a, b = r.pts[i], r.pts[i + 1]
	local n = (b - a).Unit
	local off = rng:NextNumber(math.max(o0, r.w / 2 + 2), o1) * (if rng:NextNumber() < 0.5 then -1 else 1)
	return a:Lerp(b, rng:NextNumber()) + v2(-n.Y, n.X) * off
end

local function inBox(rng: Random, r: Rect): Vector2
	return v2(rng:NextNumber(r.x0, r.x1), rng:NextNumber(r.z0, r.z1))
end

local SAMPLERS: { [string]: (Random, number) -> (Vector2, number?) } = {
	BaseRing = function(rng)
		return polar(rng, v2(0, 0), 56, 96)
	end,
	BosqueRoad = function(rng)
		return alongRoad(rng, forestRoads[rng:NextInteger(1, #forestRoads)], 8, 20)
	end,
	CiudadBox = function(rng)
		return inBox(rng, { x0 = 192, z0 = -98, x1 = 408, z1 = 98 })
	end,
	Escombros = function(rng, placed)
		return polar(rng, MOUNDS[placed % #MOUNDS + 1], 0, 8)
	end,
	TorrePie = function(rng)
		return polar(rng, v2(HILL.c.X, HILL.c.Z), 56, 66)
	end,
	Afloramiento = function(_, placed)
		return outcrops()[placed + 1] or v2(0, 0)
	end,
	MinaEntrada = function(rng)
		return v2(
			-360 + rng:NextNumber(-8, 4),
			-40 + rng:NextNumber(14, 28) * (if rng:NextNumber() < 0.5 then -1 else 1)
		)
	end,
	MinaInterior = function(_, placed)
		return MINA_ROCKS[placed + 1] or v2(0, 0), 0
	end,
	Industrial = function(rng)
		return inBox(rng, { x0 = 168, z0 = -540, x1 = 200, z1 = -440 })
	end,
	SenderoAnomalo = function(rng)
		return alongRoad(rng, ROAD_BY_ID.SenderoAnomalo, 8, 16)
	end,
	Complejo = function(rng)
		return inBox(rng, { x0 = -365, z0 = -645, x1 = -235, z1 = -515 })
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
	for _, h in HIDEOUTS do
		add(h.pos)
	end
	for _, l in LORE do
		add(l.pos)
	end
	return out
end

local function nodeAt(e: ResEntry, p: Vector2, fixedY: number?, out: { Node }, avoid: { Vector2 }): Vector3?
	if p.X < PLAY.x0 or p.X > PLAY.x1 or p.Y < PLAY.z0 or p.Y > PLAY.z1 then
		return nil
	end
	if nearRoad(p, 6) or polyDist(p, RIVER) < GORGE_CLEAR then
		return nil
	end
	if e.kind == "Arbol" and math.abs(p.X) < 12 and p.Y < -48 and p.Y > -220 then
		return nil
	end
	if ZONE_STRICT[e.zone] and zoneOf(p.X, p.Y) ~= e.zone then
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

local avoidCache: { Vector2 }? = nil
-- Cerca de un nodo de recurso o de cualquier marcador puntual (para arboles y hongos).
local function nearMarker(p: Vector2, dist: number): boolean
	for _, n in planResources() do
		if (v2(n.pos.X, n.pos.Z) - p).Magnitude < dist then
			return true
		end
	end
	avoidCache = avoidCache or avoidPoints()
	for _, a in avoidCache :: { Vector2 } do
		if (a - p).Magnitude < dist - 2 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------------------------
-- SECCIONES
--------------------------------------------------------------------------------------------------

local function terrenoA()
	for x = -720, 719, 200 do
		for z = -800, 399, 200 do
			local w, d = math.min(200, 720 - x), math.min(200, 400 - z)
			fillBlock(CFrame.new(x + w / 2, -24, z + d / 2), v3(w, 48, d), Mat.Grass)
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
	for _, m in MOUNDS do
		fillBall(v3(m.X, 2, m.Y), 13, Mat.Rock)
		fillBall(v3(m.X + 10, 0, m.Y + 6), 9, Mat.Rock)
		fillBall(v3(m.X - 9, 0, m.Y - 7), 8, Mat.Rock)
	end
	task.wait()
end

-- Garganta del rio (2.1): canal de 40 con talud sur transitable y pared norte casi vertical de roca.
local function garganta()
	local frames: { { cf: CFrame, len: number } } = {}
	for i = 1, #RIVER - 1 do
		local a, b = RIVER[i], RIVER[i + 1]
		local mid = (a + b) / 2
		local m3 = v3(mid.X, 0, mid.Y)
		table.insert(frames, { cf = CFrame.lookAt(m3, m3 + v3(b.X - a.X, 0, b.Y - a.Y)), len = (b - a).Magnitude + 12 })
	end
	-- Aire del canal (Y -26..12), luego talud sur (cuña de aire Y -14..0), banda de roca norte, barro y agua.
	for _, f in frames do
		fillBlock(f.cf * CFrame.new(0, -7, 0), v3(40, 38, f.len), Mat.Air)
	end
	for _, f in frames do
		local w = f.cf * CFrame.new(28, -7, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0)
		fillWedge(w, v3(f.len, 14, 16), Mat.Air)
	end
	task.wait()
	for _, f in frames do
		fillBlock(f.cf * CFrame.new(-24, -14, 0), v3(8, 28, f.len), Mat.Rock)
	end
	for _, f in frames do
		fillBlock(f.cf * CFrame.new(0, -26, 0), v3(40, 4, f.len), Mat.Mud)
	end
	for _, f in frames do
		fillBlock(f.cf * CFrame.new(0, -17, 0), v3(40, 10, f.len), Mat.Water)
	end
	task.wait()
end

local function terrenoB()
	garganta()
	for _, e in MINE do
		local c, s = e[1], e[2]
		hollow(c.X, c.Z, s.X, s.Z, c.Y - s.Y / 2, c.Y + s.Y / 2 + 4)
	end
	task.wait()
	-- Sotanos del complejo (3.6): suelos Y -18 y -40; el aire llega justo al techo de los forros.
	-- Los suelos van 2 por debajo del forro de Parts para que el pasto del Terrain no asome.
	hollow(-300, -600, 60, 48, -20, -6)
	hollow(-290, -606, 8, 32, -21, 5)
	hollow(-320, -636, 8, 40, -42, -10)
	hollow(-300, -650, 60, 12, -42, -24)
	hollow(-310, -640, 50, 40, -42, -18)
	-- Sin Grass bajo tierra: el pasto decorativo asomaria por los suelos.
	local ug = Region3.new(v3(-344, -52, -676), v3(-256, -2, -568)):ExpandToGrid(4)
	Terrain:ReplaceMaterial(ug, 4, Mat.Grass, Mat.Slate)
end

local function terreno(_map: Folder)
	terrenoA()
	terrenoB()
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
	fresh(map, "Caminos")
end

local function baseZone(map: Folder)
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

local function ciudad(map: Folder)
	local f = fresh(map, "Ciudad")
	local gas = model(f, "Gasolinera")
	local tienda = building(gas, "Tienda", 220, 0, -50, 28, 18, 10, { roof = true, gaps = { E = { { 7, 11, 0, 7 } } } })
	wall(tienda, "Tabique", v2(214, -59), v2(214, -41), 0, 10, 0.8, { { 7, 11, 0, 7 } }, C.Grey)
	for i, x in { 217, 220.5, 224 } do
		part(tienda, "Estanteria_" .. i, CFrame.new(x, 2.5, -50), v3(1.5, 5, 12), C.Dark)
	end
	part(tienda, "Mostrador", CFrame.new(230, 1.5, -46), v3(2, 3, 6), C.Dark)
	local taller = building(gas, "Taller", 220, 0, -18, 14, 14, 10, { roof = true, gaps = { E = { { 3, 11, 0, 7 } } } })
	part(taller, "Banco", CFrame.new(217, 1.5, -19), v3(2, 3, 6), C.Brown)
	local mq = model(gas, "Marquesina")
	part(mq, "Techo", CFrame.new(246, 12, -30), v3(24, 1, 16), C.Dark)
	for i, c in { v2(236, -36), v2(256, -36), v2(236, -24), v2(256, -24) } do
		part(mq, "Columna_" .. i, CFrame.new(c.X, 5.75, c.Y), v3(1.5, 11.5, 1.5), C.Grey)
	end
	local sur = model(gas, "Surtidores")
	for i, z in { -34, -26 } do
		part(sur, "Surtidor_" .. i, CFrame.new(246, 2.5, z), v3(2, 5, 1.5), C.Black)
	end

	local edif = folder(f, "Edificios")
	local E_W, E_S, E_N = "W", "S", "N"
	local defs: { { any } } = {
		{ 300, -60, 30, 24, 18, E_W, 10 },
		{ 300, -10, 24, 30, 14, E_W, 13 },
		{ 300, 45, 30, 24, 22, E_W, 10 },
		{ 350, -60, 26, 26, 12, E_W, 10 },
		{ 355, -10, 30, 30, 26, E_S, 13 },
		{ 350, 55, 24, 24, 14, E_N, 10 },
	}
	for i, d in defs do
		local gaps: { [string]: { Gap } } = { [d[6] :: string] = { { d[7] :: number, (d[7] :: number) + 4, 0, 7 } } }
		building(edif, "Edificio_" .. i, d[1], 0, d[2], d[3], d[4], d[5], { roof = true, gaps = gaps })
	end
	local coches = folder(f, "Coches")
	for i, c in CARS do
		car(coches, "Coche_" .. i, c[1], c[2], c[3])
	end
	local barr = folder(f, "Barricadas")
	barricada(barr, 262, -85, 0)
	barricada(barr, 330, 15, 90)
	local tab = model(f, "Tablon")
	part(tab, "Hoja", CFrame.new(234, 2.5, -40), v3(4, 3, 0.5), C.Grey)
	for _, dx in { -1.6, 1.6 } do
		part(tab, "Poste", CFrame.new(234 + dx, 0.6, -40), v3(0.4, 1.2, 0.4), C.Brown)
	end
	local esc = folder(f, "Escombros")
	local rng = rngFor("Ciudad")
	for _, m in MOUNDS do
		for i = 1, 3 do
			local p = polar(rng, m, 8, 16)
			local hit = cast(p.X, p.Y, nil, terrainParams(false))
			local y = if hit then hit.Position.Y else 0
			part(
				esc,
				"Losa_" .. i,
				CFrame.new(p.X, y + 1, p.Y)
					* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
				v3(rng:NextNumber(3, 5), 1.2, rng:NextNumber(4, 7)),
				C.Grey,
				Mat.Concrete
			)
		end
	end
end

local function torre(map: Folder)
	local f = fresh(map, "Torre")
	local m = model(f, "Torre")
	local cx, cz = -120, -150
	local corners = { v2(cx - 5, cz - 5), v2(cx + 5, cz - 5), v2(cx + 5, cz + 5), v2(cx - 5, cz + 5) }
	for i, c in corners do
		local n = corners[i % 4 + 1]
		part(m, "Pata", CFrame.new(c.X, 35, c.Y), v3(1.5, 30, 1.5), C.Dark)
		for _, y in { 20, 35 } do
			beam(m, v3(c.X, y, c.Y), v3(n.X, y + 15, n.Y), 0.5, C.Dark)
			beam(m, v3(n.X, y, n.Y), v3(c.X, y + 15, c.Y), 0.5, C.Dark)
		end
		beam(m, v3(c.X, 35, c.Y), v3(n.X, 35, n.Y), 0.6, C.Dark)
		part(m, "PosteCabina", CFrame.new(cx + (c.X - cx) * 1.35, 54, cz + (c.Y - cz) * 1.35), v3(0.5, 8, 0.5), C.Dark)
	end
	part(m, "CabinaSuelo", CFrame.new(cx, 49.5, cz), v3(14, 1, 14), C.Grey)
	building(m, "Barandilla", cx, 50, cz, 14, 14, 3, { th = 0.4, color = C.Dark, gaps = { S = { { 5, 9, 0, 3 } } } })
	part(m, "TechoCabina", CFrame.new(cx, 58.5, cz), v3(14.5, 1, 14.5), C.Dark)
	truss(m, v3(cx, 36, cz + 8.5), 32)
	part(m, "Banco", CFrame.new(cx, 51, cz - 5), v3(6, 2, 1.5), C.Brown)
	local cas = building(f, "CasetaHerramientas", -104, 20, -142, 8, 8, 7, {
		roof = true,
		floor = 3,
		gaps = { S = { { 2, 6, 0, 6 } } },
	})
	part(cas, "Mesa", CFrame.new(-104, 21.25, -145), v3(5, 2.5, 1.5), C.Brown)
	part(cas, "Mapa", CFrame.new(-104, 22.7, -145), v3(2.5, 0.2, 1.2), C.Crystal)
end

local function mina(map: Folder)
	local f = fresh(map, "Mina")
	local sup = folder(f, "Soportes")
	for _, e in MINE_FRAMES do
		local hw = e.w / 2 - 0.4
		local t = e.from
		while (e.step < 0 and t >= e.to) or (e.step > 0 and t <= e.to) do
			local function at(off: number, y: number): Vector3
				return if e.axis == "Z" then v3(e.c + off, y, t) else v3(t, y, e.c + off)
			end
			part(sup, "Poste", CFrame.new(at(-hw, (e.h - 0.5) / 2)), v3(0.8, e.h - 0.5, 0.8), C.Brown)
			part(sup, "Poste", CFrame.new(at(hw, (e.h - 0.5) / 2)), v3(0.8, e.h - 0.5, 0.8), C.Brown)
			local bsize = if e.axis == "Z" then v3(e.w, 0.8, 0.8) else v3(0.8, 0.8, e.w)
			part(sup, "Viga", CFrame.new(at(0, e.h - 0.4)), bsize, C.Brown)
			t += e.step
		end
	end
	local portal = model(f, "Portal")
	part(portal, "Poste_N", CFrame.new(-381, 7, -46.5), v3(1.5, 14, 1.5), C.Brown)
	part(portal, "Poste_S", CFrame.new(-381, 7, -33.5), v3(1.5, 14, 1.5), C.Brown)
	part(portal, "Dintel", CFrame.new(-381, 14.25, -40), v3(1.5, 1.5, 16), C.Brown)
	local rieles = folder(f, "Rieles")
	for _, z in { -41.5, -38.5 } do
		part(rieles, "Riel", CFrame.new(-457, 0.5, z), v3(34, 0.4, 0.4), C.Dark)
	end
	for x = -442, -472, -3 do
		part(rieles, "Traviesa", CFrame.new(x, 0.15, -40), v3(0.6, 0.3, 4), C.Bark)
	end
	local vag = model(f, "Vagoneta")
	part(vag, "Caja", CFrame.new(-468, 1.7, -40), v3(5, 2, 4), C.Dark)
	for _, dx in { -1.6, 1.6 } do
		for _, dz in { -2.1, 2.1 } do
			local w = part(vag, "Rueda", CFrame.new(-468 + dx, 0.6, -40 + dz), v3(1.2, 1.2, 0.4), C.Black)
			w.Shape = Enum.PartType.Cylinder
			w.CFrame = CFrame.new(-468 + dx, 0.6, -40 + dz) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end
	local vetas = folder(f, "Vetas")
	local rng = rngFor("Mina")
	for i = 1, 12 do
		local x, z = rng:NextNumber(-598, -562), rng:NextNumber(-84, -36)
		local p = part(
			vetas,
			"Veta_" .. i,
			CFrame.new(x, 2.5, z)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
			v3(rng:NextNumber(0.8, 1.4), rng:NextNumber(3, 6), rng:NextNumber(0.8, 1.4)),
			C.Crystal,
			Mat.Glass
		)
		p.Transparency = 0.35
		p.CanCollide = false
	end
	local camp = model(f, "Campamento")
	building(camp, "Caseta", -350, 0, -10, 8, 8, 7, { roof = true, gaps = { W = { { 2, 6, 0, 6 } } }, color = C.Brown })
	for i, p in { v3(-342, 1, -2), v3(-341, 1, -5), v3(-358, 1, 0) } do
		part(camp, "Caja_" .. i, CFrame.new(p), v3(2, 2, 2), C.Brown)
	end
	part(camp, "Carretilla", CFrame.new(-356, 0.8, -18) * CFrame.Angles(0, 0.5, 0), v3(2, 1.2, 3.5), C.Dark)
end

-- Barrera invisible del rio (2.1): sigue el borde norte de X -720 a 720 con un hueco de 14 en el eje del puente.
local function rio(map: Folder)
	local f = fresh(map, "Rio")
	local pts: { Vector2 } = { v2(-720, RIVER[1].Y), table.unpack(RIVER) }
	local n = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = (b - a).Unit
		local off = v2(d.Y, -d.X) * 22
		local a2, b2 = a + off, b + off
		local function piece(xa: number, xb: number, extA: boolean, extB: boolean)
			if xb - xa < 0.5 then
				return
			end
			local t0, t1 = (xa - a2.X) / (b2.X - a2.X), (xb - a2.X) / (b2.X - a2.X)
			local p0, p1 = a2:Lerp(b2, t0) - d * (if extA then 3 else 0), a2:Lerp(b2, t1) + d * (if extB then 3 else 0)
			local mid = (p0 + p1) / 2
			local pos = v3(mid.X, 135, mid.Y)
			n += 1
			local p = part(
				f,
				string.format("Barrera_%02d", n),
				CFrame.lookAt(pos, pos + v3(d.X, 0, d.Y)),
				v3(2, 330, (p1 - p0).Magnitude),
				C.Dark
			)
			p.Transparency = 1
			p.CanQuery = false
			p.CanTouch = false
			CollectionService:AddTag(p, "PlayerBarrier")
		end
		if a2.X < -7 and b2.X > 7 then
			piece(a2.X, -7, true, false)
			piece(7, b2.X, false, true)
		elseif b2.X <= -7 or a2.X >= 7 then
			piece(a2.X, b2.X, true, true)
		elseif a2.X < -7 then
			piece(a2.X, -7, true, false)
		else
			piece(7, b2.X, false, true)
		end
	end
end

local function puente(map: Folder)
	local f = fresh(map, "Puente")
	f:SetAttribute("BridgeBuilt", false)
	local roto = folder(f, "Roto")
	local conc = Mat.Concrete
	box(roto, "Estribo_Sur", 0, 0, -226, 14, 2, 12, C.Grey, conc)
	box(roto, "Relleno_Sur", 0, -4, -229, 14, 8, 6, C.Dark, conc)
	box(roto, "Estribo_Norte", 0, 0, -298, 14, 2, 12, C.Grey, conc)
	box(roto, "Tramo_Sur", 0, 0.5, -239, 10, 1, 14, C.Grey, conc)
	box(roto, "Tramo_Norte", 0, 0.5, -285, 10, 1, 14, C.Grey, conc)
	-- bordes quebrados
	for i, d in { { -3, -246.5, 0.2 }, { 1.5, -247.5, -0.3 }, { 4, -246.8, 0.4 } } do
		part(
			roto,
			"BordeSur_" .. i,
			CFrame.new(d[1], 0.3, d[2]) * CFrame.Angles(d[3], d[3] * 3, 0),
			v3(3, 0.8, 2),
			C.Grey,
			conc
		)
	end
	for i, d in { { -3.5, -277.5, -0.2 }, { 1, -278.5, 0.3 }, { 4, -277.4, -0.4 } } do
		part(
			roto,
			"BordeNorte_" .. i,
			CFrame.new(d[1], 0.3, d[2]) * CFrame.Angles(d[3], d[3] * 3, 0),
			v3(3, 0.8, 2),
			C.Grey,
			conc
		)
	end
	-- pilares rotos: cima en Y -9, bajo la calzada
	for i, z in { -254, -270 } do
		box(roto, "Pilar_" .. i, 0, -16.5, z, 6, 15, 6, C.Dark, conc)
		part(roto, "PilarRoto_" .. i, CFrame.new(1, -9, z) * CFrame.Angles(0.3, 0.4, 0.2), v3(3, 1.5, 3), C.Dark, conc)
	end
	-- escombros: losas inclinadas, cima por debajo de Y -10
	for i, d in { { 3, -12.5, -250, 0.5 }, { -2, -13.5, -258, -0.4 }, { 2, -13, -266, 0.3 }, { -3, -12.8, -274, -0.5 } } do
		part(
			roto,
			"Escombro_" .. i,
			CFrame.new(d[1], d[2], d[3]) * CFrame.Angles(d[4], d[4] * 2, d[4]),
			v3(7, 1.2, 6),
			C.Grey,
			conc
		)
	end
	-- control militar en la cabecera sur (deja libre el paso de 6 en el eje)
	local mil = model(f, "ControlMilitar")
	for _, s in { -1, 1 } do
		for i = 0, 1 do
			part(mil, "Bloque", CFrame.new(s * (6 + i * 6.5), 1.25, -205), v3(6, 2.5, 1.5), C.Grey, conc)
		end
		for i = 1, 4 do
			part(mil, "Saco", CFrame.new(s * (5 + i * 2.2), 0.6, -202.5), v3(2.2, 1.2, 1.6), C.Bark)
		end
	end
	car(mil, "VehiculoVolcado", 12, -208, 25, C.Canvas)
	local volc = mil:FindFirstChild("VehiculoVolcado") :: Model
	volc:PivotTo(volc:GetPivot() * CFrame.Angles(0, 0, math.rad(95)) + v3(0, 2, 0))

	-- variante construida (no queda en Workspace)
	local variants = fresh(ServerStorage, "MapVariants")
	local pc = model(variants, "PuenteConstruido")
	for i = 0, 7 do
		local col = if i % 2 == 0 then C.Brown else Color3.fromRGB(96, 68, 48)
		box(pc, "Tablon", 0, 0.5, -248 - i * 4, 10, 1, 4, col, Mat.Wood)
	end
	for _, x in { -3.5, 3.5 } do
		box(pc, "Viga", x, -0.75, -262, 1, 1.5, 32, C.Bark, Mat.Wood)
	end
	for _, x in { -4.75, 4.75 } do
		box(pc, "Baranda", x, 1.85, -262, 0.3, 0.3, 32, C.Brown, Mat.Wood)
		for z = -246, -278, -8 do
			box(pc, "PosteBaranda", x, 1.5, z, 0.4, 1, 0.4, C.Brown, Mat.Wood)
		end
	end
	local pivot = box(pc, "Pivot", 0, 1, -262, 1, 1, 1, C.Black)
	pivot.Transparency = 1
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pc.PrimaryPart = pivot
end

-- Misma logica que el comando de debug del servidor (WorldService.setBridgeBuilt).
local function setBridge(on: boolean)
	local map = Workspace:FindFirstChild("Map")
	local pf = map and map:FindFirstChild("Puente")
	if not pf then
		warn("setBridge: falta Workspace/Map/Puente")
		return
	end
	local old = pf:FindFirstChild("Construido")
	if old then
		old:Destroy()
	end
	if on then
		local variants = ServerStorage:FindFirstChild("MapVariants")
		local src = variants and variants:FindFirstChild("PuenteConstruido")
		if not src then
			warn("setBridge: falta ServerStorage/MapVariants/PuenteConstruido")
			return
		end
		local c = src:Clone()
		c.Name = "Construido"
		c.Parent = pf
	end
	pf:SetAttribute("BridgeBuilt", on)
end

local function industrial(map: Folder)
	local f = fresh(map, "Industrial")
	local dark, grey = C.Dark, C.Grey
	-- Nave principal con azotea (Y 24), pretil y hueco de 4 al sur sobre el patio
	local nave = model(f, "NavePrincipal")
	building(nave, "Cuerpo", 300, 0, -470, 60, 40, 23, {
		roof = true,
		gaps = { N = { { 24, 36, 0, 9 } }, S = { { 24, 36, 0, 9 } } },
	})
	building(nave, "Pretil", 300, 24, -470, 60, 40, 1.5, {
		th = 1,
		gaps = { S = { { 28, 32, 0, 1.5 } }, E = { { 18, 22, 0, 1.5 } } },
	})
	for i, d in { { 280, -480, 8, 6, 8 }, { 290, -462, 10, 4, 6 }, { 316, -478, 6, 8, 7 }, { 318, -460, 8, 5, 5 } } do
		box(nave, "Maquina_" .. i, d[1], d[4] / 2, d[2], d[3], d[4], d[5], dark)
	end
	local esc = folder(f, "Escaleras")
	truss(esc, v3(331.5, 13, -470), 26)
	-- Oficinas con azotea (Y 16)
	local ofi = model(f, "Oficinas")
	building(ofi, "Cuerpo", 220, 0, -500, 24, 20, 15, { roof = true, gaps = { N = { { 9, 13, 0, 7 } } } })
	building(ofi, "Pretil", 220, 16, -500, 24, 20, 1.5, {
		th = 1,
		gaps = { E = { { 8, 12, 0, 1.5 } }, W = { { 8, 12, 0, 1.5 } } },
	})
	for i, z in { -505, -496 } do
		box(ofi, "Mesa_" .. i, 225, 1.4, z, 4, 2.8, 2, C.Brown)
	end
	truss(esc, v3(206.5, 8.5, -500), 17)
	-- Almacen abierto al sur con camion
	local alm = model(f, "Almacen")
	wall(alm, "Muro_N", v2(210, -422), v2(250, -422), 0, 12, 1, nil, grey)
	wall(alm, "Muro_O", v2(210, -422), v2(210, -398), 0, 12, 1, nil, grey)
	wall(alm, "Muro_E", v2(250, -422), v2(250, -398), 0, 12, 1, nil, grey)
	box(alm, "Techo", 230, 12.5, -410, 41, 1, 25, dark)
	box(alm, "CamionCaja", 224, 4.5, -406, 8, 7, 12, C.Canvas)
	box(alm, "CamionCabina", 224, 3.5, -415, 8, 5, 6, C.Canvas)
	-- Patio de carga
	box(f, "Patio", 300, 0.2, -435, 50, 0.4, 30, C.Dark, Mat.Asphalt)
	-- Chimenea
	local ch = model(f, "Chimenea")
	cylinder(ch, "Fuste", v3(340, 0, -520), 70, 6, C.Grey)
	cylinder(ch, "Remate", v3(340, 70, -520), 2, 7, dark)
	-- Contenedores: 3 pilas (9) y uno abierto
	local cont = folder(f, "Contenedores")
	local function container(x: number, y: number, z: number, i: number)
		box(
			cont,
			"Contenedor_" .. i,
			x,
			y,
			z,
			8,
			8,
			20,
			if i % 2 == 0 then Color3.fromRGB(86, 96, 108) else Color3.fromRGB(104, 84, 72)
		)
		if i == 1 then
			box(cont, "Logotipo", x + 4.05, y, z, 0.1, 3, 6, C.Crystal)
		end
	end
	local cs: { { number } } = {
		{ 340, 4, -440 },
		{ 348, 4, -440 },
		{ 344, 12, -440 },
		{ 372, 4, -440 },
		{ 380, 4, -440 },
		{ 376, 12, -440 },
		{ 342, 4, -404 },
		{ 350, 4, -404 },
		{ 346, 12, -404 },
	}
	for i, c in cs do
		container(c[1], c[2], c[3], i)
	end
	local op = model(cont, "ContenedorAbierto")
	box(op, "Suelo", 360, 0.25, -420, 8, 0.5, 20, dark)
	box(op, "Techo", 360, 8, -420, 8, 0.5, 20, dark)
	box(op, "Pared_O", 356, 4, -420, 0.5, 8, 20, dark)
	box(op, "Pared_E", 364, 4, -420, 0.5, 8, 20, dark)
	box(op, "Fondo", 360, 4, -430, 8, 8, 0.5, dark)
	-- Valla perimetral con porton al oeste
	building(f, "Valla", 280, 0, -465, 230, 160, 2, { th = 0.5, color = dark, gaps = { W = { { 110, 120, 0, 2 } } } })
	-- Linea electrica (3.4): torres de 30 cada ~80 studs de (330,-560) a (-230,-610)
	local lin = fresh(map, "LineaElectrica")
	local path: { Vector2 } = { v2(330, -560), v2(200, -640), v2(40, -680), v2(-120, -660), v2(-230, -610) }
	local total = 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	local count = math.floor(total / 80 + 0.5) + 1
	local towers: { Vector3 } = {}
	for k = 0, count - 1 do
		local dist, p = total * k / (count - 1), path[1]
		for i = 1, #path - 1 do
			local len = (path[i + 1] - path[i]).Magnitude
			if dist <= len + 0.001 or i == #path - 1 then
				p = path[i]:Lerp(path[i + 1], math.clamp(dist / len, 0, 1))
				break
			end
			dist -= len
		end
		local hit = cast(p.X, p.Y, nil, terrainParams(true))
		local y = if hit then hit.Position.Y else 0
		local m = model(lin, string.format("Torre_%02d", k + 1))
		box(m, "Poste", p.X, y + 14, p.Y, 1.5, 30, 1.5, dark)
		box(m, "Travesano", p.X, y + 28, p.Y, 10, 0.8, 0.8, dark)
		table.insert(towers, v3(p.X, y + 28, p.Y))
	end
	local cables = model(lin, "Cables")
	for i = 1, #towers - 1 do
		for _, dx in { -4, 4 } do
			local a, b = towers[i] + v3(dx, 0, 0), towers[i + 1] + v3(dx, 0, 0)
			local c = beam(cables, a, b, 0.15, C.Black)
			c.Name = "Cable"
			c.CanCollide = false
		end
	end
end

local function complejo(map: Folder)
	local f = fresh(map, "Complejo")
	local dark, grey = C.Dark, C.Grey
	-- Superficie
	local cerca = building(
		f,
		"Cerca",
		-300,
		0,
		-580,
		140,
		140,
		3,
		{ th = 0.5, color = dark, gaps = { E = { { 65, 75, 0, 3 } } } }
	)
	part(cerca, "PortonRoto", CFrame.new(-230, 1.5, -571) * CFrame.Angles(0, 0.9, 0), v3(0.4, 3, 5), dark)
	local gar = building(f, "Garita", -226, 0, -560, 6, 6, 8, { roof = true, gaps = { W = { { 1.5, 4.5, 0, 6 } } } })
	box(gar, "Banco", -224, 1, -560, 1.5, 2, 3, C.Brown)
	local lab = building(f, "Laboratorio", -300, 0, -580, 40, 30, 14, {
		roof = true,
		gaps = { E = { { 13, 17, 0, 7 } } },
	})
	part(lab, "PuertaSellada", CFrame.new(-320, 3.5, -580), v3(1.2, 7, 4), C.Black, Mat.Metal)
	for i = 1, 4 do
		box(lab, "Pantalla_" .. i, -312 + i * 5, 3.5, -594, 3, 2, 0.4, C.Black)
	end
	box(lab, "Consola", -300, 1.5, -590, 14, 3, 2, dark)
	local gen =
		building(f, "Generadores", -340, 0, -530, 16, 12, 10, { roof = true, gaps = { S = { { 6, 10, 0, 7 } } } })
	box(gen, "Motor", -340, 2, -530, 8, 4, 4, C.Black)
	local para = model(f, "Parabolica")
	box(para, "Mastil", -260, 3, -630, 1.5, 6, 1.5, dark)
	local plato =
		part(para, "Plato", CFrame.new(-260, 8, -630) * CFrame.Angles(0, 0, math.rad(55)), v3(1, 10, 10), grey)
	plato.Shape = Enum.PartType.Cylinder
	local dep = model(f, "Deposito")
	for i, c in { v2(-352, -632), v2(-348, -632), v2(-352, -628), v2(-348, -628) } do
		box(dep, "Pata_" .. i, c.X, 10, c.Y, 1, 20, 1, dark)
	end
	cylinder(dep, "Tanque", v3(-350, 20, -630), 7, 9, grey)

	-- Subterraneo: forros de Parts sobre el terreno excavado
	local s1 = building(f, "Sotano1", -300, -18, -600, 60, 48, 12, { th = 2, gaps = { N = { { 6, 14, 0, 12 } } } })
	slab(
		s1,
		"Suelo",
		{ x0 = -331, z0 = -625, x1 = -269, z1 = -575 },
		-18,
		2,
		dark,
		{ x0 = -324, z0 = -626, x1 = -316, z1 = -616 }
	)
	slab(
		s1,
		"Techo",
		{ x0 = -331, z0 = -625, x1 = -269, z1 = -575 },
		-5,
		1,
		dark,
		{ x0 = -294, z0 = -608, x1 = -286, z1 = -590 }
	)
	wall(s1, "Tabique_1", v2(-330, -600), v2(-300, -600), -18, 12, 0.8, { { 22, 27, 0, 8 } }, grey)
	wall(s1, "Tabique_2", v2(-304, -624), v2(-304, -606), -18, 12, 0.8, { { 7, 12, 0, 8 } }, grey)
	for i, p in { v2(-312, -612), v2(-318, -608), v2(-296, -618), v2(-312, -592) } do
		local c = cylinder(s1, "Muestra_" .. i, v3(p.X, -18, p.Y), 4, 2, C.Crystal)
		c.Material = Mat.Glass
		c.Transparency = 0.5
		c.CanCollide = false
		c.CFrame = c.CFrame * CFrame.Angles(0.5 * i, 0, 0.3 * i)
	end
	local es1 = model(f, "Escalera1")
	for k = 1, 16 do
		local top = -18 / 16 * k
		box(es1, "Escalon", -290, (top - 19) / 2, -590 - 2 * k + 1, 8, top + 19, 2, grey)
	end
	for _, x in { -295, -285 } do
		box(es1, "Pared", x, -8.5, -606, 1, 21, 36, dark)
	end
	local es2 = model(f, "Escalera2")
	for k = 1, 20 do
		local top = -18 - 1.1 * k
		box(es2, "Escalon", -320, (top - 42) / 2, -616 - 2 * k + 1, 8, top + 42, 2, grey)
	end
	local hall = building(f, "Contencion", -310, -40, -640, 50, 40, 18, {
		th = 2,
		floor = 2,
		gaps = { E = { { 4, 16, 0, 12 } }, S = { { 11, 19, 0, 18 } } },
	})
	slab(
		hall,
		"Techo",
		{ x0 = -336, z0 = -661, x1 = -284, z1 = -619 },
		-21,
		1,
		dark,
		{ x0 = -324, z0 = -630, x1 = -316, z1 = -619 }
	)
	building(
		f,
		"Pasillo",
		-277.5,
		-40,
		-650,
		15,
		12,
		12,
		{ th = 2, floor = 2, roof = true, gaps = { W = { { 0, 12, 0, 12 } } } }
	)
	-- cristal roto y estructuras retorcidas en la sala de contencion
	local rng = rngFor("Complejo")
	for i = 1, 8 do
		local p = part(
			hall,
			"Estructura_" .. i,
			CFrame.new(-310 + rng:NextNumber(-20, 20), -36, -640 + rng:NextNumber(-16, 12))
				* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6)),
			v3(rng:NextNumber(0.6, 1.2), rng:NextNumber(5, 9), rng:NextNumber(0.6, 1.2)),
			if i % 2 == 0 then dark else C.Crystal,
			if i % 2 == 0 then Mat.Metal else Mat.Glass
		)
		p.CanCollide = false
		if i % 2 == 1 then
			p.Transparency = 0.4
		end
	end
end

local function anomTree(parent: Instance, idx: number, base: Vector3, rng: Random)
	local m = model(parent, "Arbol_" .. idx)
	local v = rng:NextInteger(1, 3)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local function dirOf(tilt: number): Vector3
		return v3(math.sin(tilt) * math.cos(yaw), math.cos(tilt), math.sin(tilt) * math.sin(yaw))
	end
	if v == 1 then
		local h = rng:NextNumber(18, 26)
		local dir = dirOf(math.rad(rng:NextNumber(8, 20)))
		tiltedCyl(m, "Tronco", base - v3(0, 1, 0), dir, h, 2.2, C.Violet)
		ball(m, "Copa", base + dir * h + v3(0, 2, 0), rng:NextNumber(7, 9), C.Teal)
	elseif v == 2 then
		local h = rng:NextNumber(12, 17)
		cylinder(m, "Tronco", base - v3(0, 1, 0), h, 2.4, C.Violet)
		for _, s in { -1, 1 } do
			local d = dirOf(0.55)
			d = v3(d.X * s, d.Y, d.Z * s)
			tiltedCyl(m, "Rama", base + v3(0, h - 1, 0), d, 8, 1.2, C.Violet)
			ball(m, "Copa", base + v3(0, h - 1, 0) + d * 8, 5, C.Teal)
		end
	else
		local h = rng:NextNumber(18, 24)
		cylinder(m, "Tronco", base - v3(0, 1, 0), h, 1.8, C.Dry)
		for k = 0, 2 do
			local a = yaw + k * 2.09
			local d = v3(math.sin(0.9) * math.cos(a), math.cos(0.9), math.sin(0.9) * math.sin(a))
			tiltedCyl(m, "Rama", base + v3(0, h * (0.55 + 0.15 * k), 0), d, rng:NextNumber(6, 9), 0.8, C.Dry)
		end
	end
end

local function bosqueAnomalo(map: Folder)
	local f = fresh(map, "BosqueAnomalo")
	local trees = folder(f, "Arboles")
	local hongos = folder(f, "Hongos")
	local rng = rngFor("BosqueAnomalo")
	local zone = ZONES[6]
	local x0, x1 = zone.pos.X - zone.size.X / 2 + 4, zone.pos.X + zone.size.X / 2 - 4
	local z0, z1 = zone.pos.Z - zone.size.Z / 2 + 4, zone.pos.Z + zone.size.Z / 2 - 4
	-- manchas de Ground y Mud
	for i = 1, 30 do
		local p = v2(rng:NextNumber(x0, x1), rng:NextNumber(z0, z1))
		local hit = cast(p.X, p.Y, nil, terrainParams(true))
		if hit and not inRect(p, rect(CAMP.X, CAMP.Y, 20, 20)) then
			local r = rng:NextNumber(6, 14)
			local y = hit.Position.Y
			local region = Region3.new(v3(p.X - r, y - 6, p.Y - r), v3(p.X + r, y + 4, p.Y + r)):ExpandToGrid(4)
			Terrain:ReplaceMaterial(region, 4, Mat.Grass, if i % 3 == 0 then Mat.Mud else Mat.Ground)
		end
	end
	task.wait()
	-- arboles anomalos (tope 220)
	local bases: { Vector3 } = {}
	local cand: { Vector2 } = {}
	for gx = x0, x1, 17 do
		for gz = z0, z1, 17 do
			local p = v2(gx + rng:NextNumber(-6, 6), gz + rng:NextNumber(-6, 6))
			local roll = rng:NextNumber()
			local clear = roll > 0.72 or nearRoad(p, 9) or nearMarker(p, 8)
			for _, r in BLOCKED do
				clear = clear or inRect(p, r)
			end
			if not clear then
				table.insert(cand, p)
			end
		end
	end
	local count = 0
	for _, p in cand do
		if count >= 220 then
			break
		end
		local hit = cast(p.X, p.Y, nil, terrainParams(false))
		if hit and hit.Material ~= Mat.Water and hit.Material ~= Mat.Rock and hit.Material ~= Mat.Slate then
			count += 1
			table.insert(bases, hit.Position)
			anomTree(trees, count, hit.Position, rng)
			if count % 200 == 0 then
				task.wait()
			end
		end
	end
	-- troncos caidos y hongos (40 grupos, 12 con luz)
	local spots: { Vector3 } = {}
	for i = 1, 8 do
		local b = bases[rng:NextInteger(1, #bases)]
		local p = b + v3(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
		local cyl = part(
			trees,
			"TroncoCaido_" .. i,
			CFrame.new(p + v3(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90)),
			v3(10, 1.8, 1.8),
			C.Violet
		)
		cyl.Shape = Enum.PartType.Cylinder
		table.insert(spots, p)
	end
	for i = 1, 40 do
		local anchor = if i <= 12 then spots[(i - 1) % #spots + 1] else bases[rng:NextInteger(1, #bases)]
		local m = model(hongos, "Grupo_" .. i)
		for k = 1, 3 do
			local d = rng:NextNumber(1, 2)
			local p = anchor + v3(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			local hit = cast(p.X, p.Z, nil, terrainParams(true))
			local y = (if hit then hit.Position.Y else 0) + d / 2
			local b = ball(
				m,
				"Hongo_" .. k,
				v3(p.X, y, p.Z),
				d,
				if k == 2 then Color3.fromRGB(80, 220, 170) else C.Neon,
				Mat.Neon
			)
			if k == 1 and i % 3 == 1 and i <= 36 then
				local l = Instance.new("PointLight")
				l.Range = 10
				l.Brightness = 0.6
				l.Color = C.Neon
				l.Shadows = false
				l.Parent = b
			end
		end
	end
	-- campamento de investigacion
	local camp = model(f, "Campamento")
	tent(camp, CAMP.X - 8, CAMP.Y + 4, 20)
	tent(camp, CAMP.X + 8, CAMP.Y - 3, -35)
	box(camp, "Mesa", CAMP.X, 1.5, CAMP.Y + 6, 5, 3, 2.5, C.Brown)
	box(camp, "Generador", CAMP.X + 2, 1.5, CAMP.Y - 8, 3, 3, 2.5, C.Dark)
	for i, d in { { -3, 1 }, { -4.5, 3 }, { 5, -4 } } do
		box(camp, "Caja_" .. i, CAMP.X + d[1], 1, CAMP.Y + d[2], 2, 2, 2, C.Canvas)
	end
	local sens = folder(f, "Sensores")
	for i, s in SENSORS do
		local hit = cast(s.X, s.Y, nil, terrainParams(true))
		local y = if hit then hit.Position.Y else 0
		box(sens, "Poste_" .. i, s.X, y + 3, s.Y, 0.8, 6, 0.8, C.Dark)
		box(sens, "Caja_" .. i, s.X, y + 5.5, s.Y, 2, 1.5, 1.5, C.Black)
	end
	local marcas = folder(f, "Marcas")
	local marked = { v2(-30, -420), v2(-46, -440), v2(-30, -462), v2(-52, -478), v2(-100, -520), v2(-86, -536) }
	for i, p in marked do
		local hit = cast(p.X, p.Y, nil, terrainParams(true))
		local y = if hit then hit.Position.Y else 0
		local m = model(marcas, "ArbolMarcado_" .. i)
		cylinder(m, "Tronco", v3(p.X, y - 1, p.Y), 16, 2, C.Violet)
		box(m, "Cinta", p.X, y + 4, p.Y, 2.4, 0.5, 2.4, Color3.fromRGB(220, 120, 40))
		box(m, "Estaca", p.X + 2, y + 1.5, p.Y + 1, 0.3, 3, 0.3, C.Brown)
	end
	local todo = folder(f, "Todoterreno")
	car(todo, "Todoterreno", -60, -480, -30, C.Canvas)
end

-- Variantes de arbol decorativo (solo Parts dentro de Map/Bosque, no son prefabs). Cada copa: tamano y altura del
-- centro sobre el suelo; el tronco es el alto. Todo se multiplica por la escala del arbol.
type Crown = { size: Vector3, y: number }
type TreeVariant = { trunk: number, color: Color3, crowns: { Crown } }
local FOREST_JITTER = 8
local FOREST_CAP = 1400
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
	for gx = PLAY.x0, PLAY.x1, 18 do
		for gz = PLAY.z0, PLAY.z1, 18 do
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
				or (math.abs(x) < 12 and z > -220 and z < -48)
				or nearRoad(p, 10)
				or polyDist(p, RIVER) < GORGE_CLEAR + 6
				or zoneOf(x, z) ~= "Bosque"
				or roll >= (if near < 150 then 0.55 else 0.15)
				or nearMarker(p, 8)
			if not clear then
				for _, r in BLOCKED do
					if inRect(p, r) then
						clear = true
						break
					end
				end
			end
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
		if count >= FOREST_CAP then
			break
		end
		local hit = cast(p.X, p.Y, nil, terrainParams(false))
		if
			hit
			and hit.Material ~= Mat.Water
			and hit.Material ~= Mat.Rock
			and hit.Material ~= Mat.Slate
			and hit.Position.Y <= 10
			and hit.Position.Y >= -2
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
				ball(m, "Bola_" .. i, v3(p.X, (if hit then hit.Position.Y else 0) + r * 0.5, p.Y), r, C.Green)
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
	local w, d = PLAY.x1 - PLAY.x0, PLAY.z1 - PLAY.z0
	local cz = (PLAY.z0 + PLAY.z1) / 2
	local walls: { { id: string, pos: Vector3, size: Vector3 } } = {
		{ id = "N", pos = v3(0, 150, PLAY.z0 - 2), size = v3(w + 8, 300, 4) },
		{ id = "S", pos = v3(0, 150, PLAY.z1 + 2), size = v3(w + 8, 300, 4) },
		{ id = "E", pos = v3(PLAY.x1 + 2, 150, cz), size = v3(4, 300, d + 8) },
		{ id = "O", pos = v3(PLAY.x0 - 2, 150, cz), size = v3(4, 300, d + 8) },
	}
	for _, wl in walls do
		mk(lim, "Muro_" .. wl.id, CFrame.new(wl.pos), wl.size, nil, nil).CanCollide = true
	end

	local root = fresh(Workspace, "Markers")
	snapParams = worldParams()
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
	for i = 1, #RIVER - 1 do
		local a, b = RIVER[i], RIVER[i + 1]
		local mid = (a + b) / 2
		local c = v3(mid.X, -19, mid.Y)
		mk(
			water,
			"Rio_" .. i,
			CFrame.lookAt(c, c + v3(b.X - a.X, 0, b.Y - a.Y)),
			v3(44, 11, (b - a).Magnitude),
			"WaterZone",
			nil
		)
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
			local ey = if r.ys then r.ys[i] else nil
			local hit = cast(p.X, p.Y, if ey then ey + 6 else nil, params)
			if not hit then
				warn(string.format("PatrolPoint sin superficie: %s %d", r.id, i))
			end
			spot(
				rf,
				string.format("%02d", i),
				v3(p.X, if hit then hit.Position.Y else (ey or 0), p.Y),
				"PatrolPoint",
				{ RouteId = r.id, Order = i }
			)
		end
	end

	local hid = folder(root, "Hideouts")
	for _, h in HIDEOUTS do
		spot(hid, h.id, h.pos, "Hideout", nil)
	end

	mk(
		root,
		"BridgeSite",
		CFrame.new(0, 1, -262),
		v3(14, 12, 32),
		"BridgeSite",
		{ BridgeId = "Principal", Segments = 3 }
	)
	local ends = folder(root, "BridgeEnds")
	mk(ends, "Sur", CFrame.new(0, 1, -232), v3(10, 1, 4), "BridgeEnd", { Side = "Sur" })
	mk(ends, "Norte", CFrame.new(0, 1, -292), v3(10, 1, 4), "BridgeEnd", { Side = "Norte" })

	local cr = folder(root, "CreatureCrossings")
	for _, c in CROSSINGS do
		for side, p in { Sur = c.sur, Norte = c.norte } do
			local hit = cast(p.X, p.Y, nil, params)
			spot(
				cr,
				c.id .. "_" .. side,
				v3(p.X, if hit then hit.Position.Y else 0, p.Y),
				"CreatureCrossing",
				{ CrossingId = c.id, Side = side }
			)
		end
	end

	local an = folder(root, "AnomalyZones")
	for _, a in ANOMALIES do
		mk(an, a.id, CFrame.new(a.pos), a.size, "AnomalyZone", {
			AnomalyId = a.id,
			Intensity = a.i,
			FogHint = a.fog,
			EMHint = a.em,
			AudioHint = a.audio,
			Propagation = a.prop,
		})
	end

	local lore = folder(root, "LorePoints")
	for _, l in LORE do
		spot(lore, l.id, l.pos, "LorePoint", { LoreId = l.id, ZoneId = l.zone, Act = l.act })
	end
end

--------------------------------------------------------------------------------------------------
-- VERIFICACION Y RESUMEN
--------------------------------------------------------------------------------------------------

local function summary(strict: boolean)
	print("--- MapBuilder: resumen ---")
	local function check(label: string, got: number, want: number)
		print(string.format("%-18s %d (esperado %d)", label, got, want))
		if strict and got ~= want then
			warn(string.format("Conteo no cuadra: %s = %d, esperado %d", label, got, want))
		end
	end
	for _, e in EXPECTED do
		check(e[1] :: string, #CollectionService:GetTagged(e[1] :: string), e[2] :: number)
	end
	local kinds: { [string]: number } = { Arbol = 0, Roca = 0 }
	for _, inst in CollectionService:GetTagged("ResourceSpawn") do
		local k = inst:GetAttribute("Kind")
		if type(k) == "string" and kinds[k] then
			kinds[k] += 1
		end
	end
	check("ResourceSpawn Arbol", kinds.Arbol, 68)
	check("ResourceSpawn Roca", kinds.Roca, 42)
	local routes: { [string]: number } = {}
	for _, inst in CollectionService:GetTagged("PatrolPoint") do
		local id = inst:GetAttribute("RouteId")
		if type(id) == "string" then
			routes[id] = (routes[id] or 0) + 1
		end
	end
	for _, r in PATROLS do
		print(string.format("PatrolPoint %s: %d", r.id, routes[r.id] or 0))
		-- ningun punto subterraneo puede quedar en la Y de superficie por un raycast fallido
		if r.ys then
			for _, inst in CollectionService:GetTagged("PatrolPoint") do
				local order = inst:GetAttribute("Order")
				local ey = if inst:GetAttribute("RouteId") == r.id and type(order) == "number" then r.ys[order] else nil
				if ey and inst:IsA("BasePart") and math.abs(inst.Position.Y - 0.5 - ey) > 2 then
					warn(string.format("PatrolPoint subterraneo fuera de Y: %s (esperado %d)", inst:GetFullName(), ey))
				end
			end
		end
	end
	for _, z in ZONES do
		local d = z.anchor.Magnitude
		print(string.format("Zona %s: %.0f studs a la base (spec %d)", z.id, d, z.expected))
		if strict and math.abs(d - z.expected) > math.max(z.expected * 0.1, 1) then
			warn("Distancia fuera del 10 por ciento: " .. z.id)
		end
	end
	-- Ningun marcador a mas de 2 studs de su superficie
	local params = worldParams()
	for _, tag in
		{
			"PieceSpawn",
			"LootSpawn",
			"ResourceSpawn",
			"Hideout",
			"EnemySpawn",
			"PatrolPoint",
			"LorePoint",
			"CreatureCrossing",
		}
	do
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
	-- Presupuesto (9)
	local map = Workspace:FindFirstChild("Map")
	local parts, lights, anom, groups = 0, 0, 0, 0
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("PointLight") then
				lights += 1
			end
		end
		local ba = map:FindFirstChild("BosqueAnomalo")
		anom = if ba and ba:FindFirstChild("Arboles") then #(ba.Arboles:GetChildren() :: { Instance }) else 0
		groups = if ba and ba:FindFirstChild("Hongos") then #(ba.Hongos:GetChildren() :: { Instance }) else 0
		local bosqueF = map:FindFirstChild("Bosque")
		local nb = if bosqueF and bosqueF:FindFirstChild("Arboles")
			then #(bosqueF.Arboles:GetChildren() :: { Instance })
			else 0
		print(
			string.format(
				"Presupuesto: BaseParts %d (<9000), bosque %d (<=1400), anomalos %d (<=220+8 troncos), hongos %d (40), luces %d (<=12)",
				parts,
				nb,
				anom,
				groups,
				lights
			)
		)
		if strict and (parts >= 9000 or nb > FOREST_CAP or anom > 228 or groups ~= 40 or lights > 12) then
			warn("Presupuesto de rendimiento superado")
		end
	end
	-- Barrera del rio: de -720 a 720 con un solo hueco de 14
	local spans: { { number } } = {}
	for _, inst in CollectionService:GetTagged("PlayerBarrier") do
		if inst:IsA("BasePart") then
			local cf, s = inst.CFrame, inst.Size
			local ext = (
				math.abs(cf.RightVector.X) * s.X
				+ math.abs(cf.UpVector.X) * s.Y
				+ math.abs(cf.LookVector.X) * s.Z
			) / 2
			table.insert(spans, { cf.Position.X - ext, cf.Position.X + ext })
		end
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local gapsFound, reach = 0, if #spans > 0 then spans[1][2] else 0
	for i = 2, #spans do
		if spans[i][1] - reach > 1.5 then
			gapsFound += 1
			print(string.format("Hueco de barrera: X %.1f a %.1f (%.1f)", reach, spans[i][1], spans[i][1] - reach))
		end
		reach = math.max(reach, spans[i][2])
	end
	print(
		string.format(
			"PlayerBarrier: %d partes, X %.0f a %.0f, huecos %d",
			#spans,
			if #spans > 0 then spans[1][1] else 0,
			reach,
			gapsFound
		)
	)
	if strict and (#spans == 0 or spans[1][1] > -719 or reach < 719 or gapsFound ~= 1) then
		warn("PlayerBarrier no cubre -720..720 con un solo hueco")
	end
	-- Existencias
	local function exists(inst: Instance?, what: string)
		if not inst then
			warn("Falta: " .. what)
		end
	end
	local markers = Workspace:FindFirstChild("Markers")
	exists(markers and markers:FindFirstChild("BaseSpawn"), "Markers/BaseSpawn")
	exists(markers and markers:FindFirstChild("RadioSocket"), "Markers/RadioSocket")
	exists(markers and markers:FindFirstChild("CampfireSocket"), "Markers/CampfireSocket")
	local radio = map and map:FindFirstChild("Base") and map.Base:FindFirstChild("Radio")
	exists(radio, "Map/Base/Radio")
	local pf = map and map:FindFirstChild("Puente")
	exists(pf, "Map/Puente")
	if pf and pf:GetAttribute("BridgeBuilt") ~= false then
		warn("Map/Puente.BridgeBuilt no es false")
	end
	local variants = ServerStorage:FindFirstChild("MapVariants")
	exists(variants and variants:FindFirstChild("PuenteConstruido"), "ServerStorage/MapVariants/PuenteConstruido")
	if Workspace:FindFirstChild("Baseplate") then
		warn("Existe Workspace.Baseplate")
	end
	local nSpawn = 0
	for _, dsc in Workspace:GetDescendants() do
		if dsc:IsA("SpawnLocation") then
			nSpawn += 1
		end
	end
	check("SpawnLocation", nSpawn, 1)
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
	TerrenoA = terrenoA,
	TerrenoB = terrenoB,
	Caminos = caminos,
	Base = baseZone,
	Ciudad = ciudad,
	Torre = torre,
	Mina = mina,
	Rio = rio,
	Puente = puente,
	Industrial = industrial,
	Complejo = complejo,
	BosqueAnomalo = bosqueAnomalo,
	Bosque = bosque,
	Marcadores = marcadores,
}

if SECTION == "PuenteOn" or SECTION == "PuenteOff" then
	setBridge(SECTION == "PuenteOn")
	print("MapBuilder: " .. SECTION .. " hecho")
	return true
end

assert(SECTION == "All" or RUNNERS[SECTION] ~= nil, "SECTION invalida: " .. SECTION)
local t0 = os.clock()
removeBaseplate()
if SECTION == "All" or SECTION == "Terreno" or SECTION == "TerrenoA" then
	Terrain:Clear()
	for _, n in { "Map", "Markers" } do
		local old = Workspace:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local mv = ServerStorage:FindFirstChild("MapVariants")
	if mv then
		mv:Destroy()
	end
end
local mapFolder = Workspace:FindFirstChild("Map")
if not (mapFolder and mapFolder:IsA("Folder")) then
	mapFolder = folder(Workspace, "Map")
end
local order = SECTIONS
if SECTION ~= "All" then
	order = { SECTION }
end
for _, s in order do
	RUNNERS[s](mapFolder :: Folder)
	if s == "Marcadores" then
		setupSpawn()
	end
	print(string.format("MapBuilder: %s lista (%.1fs)", s, os.clock() - t0))
	task.wait()
end
if SECTION == "All" or SECTION == "Marcadores" then
	summary(true)
end
print(string.format("MapBuilder: %s terminado en %.1fs", SECTION, os.clock() - t0))
return true
