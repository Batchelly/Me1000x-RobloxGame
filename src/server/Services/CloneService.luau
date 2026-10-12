--[[
	CloneService.luau
	O servidor guarda SÓ OS DADOS de cada clone: caminho comprimido, início do loop e estado.
	Não existe Humanoid físico no servidor. A posição é simulada pelo tempo:

		fase = (Clock.now() - startTime) % duração  ->  Path.sample(path, fase)

	A cada Config.CloneTickRate (0,1 s) o servidor varre o segmento percorrido por cada clone
	contra as moedas (spatial hash) e as bananas. Os clientes renderizam (CloneRenderer).

	v2: cada clone é uma FITA na estante da base.
	- zone = "city" (gravado na Cidade, caminho no espaço do mundo) ou "track" (gravado na
	  Pista da base, caminho salvo no espaço LOCAL do plot: roda na base atual do dono, mesmo
	  que ele caia em outro plot na próxima sessão ou que a fita seja roubada).
	- transit = fita sendo carregada por um ladrão (o clone para).
	- rate = quanto a fita rendeu no último minuto.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Base64 = require(Shared.Base64)
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Path = require(Shared.Path)
local Types = require(Shared.Types)

local CloneService = {}

export type Collector = {
	player: Player,
	golden: boolean,
	kind: string, -- "clone" | "player"
	color: Color3,
	clone: any?,
}

export type Clone = {
	id: number,
	owner: Player,
	ownerId: number,
	ownerName: string,
	slot: number,
	buffer: buffer, -- caminho no espaço do mundo (o que roda)
	localBuffer: buffer?, -- fitas da Pista: caminho no espaço local do plot (o que é salvo)
	encoded: string?,
	path: Path.PathData,
	zone: string,
	label: string,
	tapeColor: string,
	origin: string?,
	startTime: number,
	fallen: boolean,
	fallenPhase: number,
	transit: boolean,
	golden: boolean,
	debug: boolean,
	collector: Collector,
	minuteEarned: number,
	rate: number,
	rateAt: number,
	createdAt: number,
	-- estado da simulação
	lx: number?,
	ly: number?,
	lz: number?,
	lastPhase: number?,
}

local Services
local clones: { [number]: Clone } = {}
local byOwner: { [Player]: { [number]: Clone } } = {}
local nextId = 0
local templates: Folder

local function toInfo(clone: Clone): Types.CloneInfo
	return {
		id = clone.id,
		ownerId = clone.ownerId,
		ownerName = clone.ownerName,
		slot = clone.slot,
		golden = clone.golden,
		fallen = clone.fallen,
		fallenPhase = clone.fallenPhase,
		transit = clone.transit,
		startTime = clone.startTime,
		path = clone.buffer,
		color = clone.collector.color,
		zone = clone.zone,
		label = clone.label,
		debug = clone.debug,
	}
end

-- Registro salvo de uma fita (o caminho da Pista vai no espaço local).
function CloneService.serialize(clone: Clone): Types.SavedClone
	if not clone.encoded then
		clone.encoded = Base64.encode(clone.localBuffer or clone.buffer)
	end
	return {
		P = clone.encoded :: string,
		F = clone.fallen or nil,
		Z = clone.zone,
		K = clone.tapeColor,
		N = clone.label,
		O = clone.origin,
	}
end

-- Regrava data.Clones a partir dos clones vivos (não-debug) do jogador.
local function persist(player: Player)
	local profile = Services.DataService.get(player)
	if not profile then
		return
	end
	local saved = {}
	for slot, clone in byOwner[player] or {} do
		if not clone.debug then
			saved[tostring(slot)] = CloneService.serialize(clone)
		end
	end
	profile.Data.Clones = saved
end

-- =========================================================================
-- Templates R6 (um por dono)
-- =========================================================================
local function prepareTemplate(model: Model, desc: HumanoidDescription)
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Animator") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = math.max(d.Transparency, Config.CloneTransparency)
			end
		elseif d:IsA("Decal") then
			d.Transparency = math.max(d.Transparency, Config.CloneTransparency)
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
		root.Transparency = 1
		model.PrimaryPart = root
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false -- sem física de Humanoid: o cliente move tudo
	end
	model:SetAttribute("GhostColor", desc.TorsoColor)
end

function CloneService.ensureTemplate(player: Player)
	local name = tostring(player.UserId)
	if templates:FindFirstChild(name) then
		return
	end
	local desc = Services.CharacterService.getDescription(player)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not ok or not model then
		warn("[CloneService] template R6 falhou para " .. player.Name .. ": " .. tostring(model))
		return
	end
	prepareTemplate(model, desc)
	model.Name = name
	model.Parent = templates
end

-- =========================================================================
-- CRUD de clones
-- =========================================================================
export type CreateOptions = {
	startTime: number?,
	fallen: boolean?,
	debug: boolean?,
	skipPersist: boolean?,
	zone: string?,
	localBuffer: buffer?,
	label: string?,
	tapeColor: string?,
	origin: string?,
	displayName: string?, -- nome no BillboardGui (bots do teste de carga)
}

function CloneService.create(player: Player, slot: number, buf: buffer, options: CreateOptions?): Clone?
	local opts: CreateOptions = options or {}
	local path = Path.decode(buf)
	if not path then
		warn("[CloneService] caminho inválido para " .. player.Name)
		return nil
	end
	local owned = byOwner[player]
	if not owned then
		owned = {}
		byOwner[player] = owned
	end
	local existing = owned[slot]
	if existing then
		CloneService.remove(existing, true)
	end

	nextId += 1
	local now = Clock.now()
	local clone: Clone = {
		id = nextId,
		owner = player,
		ownerId = player.UserId,
		ownerName = opts.displayName or player.DisplayName,
		slot = slot,
		buffer = buf,
		localBuffer = opts.localBuffer,
		encoded = nil,
		path = path,
		zone = opts.zone or "city",
		label = opts.label or string.format("%s #%d", player.DisplayName, slot),
		tapeColor = opts.tapeColor or Config.TapeColors[(slot - 1) % #Config.TapeColors + 1],
		origin = opts.origin,
		startTime = opts.startTime or now,
		fallen = opts.fallen == true,
		fallenPhase = 0,
		transit = false,
		golden = false,
		debug = opts.debug == true,
		collector = {
			player = player,
			golden = false,
			kind = "clone",
			color = Services.CharacterService.getColor(player),
			clone = nil,
		},
		minuteEarned = 0,
		rate = 0,
		rateAt = os.clock(),
		createdAt = os.clock(),
	}
	clone.collector.clone = clone
	clones[clone.id] = clone
	owned[slot] = clone

	CloneService.refreshGolden(player, clone)
	if not clone.debug and not opts.skipPersist then
		persist(player)
	end
	Net.fireAll("CloneAdded", toInfo(clone))
	if not clone.debug then
		Services.TheftService.onCloneAdded(clone)
	end
	Services.EconomyService.markDirty(player)
	return clone
end

-- Recria uma fita salva (perfil, roubo, recuperação). Fitas da Pista vão para a base atual.
function CloneService.createFromSaved(
	player: Player,
	slot: number,
	saved: Types.SavedClone,
	opts: CreateOptions?
): Clone?
	if type(saved) ~= "table" or type(saved.P) ~= "string" then
		return nil
	end
	local stored = Base64.decode(saved.P)
	if not stored then
		return nil
	end
	local zone = if saved.Z == "track" then "track" else "city"
	local worldBuf: buffer? = stored
	local localBuf: buffer? = nil
	if zone == "track" then
		local index = Services.PlotService.getPlotIndex(player)
		if not index then
			return nil
		end
		localBuf = stored
		worldBuf = Path.mapXZ(stored, Services.PlotService.toWorldFn(index))
	end
	if not worldBuf then
		return nil
	end
	local options: CreateOptions = if opts then table.clone(opts) else {}
	options.zone = zone
	options.localBuffer = localBuf
	options.fallen = options.fallen or saved.F == true
	options.label = if type(saved.N) == "string" then string.sub(saved.N, 1, 40) else nil
	options.tapeColor = if type(saved.K) == "string" then saved.K else nil
	options.origin = if type(saved.O) == "string" then string.sub(saved.O, 1, 40) else nil
	return CloneService.create(player, slot, worldBuf :: buffer, options)
end

-- silent = não regrava data.Clones (usado na saída do jogador).
function CloneService.remove(clone: Clone, silent: boolean?)
	if not clones[clone.id] then
		return
	end
	clones[clone.id] = nil
	local owned = byOwner[clone.owner]
	if owned and owned[clone.slot] == clone then
		owned[clone.slot] = nil
	end
	Net.fireAll("CloneRemoved", clone.id)
	if not clone.debug then
		Services.TheftService.onCloneRemoved(clone)
	end
	if not silent and not clone.debug then
		persist(clone.owner)
		CloneService.refreshGolden(clone.owner)
	end
	Services.EconomyService.markDirty(clone.owner)
end

-- Remove todos os clones do jogador. clearSaved = apaga também do perfil (rebirth).
function CloneService.removeAll(player: Player, clearSaved: boolean?)
	for _, clone in table.clone(byOwner[player] or {}) do
		CloneService.remove(clone, true)
	end
	if clearSaved then
		local profile = Services.DataService.get(player)
		if profile then
			profile.Data.Clones = {}
		end
	end
end

function CloneService.removeDebug(player: Player?)
	for _, clone in table.clone(clones) do
		if clone.debug and (player == nil or clone.owner == player) then
			CloneService.remove(clone, true)
		end
	end
end

-- Passa a fita para outro dono (roubo entregue). Retorna o clone novo.
function CloneService.transfer(clone: Clone, newOwner: Player, slot: number): Clone?
	local saved = CloneService.serialize(clone)
	saved.F = nil
	saved.O = clone.origin or clone.owner.DisplayName
	local oldOwner = clone.owner
	CloneService.remove(clone, false)
	local created = CloneService.createFromSaved(newOwner, slot, saved)
	Services.EconomyService.markDirty(oldOwner)
	return created
end

-- Clone dourado (passe GoldenClone): o clone de menor slot do dono.
function CloneService.refreshGolden(player: Player, pending: Clone?)
	local owned = byOwner[player]
	if not owned then
		return
	end
	local hasPass = Services.MonetizationService.ownsPass(player, "GoldenClone")
	local goldenSlot = math.huge
	if hasPass then
		for slot, clone in owned do
			if not clone.debug and slot < goldenSlot then
				goldenSlot = slot
			end
		end
	end
	for slot, clone in owned do
		local golden = hasPass and slot == goldenSlot
		if clone.golden ~= golden then
			clone.golden = golden
			clone.collector.golden = golden
			if clone ~= pending then -- o clone novo vai com o estado certo no CloneAdded
				Net.fireAll("CloneUpdated", clone.id, { golden = golden })
				Services.TheftService.onCloneUpdated(clone)
			end
		end
	end
end

-- =========================================================================
-- Estados: caído (banana) e em trânsito (roubo)
-- =========================================================================
function CloneService.phaseOf(clone: Clone, now: number): number
	return Path.phase(clone.path, now - clone.startTime)
end

function CloneService.setFallen(clone: Clone, fallen: boolean)
	if clone.fallen == fallen then
		return
	end
	local now = Clock.now()
	if fallen then
		clone.fallenPhase = CloneService.phaseOf(clone, now)
		clone.fallen = true
	else
		-- Continua o loop de onde caiu.
		clone.startTime = now - clone.fallenPhase
		clone.fallen = false
		clone.lastPhase = nil
	end
	Net.fireAll("CloneUpdated", clone.id, {
		fallen = clone.fallen,
		fallenPhase = clone.fallenPhase,
		startTime = clone.startTime,
	})
	if not clone.debug then
		persist(clone.owner)
	end
	Services.EconomyService.markDirty(clone.owner)
end

function CloneService.setTransit(clone: Clone, transit: boolean)
	if clone.transit == transit then
		return
	end
	clone.transit = transit
	clone.lastPhase = nil
	Net.fireAll("CloneUpdated", clone.id, { transit = transit })
	Services.EconomyService.markDirty(clone.owner)
end

function CloneService.fixAll(player: Player)
	for _, clone in table.clone(byOwner[player] or {}) do
		if clone.fallen then
			CloneService.setFallen(clone, false)
		end
	end
end

-- =========================================================================
-- Consultas
-- =========================================================================
function CloneService.get(id: number): Clone?
	return clones[id]
end

function CloneService.count(player: Player): number
	local n = 0
	for _, clone in byOwner[player] or {} do
		if not clone.debug then
			n += 1
		end
	end
	return n
end

function CloneService.getSlot(player: Player, slot: number): Clone?
	local owned = byOwner[player]
	return owned and owned[slot]
end

function CloneService.owned(player: Player): { [number]: Clone }
	return byOwner[player] or {}
end

function CloneService.freeSlot(player: Player, slots: number): number?
	local owned = byOwner[player] or {}
	for slot = 1, math.min(slots, Config.MaxClonesPerPlayer) do
		if not owned[slot] then
			return slot
		end
	end
	return nil
end

local function rateOf(clone: Clone): number
	local elapsed = os.clock() - clone.rateAt
	if clone.rate > 0 or os.clock() - clone.createdAt >= 60 then
		return clone.rate
	end
	return if elapsed > 5 then math.floor(clone.minuteEarned / elapsed * 60) else 0
end

function CloneService.summary(player: Player): ({ Types.CloneSummary }, number)
	local list = {}
	local fallenCount = 0
	for slot, clone in byOwner[player] or {} do
		if not clone.debug then
			table.insert(list, {
				slot = slot,
				fallen = clone.fallen,
				golden = clone.golden,
				transit = clone.transit,
				zone = clone.zone,
				label = clone.label,
				tapeColor = clone.tapeColor,
				origin = clone.origin,
				rate = rateOf(clone),
				cloneId = clone.id,
			})
			if clone.fallen then
				fallenCount += 1
			end
		end
	end
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list, fallenCount
end

function CloneService.snapshot(): { Types.CloneInfo }
	local list = {}
	for _, clone in clones do
		table.insert(list, toInfo(clone))
	end
	return list
end

function CloneService.all(): { [number]: Clone }
	return clones
end

-- =========================================================================
-- Simulação (chamada pelo Main a cada Config.CloneTickRate)
-- =========================================================================
function CloneService.tick(now: number)
	local PickupService = Services.PickupService
	local TrapService = Services.TrapService
	local clock = os.clock()
	for _, clone in clones do
		-- renda por minuto de cada fita
		if clock - clone.rateAt >= 60 then
			clone.rate = clone.minuteEarned
			clone.minuteEarned = 0
			clone.rateAt = clock
		end
		if clone.fallen or clone.transit then
			continue
		end
		local phase = Path.phase(clone.path, now - clone.startTime)
		local x, y, z = Path.sample(clone.path, phase)
		local lx, ly, lz = clone.lx, clone.ly, clone.lz
		-- Na virada do loop o clone "teleporta" para o início: não varre esse trecho.
		if lx == nil or clone.lastPhase == nil or phase < clone.lastPhase then
			lx, ly, lz = x, y, z
		end
		clone.lx, clone.ly, clone.lz, clone.lastPhase = x, y, z, phase

		if TrapService.checkClone(clone, lx :: number, ly :: number, lz :: number, x, y, z) then
			continue -- caiu nesta varredura
		end
		PickupService.sweep(lx :: number, ly :: number, lz :: number, x, y, z, clone.collector, 0)
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function CloneService.init(services)
	Services = services
	templates = ReplicatedStorage:FindFirstChild("CloneTemplates") :: Folder
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "CloneTemplates"
		templates.Parent = ReplicatedStorage
	end
end

function CloneService.start()
	Net.handle("DeleteClone", function(player, slot)
		if not Net.check.int(slot, 1, Config.MaxClonesPerPlayer) then
			return false, "unknown"
		end
		local clone = CloneService.getSlot(player, slot)
		if not clone then
			return false, "not_found"
		end
		if clone.transit then
			return false, "carrying"
		end
		CloneService.remove(clone, false)
		Net.fire("Notify", player, "toast_clone_deleted", { slot = slot }, "info")
		return true, nil
	end)
end

-- Recria as fitas salvas (as gravações vivem no perfil).
function CloneService.onPlayerLoaded(player: Player, profile)
	CloneService.ensureTemplate(player)
	local maxSlot = Config.MaxClonesPerPlayer
	for slotText, saved in profile.Data.Clones do
		local slot = tonumber(slotText)
		if slot and slot >= 1 and slot <= maxSlot then
			CloneService.createFromSaved(player, slot, saved, { skipPersist = true })
		end
	end
end

function CloneService.onPlayerRemoving(player: Player)
	-- Os clones somem do mundo, mas continuam salvos no perfil (renda offline).
	for _, clone in table.clone(byOwner[player] or {}) do
		CloneService.remove(clone, true)
	end
	byOwner[player] = nil
	local template = templates:FindFirstChild(tostring(player.UserId))
	if template then
		template:Destroy()
	end
end

return CloneService
