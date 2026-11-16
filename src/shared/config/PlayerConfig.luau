--!strict
return {
	Camera = { Fov = 75, BobAmplitudeStuds = 0.06, BobFrequencyHz = 8, CrouchOffsetStuds = 1 },
	Speed = { Walk = 12, Sprint = 20, Crouch = 6, Downed = 2, HeavyCarry = 8 },
	Stamina = {
		Max = 100,
		SprintDrainPerSecond = 20,
		RegenPerSecond = 15,
		RegenDelaySeconds = 1.5,
		RestartSprintAt = 20,
	},
	Health = {
		Max = 100,
		Revive = 40,
		Respawn = 100,
		BandageHeal = 35,
		BandageHoldSeconds = 2,
		ReviveHoldSeconds = 4,
		BleedoutSeconds = 30,
		SoloAutoReviveSeconds = 10,
	},
	Flashlight = {
		MaxBattery = 100,
		InitialBattery = 50,
		RespawnBattery = 50,
		DrainPerSecond = 0.5,
		BatteryRestore = 50,
		ReplaceHoldSeconds = 2,
	},
	InitialItems = { Madera = 4, Piedra = 4 },
}
