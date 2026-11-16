--!strict
return {
	HitRangeStuds = 10,
	Nodes = {
		Arbol = { MaxHealth = 50, RequiredTool = "Hacha", OutputItem = "Madera" },
		Roca = { MaxHealth = 60, RequiredTool = "Pico", OutputItem = "Piedra" },
	},
	BareHand = { Damage = 5, Yield = 1, CooldownSeconds = 1.2 },
	ZoneLoot = { ContainersPerZone = 3, PilaPerContainer = 1, ChatarraPerContainer = 2, BasePila = 2 },
}
