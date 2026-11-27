--!strict
-- Contratos de docs/specs/remotes.md. Solo tipos; no ejecuta logica.
export type Req = { requestId: string, runId: string }
export type Placement =
	{ pieceId: "Cimiento", gridX: number, gridZ: number, quarterTurns: number }
	| { pieceId: "Pared" | "MarcoPuerta", parentId: string, socketId: "EdgeN" | "EdgeE" | "EdgeS" | "EdgeW" }
	| { pieceId: "Fogata" }
export type InteractionAction =
	"PickupObjective"
	| "InstallObjective"
	| "StartTransmission"
	| "ResumeTransmission"
	| "RevivePlayer"
	| "UseBandage"
	| "ReplaceBattery"
	| "RepairStructure"
	| "FuelCampfire"
	| "IgniteCampfire"
	| "SearchContainer"
	| "PickupLoot"
	| "LootBackpack"
	| "OpenDoor"
	| "CloseDoor"
export type RequestSnapshot = Req
export type SetReady = Req & { ready: boolean }
export type SetMovementMode = Req & { mode: "Walk" | "Sprint" | "Crouch" }
export type SetFlashlight = Req & { enabled: boolean }
export type SetFlashlightAim = Req & { direction: Vector3 }
export type EquipTool = Req & { slot: number }
export type HitResource = Req & { targetId: string }
export type CraftItem = Req & { recipeId: string, count: number }
export type PlaceStructure = Req & { placement: Placement }
export type DropObjective = Req
export type BeginInteraction = Req & { action: InteractionAction, targetId: string }
export type CancelInteraction = Req & { interactionId: string }
export type Shout = Req
export type DebugBridge = Req & { enabled: boolean }
export type Phase = "Lobby" | "Day" | "Dusk" | "Night" | "Dawn" | "Result"
export type ItemId = "Madera" | "Piedra" | "Pila" | "Chatarra" | "Hacha" | "Pico" | "Venda"
export type PieceId = "Bateria" | "Antena" | "Transceptor" | "Cristal"
export type LifeState = "Alive" | "Downed" | "Spectating"
export type Stack = { slot: number, itemId: ItemId, count: number }
export type MetaView = {
	runsPlayed: number,
	wins: number,
	highestNightReached: number,
	piecesRecovered: number,
	earlyRescues: number,
	bestRescueNight: number?,
}
export type PlayerView = {
	id: string,
	userId: number,
	participant: boolean,
	ready: boolean,
	life: LifeState,
	health: number,
	maxHealth: number,
	flashlightOn: boolean,
	flashlightDirection: Vector3,
	carrying: PieceId?,
}
export type SelfView = {
	profile: "Loading" | "Ready" | "Unavailable",
	save: "Pending" | "Saved" | "Unavailable",
	stamina: number,
	maxStamina: number,
	battery: number,
	maxBattery: number,
	moveMode: "Walk" | "Sprint" | "Crouch",
	equippedSlot: number,
	inventory: { Stack },
	meta: MetaView?,
	bleedoutAt: number?,
	soloChanceAvailable: boolean,
	autoReviveAt: number?,
	interaction: { id: string, action: InteractionAction, targetId: string, startedAt: number, endsAt: number }?,
}
export type PieceView = {
	id: PieceId,
	entityId: string,
	state: "World" | "Carried" | "Installed",
	discovered: boolean,
	carrierUserId: number?,
	droppedPosition: Vector3?,
}
export type StructureView = {
	id: string,
	pieceId: "Cimiento" | "Pared" | "MarcoPuerta" | "Fogata",
	health: number,
	maxHealth: number,
	doorOpen: boolean?,
	fireLit: boolean?,
	fuelSeconds: number?,
}
export type ContainerView =
	{ id: string, kind: "LootContainer" | "Loot" | "Backpack", open: boolean, stacks: { Stack } }
export type RunResult = {
	outcome: "Rescued" | "Annihilation" | "OutOfTime",
	night: number,
	durationSeconds: number,
	installedPieces: number,
	transmissionSeconds: number,
	rescuedUserIds: { number },
}
export type Snapshot = {
	protocolVersion: number,
	runId: string,
	revision: number,
	serverTime: number,
	phase: Phase,
	day: number,
	night: number,
	phaseEndsAt: number,
	rosterSize: number,
	players: { PlayerView },
	self: SelfView,
	objectives: {
		radioId: string,
		pieces: { PieceView },
		installedCount: number,
		transmissionState: "Incomplete" | "Ready" | "Transmitting" | "Paused" | "Complete",
		elapsedSeconds: number,
		requiredSeconds: number,
		completedNight: number?,
	},
	structures: { StructureView },
	containers: { ContainerView },
	result: RunResult?,
}
export type ResultCode =
	"Ok"
	| "Accepted"
	| "InvalidPayload"
	| "RateLimited"
	| "StaleRun"
	| "NotReady"
	| "WrongPhase"
	| "NotAlive"
	| "HandsBusy"
	| "Busy"
	| "NotFound"
	| "OutOfRange"
	| "Blocked"
	| "WrongTool"
	| "Cooldown"
	| "InsufficientItems"
	| "InventoryFull"
	| "Occupied"
	| "LimitReached"
	| "InvalidState"
	| "Cancelled"
	| "InternalError"
export type ActionResult = {
	runId: string,
	requestId: string,
	ok: boolean,
	code: ResultCode,
	revision: number,
	entityId: string?,
}
export type InteractionState = {
	runId: string,
	interactionId: string,
	requestId: string,
	action: InteractionAction,
	targetId: string,
	state: "Started" | "Completed" | "Cancelled",
	startedAt: number,
	endsAt: number,
	code: ResultCode,
}
export type CueId =
	"ResourceHit"
	| "ResourceDepleted"
	| "StructureBuilt"
	| "StructureHit"
	| "StructureBroken"
	| "DoorOpened"
	| "DoorClosed"
	| "ContainerOpened"
	| "Revive"
	| "Shout"
	| "CampfireLit"
	| "CampfireOut"
	| "PieceInstalled"
	| "TransmissionStarted"
	| "TransmissionPaused"
	| "TransmissionComplete"
	| "ThreatPresence"
	| "ThreatFar"
	| "ThreatNear"
	| "ThreatVeryNear"
	| "ThreatAttack"
	| "DaySighting"
export type Feedback = { runId: string, cueId: CueId, sourceId: string, position: Vector3, at: number }
return {}
