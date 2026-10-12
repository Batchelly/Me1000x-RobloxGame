--[[
	MonetizationService.luau
	Game Passes e Developer Products. IDs em Config.GamePasses / Config.Products (0 = "em breve").

	- Passes: UserOwnsGamePassAsync com cache por jogador; PromptGamePassPurchaseFinished
	  aplica na hora.
	- Produtos: ProcessReceipt IDEMPOTENTE. O PurchaseId é gravado no perfil e o perfil é
	  SALVO antes de retornar PurchaseGranted. Se o save falhar, retorna NotProcessedYet e o
	  Roblox tenta de novo (na nova tentativa o PurchaseId já está no perfil: não duplica).
	- Sem itens aleatórios pagos no MVP (ver TODO em Config.luau).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local MonetizationService = {}

local Services
local passCache: { [Player]: { [string]: boolean } } = {}
local passById: { [number]: string } = {}
local productById: { [number]: string } = {}

function MonetizationService.ownsPass(player: Player, key: string): boolean
	if Config.DebugOwnAllPassesInStudio and RunService:IsStudio() then
		return true
	end
	local cache = passCache[player]
	return cache ~= nil and cache[key] == true
end

-- Reaplica os efeitos dos passes (atributo VIP, clone dourado, velocidade, HUD).
local function applyPassEffects(player: Player)
	player:SetAttribute("VIP", MonetizationService.ownsPass(player, "VIP"))
	Services.CloneService.refreshGolden(player)
	if not Services.TheftService.isCarrying(player) then
		Services.EconomyService.applyMovement(player)
	end
	Services.PlotService.refresh(player)
	Services.EconomyService.markDirty(player)
end

local function announce(player: Player, itemKey: string)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.fire("Notify", other, "toast_purchase", { name = player.DisplayName, itemKey = itemKey }, "info")
		end
	end
end

-- =========================================================================
-- Efeitos dos produtos (consumíveis)
-- =========================================================================
local handlers: { [string]: (Player) -> () } = {
	FixAllClones = function(player)
		Services.CloneService.fixAll(player)
		Net.fire("Notify", player, "toast_fixed", nil, "good")
	end,
	Shield30 = function(player)
		Services.EconomyService.addShield(player, Config.ShieldProductSeconds)
		Net.fire("Notify", player, "toast_shield", { t = Format.time(Config.ShieldProductSeconds) }, "good")
	end,
	CoinRain = function(player)
		Services.PickupService.startCoinRain()
		Net.fireAll("Notify", "toast_coin_rain", { name = player.DisplayName }, "gold")
	end,
	BananaPack10 = function(player)
		Services.EconomyService.addBananas(player, Config.BananaPackAmount)
		Net.fire("Notify", player, "toast_bananas_received", { n = Config.BananaPackAmount }, "good")
	end,
	DoubleOffline = function(player)
		Services.EconomyService.doubleOffline(player)
	end,
	CashPackS = function(player)
		local amount = Services.EconomyService.cashPackAmount(player, "CashPackS")
		Services.EconomyService.addCash(player, amount)
		Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
	end,
	CashPackM = function(player)
		local amount = Services.EconomyService.cashPackAmount(player, "CashPackM")
		Services.EconomyService.addCash(player, amount)
		Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
	end,
	LockBase5 = function(player)
		Services.PlotService.lock(player, Config.Lock.ProductSeconds.LockBase5, true)
	end,
	LockBase30 = function(player)
		Services.PlotService.lock(player, Config.Lock.ProductSeconds.LockBase30, true)
	end,
	RecoverTape = function(player)
		if not Services.TheftService.recover(player) then
			-- Nada para recuperar (ou estante lotada): entrega o equivalente em Cash.
			local amount = Services.EconomyService.cashPackAmount(player, "CashPackS")
			Services.EconomyService.addCash(player, amount)
			Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
		end
	end,
	CashPackL = function(player)
		local amount = Services.EconomyService.cashPackAmount(player, "CashPackL")
		Services.EconomyService.addCash(player, amount)
		Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
	end,
}

-- InstantBaseLevel2..6: constrói o PRÓXIMO nível da base na hora (o preço sobe com o nível).
-- Se a base já estiver completa, entrega o preço do nível em Cash.
for key, info in Config.Products do
	if info.Level then
		handlers[key] = function(player)
			local ok = Services.PlotService.buyLevel(player, true)
			if not ok then
				local spec = Config.BaseLevels[info.Level]
				local amount = if spec then spec.Price else 0
				Services.EconomyService.addCash(player, amount)
				Net.fire("Notify", player, "toast_cash_received", { n = amount }, "gold")
			end
		end
	end
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local DataService = Services.DataService
	local profile = DataService.get(player) or DataService.waitFor(player, 10)
	if not profile or profile.Released then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if DataService.hasPurchase(profile, purchaseId) then
		-- Já aplicado antes. Garante que está salvo antes de confirmar.
		if DataService.save(player, false) or DataService.isOffline() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = productById[receiptInfo.ProductId]
	local handler = key and handlers[key]
	if not handler then
		warn("[Monetization] produto desconhecido: " .. tostring(receiptInfo.ProductId) .. " (confira Config.Products)")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(handler, player)
	if not ok then
		warn("[Monetization] erro ao aplicar " .. key .. ": " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.addPurchase(profile, purchaseId)
	Services.EconomyService.markDirty(player)
	if key ~= "CoinRain" then
		announce(player, "product_" .. key .. "_name")
	end

	if DataService.save(player, false) or DataService.isOffline() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function MonetizationService.init(services)
	Services = services
	for key, info in Config.GamePasses do
		if info.Id ~= 0 then
			passById[info.Id] = key
		end
	end
	for key, info in Config.Products do
		if info.Id ~= 0 then
			productById[info.Id] = key
		end
	end
end

function MonetizationService.onPlayerLoaded(player: Player, _profile)
	local cache = {}
	passCache[player] = cache
	for key, info in Config.GamePasses do
		if info.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.Id)
			end)
			cache[key] = ok and owns == true
		end
	end
	player:SetAttribute("VIP", MonetizationService.ownsPass(player, "VIP"))
end

-- Depois que clones e personagem já existem.
function MonetizationService.onPlayerReady(player: Player)
	applyPassEffects(player)
end

function MonetizationService.onPlayerRemoving(player: Player)
	passCache[player] = nil
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = passById[passId]
		if not key then
			return
		end
		local cache = passCache[player]
		if not cache then
			cache = {}
			passCache[player] = cache
		end
		cache[key] = true
		applyPassEffects(player)
		Net.fire("Notify", player, "toast_pass_bought", { itemKey = "pass_" .. key .. "_name" }, "gold")
		announce(player, "pass_" .. key .. "_name")
	end)
end

return MonetizationService
