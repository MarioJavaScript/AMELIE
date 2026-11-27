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
			Zone = "Gasolinera",
			ApproxDistanceStuds = 150,
			Prefab = "PiezaBateria",
			Heavy = false,
			SpawnCount = 3,
		},
		Antena = { Zone = "Torre", ApproxDistanceStuds = 300, Prefab = "PiezaAntena", Heavy = true, SpawnCount = 3 },
		Transceptor = {
			Zone = "Pantano",
			ApproxDistanceStuds = 450,
			Prefab = "PiezaTransceptor",
			Heavy = false,
			SpawnCount = 3,
		},
		Cristal = { Zone = "Mina", ApproxDistanceStuds = 600, Prefab = "PiezaCristal", Heavy = false, SpawnCount = 3 },
	},
}
