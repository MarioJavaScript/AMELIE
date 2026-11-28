--!strict
-- Pose de sostener y golpe cosmetico de todos los personajes (docs/specs/jugador.md, «Herramienta en la mano»).
-- Todo es local: se aplica un offset al hombro (C0 de Motor6D o Transform de AnimationConstraint, no se replica) mientras exista HeldRight / HeldLeft.
-- El golpe de otros jugadores se dispara con el atributo SwingSeq; el propio se reproduce al enviar el golpe.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("PresentationConfig"))

local Controller = {}

export type Context = { [string]: unknown }
type Joint = Motor6D | AnimationConstraint
type Arm = { motor: Joint?, base: CFrame, applied: boolean }
type State = { right: Arm, left: Arm, swingAt: number?, isLocal: boolean, connections: { RBXScriptConnection } }

local localPlayer = Players.LocalPlayer
local connections: { RBXScriptConnection } = {}
local states: { [Model]: State } = {}

local function newArm(): Arm
	return { motor = nil, base = CFrame.identity, applied = false }
end

local function smooth(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

-- Desplazamiento de pitch del golpe: sube atras, baja al frente y recupera. nil al terminar.
local function swingPitch(state: State, now: number): number?
	local startedAt = state.swingAt
	if startedAt == nil then
		return nil
	end
	local pose = PresentationConfig.HeldPose
	local t = (now - startedAt) / pose.SwingSeconds
	if t >= 1 then
		state.swingAt = nil
		return nil
	end
	local windup, strike = pose.SwingWindupFraction, pose.SwingStrikeFraction
	if t < windup then
		return pose.SwingWindupDegrees * smooth(t / windup)
	elseif t < strike then
		return pose.SwingWindupDegrees
			+ (pose.SwingFollowDegrees - pose.SwingWindupDegrees) * smooth((t - windup) / (strike - windup))
	end
	return pose.SwingFollowDegrees * (1 - smooth((t - strike) / (1 - strike)))
end

-- R15 moderno usa AnimationConstraint en lugar de Motor6D; ambos tienen C0.
local function findMotor(character: Model, side: string): Joint?
	local upper = character:FindFirstChild(side .. "UpperArm") -- R15
	local holder = if upper ~= nil then upper else character:FindFirstChild("Torso") -- R6
	local motor = if holder ~= nil
		then holder:FindFirstChild(if upper ~= nil then side .. "Shoulder" else side .. " Shoulder")
		else nil
	return if motor ~= nil and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then motor else nil
end

-- Aplica (angles ~= nil) o restaura (angles == nil) la pose del brazo girando sobre el pivote del hombro.
local function setArm(character: Model, arm: Arm, side: string, angles: Vector3?)
	if angles == nil then
		-- El Animator reescribe el Transform de AnimationConstraint solo; el C0 de Motor6D hay que devolverlo.
		if arm.applied and arm.motor ~= nil and arm.motor.Parent ~= nil and arm.motor:IsA("Motor6D") then
			arm.motor.C0 = arm.base
		end
		arm.applied = false
		return
	end
	local motor = arm.motor
	if motor == nil or motor.Parent == nil then
		motor = findMotor(character, side)
		arm.motor, arm.applied = motor, false
		if motor == nil then
			return
		end
	end
	if not arm.applied then
		arm.base, arm.applied = motor.C0, true
	end
	local rotation = CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	if motor:IsA("Motor6D") then
		motor.C0 = CFrame.new(arm.base.Position) * rotation * arm.base.Rotation
	else
		-- AnimationConstraint: C0 es de solo lectura; el pose equivalente se escribe en Transform cada frame.
		motor.Transform = arm.base.Rotation:Inverse() * rotation * arm.base.Rotation
	end
end

local function armAngles(
	held: boolean,
	pose: { Pitch: number, Yaw: number, Roll: number },
	extraPitch: number?
): Vector3?
	if not held and extraPitch == nil then
		return nil
	end
	local base = if held then Vector3.new(pose.Pitch, pose.Yaw, pose.Roll) else Vector3.zero
	return base + Vector3.new(extraPitch or 0, 0, 0)
end

local function step(character: Model, state: State, now: number)
	local pose = PresentationConfig.HeldPose
	local heldRight = character:FindFirstChild("HeldRight")
	local heldLeft = character:FindFirstChild("HeldLeft")
	setArm(character, state.right, "Right", armAngles(heldRight ~= nil, pose.Right, swingPitch(state, now)))
	setArm(character, state.left, "Left", armAngles(heldLeft ~= nil, pose.Left, nil))
	-- La luz del propio jugador sale de la camara: el Beam del modelo en mano se apaga en local.
	if state.isLocal and heldLeft ~= nil then
		local beam = heldLeft:FindFirstChild("Beam", true)
		if beam ~= nil and beam:IsA("SpotLight") and beam.Enabled then
			beam.Enabled = false
		end
	end
end

local function untrack(character: Model)
	local state = states[character]
	if state == nil then
		return
	end
	setArm(character, state.right, "Right", nil)
	setArm(character, state.left, "Left", nil)
	for _, connection in state.connections do
		connection:Disconnect()
	end
	states[character] = nil
end

local function track(player: Player, character: Model)
	untrack(character)
	local state: State =
		{ right = newArm(), left = newArm(), swingAt = nil, isLocal = player == localPlayer, connections = {} }
	states[character] = state
	if not state.isLocal then
		table.insert(
			state.connections,
			character:GetAttributeChangedSignal("SwingSeq"):Connect(function()
				state.swingAt = os.clock()
			end)
		)
	end
end

local function watch(player: Player)
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			track(player, character)
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function(character)
			untrack(character)
		end)
	)
	if player.Character ~= nil then
		track(player, player.Character)
	end
end

function Controller.Init(_context: Context) end

function Controller.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	table.insert(
		connections,
		RunService.PreSimulation:Connect(function()
			local now = os.clock()
			for character, state in states do
				step(character, state, now)
			end
		end)
	)
end

function Controller.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for character in states do
		untrack(character)
	end
end

-- Golpe cosmetico inmediato del jugador local (no espera al servidor).
function Controller.PlaySwing()
	local character = localPlayer.Character
	local state = if character ~= nil then states[character] else nil
	if state ~= nil then
		state.swingAt = os.clock()
	end
end

return Controller
