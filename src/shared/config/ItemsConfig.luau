--!strict
return {
	InventorySlots = 12,
	Items = {
		Madera = { Kind = "Material", MaxStack = 50 },
		Piedra = { Kind = "Material", MaxStack = 50 },
		Pila = { Kind = "Consumable", MaxStack = 5 },
		Chatarra = { Kind = "Material", MaxStack = 20 },
		Hacha = {
			Kind = "Tool",
			MaxStack = 1,
			ResourceKind = "Arbol",
			Damage = 10,
			Yield = 2,
			HitCooldownSeconds = 0.8,
		},
		Pico = { Kind = "Tool", MaxStack = 1, ResourceKind = "Roca", Damage = 10, Yield = 2, HitCooldownSeconds = 1 },
		Venda = { Kind = "Consumable", MaxStack = 10 },
	},
}
