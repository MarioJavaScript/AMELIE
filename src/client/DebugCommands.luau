--!strict
-- Comandos de chat solo para Studio (pruebas del cliente sin servidor completo). No hacen nada fuera de Studio.
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local DebugCommands = {}

function DebugCommands.Register(name: string, handler: ({ string }) -> ())
	if not RunService:IsStudio() then
		return
	end
	local folder = TextChatService:FindFirstChild("TextChatCommands")
	if folder == nil then
		warn("DebugCommands: TextChatService.TextChatCommands no existe; el comando /" .. name .. " no esta disponible")
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "Debug_" .. name
	command.PrimaryAlias = "/" .. name
	command.Parent = folder
	command.Triggered:Connect(function(_origin: TextSource, text: string)
		local args = string.split(text, " ")
		table.remove(args, 1)
		handler(args)
	end)
end

return DebugCommands
