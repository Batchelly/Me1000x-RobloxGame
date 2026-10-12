--[[
	DataService.luau
	Perfis no DataStore com session locking feito à mão via UpdateAsync.

	Registro salvo por chave "Player_<UserId>":
		{ Data = PlayerData, Lock = { JobId, Time }?, SavedAt = os.time() }

	- Ao carregar: UpdateAsync pega o lock. Se outro servidor tem um lock "fresco"
	  (< Config.Data.LockStaleSeconds), espera e tenta de novo; depois de N tentativas, chuta.
	- Autosave a cada Config.Data.AutosaveSeconds renova o lock.
	- Ao sair (ou no BindToClose): salva e libera o lock.
	- Se o lock foi roubado por outro servidor, NÃO sobrescreve e chuta o jogador.
	- Sem acesso a API (Studio sem "Enable Studio Access to API Services"): modo memória
	  (o jogo funciona, mas nada é salvo). Um aviso aparece no Output.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Types = require(ReplicatedStorage.Shared.Types)

local DataService = {}

export type Profile = {
	Player: Player,
	Key: string,
	Data: Types.PlayerData,
	Session: { [string]: any }, -- dados só da sessão (não salvos)
	Released: boolean,
	Saving: boolean,
	LastSave: number,
}

local DATA_VERSION = 2

local function defaultData(): Types.PlayerData
	return {
		Version = DATA_VERSION,
		Cash = Config.StartingCash,
		Rebirths = 0,
		TotalEarned = 0,
		Upgrades = { Record = 0, Speed = 0 },
		BaseLevel = 1,
		VaultCash = 0,
		Clones = {},
		Bananas = Config.BananaFreeAmount,
		LastBananaRefill = 0,
		ShieldUntil = 0,
		Cosmetics = {},
		PurchaseHistory = {},
		LastLogin = 0,
		EarnPerMin = 0,
		PendingOfflineDouble = 0,
		Daily = { Streak = 0, LastDay = 0 },
		GroupRewardClaimed = false,
		RedeemedCodes = {},
		Settings = table.clone(Config.DefaultSettings),
		PlayTime = 0,
	}
end

-- Preenche campos que faltam (dados antigos) sem apagar o que existe.
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			reconcile(target[key], value)
		end
	end
end

local store: DataStore? = nil
local offlineMode = false
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { [Player]: { thread } } = {}
local shuttingDown = false

-- =========================================================================
-- Inicialização
-- =========================================================================
function DataService.init(_services)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
		-- Testa o acesso (no Studio sem API access isso falha).
		local probeOk, probeErr = pcall(function()
			return (result :: DataStore):GetAsync("__probe")
		end)
		if not probeOk then
			offlineMode = true
			warn(
				"[DataService] DataStore indisponível ("
					.. tostring(probeErr)
					.. "). "
					.. "Rodando em MODO MEMÓRIA: nada será salvo. No Studio, ative "
					.. "Game Settings > Security > Enable Studio Access to API Services."
			)
		end
	else
		offlineMode = true
		warn("[DataService] Não foi possível abrir o DataStore: " .. tostring(result))
	end
end

function DataService.isOffline(): boolean
	return offlineMode
end

-- =========================================================================
-- Load / save
-- =========================================================================
local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function lockIsFresh(lock: any): boolean
	return type(lock) == "table"
		and lock.JobId ~= game.JobId
		and type(lock.Time) == "number"
		and os.time() - lock.Time < Config.Data.LockStaleSeconds
end

local function trimForSize(data: Types.PlayerData)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then
		return
	end
	if #encoded <= Config.Data.MaxBytes then
		return
	end
	-- Nunca deveria acontecer com os limites atuais; descarta clones do maior slot para o menor.
	warn("[DataService] Perfil acima do limite (" .. #encoded .. " bytes), removendo gravações")
	local slots = {}
	for slot in data.Clones do
		table.insert(slots, tonumber(slot) or 0)
	end
	table.sort(slots, function(a, b)
		return a > b
	end)
	for _, slot in slots do
		data.Clones[tostring(slot)] = nil
		local _, again = pcall(HttpService.JSONEncode, HttpService, data)
		if type(again) == "string" and #again <= Config.Data.MaxBytes then
			return
		end
	end
end

-- Carrega (e trava) o perfil. Retorna nil se falhou (o jogador já foi chutado).
function DataService.load(player: Player): Profile?
	local key = keyFor(player)
	local data: Types.PlayerData? = nil

	if offlineMode or not store then
		data = defaultData()
	else
		for attempt = 1, Config.Data.LoadAttempts do
			if not player.Parent then
				return nil
			end
			local status = "error"
			local loaded = nil
			local ok, err = pcall(function()
				(store :: DataStore):UpdateAsync(key, function(old)
					if old ~= nil and type(old) ~= "table" then
						old = nil
					end
					-- No Studio, sempre assume o lock (não há outro servidor de verdade).
					if old and lockIsFresh(old.Lock) and not RunService:IsStudio() then
						status = "locked"
						return nil -- cancela a escrita
					end
					local record = old or {}
					record.Lock = { JobId = game.JobId, Time = os.time() }
					status = "ok"
					loaded = record.Data
					return record
				end)
			end)
			if ok and status == "ok" then
				data = if type(loaded) == "table" then loaded else defaultData()
				break
			end
			if not ok then
				warn(string.format("[DataService] erro ao carregar %s (tentativa %d): %s", key, attempt, tostring(err)))
			end
			task.wait(Config.Data.LoadRetryDelay)
		end
	end

	if not data then
		player:Kick(Strings.get(Strings.langFor(player.LocaleId), "kick_data"))
		return nil
	end

	-- Migração v1 -> v2: os slots comprados viram nível de base equivalente.
	local raw = data :: any
	if (raw.Version or 1) < 2 then
		local bought = if type(raw.Upgrades) == "table" then raw.Upgrades.Slot or 0 else 0
		local level = 1
		for index, spec in Config.BaseLevels do
			if spec.Slots <= 3 + bought then
				level = index
			end
		end
		raw.BaseLevel = level
		if type(raw.Upgrades) == "table" then
			raw.Upgrades.Slot = nil
		end
	end
	reconcile(raw, defaultData() :: any)
	data.Version = DATA_VERSION

	local profile: Profile = {
		Player = player,
		Key = key,
		Data = data,
		Session = { JoinedAt = os.time(), PreviousLogin = data.LastLogin },
		Released = false,
		Saving = false,
		LastSave = os.clock(),
	}
	profiles[player] = profile

	local waiting = loadedCallbacks[player]
	loadedCallbacks[player] = nil
	if waiting then
		for _, thread in waiting do
			task.spawn(thread, profile)
		end
	end
	return profile
end

-- Salva o perfil. release = true libera o lock (saída do jogador / servidor fechando).
function DataService.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if offlineMode or not store then
		return true
	end
	-- Evita saves concorrentes do mesmo perfil.
	while profile.Saving do
		task.wait(0.1)
	end
	profile.Saving = true

	local data = profile.Data
	data.LastLogin = os.time()
	trimForSize(data)

	local lostLock = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(profile.Key, function(old)
			if type(old) == "table" and lockIsFresh(old.Lock) and not RunService:IsStudio() then
				lostLock = true
				return nil
			end
			return {
				Data = data,
				Lock = if release then nil else { JobId = game.JobId, Time = os.time() },
				SavedAt = os.time(),
			}
		end)
	end)
	profile.Saving = false
	profile.LastSave = os.clock()

	if not ok then
		warn("[DataService] erro ao salvar " .. profile.Key .. ": " .. tostring(err))
		return false
	end
	if lostLock then
		warn("[DataService] lock perdido para " .. profile.Key .. "; não sobrescrevendo")
		profile.Released = true
		profiles[player] = nil
		if player.Parent then
			player:Kick(Strings.get(Strings.langFor(player.LocaleId), "kick_data_lost"))
		end
		return false
	end
	return true
end

-- Salva, libera o lock e esquece o perfil. Idempotente.
function DataService.release(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	DataService.save(player, true)
	profiles[player] = nil
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Espera o perfil carregar (até timeout segundos).
function DataService.waitFor(player: Player, timeout: number?): Profile?
	local profile = profiles[player]
	if profile then
		return profile
	end
	local thread = coroutine.running()
	local list = loadedCallbacks[player]
	if not list then
		list = {}
		loadedCallbacks[player] = list
	end
	table.insert(list, thread)
	local resumed = false
	task.delay(timeout or 30, function()
		if not resumed then
			local current = loadedCallbacks[player]
			if current then
				local index = table.find(current, thread)
				if index then
					table.remove(current, index)
					task.spawn(thread, nil)
				end
			end
		end
	end)
	local result = coroutine.yield()
	resumed = true
	return result
end

function DataService.profiles(): { [Player]: Profile }
	return profiles
end

-- Grava um PurchaseId no histórico (idempotência do ProcessReceipt).
function DataService.hasPurchase(profile: Profile, purchaseId: string): boolean
	return table.find(profile.Data.PurchaseHistory, purchaseId) ~= nil
end

function DataService.addPurchase(profile: Profile, purchaseId: string)
	local history = profile.Data.PurchaseHistory
	table.insert(history, purchaseId)
	while #history > Config.Data.PurchaseHistoryMax do
		table.remove(history, 1)
	end
end

function DataService.isShuttingDown(): boolean
	return shuttingDown
end

-- =========================================================================
-- Autosave e BindToClose
-- =========================================================================
function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player, profile in table.clone(profiles) do
				if not profile.Released and os.clock() - profile.LastSave >= Config.Data.AutosaveSeconds * 0.9 then
					task.spawn(DataService.save, player, false)
					task.wait(0.5) -- espalha as requisições
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		loadedCallbacks[player] = nil
	end)
end

-- Chamado pelo Main no BindToClose, depois que os serviços gravaram seus dados no perfil.
function DataService.releaseAll()
	shuttingDown = true
	local pending = 0
	for player in table.clone(profiles) do
		pending += 1
		task.spawn(function()
			DataService.release(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return DataService
