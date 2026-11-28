--!strict
-- Consultas espaciales del servidor (rango contra Hitbox y linea de vision). Sin estado.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Spatial = {}

-- Punto de `part` mas cercano a `point` (caja orientada).
function Spatial.ClosestPoint(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return part.CFrame:PointToWorldSpace(
		Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
	)
end

-- true si no hay geometria solida entre origin y target; ignora `ignore` y los personajes.
function Spatial.HasLineOfSight(origin: Vector3, target: Vector3, ignore: Instance): boolean
	local filter: { Instance } = { ignore }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return Workspace:Raycast(origin, target - origin, params) == nil
end

return Spatial
