--[[
	Config.luau
	TODOS os números de balanceamento e IDs (produtos, passes, sons, ícones) do "Me x1000".

	Este módulo é PURO (não usa nenhuma API do Roblox) para poder ser testado fora
	do Studio com o Lune (`lune run tests/run`). Mantenha assim: nada de BrickColor,
	Vector3, game:GetService etc. neste arquivo.
]]

local Config = {}

-- =========================================================================
-- Geral / debug
-- =========================================================================
Config.GameName = "Me x1000"
Config.Version = 2
Config.MapSeed = 1 -- semente do MapBuilder.build(seed). Troque toda semana para gerar um "mapa novo".
Config.MaxPlayers = 8 -- defina o mesmo valor em Game Settings > Places > Max Players.

-- UserIds que podem usar comandos de debug (/spawnclones etc.) fora do Studio.
Config.Admins = {} :: { number }
Config.DebugCommandsInStudio = true -- no Studio qualquer jogador pode usar os comandos de debug
Config.DebugOwnAllPassesInStudio = false -- true = no Studio você "tem" todos os passes (para testar)
Config.DebugBananasHitOwnClones = false -- true = sua banana derruba seus próprios clones (teste solo)
Config.DebugMaxClones = 300 -- teto do /spawnclones
Config.MaxPartsBudget = 8000 -- aviso no Output se o mapa passar disso

-- =========================================================================
-- Mapa (layout em anel: 8 plots nas bordas + Cidade de Blocos no centro)
-- =========================================================================
Config.Map = {
	PlotCount = 8,
	PlotSize = 70, -- cada plot tem 70x70 studs
	PlotRadius = 192, -- distância do centro do mapa ao centro de cada plot (testado: não invade a rua)
	PlotAngleOffset = 22.5, -- graus; os plots ficam entre as avenidas (0°, 90°...)
	CityHalf = 115, -- a cidade ocupa -115..115 em X e Z
	RingRoadWidth = 12, -- rua em volta da cidade
	GroundHalf = 245, -- chão vai de -245 a 245; depois disso, montanhas
	MountainDepth = 40,
}

-- =========================================================================
-- Movimento do jogador (avatar R6)
-- =========================================================================
Config.BaseWalkSpeed = 16
Config.JumpPower = 50 -- R6 usa JumpPower (altura ~6,4 studs com gravidade 196,2)
Config.RespawnTime = 3
Config.TrampolinePower = 110 -- velocidade vertical aplicada pelo trampolim (altura ~30 studs)
Config.ConveyorSpeed = 20 -- velocidade das esteiras (studs/s)
Config.Sprint = {
	Multiplier = 1.4, -- segurar Shift multiplica a WalkSpeed atual (upgrades e carga de fita inclusos)
	FieldOfView = 76, -- FOV da câmera correndo
	NormalFieldOfView = 70,
}

-- =========================================================================
-- Gravação
-- =========================================================================
Config.RecordHz = 10 -- amostras por segundo do HumanoidRootPart (o servidor amostra)
Config.RecordSeconds = 20 -- duração base da gravação
Config.RecordSecondsWithPass = 40 -- duração base com o passe LongRecord
Config.RecordUpgradeStep = 2 -- cada nível do upgrade "Tempo" soma 2 s
Config.RecordUpgradeMaxLevel = 5 -- teto: 20 + 10 = 30 s (ou 40 + 10 = 50 s com passe)
Config.MinRecordSeconds = 3 -- gravações menores que isso são descartadas
Config.PathScale = 20 -- precisão da compressão: 20 unidades int16 por stud (0,05 stud)
Config.MaxSamples = 600 -- teto absoluto de amostras por gravação (60 s a 10 Hz)

-- Anti-teleporte: amostra é inválida se a distância percorrida em dt passar de
-- velocidadeMáxima * dt * TeleportTolerance (+ TeleportFlatSlack).
Config.TeleportTolerance = 1.5
Config.TeleportFlatSlack = 1 -- folga fixa em studs (jitter de física)
Config.HorizontalSpeedSlack = 26 -- soma à WalkSpeed: esteira (20) + empurrões
Config.MaxVerticalSpeed = 230 -- queda da torre (~180 studs/s) + trampolim

-- =========================================================================
-- Clones / Fitas
-- =========================================================================
Config.RebirthSlotBonus = 1 -- cada rebirth dá +1 slot de fita permanente
Config.MaxClonesPerPlayer = 30 -- teto de desempenho (8 jogadores x 30 = 240 clones) = vagas da estante
Config.CloneTickRate = 0.1 -- o servidor simula/coleta a cada 0,1 s
Config.GoldenCloneMultiplier = 3 -- clone dourado (passe GoldenClone) rende 3x
Config.CloneTransparency = 0.2
Config.TapeColors = { "Bright red", "Bright blue", "Bright yellow", "Bright green", "Bright orange", "Bright violet" }

-- Renderização no cliente
Config.MaxRenderedClones = 120 -- padrão; o jogador escolhe 30/60/120 em Configurações
Config.CloneQualityOptions = { 30, 60, 120 }
Config.LodUpdateInterval = 0.5 -- segundos entre reordenações por distância
Config.CloneAnimDistance = 90 -- só anima braços/pernas até essa distância
Config.CloneLabelDistance = 70 -- distância máxima do BillboardGui "Nome #N"
Config.GhostTransparency = 0.35 -- transparência dos "fantasmas" de baixo detalhe

-- =========================================================================
-- Base do jogador (tycoon). Nível 1 é grátis (ao entrar).
-- Slots = vagas de fita na estante. VaultCapacity = limite do Cofre.
-- LockBonus = segundos extras de porta trancada.
-- =========================================================================
Config.BaseLevels = {
	{ Price = 0, Slots = 3, VaultCapacity = 600, LockBonus = 0 },
	{ Price = 2500, Slots = 5, VaultCapacity = 2500, LockBonus = 10 },
	{ Price = 12000, Slots = 8, VaultCapacity = 10000, LockBonus = 20 },
	{ Price = 50000, Slots = 11, VaultCapacity = 40000, LockBonus = 30 },
	{ Price = 200000, Slots = 15, VaultCapacity = 150000, LockBonus = 45 },
	{ Price = 800000, Slots = 20, VaultCapacity = 600000, LockBonus = 60 },
}
Config.DefenseLaserLevel = 5 -- nível que libera o laser de defesa
Config.BuildPieceStagger = 0.035 -- atraso entre blocos na animação de construção (s)

-- Cofre
Config.Vault = {
	CollectRadius = 6, -- encostar no cofre (distância do HRP)
	StealFraction = 0.25, -- ladrão leva 25% do cofre
	StealCooldown = 120, -- 1 roubo de cofre por base a cada 2 min
	BigVaultMultiplier = 3, -- passe BigVault
}

-- Porta laser
Config.Lock = {
	Seconds = 60, -- tempo trancada (+ LockBonus do nível)
	Cooldown = 60, -- recarga depois de destrancar
	NewbieProtection = 600, -- primeiros 10 min da sessão: base protegida
	ProductSeconds = { LockBase5 = 5 * 60, LockBase30 = 30 * 60 },
}

-- Roubo
Config.Theft = {
	PickupRadius = 8, -- distância máxima da fita para pegar
	DeliverRadius = 10, -- distância da própria estante para entregar
	CarrySpeedMultiplier = 0.7, -- -30% de velocidade carregando (passe FastThief ignora)
	MaxCarrySeconds = 90, -- depois disso a fita volta sozinha
	BaseCooldown = 180, -- no máximo 1 fita roubada por base a cada 3 min
	AlertCooldown = 20, -- alerta de invasão repetido para o mesmo ladrão
}

-- Tapa
Config.Slap = {
	Range = 7,
	Cooldown = 0.8,
	Knockback = 55,
	StunSeconds = 1.2,
}

-- Laser de defesa (nível 5)
Config.DefenseLaser = {
	IdleSeconds = 3, -- invasor parado por 3 s é empurrado
	IdleTolerance = 2.5, -- "parado" = andou menos que isso
}

Config.TeleportCooldown = 3

-- =========================================================================
-- Coletáveis (PickupService)
-- =========================================================================
Config.CoinRespawn = 4 -- respawn das moedas comuns (s)
Config.Pickups = {
	Coin = { Value = 1, Respawn = Config.CoinRespawn, Radius = 3 },
	Gem = { Value = 10, Respawn = 30, Radius = 3.2 }, -- rara
	Chest = { Value = 100, Respawn = 120, Radius = 4.5 }, -- um por mapa, topo do castelo
	-- Pista de Gravação da base: só o dono e os clones dele coletam. Renda menor, mas segura.
	TrackCoin = { Value = 1, Respawn = 7, Radius = 3 },
	TrackGem = { Value = 10, Respawn = 50, Radius = 3.2 },
	TrackChest = { Value = 100, Respawn = 200, Radius = 4.5 },
}
Config.PlayerPickupRadiusBonus = 0.5 -- jogadores têm o corpo maior que o ponto do clone
Config.SpatialCellSize = 8 -- célula do spatial hash (studs)
Config.CoinRainDuration = 300 -- produto CoinRain: 5 min
Config.CoinRainFactor = 3 -- moedas renascem 3x mais rápido durante a chuva
Config.PopupMaxDistance = 150 -- cliente só mostra "+12" até essa distância

-- =========================================================================
-- Bananas (TrapService)
-- =========================================================================
Config.BananaFreeAmount = 3 -- recarga grátis: volta para 3...
Config.BananaRefillSeconds = 600 -- ...a cada 10 min (se tiver menos de 3)
Config.BananaLifetime = 60 -- a banana some depois de 60 s (ou ao derrubar 1 clone)
Config.BananaRadius = 2.6 -- raio de "pisar" na banana
Config.BananaPlaceDistance = 6 -- colocada 6 studs à frente do jogador
Config.BananaCooldown = 1 -- segundos entre bananas
Config.MaxActiveBananasPerPlayer = 5
Config.BananaPackAmount = 10 -- produto BananaPack10

-- =========================================================================
-- Economia (EconomyService)
-- =========================================================================
Config.StartingCash = 0
Config.RebirthMultiplierStep = 0.5 -- Multiplier = 1 + Rebirths * 0.5 (x passes)
Config.DoubleCashMultiplier = 2 -- passe DoubleCash

-- Custo do rebirth n (n = quantos rebirths o jogador já tem).
-- O rebirth zera Cash, nível da base, cofre e clones.
function Config.RebirthCost(n: number): number
	return math.floor(250000 * 3 ^ n)
end

-- Upgrades da loja in-game (pagos em Cash). Price(level) = preço para ir de level para level+1.
-- (Os slots de fita agora vêm do nível da base: Config.BaseLevels.)
Config.UpgradeOrder = { "Record", "Speed" }
Config.Upgrades = {
	Record = {
		-- +2 s de gravação, até o teto (RecordUpgradeMaxLevel).
		MaxLevel = Config.RecordUpgradeMaxLevel,
		Price = function(level: number): number
			return math.floor(400 * 2.5 ^ level)
		end,
	},
	Speed = {
		-- Velocidade de corrida. O prompt sugere +1 por nível; usamos 2 studs/s porque +1 é
		-- quase imperceptível. Ajuste em SpeedStep.
		MaxLevel = 5,
		Price = function(level: number): number
			return math.floor(250 * 2.4 ^ level)
		end,
	},
}
Config.SpeedStep = 2

-- Renda offline
Config.Offline = {
	Efficiency = 0.5, -- 50% do que os clones rendiam
	CapHours = 8, -- teto sem passe
	CapHoursWithPass = 24, -- teto com passe OfflinePlus
	MinSeconds = 120, -- menos que isso não mostra a tela de retorno
	RateWindowMinutes = 10, -- média de ganho/min dos clones nos últimos N minutos da sessão
}

-- =========================================================================
-- Monetização. TODOS os IDs ficam 0 até você criar os itens no Creator Hub.
-- Com Id = 0 o jogo funciona normalmente e a loja mostra "em breve".
-- Popular = destaque "MAIS POPULAR" na loja (um por aba).
-- =========================================================================
Config.PassOrder = {
	"ExtraSlots",
	"LongRecord",
	"DoubleCash",
	"GoldenClone",
	"VIP",
	"OfflinePlus",
	"AutoCollect",
	"BigVault",
	"FastThief",
}
Config.GamePasses = {
	ExtraSlots = { Id = 0, Price = 299, Icon = "➕" }, -- TROCAR: +5 slots de fita
	LongRecord = { Id = 0, Price = 399, Icon = "⏱️" }, -- TROCAR: gravação 20 s -> 40 s
	DoubleCash = { Id = 0, Price = 399, Icon = "💰", Popular = true }, -- TROCAR: 2x Cash
	GoldenClone = { Id = 0, Price = 249, Icon = "⭐" }, -- TROCAR: 1 clone rende 3x, brilha e não pode ser roubado
	VIP = { Id = 0, Price = 299, Icon = "👑" }, -- TROCAR: tag [VIP] + sala VIP com moedas extras
	OfflinePlus = { Id = 0, Price = 199, Icon = "🌙" }, -- TROCAR: teto offline 8 h -> 24 h
	AutoCollect = { Id = 0, Price = 249, Icon = "🤖" }, -- TROCAR: o Cofre deposita sozinho
	BigVault = { Id = 0, Price = 199, Icon = "🏦" }, -- TROCAR: Cofre com capacidade 3x
	FastThief = { Id = 0, Price = 299, Icon = "🏃" }, -- TROCAR: carrega fita sem perder velocidade
}
Config.ExtraSlotsAmount = 5

Config.ProductOrder = {
	"FixAllClones",
	"Shield30",
	"CoinRain",
	"BananaPack10",
	"DoubleOffline",
	"CashPackS",
	"CashPackM",
	"CashPackL",
	"LockBase5",
	"LockBase30",
	"RecoverTape",
	"InstantBaseLevel2",
	"InstantBaseLevel3",
	"InstantBaseLevel4",
	"InstantBaseLevel5",
	"InstantBaseLevel6",
}
Config.Products = {
	FixAllClones = { Id = 0, Price = 29, Icon = "🔧" }, -- TROCAR: levanta todos os clones caídos
	Shield30 = { Id = 0, Price = 49, Icon = "🛡️" }, -- TROCAR: escudo anti-banana 30 min
	CoinRain = { Id = 0, Price = 99, Icon = "🌧️", Popular = true }, -- TROCAR: 5 min de moedas 3x para o servidor
	BananaPack10 = { Id = 0, Price = 25, Icon = "🍌" }, -- TROCAR: +10 bananas
	DoubleOffline = { Id = 0, Price = 49, Icon = "✖️" }, -- TROCAR: dobra o ganho offline
	CashPackS = { Id = 0, Price = 49, Icon = "💵", RebirthFraction = 0.1 }, -- TROCAR
	CashPackM = { Id = 0, Price = 149, Icon = "💰", RebirthFraction = 0.35 }, -- TROCAR
	CashPackL = { Id = 0, Price = 399, Icon = "🏦", RebirthFraction = 1 }, -- TROCAR
	LockBase5 = { Id = 0, Price = 39, Icon = "🔒" }, -- TROCAR: tranca a base 5 min (ignora recarga)
	LockBase30 = { Id = 0, Price = 129, Icon = "🔐" }, -- TROCAR: tranca a base 30 min
	RecoverTape = { Id = 0, Price = 49, Icon = "📼" }, -- TROCAR: recupera a última fita roubada
	-- Construir o próximo nível da base na hora (um produto por nível, preço em escala).
	InstantBaseLevel2 = { Id = 0, Price = 99, Icon = "🏗️", Level = 2 }, -- TROCAR
	InstantBaseLevel3 = { Id = 0, Price = 149, Icon = "🏗️", Level = 3 }, -- TROCAR
	InstantBaseLevel4 = { Id = 0, Price = 249, Icon = "🏗️", Level = 4 }, -- TROCAR
	InstantBaseLevel5 = { Id = 0, Price = 349, Icon = "🏗️", Level = 5 }, -- TROCAR
	InstantBaseLevel6 = { Id = 0, Price = 499, Icon = "🏗️", Level = 6 }, -- TROCAR
}
Config.ShieldProductSeconds = 30 * 60
-- Produtos que aparecem na aba "Produtos" da loja (os outros aparecem em ofertas contextuais
-- ou no menu da Base).
Config.ShopProducts = {
	"CoinRain",
	"FixAllClones",
	"Shield30",
	"BananaPack10",
	"LockBase5",
	"LockBase30",
	"CashPackS",
	"CashPackM",
	"CashPackL",
}

-- TODO(caixas pagas): o MVP NÃO tem itens aleatórios pagos. Um futuro sistema de caixas
-- precisa seguir a política "Paid Random Items" do Roblox: exibir as chances de cada item
-- antes da compra e consultar PolicyService:GetPolicyInfoForPlayerAsync
-- (ArePaidRandomItemsRestricted) para esconder a compra onde for proibido.

-- =========================================================================
-- Retenção
-- =========================================================================
-- Recompensa diária: dia 1..7 crescente; perdeu um dia, volta ao dia 1.
-- Cash é multiplicado por (1 + Rebirths) para continuar relevante.
Config.DailyRewards = {
	{ Cash = 100 },
	{ Cash = 250 },
	{ Cash = 500, Bananas = 3 },
	{ Cash = 1000 },
	{ Cash = 2000, Bananas = 5 },
	{ Cash = 4000 },
	{ Cash = 8000, ShieldSeconds = 30 * 60 },
}

Config.GroupId = 0 -- TROCAR: id do seu grupo do Roblox (0 = recompensa de grupo desativada)
Config.GroupReward = { Bananas = 3, ShieldSeconds = 30 * 60 } -- +3 bananas e 1 escudo (30 min)

-- Códigos: CÓDIGO (maiúsculas) -> recompensa. Uso único por jogador.
Config.Codes = {
	MEX1000 = { Cash = 500, Bananas = 3 },
	BANANA = { Bananas = 5 },
	ESCUDO = { ShieldSeconds = 15 * 60 },
}

-- =========================================================================
-- Dados (DataService)
-- =========================================================================
Config.Data = {
	StoreName = "MeX1000_PlayerData_v1", -- mesma store da v1 (o perfil é migrado)
	AutosaveSeconds = 60,
	LockStaleSeconds = 180, -- lock de sessão mais velho que isso é considerado abandonado
	LoadAttempts = 6,
	LoadRetryDelay = 5,
	MaxBytes = 3900000, -- limite de 4 MB por chave, com margem
	PurchaseHistoryMax = 100, -- últimos PurchaseIds guardados (idempotência)
}

Config.Leaderboard = {
	GlobalStoreName = "MeX1000_TopRebirths_v1",
	GlobalRefreshSeconds = 120,
	ServerRefreshSeconds = 5,
	BoardSize = 8,
}

-- Configurações do jogador (menu Configurações), salvas no perfil.
Config.DefaultSettings = {
	Music = 0.35,
	Ambient = 0.5,
	Sfx = 0.6,
	CloneQuality = 120,
	Alerts = true,
}

-- =========================================================================
-- Visual
-- =========================================================================
-- Se os studs (TopSurface = Studs) não renderizarem no seu Studio, coloque aqui o id de uma
-- imagem de studs clássica (ex.: "rbxassetid://123") e ligue UseStudsTexture.
Config.StudsTextureId = ""
Config.UseStudsTexture = false
Config.BaseColors = {
	"Bright red",
	"Bright blue",
	"Bright yellow",
	"Bright green",
	"Bright orange",
	"Bright violet",
	"Cyan",
	"Hot pink",
}

-- Ciclo dia/noite: 12 min por dia completo; DayFraction do tempo é dia (6h-18h).
Config.DayNight = {
	CycleSeconds = 720,
	DayFraction = 2 / 3,
}

-- Ícones da UI: coloque IDs de ícones gratuitos da Creator Store ("rbxassetid://...").
-- Enquanto estiver vazio, a UI usa o emoji de Theme.Emoji.
Config.Icons = {
	Cash = "", -- TROCAR
	Shop = "", -- TROCAR
	Base = "", -- TROCAR
	Clones = "", -- TROCAR
	Rebirth = "", -- TROCAR
	Daily = "", -- TROCAR
	Codes = "", -- TROCAR
	Settings = "", -- TROCAR
	Banana = "", -- TROCAR
	Slap = "", -- TROCAR
	Lock = "", -- TROCAR
	Vault = "", -- TROCAR
	Record = "", -- TROCAR
	City = "", -- TROCAR
	Home = "", -- TROCAR
}

-- =========================================================================
-- Áudio. Grupos: Music, Ambient, SFX (volumes no menu Configurações).
-- Música: use faixas da biblioteca licenciada do Roblox na Creator Store
-- (Audio > Music, autoria "Roblox"/APM, liberadas para qualquer experiência).
-- Vazio = sem música (nada quebra).
-- =========================================================================
Config.Audio = {
	Crossfade = 2, -- segundos de crossfade entre faixas
	FadeIn = 4, -- fade-in da música depois que o jogo carrega
	ZoneFade = 1.5, -- fade ao trocar de zona (base/cidade/chuva)
}
Config.Music = {
	Tracks = { -- playlist da Cidade (ordem aleatória)
		"", -- TROCAR: faixa lo-fi / chiptune leve
		"", -- TROCAR
		"", -- TROCAR
		"", -- TROCAR
	},
	BaseTrack = "", -- TROCAR: faixa mais calma, toca dentro da própria base
	CoinRainTrack = "", -- TROCAR: faixa animada durante a Chuva de Moedas
}
Config.Ambient = {
	DayBirds = "", -- TROCAR: pássaros (loop)
	Wind = "", -- TROCAR: vento leve (loop)
	NightCrickets = "", -- TROCAR: grilos (loop)
	Water = "", -- TROCAR: água da fonte/lago (loop, 3D)
}
-- Efeitos: sons que já vêm com o cliente do Roblox (rbxasset://sounds/...). Funcionam sem
-- upload, mas são simples: troque por IDs da Creator Store para mais qualidade.
Config.Sfx = {
	Click = "rbxasset://sounds/clickfast.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Build = "rbxasset://sounds/snap.wav",
	Siren = "rbxasset://sounds/electronicpingshort.wav",
	Laser = "rbxasset://sounds/swoosh.wav",
	Slap = "rbxasset://sounds/snap.wav",
	Rebirth = "rbxasset://sounds/swoosh.wav",
	Error = "rbxasset://sounds/button.wav",
	Open = "rbxasset://sounds/swoosh.wav",
}

-- =========================================================================
-- Rede (rate limit por jogador: Rate = fichas por segundo, Burst = máximo acumulado)
-- =========================================================================
Config.RateLimits = {
	Default = { Rate = 4, Burst = 8 },
	Hello = { Rate = 0.5, Burst = 2 },
	Record = { Rate = 3, Burst = 5 },
	BuyUpgrade = { Rate = 5, Burst = 8 },
	BuyBaseLevel = { Rate = 2, Burst = 3 },
	Rebirth = { Rate = 1, Burst = 2 },
	PlaceBanana = { Rate = 3, Burst = 4 },
	RedeemCode = { Rate = 0.5, Burst = 3 },
	ClaimDaily = { Rate = 1, Burst = 2 },
	ClaimGroup = { Rate = 0.5, Burst = 2 },
	DismissOffline = { Rate = 1, Burst = 2 },
	LockBase = { Rate = 1, Burst = 2 },
	Teleport = { Rate = 1, Burst = 2 },
	Slap = { Rate = 3, Burst = 3 },
	DeleteClone = { Rate = 2, Burst = 3 },
	SaveSettings = { Rate = 1, Burst = 3 },
}

return Config
