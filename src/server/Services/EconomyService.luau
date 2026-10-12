--[[
	EconomyService.luau
	Cash, multiplicadores, upgrades da loja (Cash), rebirth, bananas/escudo no perfil,
	renda offline e o snapshot de estado enviado ao cliente (StateSync).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local EconomyService = {}

local Services
local DataService

type Session = {
	minuteStart: number,
	current: number, -- ganho dos clones no minuto atual
	buckets: { number }, -- ganho dos clones por minuto (janela móvel)
	dirty: boolean,
	offline: { amount: number, minutes: number }?,
}

local sessions: { [Player]: Session } = {}

local function dataOf(player: Player): Types.PlayerData?
	local profile = DataService.get(player)
	return if profile then profile.Data else nil
end

-- =========================================================================
-- Consultas
-- =========================================================================
function EconomyService.getMultiplier(player: Player): number
	local data = dataOf(player)
	local rebirths = if data then data.Rebirths else 0
	return EconomyMath.multiplier(
		rebirths,
		Config.RebirthMultiplierStep,
		Services.MonetizationService.ownsPass(player, "DoubleCash"),
		Config.DoubleCashMultiplier
	)
end

-- Vagas de fita = vagas do nível da base + 1 por rebirth + passe ExtraSlots (teto 30).
function EconomyService.getSlots(player: Player): number
	local data = dataOf(player)
	if not data then
		return Config.BaseLevels[1].Slots
	end
	local level = Config.BaseLevels[data.BaseLevel] or Config.BaseLevels[1]
	local passBonus = if Services.MonetizationService.ownsPass(player, "ExtraSlots") then Config.ExtraSlotsAmount else 0
	return EconomyMath.totalSlots(
		level.Slots,
		data.Rebirths,
		Config.RebirthSlotBonus,
		0,
		passBonus,
		Config.MaxClonesPerPlayer
	)
end

function EconomyService.getVaultCapacity(player: Player): number
	local data = dataOf(player)
	local level = Config.BaseLevels[if data then data.BaseLevel else 1] or Config.BaseLevels[1]
	local multiplier = if Services.MonetizationService.ownsPass(player, "BigVault")
		then Config.Vault.BigVaultMultiplier
		else 1
	return level.VaultCapacity * multiplier
end

function EconomyService.getRecordSeconds(player: Player): number
	local data = dataOf(player)
	local base = if Services.MonetizationService.ownsPass(player, "LongRecord")
		then Config.RecordSecondsWithPass
		else Config.RecordSeconds
	local level = if data then math.min(data.Upgrades.Record, Config.RecordUpgradeMaxLevel) else 0
	return math.min(
		EconomyMath.recordSeconds(base, level, Config.RecordUpgradeStep),
		Config.MaxSamples / Config.RecordHz
	)
end

function EconomyService.getWalkSpeed(player: Player): number
	local data = dataOf(player)
	local level = if data then data.Upgrades.Speed else 0
	return EconomyMath.walkSpeed(Config.BaseWalkSpeed, level, Config.SpeedStep)
end

function EconomyService.hasShield(player: Player): boolean
	local data = dataOf(player)
	return data ~= nil and data.ShieldUntil > os.time()
end

-- Pode comprar mais um nível? Retorna (pode, motivo)
local function canUpgrade(player: Player, key: string): (boolean, string?)
	local data = dataOf(player)
	local upgrade = Config.Upgrades[key]
	if not data or not upgrade then
		return false, "unknown"
	end
	if data.Upgrades[key] >= upgrade.MaxLevel then
		return false, "max_level"
	end
	return true, nil
end

-- =========================================================================
-- Movimento do Cash
-- =========================================================================

-- Coleta: aplica multiplicador (e 3x do clone dourado). Retorna o valor gerado.
-- O que os CLONES geram cai no Cofre da base (com limite); o passe AutoCollect manda direto
-- para o Cash. O que o próprio jogador coleta vai direto para o Cash.
function EconomyService.award(player: Player, base: number, golden: boolean?, fromClone: boolean?): number
	local data = dataOf(player)
	if not data then
		return 0
	end
	local extra = if golden then Config.GoldenCloneMultiplier else 1
	local amount = EconomyMath.award(base, EconomyService.getMultiplier(player), extra)
	if fromClone and not Services.MonetizationService.ownsPass(player, "AutoCollect") then
		local space = math.max(0, EconomyService.getVaultCapacity(player) - data.VaultCash)
		data.VaultCash += math.min(space, amount)
	else
		data.Cash += amount
	end
	data.TotalEarned += amount
	local session = sessions[player]
	if session then
		if fromClone then
			session.current += amount
		end
		session.dirty = true
	end
	return amount
end

-- Dono encostou no Cofre: tudo vai para o Cash. Retorna o valor coletado.
function EconomyService.collectVault(player: Player): number
	local data = dataOf(player)
	if not data or data.VaultCash <= 0 then
		return 0
	end
	local amount = math.floor(data.VaultCash)
	data.VaultCash = 0
	data.Cash += amount
	EconomyService.markDirty(player)
	return amount
end

-- Invasor encostou no Cofre de outra base: leva Config.Vault.StealFraction (25%).
function EconomyService.stealFromVault(thief: Player, victim: Player): number
	local victimData = dataOf(victim)
	local thiefData = dataOf(thief)
	if not victimData or not thiefData then
		return 0
	end
	local amount = math.floor(victimData.VaultCash * Config.Vault.StealFraction)
	if amount <= 0 then
		return 0
	end
	victimData.VaultCash -= amount
	thiefData.Cash += amount
	EconomyService.markDirty(thief)
	EconomyService.markDirty(victim)
	return amount
end

-- Cash direto (pacotes, recompensas). Não passa pelo multiplicador.
function EconomyService.addCash(player: Player, amount: number)
	local data = dataOf(player)
	if not data or amount <= 0 then
		return
	end
	data.Cash += math.floor(amount)
	data.TotalEarned += math.floor(amount)
	EconomyService.markDirty(player)
end

function EconomyService.addBananas(player: Player, amount: number)
	local data = dataOf(player)
	if not data then
		return
	end
	data.Bananas += amount
	EconomyService.markDirty(player)
end

-- Consome 1 banana. Começa o timer de recarga quando cai abaixo do estoque grátis.
function EconomyService.useBanana(player: Player): boolean
	local data = dataOf(player)
	if not data or data.Bananas <= 0 then
		return false
	end
	if data.Bananas >= Config.BananaFreeAmount and data.Bananas - 1 < Config.BananaFreeAmount then
		data.LastBananaRefill = os.time()
	end
	data.Bananas -= 1
	EconomyService.markDirty(player)
	return true
end

function EconomyService.addShield(player: Player, seconds: number)
	local data = dataOf(player)
	if not data then
		return
	end
	data.ShieldUntil = math.max(data.ShieldUntil, os.time()) + seconds
	EconomyService.markDirty(player)
end

-- Recompensa genérica { Cash?, Bananas?, ShieldSeconds? }. scaleCash = multiplica Cash por (1 + Rebirths).
function EconomyService.grantReward(player: Player, reward: { [string]: number }, scaleCash: boolean?)
	local data = dataOf(player)
	if not data then
		return
	end
	if reward.Cash then
		local scale = if scaleCash then 1 + data.Rebirths else 1
		EconomyService.addCash(player, reward.Cash * scale)
	end
	if reward.Bananas then
		EconomyService.addBananas(player, reward.Bananas)
	end
	if reward.ShieldSeconds then
		EconomyService.addShield(player, reward.ShieldSeconds)
	end
end

function EconomyService.applyMovement(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = EconomyService.getWalkSpeed(player)
	end
end

-- =========================================================================
-- Loja (Cash) e rebirth
-- =========================================================================
function EconomyService.buyUpgrade(player: Player, key: any): (boolean, string?)
	if not Net.check.oneOf(key, Config.UpgradeOrder) then
		return false, "unknown"
	end
	local data = dataOf(player)
	if not data then
		return false, "not_loaded"
	end
	local ok, reason = canUpgrade(player, key)
	if not ok then
		return false, reason
	end
	local price = Config.Upgrades[key].Price(data.Upgrades[key])
	if data.Cash < price then
		return false, "not_enough_cash"
	end
	data.Cash -= price
	data.Upgrades[key] += 1
	if key == "Speed" then
		EconomyService.applyMovement(player)
	end
	EconomyService.markDirty(player)
	return true, nil
end

function EconomyService.rebirth(player: Player): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "not_loaded"
	end
	local cost = Config.RebirthCost(data.Rebirths)
	if data.Cash < cost then
		return false, "not_enough_cash"
	end
	Services.RecordingService.cancel(player, "cancel")
	data.Cash = Config.StartingCash
	data.Rebirths += 1
	data.BaseLevel = 1
	data.VaultCash = 0
	Services.CloneService.removeAll(player, true)
	Services.PlotService.rebuild(player)
	Net.fireAll("Fx", "rebirth", { userId = player.UserId })
	Services.LeaderboardService.onRebirth(player, data.Rebirths)

	Net.fire("Notify", player, "toast_rebirth_self", {
		n = data.Rebirths,
		mult = string.format("x%.1f", EconomyService.getMultiplier(player)),
	}, "gold")
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.fire("Notify", other, "toast_rebirth_other", { name = player.DisplayName, n = data.Rebirths }, "info")
		end
	end
	EconomyService.markDirty(player)
	return true, nil
end

function EconomyService.dismissOffline(player: Player)
	local session = sessions[player]
	if session and session.offline then
		session.offline = nil
		EconomyService.markDirty(player)
	end
	return true
end

-- Produto DoubleOffline: credita de novo o último ganho offline.
function EconomyService.doubleOffline(player: Player)
	local data = dataOf(player)
	if not data then
		return
	end
	local amount = data.PendingOfflineDouble
	if amount <= 0 then
		-- Comprou sem ganho pendente: entrega o equivalente ao pacote pequeno.
		amount = EconomyMath.cashPack(data.Rebirths, Config.Products.CashPackS.RebirthFraction, Config.RebirthCost)
	end
	data.PendingOfflineDouble = 0
	EconomyService.addCash(player, amount)
	EconomyService.dismissOffline(player)
	Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
end

function EconomyService.cashPackAmount(player: Player, productKey: string): number
	local data = dataOf(player)
	local info = Config.Products[productKey]
	return EconomyMath.cashPack(if data then data.Rebirths else 0, info.RebirthFraction or 0.1, Config.RebirthCost)
end

-- =========================================================================
-- Estado para o cliente
-- =========================================================================
function EconomyService.markDirty(player: Player)
	local session = sessions[player]
	if session then
		session.dirty = true
	end
end

function EconomyService.markAllDirty()
	for _, session in sessions do
		session.dirty = true
	end
end

function EconomyService.buildState(player: Player): Types.ClientState?
	local data = dataOf(player)
	local session = sessions[player]
	if not data or not session then
		return nil
	end
	local now = os.time()
	local monetization = Services.MonetizationService

	local prices = {}
	for _, key in Config.UpgradeOrder do
		if canUpgrade(player, key) then
			prices[key] = Config.Upgrades[key].Price(data.Upgrades[key])
		end
	end

	local passes = {}
	for key in Config.GamePasses do
		passes[key] = monetization.ownsPass(player, key)
	end

	local cashPacks = {}
	for _, key in { "CashPackS", "CashPackM", "CashPackL" } do
		cashPacks[key] = EconomyService.cashPackAmount(player, key)
	end

	local summary, fallenCount = Services.CloneService.summary(player)
	local lockedUntil, cooldownUntil, protectedUntil = Services.PlotService.getLockInfo(player)
	local refillLeft = 0
	if data.Bananas < Config.BananaFreeAmount then
		refillLeft = math.max(0, data.LastBananaRefill + Config.BananaRefillSeconds - now)
	end

	return {
		loaded = true,
		cash = data.Cash,
		rebirths = data.Rebirths,
		multiplier = EconomyService.getMultiplier(player),
		nextMultiplier = EconomyMath.multiplier(
			data.Rebirths + 1,
			Config.RebirthMultiplierStep,
			monetization.ownsPass(player, "DoubleCash"),
			Config.DoubleCashMultiplier
		),
		rebirthCost = Config.RebirthCost(data.Rebirths),
		slots = EconomyService.getSlots(player),
		cloneCount = #summary,
		fallenCount = fallenCount,
		clones = summary,
		bananas = data.Bananas,
		bananaRefillLeft = refillLeft,
		shieldLeft = math.max(0, data.ShieldUntil - now),
		coinRainLeft = Services.PickupService.coinRainLeft(),
		recordSeconds = EconomyService.getRecordSeconds(player),
		walkSpeed = EconomyService.getWalkSpeed(player),
		upgrades = table.clone(data.Upgrades),
		prices = prices,
		passes = passes,
		cashPacks = cashPacks,
		daily = Services.RetentionService.dailyInfo(player),
		groupClaimed = data.GroupRewardClaimed,
		offline = session.offline,
		recording = Services.RecordingService.isRecording(player),
		vip = monetization.ownsPass(player, "VIP"),
		plot = Services.PlotService.getPlotIndex(player),
		baseLevel = data.BaseLevel,
		nextLevelPrice = if Config.BaseLevels[data.BaseLevel + 1]
			then Config.BaseLevels[data.BaseLevel + 1].Price
			else nil,
		vaultCash = data.VaultCash,
		vaultCapacity = EconomyService.getVaultCapacity(player),
		lockedUntil = lockedUntil,
		cooldownUntil = cooldownUntil,
		protectedUntil = protectedUntil,
		carrying = Services.TheftService.isCarrying(player),
		hasStolenTape = data.LastStolen ~= nil,
		settings = data.Settings,
	}
end

local function flush(player: Player, session: Session)
	session.dirty = false
	local state = EconomyService.buildState(player)
	if state then
		Net.fire("StateSync", player, state)
		Services.LeaderboardService.updateStats(player, state.cash, state.rebirths)
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function EconomyService.init(services)
	Services = services
	DataService = services.DataService
end

local function refillBananas(data: Types.PlayerData)
	if data.Bananas < Config.BananaFreeAmount then
		if os.time() - data.LastBananaRefill >= Config.BananaRefillSeconds then
			data.Bananas = Config.BananaFreeAmount
			data.LastBananaRefill = os.time()
			return true
		end
	end
	return false
end

function EconomyService.onPlayerLoaded(player: Player, profile)
	local data: Types.PlayerData = profile.Data
	local session: Session = {
		minuteStart = os.clock(),
		current = 0,
		buckets = {},
		dirty = true,
		offline = nil,
	}
	sessions[player] = session
	refillBananas(data)
	data.PendingOfflineDouble = 0 -- "Dobrar" só vale para o ganho offline desta entrada

	-- Renda offline: ganho/min da última sessão x minutos fora, com teto e eficiência.
	local previous = profile.Session.PreviousLogin or 0
	if previous > 0 and data.EarnPerMin > 0 then
		local away = os.time() - previous
		if away >= Config.Offline.MinSeconds then
			local capHours = if Services.MonetizationService.ownsPass(player, "OfflinePlus")
				then Config.Offline.CapHoursWithPass
				else Config.Offline.CapHours
			local amount = EconomyMath.offlineEarnings(data.EarnPerMin, away, capHours, Config.Offline.Efficiency)
			if amount > 0 then
				data.Cash += amount
				data.TotalEarned += amount
				data.PendingOfflineDouble = amount
				session.offline = {
					amount = amount,
					minutes = math.floor(math.min(away, capHours * 3600) / 60),
				}
			end
		end
	end

	EconomyService.applyMovement(player)
end

-- Fecha o balde do minuto e recalcula o ganho/min salvo no perfil.
local function rotateBucket(player: Player, session: Session, final: boolean)
	local data = dataOf(player)
	if not data then
		return
	end
	local elapsed = os.clock() - session.minuteStart
	if not final or elapsed >= 60 then
		table.insert(session.buckets, session.current)
		while #session.buckets > Config.Offline.RateWindowMinutes do
			table.remove(session.buckets, 1)
		end
		session.current = 0
		session.minuteStart = os.clock()
		data.EarnPerMin = EconomyMath.averageRate(session.buckets)
	elseif #session.buckets == 0 and elapsed >= 20 then
		-- Sessão curta (< 1 min): estima pelo que deu.
		data.EarnPerMin = session.current / (elapsed / 60)
	end
end

function EconomyService.onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		rotateBucket(player, session, true)
		local data = dataOf(player)
		if data then
			data.PlayTime += os.time() - ((DataService.get(player) :: any).Session.JoinedAt or os.time())
		end
	end
	sessions[player] = nil
end

function EconomyService.start()
	Net.handle("BuyUpgrade", function(player, key)
		local ok, reason = EconomyService.buyUpgrade(player, key)
		return ok, reason
	end)
	Net.handle("Rebirth", function(player)
		return EconomyService.rebirth(player)
	end)
	Net.handle("DismissOffline", function(player)
		return EconomyService.dismissOffline(player)
	end)
	Net.handle("Hello", function(player)
		local profile = DataService.waitFor(player, 30)
		if not profile then
			return nil
		end
		-- Espera o EconomyService montar a sessão (onPlayerLoaded roda logo depois do load).
		local deadline = os.clock() + 10
		while not sessions[player] and os.clock() < deadline and player.Parent do
			task.wait(0.1)
		end
		return {
			state = EconomyService.buildState(player),
			clones = Services.CloneService.snapshot(),
		}
	end)

	-- Envia estados sujos a 5 Hz e roda os timers por minuto.
	task.spawn(function()
		local lastSecond = os.clock()
		while true do
			task.wait(0.3)
			local secondTick = os.clock() - lastSecond >= 1
			if secondTick then
				lastSecond = os.clock()
			end
			for player, session in sessions do
				if secondTick then
					if os.clock() - session.minuteStart >= 60 then
						rotateBucket(player, session, false)
					end
					local data = dataOf(player)
					if data and refillBananas(data) then
						session.dirty = true
					end
				end
				if session.dirty and player.Parent then
					flush(player, session)
				end
			end
		end
	end)
end

return EconomyService
