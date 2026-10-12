--[[
	Net.luau
	Cria (servidor) ou obtém (cliente) todos os RemoteEvents/RemoteFunctions do jogo.
	No servidor, todo handler passa por rate limit (token bucket por jogador, valores em
	Config.RateLimits) e pcall. Os handlers continuam responsáveis por validar os tipos
	dos argumentos (use Net.check.*): NUNCA confie no cliente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Net = {}

-- Servidor -> cliente
local SERVER_EVENTS = {
	"StateSync", -- (state) snapshot do estado do jogador
	"CloneAdded", -- (info) clone novo (com o caminho em buffer)
	"CloneRemoved", -- (id)
	"CloneUpdated", -- (id, patch) caído/levantado/dourado
	"PickupFx", -- ({ {pos, amount, color, kind} }) popups "+12"
	"Notify", -- (key, args, style) toast no topo
	"RecordState", -- (status, data) início/fim da gravação
	"BananaFx", -- (pos, kind) efeito de banana
	"Alert", -- (kind, data) invasão / fita pega / fita roubada (alerta do dono)
	"Fx", -- (kind, data) efeitos visuais: tapa, laser, fita voltando, cofre, rebirth
	"Slapped", -- (impulse: Vector3, stun) você levou um tapa
}

-- Cliente -> servidor, sem resposta
local CLIENT_EVENTS = {
	"Record", -- ("toggle" | "start" | "stop" | "rerecord", slot?)
	"Slap", -- ()
}

-- Cliente -> servidor, com resposta
local FUNCTIONS = {
	"Hello", -- () -> { state, clones }
	"BuyUpgrade", -- (key) -> ok, reason
	"Rebirth", -- () -> ok, reason
	"PlaceBanana", -- () -> ok, reason
	"RedeemCode", -- (code) -> ok, reason
	"ClaimDaily", -- () -> ok, reason
	"ClaimGroup", -- () -> ok, reason
	"DismissOffline", -- () -> ok
	"BuyBaseLevel", -- () -> ok, reason
	"LockBase", -- () -> ok, reason
	"Teleport", -- ("base" | "city") -> ok, reason
	"DeleteClone", -- (slot) -> ok, reason
	"SaveSettings", -- (settings) -> ok
}

local FOLDER_NAME = "Remotes"
local isServer = RunService:IsServer()

local folder: Folder
if isServer then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	local function ensure(className: string, name: string)
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in SERVER_EVENTS do
		ensure("RemoteEvent", name)
	end
	for _, name in CLIENT_EVENTS do
		ensure("RemoteEvent", name)
	end
	for _, name in FUNCTIONS do
		ensure("RemoteFunction", name)
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function remote(name: string): any
	local found = folder:FindFirstChild(name)
	if found then
		return found
	end
	if isServer then
		error("[Net] remote desconhecido: " .. name)
	end
	return folder:WaitForChild(name)
end

-- =========================================================================
-- Rate limit (servidor)
-- =========================================================================
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local function allow(player: Player, name: string): boolean
	local limit = Config.RateLimits[name] or Config.RateLimits.Default
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.Burst, last = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(limit.Burst, bucket.tokens + (now - bucket.last) * limit.Rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

if isServer then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-- =========================================================================
-- Validadores
-- =========================================================================
Net.check = {}

function Net.check.string(value: any, maxLength: number): boolean
	return type(value) == "string" and #value <= maxLength and utf8.len(value) ~= nil
end

function Net.check.int(value: any, min: number, max: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

function Net.check.oneOf(value: any, options: { string }): boolean
	return type(value) == "string" and table.find(options, value) ~= nil
end

-- =========================================================================
-- API do servidor
-- =========================================================================

-- Escuta um RemoteEvent vindo do cliente.
function Net.on(name: string, handler: (Player, ...any) -> ())
	assert(isServer, "Net.on é só do servidor")
	remote(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] erro em %s de %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

-- Responde a um RemoteFunction vindo do cliente.
function Net.handle(name: string, handler: (Player, ...any) -> ...any)
	assert(isServer, "Net.handle é só do servidor")
	remote(name).OnServerInvoke = function(player: Player, ...)
		if not allow(player, name) then
			return false, "rate_limited"
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(string.format("[Net] erro em %s de %s: %s", name, player.Name, tostring(results[2])))
			return false, "error"
		end
		return table.unpack(results, 2, results.n)
	end
end

function Net.fire(name: string, player: Player, ...: any)
	remote(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	remote(name):FireAllClients(...)
end

-- =========================================================================
-- API do cliente
-- =========================================================================
function Net.connect(name: string, handler: (...any) -> ()): RBXScriptConnection
	return remote(name).OnClientEvent:Connect(handler)
end

function Net.send(name: string, ...: any)
	remote(name):FireServer(...)
end

-- Chama um RemoteFunction com pcall. Retorna os valores do servidor ou (false, "network").
function Net.invoke(name: string, ...: any): ...any
	local results = table.pack(pcall(remote(name).InvokeServer, remote(name), ...))
	if not results[1] then
		warn("[Net] falha ao chamar " .. name .. ": " .. tostring(results[2]))
		return false, "network"
	end
	return table.unpack(results, 2, results.n)
end

return Net
