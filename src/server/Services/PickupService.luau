--[[
	PickupService.luau
	Moedas (1), gemas (10) e baús (100) nos pontos gerados pelo MapBuilder (Cidade) e pelo
	PlotBuilder (Pista de Gravação de cada base).

	REGRA PRINCIPAL: o primeiro clone ou jogador que encostar leva. O valor é multiplicado
	pelo multiplicador do DONO. Tudo é decidido no servidor:
	- Clones: CloneService varre o segmento percorrido a cada 0,1 s (sweep).
	- Jogadores: este serviço varre o segmento do HumanoidRootPart a cada 0,1 s.
	Busca por spatial hash (células de Config.SpatialCellSize studs).

	Grupos: "city" (fixo) e "plot<N>" (moedas da Pista da base N; só o dono e os clones
	dele coletam). Grupos de plot são criados/removidos quando a base muda.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Path = require(Shared.Path)
local SpatialHash = require(Shared.SpatialHash)
local Types = require(Shared.Types)

local Prefabs = require(script.Parent.Parent.Build.Prefabs)

local PickupService = {}

type Pickup = {
	kind: string,
	visualKind: string, -- "Coin" | "Gem" | "Chest" (sem o prefixo Track)
	value: number,
	radius: number,
	respawn: number,
	x: number,
	y: number,
	z: number,
	position: Vector3,
	vip: boolean,
	plot: number?, -- só o dono deste plot (e os clones dele) coleta
	model: Model,
	parts: { BasePart },
	transparency: { number },
	active: boolean,
	respawnAt: number,
	removed: boolean,
}

export type SpawnSpec = { kind: string, position: Vector3, vip: boolean? }

local Services
local groups: { [string]: { Pickup } } = {}
local hash = SpatialHash.new(Config.SpatialCellSize)
local maxRadius = 0
local fxQueue: { Types.PickupFx } = {}
local coinRainUntil = 0
local playerLast: { [Player]: Vector3 } = {}
local playerCollectors: { [Player]: any } = {}
local folder: Folder

local NO_RAIN = { Chest = true, TrackChest = true }

local function setVisible(pickup: Pickup, visible: boolean)
	pickup.model:SetAttribute("Active", visible)
	for i, part in pickup.parts do
		part.Transparency = if visible then pickup.transparency[i] else 1
	end
end

local function respawnDelay(pickup: Pickup): number
	if not NO_RAIN[pickup.kind] and os.clock() < coinRainUntil then
		return pickup.respawn / Config.CoinRainFactor
	end
	return pickup.respawn
end

local function collect(pickup: Pickup, collector)
	pickup.active = false
	pickup.respawnAt = os.clock() + respawnDelay(pickup)
	setVisible(pickup, false)
	local amount =
		Services.EconomyService.award(collector.player, pickup.value, collector.golden, collector.kind == "clone")
	if collector.clone then
		collector.clone.minuteEarned += amount
	end
	table.insert(fxQueue, {
		pos = pickup.position,
		amount = amount,
		color = collector.color,
		kind = pickup.visualKind,
	})
end

-- Varre o segmento A->B do coletor. bonus = raio extra (jogadores).
function PickupService.sweep(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	collector,
	bonus: number
)
	local r = maxRadius + bonus
	hash:queryRect(
		math.min(ax, bx) - r,
		math.min(az, bz) - r,
		math.max(ax, bx) + r,
		math.max(az, bz) + r,
		function(pickup: Pickup)
			if not pickup.active then
				return
			end
			local radius = pickup.radius + bonus
			if Path.segmentDistanceSq(ax, ay, az, bx, by, bz, pickup.x, pickup.y, pickup.z) > radius * radius then
				return
			end
			if pickup.plot and Services.PlotService.ownerOf(pickup.plot) ~= collector.player then
				return
			end
			if pickup.vip and not Services.MonetizationService.ownsPass(collector.player, "VIP") then
				return
			end
			collect(pickup, collector)
		end
	)
end

-- =========================================================================
-- Grupos de coletáveis
-- =========================================================================
function PickupService.addGroup(key: string, list: { SpawnSpec }, plotIndex: number?)
	local group = groups[key]
	if not group then
		group = {}
		groups[key] = group
	end
	for _, spawnPoint in list do
		local config = Config.Pickups[spawnPoint.kind]
		if not config then
			continue
		end
		local model
		if spawnPoint.kind == "Gem" or spawnPoint.kind == "TrackGem" then
			model = Prefabs.gem(spawnPoint.position)
		elseif spawnPoint.kind == "Chest" or spawnPoint.kind == "TrackChest" then
			model = Prefabs.chest(spawnPoint.position)
		else
			model = Prefabs.coin(spawnPoint.position)
		end
		local visualKind = string.gsub(spawnPoint.kind, "^Track", "")
		model:SetAttribute("Kind", visualKind)
		model:SetAttribute("Active", true)
		model:SetAttribute("Vip", spawnPoint.vip == true)
		if plotIndex then
			model:SetAttribute("Plot", plotIndex)
		end
		model:AddTag("Pickup")
		model.Parent = folder

		local parts, transparency = {}, {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				table.insert(transparency, d.Transparency)
			end
		end

		local pos = spawnPoint.position
		local pickup: Pickup = {
			kind = spawnPoint.kind,
			visualKind = visualKind,
			value = config.Value,
			radius = config.Radius,
			respawn = config.Respawn,
			x = pos.X,
			y = pos.Y,
			z = pos.Z,
			position = pos,
			vip = spawnPoint.vip == true,
			plot = plotIndex,
			model = model,
			parts = parts,
			transparency = transparency,
			active = true,
			respawnAt = 0,
			removed = false,
		}
		table.insert(group, pickup)
		hash:insert(pickup, pos.X, pos.Z)
		maxRadius = math.max(maxRadius, config.Radius)
	end
end

function PickupService.removeGroup(key: string)
	local group = groups[key]
	if not group then
		return
	end
	groups[key] = nil
	for _, pickup in group do
		pickup.removed = true
		pickup.active = false
		hash:remove(pickup, pickup.x, pickup.z)
		pickup.model:Destroy()
	end
end

function PickupService.coinRainLeft(): number
	return math.max(0, math.floor(coinRainUntil - os.clock()))
end

-- Produto CoinRain: 5 min de respawn 3x mais rápido para o servidor todo.
function PickupService.startCoinRain()
	coinRainUntil = math.max(coinRainUntil, os.clock()) + Config.CoinRainDuration
	-- Começa com tudo cheio: o que estiver apagado volta em até 1 s.
	for _, group in groups do
		for _, pickup in group do
			if not pickup.active and not NO_RAIN[pickup.kind] then
				pickup.respawnAt = math.min(pickup.respawnAt, os.clock() + math.random())
			end
		end
	end
	Services.EconomyService.markAllDirty()
end

local function collectorFor(player: Player)
	local collector = playerCollectors[player]
	if not collector then
		collector = { player = player, golden = false, kind = "player", color = Color3.new(1, 1, 1) }
		playerCollectors[player] = collector
	end
	collector.color = Services.CharacterService.getColor(player)
	return collector
end

function PickupService.tick(_now: number)
	local clock = os.clock()
	for _, group in groups do
		for _, pickup in group do
			if not pickup.active and not pickup.removed and clock >= pickup.respawnAt then
				pickup.active = true
				setVisible(pickup, true)
			end
		end
	end

	-- Jogadores coletam pelo segmento percorrido desde o último tick.
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 or not Services.DataService.get(player) then
			playerLast[player] = nil
			continue
		end
		local pos = root.Position
		local last = playerLast[player]
		if not last or (pos - last).Magnitude > 30 then
			last = pos -- teleporte/respawn: não varre o trecho
		end
		playerLast[player] = pos
		PickupService.sweep(
			last.X,
			last.Y,
			last.Z,
			pos.X,
			pos.Y,
			pos.Z,
			collectorFor(player),
			Config.PlayerPickupRadiusBonus
		)
	end
end

-- Envia os popups "+N" acumulados no tick (um único FireAllClients).
function PickupService.flush()
	if #fxQueue > 0 then
		Net.fireAll("PickupFx", fxQueue)
		fxQueue = {}
	end
end

function PickupService.count(): number
	local n = 0
	for _, group in groups do
		n += #group
	end
	return n
end

function PickupService.init(services)
	Services = services
	folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = workspace
	PickupService.addGroup("city", services.Map.spawns, nil)
	print(string.format("[PickupService] %d coletáveis na Cidade", #groups.city))
end

function PickupService.onPlayerRemoving(player: Player)
	playerLast[player] = nil
	playerCollectors[player] = nil
end

return PickupService
