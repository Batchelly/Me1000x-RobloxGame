--[[
	Main.server.luau
	Ponto de entrada do servidor do "Me x1000".
	1. Iluminação + mapa por código (MapBuilder.build(seed)): plots nas bordas + Cidade.
	2. Serviços: init(Services) -> start() em ordem fixa (injeção de dependência pela
	   tabela Services, sem requires circulares).
	3. Ciclo do jogador: onPlayerAdded -> DataService.load -> onPlayerLoaded -> onPlayerReady.
	4. Um único loop de simulação a cada Config.CloneTickRate (clones, bananas, moedas).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
require(Shared.Net) -- cria os RemoteEvents/RemoteFunctions antes de qualquer cliente pedir

local Build = script.Parent:WaitForChild("Build")
local ServiceModules = script.Parent:WaitForChild("Services")
local MapBuilder = require(Build:WaitForChild("MapBuilder"))

-- =========================================================================
-- Mundo
-- =========================================================================
MapBuilder.setupLighting()
local map = MapBuilder.build(Config.MapSeed)

-- =========================================================================
-- Serviços
-- =========================================================================
local ORDER = {
	"DataService",
	"MonetizationService",
	"SettingsService",
	"EconomyService",
	"LeaderboardService",
	"PlotService",
	"CharacterService",
	"CloneService",
	"TheftService",
	"RecordingService",
	"PickupService",
	"TrapService",
	"RetentionService",
	"DebugService",
}

-- Ordem em que os serviços recebem o perfil carregado.
local LOADED_ORDER = {
	"MonetizationService", -- passes primeiro (afetam slots, offline, dourado)
	"EconomyService", -- sessão, renda offline, velocidade
	"LeaderboardService", -- leaderstats
	"PlotService", -- constrói os níveis da base e a Pista
	"CloneService", -- template R6 + fitas salvas (na estante)
}

-- Ordem de saída: quem escreve no perfil vem antes do DataService.release.
local REMOVING_ORDER = {
	"RecordingService",
	"TheftService", -- ladrão saindo: a fita volta para o dono
	"DebugService",
	"TrapService",
	"CloneService",
	"PickupService",
	"EconomyService",
	"LeaderboardService",
	"PlotService", -- libera o plot
	"MonetizationService",
	"CharacterService",
}

local Services: { [string]: any } = { Map = map }
for _, name in ORDER do
	Services[name] = require(ServiceModules:WaitForChild(name))
end
for _, name in ORDER do
	local service = Services[name]
	if service.init then
		service.init(Services)
	end
end
for _, name in ORDER do
	local service = Services[name]
	if service.start then
		service.start()
	end
end

-- =========================================================================
-- Jogadores
-- =========================================================================
local function onPlayerAdded(player: Player)
	Services.PlotService.onPlayerAdded(player) -- recebe um plot e nasce nele
	Services.CharacterService.onPlayerAdded(player)

	local profile = Services.DataService.load(player)
	if not profile then
		return
	end
	if not player.Parent then
		Services.DataService.release(player)
		return
	end
	for _, name in LOADED_ORDER do
		local ok, err = pcall(Services[name].onPlayerLoaded, player, profile)
		if not ok then
			warn(string.format("[Main] %s.onPlayerLoaded falhou para %s: %s", name, player.Name, tostring(err)))
		end
	end
	Services.MonetizationService.onPlayerReady(player)
	Services.EconomyService.markDirty(player)
end

local function runRemoving(player: Player)
	for _, name in REMOVING_ORDER do
		local service = Services[name]
		if service.onPlayerRemoving then
			local ok, err = pcall(service.onPlayerRemoving, player)
			if not ok then
				warn(string.format("[Main] %s.onPlayerRemoving falhou: %s", name, tostring(err)))
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	runRemoving(player)
	Services.DataService.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		runRemoving(player)
	end
	Services.DataService.releaseAll()
end)

-- =========================================================================
-- Loop de simulação (10 Hz)
-- =========================================================================
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < Config.CloneTickRate then
		return
	end
	accumulator = math.min(accumulator - Config.CloneTickRate, Config.CloneTickRate)
	local now = Clock.now()
	debug.profilebegin("MeX1000.Tick")
	Services.TrapService.tick(now)
	Services.CloneService.tick(now)
	Services.PickupService.tick(now)
	Services.PickupService.flush()
	debug.profileend()
end)

print(
	string.format(
		"[Me x1000] servidor pronto: mapa seed %d, %d coletáveis na Cidade, %d Parts",
		map.seed,
		#map.spawns,
		map.partCount
	)
)
