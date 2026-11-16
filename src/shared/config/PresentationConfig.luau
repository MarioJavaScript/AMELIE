--!strict
-- Valores de presentacion (cliente). Los valores de luz y niebla son iniciales: se ajustan en Studio tras playtest
-- (docs/specs/ciclo-partida.md: la densidad de niebla no es un equivalente exacto de VisibilityStuds).
-- TODO: IDs de audio se definen con los assets de Studio.
return {
	InputBindings = {
		Crouch = Enum.KeyCode.C,
		Sprint = Enum.KeyCode.LeftShift,
		Flashlight = Enum.KeyCode.F,
		DebugCyclePhase = Enum.KeyCode.F6,
		DebugCycleNight = Enum.KeyCode.F7,
	},
	AudioIds = {},
	Colors = {
		HudText = Color3.fromRGB(235, 235, 235),
		HudBarBack = Color3.fromRGB(20, 20, 20),
		Health = Color3.fromRGB(190, 45, 45),
		Stamina = Color3.fromRGB(215, 185, 70),
		Battery = Color3.fromRGB(90, 170, 220),
		BatteryLow = Color3.fromRGB(220, 110, 60),
	},
	ReducedMotionBobAmplitudeStuds = 0,

	FirstPerson = {
		-- Escala maxima de balanceo respecto a la velocidad de caminar (correr = Sprint / Walk).
		BobMaxSpeedFactor = 1.5,
		-- Velocidad horizontal minima para que haya balanceo.
		BobMinSpeedStudsPerSecond = 0.5,
		-- Tasas de suavizado exponencial (1/s).
		BobAmplitudeSmoothing = 10,
		CrouchSmoothing = 12,
		-- Sin reconciliacion con el snapshot antes de este tiempo tras pedir un cambio de modo.
		ModeReconcileSeconds = 3,
		-- SetCore puede fallar al inicio: reintentos para desactivar el boton de reiniciar.
		ResetButtonRetries = 30,
		ResetButtonRetrySeconds = 1,
	},

	Flashlight = {
		Brightness = 2.5,
		Color = Color3.fromRGB(255, 244, 222),
		-- Parpadeo por evento Feedback (ThreatVeryNear). El parpadeo es solo visual.
		FlickerSeconds = 1.5,
		FlickerRateHz = 14,
		-- Nivel de brillo (fraccion) maximo durante la fase tenue de cada parpadeo.
		FlickerDimLevel = 0.1,
		FlickerCues = { ThreatVeryNear = true },
		-- Con bateria por debajo de este valor el HUD la pinta en color de aviso.
		LowBatteryThreshold = 20,
		AimHeartbeatSeconds = 0.5,
		AimMinChangeDegrees = 0.5,
		-- Margen respecto al pitch maximo del servidor para no rozar el limite.
		AimPitchMarginDegrees = 1,
	},

	Hud = {
		-- Constante de suavizado de las barras hacia el valor del servidor (1/s).
		BarSmoothing = 8,
		BarWidth = 220,
		BarHeight = 14,
		BarGap = 6,
		Margin = 16,
	},

	Lighting = {
		-- Fase -> preset. Lobby y Result reutilizan presets existentes.
		PhasePreset = { Lobby = "Day", Day = "Day", Dusk = "Dusk", Night = "Night", Dawn = "Dawn", Result = "Dawn" },
		-- Atmosphere para Studio: el Technology = Future solo se puede fijar en Studio, no por script.
		RequiredTechnology = "Future",
	},

	LightingPresets = {
		Day = {
			TransitionSeconds = 4,
			Lighting = {
				Brightness = 3,
				ClockTime = 14,
				Ambient = Color3.fromRGB(70, 75, 80),
				OutdoorAmbient = Color3.fromRGB(110, 115, 120),
				ExposureCompensation = 0,
				EnvironmentDiffuseScale = 1,
				EnvironmentSpecularScale = 1,
			},
			Atmosphere = {
				Color = Color3.fromRGB(190, 200, 210),
				Decay = Color3.fromRGB(150, 165, 180),
				Density = 0.25,
				Offset = 0.1,
				Glare = 0,
				Haze = 0.5,
			},
			ColorCorrection = {
				Brightness = 0,
				Contrast = 0.05,
				Saturation = 0,
				TintColor = Color3.fromRGB(255, 255, 255),
			},
		},
		Dusk = {
			TransitionSeconds = 20,
			Lighting = {
				Brightness = 2,
				ClockTime = 18.3,
				Ambient = Color3.fromRGB(70, 55, 55),
				OutdoorAmbient = Color3.fromRGB(95, 70, 60),
				ExposureCompensation = -0.2,
				EnvironmentDiffuseScale = 0.8,
				EnvironmentSpecularScale = 0.8,
			},
			Atmosphere = {
				Color = Color3.fromRGB(215, 150, 100),
				Decay = Color3.fromRGB(170, 95, 60),
				Density = 0.33,
				Offset = 0.15,
				Glare = 0.3,
				Haze = 1.2,
			},
			ColorCorrection = {
				Brightness = -0.02,
				Contrast = 0.1,
				Saturation = 0.05,
				TintColor = Color3.fromRGB(255, 220, 190),
			},
		},
		Night = {
			TransitionSeconds = 10,
			Lighting = {
				Brightness = 0.3,
				ClockTime = 0,
				Ambient = Color3.fromRGB(8, 10, 16),
				OutdoorAmbient = Color3.fromRGB(14, 18, 28),
				ExposureCompensation = -0.5,
				EnvironmentDiffuseScale = 0.3,
				EnvironmentSpecularScale = 0.3,
			},
			Atmosphere = {
				Color = Color3.fromRGB(35, 45, 60),
				Decay = Color3.fromRGB(15, 20, 30),
				Density = 0.4,
				Offset = 0.2,
				Glare = 0,
				Haze = 2,
			},
			ColorCorrection = {
				Brightness = -0.05,
				Contrast = 0.15,
				Saturation = -0.2,
				TintColor = Color3.fromRGB(195, 210, 255),
			},
		},
		Dawn = {
			TransitionSeconds = 10,
			Lighting = {
				Brightness = 1.8,
				ClockTime = 5.6,
				Ambient = Color3.fromRGB(55, 55, 65),
				OutdoorAmbient = Color3.fromRGB(85, 80, 90),
				ExposureCompensation = -0.1,
				EnvironmentDiffuseScale = 0.7,
				EnvironmentSpecularScale = 0.7,
			},
			Atmosphere = {
				Color = Color3.fromRGB(200, 185, 190),
				Decay = Color3.fromRGB(180, 140, 130),
				Density = 0.3,
				Offset = 0.1,
				Glare = 0.1,
				Haze = 1,
			},
			ColorCorrection = {
				Brightness = 0,
				Contrast = 0.05,
				Saturation = -0.05,
				TintColor = Color3.fromRGB(235, 235, 255),
			},
		},
	},

	-- Niebla por noche (1..5): se mezcla sobre el preset Night. La noche 5 (Luna roja) agrega un tinte rojizo.
	-- Densidad crece cuando baja NightsConfig.Nights[n].VisibilityStuds (120, 100, 80, 60, 45).
	NightOverrides = {
		{ Atmosphere = { Density = 0.38, Haze = 1.6 } },
		{ Atmosphere = { Density = 0.43, Haze = 1.9 } },
		{ Atmosphere = { Density = 0.48, Haze = 2.2 } },
		{ Atmosphere = { Density = 0.54, Haze = 2.6 } },
		{
			Atmosphere = {
				Density = 0.62,
				Haze = 3,
				Color = Color3.fromRGB(70, 35, 35),
				Decay = Color3.fromRGB(40, 12, 12),
			},
			ColorCorrection = { TintColor = Color3.fromRGB(255, 190, 190), Saturation = -0.1 },
			Lighting = { OutdoorAmbient = Color3.fromRGB(30, 14, 14) },
		},
	},
}
