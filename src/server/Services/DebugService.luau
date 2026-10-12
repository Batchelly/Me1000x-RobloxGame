--[[
	DebugService.luau
	Comandos de chat para testar (no Studio, ou para Config.Admins):
		/spawnclones N   cria N clones simulados (teste de desempenho: /spawnclones 240)
		/clearclones     remove os clones de teste
		/cash N          soma N de Cash
		/bananas N       soma N bananas
		/stress N        teste de carga: bases livres viram "bots" nível 6 + N clones
		                 espalhados entre a Cidade e as Pistas (padrão 240)
		/level           constrói o próximo nível da sua base de graça
	Os clones de teste não são salvos e não contam nos slots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MapLayout = require(Shared.MapLayout)
local Path = require(Shared.Path)

local PlotBuilder = require(script.Parent.Parent.Build.PlotBuilder)

local DebugService = {}

local Services
local lastCommand: { [Player]: { text: string, at: number } } = {}

local function isAllowed(player: Player): boolean
	if RunService:IsStudio() and Config.DebugCommandsInStudio then
		return true
	end
	return table.find(Config.Admins, player.UserId) ~= nil
end

-- Gera um caminho em círculo no chão do mapa, com pulos ocasionais.
local function syntheticPath(rng: Random, rayParams: RaycastParams): buffer
	local cx, cz = rng:NextNumber(-105, 105), rng:NextNumber(-105, 105)
	local radius = rng:NextNumber(6, 22)
	local speed = rng:NextNumber(12, 18)
	local omega = speed / radius * (if rng:NextNumber() < 0.5 then 1 else -1)
	local theta0 = rng:NextNumber(0, math.pi * 2)
	local seconds = 20
	local n = seconds * Config.RecordHz + 1
	local xs, ys, zs, yaws, flags = {}, {}, {}, {}, {}
	local groundY = 0
	for i = 1, n do
		local t = (i - 1) / Config.RecordHz
		local theta = theta0 + omega * t
		local x = math.clamp(cx + math.cos(theta) * radius, -125, 125)
		local z = math.clamp(cz + math.sin(theta) * radius, -125, 125)
		if i % 3 == 1 then
			local hit = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -200, 0), rayParams)
			groundY = if hit then hit.Position.Y else 0
		end
		-- tangente do círculo = direção do movimento
		local dx, dz = -math.sin(theta) * omega, math.cos(theta) * omega
		xs[i], ys[i], zs[i] = x, groundY + 3, z
		yaws[i] = math.atan2(-dx, -dz)
		flags[i] = if i % 40 == 0 then Path.FLAG_JUMP else 0
	end
	return Path.encode(xs, ys, zs, yaws, flags, Config.RecordHz, Config.PathScale)
end

function DebugService.spawnClones(player: Player, count: number)
	count = math.clamp(math.floor(count), 1, Config.DebugMaxClones)
	Services.CloneService.removeDebug(player)
	Services.CloneService.ensureTemplate(player)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { Services.Map.root }
	local rng = Random.new(player.UserId + os.time())
	local now = Clock.now()
	for i = 1, count do
		local buf = syntheticPath(rng, rayParams)
		Services.CloneService.create(player, 1000 + i, buf, {
			debug = true,
			startTime = now - rng:NextNumber(0, 20),
		})
		if i % 20 == 0 then
			task.wait() -- espalha o custo de rede/raycast
		end
	end
	Net.fire("Notify", player, "debug_spawned", { n = count }, "info")
end

-- Caminho de 20 s dando voltas na Pista de Gravação do plot (espaço local -> mundo).
local function trackPath(plotIndex: number, offset: number): buffer
	local half = { 14, 10 }
	local center = MapLayout.Local.TrackCenter
	local perimeter = 4 * (half[1] + half[2])
	local n = 20 * Config.RecordHz + 1
	local xs, ys, zs, yaws, flags = {}, {}, {}, {}, {}
	for i = 1, n do
		local s = (offset + (i - 1) / Config.RecordHz * 16) % perimeter
		local lx, lz, dx, dz
		local w, h = half[1] * 2, half[2] * 2
		if s < w then
			lx, lz, dx, dz = -half[1] + s, -half[2], 1, 0
		elseif s < w + h then
			lx, lz, dx, dz = half[1], -half[2] + (s - w), 0, 1
		elseif s < 2 * w + h then
			lx, lz, dx, dz = half[1] - (s - w - h), half[2], -1, 0
		else
			lx, lz, dx, dz = -half[1], half[2] - (s - 2 * w - h), 0, -1
		end
		xs[i], ys[i], zs[i] = center[1] + lx, MapLayout.FLOOR_TOP + 3, center[2] + lz
		yaws[i] = math.atan2(-dx, -dz)
		flags[i] = 0
	end
	local localBuf = Path.encode(xs, ys, zs, yaws, flags, Config.RecordHz, Config.PathScale)
	local _, _, yaw = MapLayout.plot(plotIndex)
	return Path.mapXZ(localBuf, function(x, z, rot)
		local wx, wz = MapLayout.toWorld(plotIndex, x, z)
		return wx, wz, rot + yaw
	end) :: buffer
end

-- Teste de carga: simula 8 jogadores (bases livres viram bots nível 6) e N clones.
function DebugService.stress(player: Player, count: number)
	count = math.clamp(math.floor(count), 1, Config.DebugMaxClones)
	Services.CloneService.removeDebug(player)
	Services.CloneService.ensureTemplate(player)
	local plots = Services.PlotService.plots()
	local botPlots = {}
	for index, plot in plots do
		if not Services.PlotService.ownerOf(index) then
			plot.model:SetAttribute("Bot", true)
			PlotBuilder.setOwner(plot, "Bot " .. index, nil, Config.BaseColors[index])
			for level = 1, #Config.BaseLevels do
				PlotBuilder.buildLevel(plot, level, false)
			end
			PlotBuilder.setShelfCapacity(plot, 30)
			table.insert(botPlots, index)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { Services.Map.root }
	local rng = Random.new(os.time())
	local now = Clock.now()
	for i = 1, count do
		local buf, name
		if #botPlots > 0 and i % 2 == 0 then
			local index = botPlots[(i // 2) % #botPlots + 1]
			buf = trackPath(index, rng:NextNumber(0, 96))
			name = "Bot " .. index
		else
			buf = syntheticPath(rng, rayParams)
			name = "Bot " .. (i % 8 + 1)
		end
		Services.CloneService.create(player, 1000 + i, buf, {
			debug = true,
			startTime = now - rng:NextNumber(0, 20),
			displayName = name,
		})
		if i % 20 == 0 then
			task.wait()
		end
	end
	Net.fire("Notify", player, "debug_stress", { plots = #botPlots, n = count }, "info")
end

local function clearBots()
	for index, plot in Services.PlotService.plots() do
		if plot.model:GetAttribute("Bot") and not Services.PlotService.ownerOf(index) then
			plot.model:SetAttribute("Bot", nil)
			PlotBuilder.clearLevels(plot)
			PlotBuilder.setOwner(plot, nil, nil, nil)
			PlotBuilder.setShelfCapacity(plot, 0)
		end
	end
end

local function runCommand(player: Player, text: string)
	if not isAllowed(player) then
		return
	end
	-- Evita rodar duas vezes quando TextChatCommand e Player.Chatted disparam juntos.
	local previous = lastCommand[player]
	if previous and previous.text == text and os.clock() - previous.at < 1 then
		return
	end
	lastCommand[player] = { text = text, at = os.clock() }

	local args = string.split(text, " ")
	local command = string.lower(args[1] or "")
	local amount = tonumber(args[2])
	if command == "/spawnclones" then
		DebugService.spawnClones(player, amount or 240)
	elseif command == "/clearclones" then
		Services.CloneService.removeDebug(player)
		clearBots()
		Net.fire("Notify", player, "debug_cleared", nil, "info")
	elseif command == "/stress" then
		DebugService.stress(player, amount or 240)
	elseif command == "/level" then
		Services.PlotService.buyLevel(player, true)
	elseif command == "/cash" then
		Services.EconomyService.addCash(player, amount or 10000)
	elseif command == "/bananas" then
		Services.EconomyService.addBananas(player, amount or 10)
	end
end

function DebugService.init(services)
	Services = services
end

function DebugService.start()
	-- TextChatService (padrão em jogos novos): comandos que não aparecem no chat.
	local commands = {
		{ name = "SpawnClones", alias = "/spawnclones" },
		{ name = "ClearClones", alias = "/clearclones" },
		{ name = "Cash", alias = "/cash" },
		{ name = "Bananas", alias = "/bananas" },
		{ name = "Stress", alias = "/stress" },
		{ name = "Level", alias = "/level" },
	}
	local ok = pcall(function()
		for _, info in commands do
			local command = Instance.new("TextChatCommand")
			command.Name = "MeX1000_" .. info.name
			command.PrimaryAlias = info.alias
			command.Triggered:Connect(function(textSource: TextSource, text: string)
				local player = Players:GetPlayerByUserId(textSource.UserId)
				if player then
					runCommand(player, text)
				end
			end)
			command.Parent = TextChatService
		end
	end)
	if not ok then
		warn("[DebugService] TextChatCommand indisponível; usando Player.Chatted")
	end

	-- Chat legado (fallback).
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			if string.sub(message, 1, 1) == "/" then
				runCommand(player, message)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

function DebugService.onPlayerRemoving(player: Player)
	Services.CloneService.removeDebug(player)
	lastCommand[player] = nil
end

return DebugService
