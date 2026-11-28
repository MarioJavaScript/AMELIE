--!strict
-- Nodos y loot (docs/specs/recoleccion-inventario.md). LootTables[ZoneId].Containers[n] es el contenido del
-- marcador <ZoneId>_0n; cada entrada es un stack y su posicion es el numero de lote.
local function stacks(...: { any }): { { Item: string, Count: number } }
	local list = {}
	for _, entry in { ... } do
		table.insert(list, { Item = entry[1], Count = entry[2] })
	end
	return list
end

local city = stacks({ "Pila", 1 }, { "Chatarra", 2 }, { "Lata", 1 })
return {
	HitRangeStuds = 10,
	Nodes = {
		Arbol = { MaxHealth = 50, OutputItem = "Madera", HandOnly = false, NoiseKind = "ResourceHit" },
		Roca = { MaxHealth = 60, OutputItem = "Piedra", HandOnly = false, NoiseKind = "ResourceHit" },
		Arbusto = { MaxHealth = 15, OutputItem = "Baya", HandOnly = true, NoiseKind = "Forage" },
	},
	BareHand = { Damage = 5, Yield = 1, HitCooldownSeconds = 1.2 },
	LootTables = {
		Base = { Containers = { stacks({ "Pila", 2 }) } },
		Ciudad = { OpenNoiseKind = "MetalOpen", Containers = { city, city, city } },
		Mina = {
			Containers = {
				stacks({ "Pila", 1 }, { "Chatarra", 2 }),
				stacks({ "Pila", 1 }, { "Chatarra", 2 }, { "Venda", 1 }),
				stacks({ "Pila", 1 }, { "Chatarra", 2 }),
			},
		},
		Industrial = { OpenNoiseKind = "MetalOpen", Containers = { city, city, city } },
		Complejo = {
			OpenNoiseKind = "MetalOpen",
			Containers = {
				stacks({ "Pila", 1 }, { "Chatarra", 2 }, { "Venda", 1 }),
				stacks({ "Pila", 1 }, { "Chatarra", 2 }, { "Botiquin", 1 }),
				stacks({ "Pila", 1 }, { "Chatarra", 2 }, { "Venda", 1 }),
			},
		},
	},
}
