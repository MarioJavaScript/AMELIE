--!strict
return {
	PickupHoldSeconds = 2,
	InstallHoldSeconds = 2,
	StartHoldSeconds = 3,
	ResumeHoldSeconds = 3,
	DropForwardStuds = 3,
	DropCooldownSeconds = 0.5,
	ImpactMinDropStuds = 4,
	RecoveryIntervalSeconds = 1,
	RevealRadiusStuds = 60,
	TransmissionSeconds = 180,
	Pieces = {
		Bateria = {
			Zone = "Ciudad",
			ApproxDistanceStuds = 230,
			Prefab = "PiezaBateria",
			Heavy = false,
			SpawnCount = 3,
		},
		Antena = {
			Zone = "Industrial",
			ApproxDistanceStuds = 530,
			Prefab = "PiezaAntena",
			Heavy = true,
			SpawnCount = 3,
		},
		Transceptor = {
			Zone = "Complejo",
			ApproxDistanceStuds = 650,
			Prefab = "PiezaTransceptor",
			Heavy = false,
			SpawnCount = 3,
		},
		Cristal = { Zone = "Mina", ApproxDistanceStuds = 470, Prefab = "PiezaCristal", Heavy = false, SpawnCount = 3 },
	},
	-- Puente roto entre territorios (docs/specs/mapa.md 2.2): variante construida y comando de debug en Studio.
	Bridge = {
		MapPath = "Map/Puente",
		BuiltVariantPath = "MapVariants/PuenteConstruido", -- bajo ServerStorage
		BuiltAttribute = "BridgeBuilt",
		BuiltChildName = "Construido",
		DebugCommand = "puente",
	},
}
