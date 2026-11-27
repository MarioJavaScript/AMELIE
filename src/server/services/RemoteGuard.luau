--!strict
-- Validacion F0-4 M1. Solo valida forma y frecuencia; gameplay valida estado/rango/materiales.
local Guard = {}
local config: any
local buckets: { [Player]: { [string]: { tokens: number, at: number } } } = {}
local keys: { [string]: { [string]: string } } = {
	RequestSnapshot = { requestId = "id", runId = "id" },
	SetReady = { requestId = "id", runId = "id", ready = "boolean" },
	SetMovementMode = { requestId = "id", runId = "id", mode = "mode" },
	SetFlashlight = { requestId = "id", runId = "id", enabled = "boolean" },
	SetFlashlightAim = { requestId = "id", runId = "id", direction = "direction" },
	EquipTool = { requestId = "id", runId = "id", slot = "slot" },
	HitResource = { requestId = "id", runId = "id", targetId = "id" },
	CraftItem = { requestId = "id", runId = "id", recipeId = "id", count = "count" },
	PlaceStructure = { requestId = "id", runId = "id", placement = "placement" },
	DropObjective = { requestId = "id", runId = "id" },
	BeginInteraction = { requestId = "id", runId = "id", action = "action", targetId = "id" },
	CancelInteraction = { requestId = "id", runId = "id", interactionId = "id" },
	Shout = { requestId = "id", runId = "id" },
	DebugBridge = { requestId = "id", runId = "id", enabled = "boolean" },
}
local actions = {
	PickupObjective = true,
	InstallObjective = true,
	StartTransmission = true,
	ResumeTransmission = true,
	RevivePlayer = true,
	UseBandage = true,
	ReplaceBattery = true,
	RepairStructure = true,
	FuelCampfire = true,
	IgniteCampfire = true,
	SearchContainer = true,
	PickupLoot = true,
	LootBackpack = true,
	OpenDoor = true,
	CloseDoor = true,
}

local function finite(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end
local function integer(value: unknown, minimum: number, maximum: number): boolean
	return finite(value)
		and math.floor(value :: number) == value
		and (value :: number) >= minimum
		and (value :: number) <= maximum
end
local function id(value: unknown, allowEmpty: boolean): boolean
	if typeof(value) ~= "string" then
		return false
	end
	if #value > config.MaxIdBytes then
		return false
	end
	if value == "" then
		return allowEmpty
	end
	return string.match(value, "^[%w_:%-]+$") ~= nil
end
local function placement(value: unknown): boolean
	if typeof(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	local piece = (value :: any).pieceId
	local allowed: { [string]: boolean }
	if piece == "Cimiento" then
		allowed = { pieceId = true, gridX = true, gridZ = true, quarterTurns = true }
	elseif piece == "Pared" or piece == "MarcoPuerta" then
		allowed = { pieceId = true, parentId = true, socketId = true }
	elseif piece == "Fogata" then
		allowed = { pieceId = true }
	else
		return false
	end
	local count = 0
	for key in value :: any do
		if typeof(key) ~= "string" or not allowed[key] then
			return false
		end
		count += 1
	end
	local required = if piece == "Cimiento" then 4 elseif piece == "Fogata" then 1 else 3
	if count ~= required then
		return false
	end
	if piece == "Cimiento" then
		return integer((value :: any).gridX, -config.MaxGridCoordinate, config.MaxGridCoordinate)
			and integer((value :: any).gridZ, -config.MaxGridCoordinate, config.MaxGridCoordinate)
			and integer((value :: any).quarterTurns, 0, 3)
	end
	if piece == "Fogata" then
		return true
	end
	local socket = (value :: any).socketId
	return id((value :: any).parentId, false)
		and (socket == "EdgeN" or socket == "EdgeE" or socket == "EdgeS" or socket == "EdgeW")
end
local function validField(kind: string, value: unknown, allowEmpty: boolean): boolean
	if kind == "id" then
		return id(value, allowEmpty)
	end
	if kind == "boolean" then
		return typeof(value) == "boolean"
	end
	if kind == "mode" then
		return value == "Walk" or value == "Sprint" or value == "Crouch"
	end
	if kind == "action" then
		return typeof(value) == "string" and #value <= config.MaxIdBytes and actions[value :: string] == true
	end
	if kind == "slot" then
		return integer(value, 0, 12)
	end
	if kind == "count" then
		return integer(value, 1, 5)
	end
	if kind == "placement" then
		return placement(value)
	end
	if kind == "direction" then
		if typeof(value) ~= "Vector3" then
			return false
		end
		local vector = value :: Vector3
		return finite(vector.X)
			and finite(vector.Y)
			and finite(vector.Z)
			and vector.Magnitude >= 0.99
			and vector.Magnitude <= 1.01
	end
	return false
end
local function consume(player: Player, name: string, now: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	for _, bucketName in { "_global", name } do
		local limit = if bucketName == "_global"
			then { Rate = config.GlobalRate, Burst = config.GlobalBurst }
			else config.RateLimits[bucketName]
		if not limit then
			return false
		end
		local bucket = playerBuckets[bucketName]
		if not bucket then
			bucket = { tokens = limit.Burst, at = now }
			playerBuckets[bucketName] = bucket
		end
		bucket.tokens = math.min(limit.Burst, bucket.tokens + math.max(0, now - bucket.at) * limit.Rate)
		bucket.at = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
	end
	return true
end
function Guard.Init(networkConfig: any)
	config = networkConfig
end
function Guard.Forget(player: Player)
	buckets[player] = nil
end
function Guard.Check(player: Player, name: string, ...: unknown): (boolean, string, any?)
	if not consume(player, name, os.clock()) then
		return false, "RateLimited", nil
	end
	if select("#", ...) ~= 1 then
		return false, "InvalidPayload", nil
	end
	local payload = select(1, ...)
	if typeof(payload) ~= "table" or getmetatable(payload) ~= nil then
		return false, "InvalidPayload", nil
	end
	local schema = keys[name]
	if not schema then
		return false, "InvalidPayload", nil
	end
	local count = 0
	local bytes = 0
	for key, value in payload :: any do
		if typeof(key) ~= "string" or not schema[key] then
			return false, "InvalidPayload", nil
		end
		count += 1
		bytes += #key
		if typeof(value) == "string" then
			bytes += #(value :: string)
		else
			bytes += 32
		end
		if count > config.MaxRequestKeys or bytes > config.MaxRequestBytes then
			return false, "InvalidPayload", nil
		end
	end
	local expected = 0
	for key, kind in schema do
		expected += 1
		if not validField(kind, (payload :: any)[key], key == "runId" and name == "RequestSnapshot") then
			return false, "InvalidPayload", nil
		end
	end
	if count ~= expected then
		return false, "InvalidPayload", nil
	end
	return true, "Ok", payload
end
return Guard
