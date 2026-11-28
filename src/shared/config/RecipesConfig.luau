--!strict
-- Fuente unica de recetas (docs/specs/recoleccion-inventario.md).
return {
	MaxBatch = 5,
	CraftCooldownSeconds = 0.5,
	Recipes = {
		Hacha = {
			Id = "Hacha",
			Inputs = { Madera = 2, Piedra = 2 },
			Output = { ItemId = "Hacha", Count = 1 },
			Order = 1,
		},
		Pico = { Id = "Pico", Inputs = { Madera = 2, Piedra = 2 }, Output = { ItemId = "Pico", Count = 1 }, Order = 2 },
		Venda = { Id = "Venda", Inputs = { Madera = 3 }, Output = { ItemId = "Venda", Count = 1 }, Order = 3 },
		Botiquin = {
			Id = "Botiquin",
			Inputs = { Venda = 2, Chatarra = 1 },
			Output = { ItemId = "Botiquin", Count = 1 },
			Order = 4,
		},
	},
}
