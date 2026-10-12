--[[
	PlotService.luau
	Bases de tycoon (plots) nas bordas do mapa:
	- Cada jogador recebe um plot ao entrar e nasce nele (SpawnLocation + RespawnLocation).
	- Níveis 1..6 comprados com Cash (botão no chão da base ou menu). Cada nível constrói peças
	  novas com animação e libera coletáveis na Pista de Gravação (só o dono coleta).
	- Cofre: recebe o dinheiro dos clones (EconomyService). O dono encosta para coletar;
	  invasores encostam para levar 25% (1x por base a cada 2 min).
	- Porta laser: TRANCAR fecha por 60 s (+bônus do nível) e depois recarrega 60 s.
	  Produtos LockBase5/30 trancam sem recarga. Proteção de novato nos primeiros 10 min.
	- Invasão: alerta o dono; base trancada/protegida empurra invasores para fora.
	- Laser de defesa (nível 5): empurra invasores parados há mais de 3 s.
	- Teleporte "Ir para Base" / "Ir para Cidade".
	Tudo validado no servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local MapLayout = require(Shared.MapLayout)
local Net = require(Shared.Net)

local PlotBuilder = require(script.Parent.Parent.Build.PlotBuilder)

local PlotService = {}

type PlotState = {
	lockedUntil: number, -- Clock.now()
	cooldownUntil: number,
	protectedUntil: number,
	vaultStealAt: number, -- os.clock() do último roubo de cofre
	lastVaultLabel: string,
	lastGateLabel: string,
	invaders: { [Player]: { since: number, anchor: Vector3, alertAt: number } },
}

local Services
local plots: { PlotBuilder.Plot } = {}
local owners: { [number]: Player } = {}
local playerPlot: { [Player]: number } = {}
local states: { [number]: PlotState } = {}
local padArmed: { [Player]: { [string]: boolean } } = {}
local lastTeleport: { [Player]: number } = {}
local lastPushNotice: { [Player]: number } = {}

local F = MapLayout.FLOOR_TOP

local function newState(): PlotState
	return {
		lockedUntil = 0,
		cooldownUntil = 0,
		protectedUntil = 0,
		vaultStealAt = -math.huge,
		lastVaultLabel = "",
		lastGateLabel = "",
		invaders = {},
	}
end

local function dataOf(player: Player)
	local profile = Services.DataService.get(player)
	return profile and profile.Data
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- =========================================================================
-- Consultas
-- =========================================================================
function PlotService.getPlotIndex(player: Player): number?
	return playerPlot[player]
end

function PlotService.getPlot(player: Player): PlotBuilder.Plot?
	local index = playerPlot[player]
	return index and plots[index]
end

function PlotService.ownerOf(index: number): Player?
	return owners[index]
end

function PlotService.plots(): { PlotBuilder.Plot }
	return plots
end

function PlotService.getSpawnCFrame(player: Player): CFrame
	local plot = PlotService.getPlot(player)
	if plot then
		local s = MapLayout.Local.Spawn
		return plot.cframe * CFrame.new(s[1], F + 3, s[2])
	end
	return Services.Map.fallbackSpawn
end

function PlotService.isInsideOwnPlot(player: Player): boolean
	local root = rootOf(player)
	local index = playerPlot[player]
	if not root or not index then
		return false
	end
	return MapLayout.plotAt(root.Position.X, root.Position.Z) == index
end

-- Base aberta para invasão? (não trancada e sem proteção de novato)
function PlotService.isOpen(index: number): boolean
	local state = states[index]
	local now = Clock.now()
	return state ~= nil and now >= state.lockedUntil and now >= state.protectedUntil
end

function PlotService.getLockInfo(player: Player): (number, number, number)
	local index = playerPlot[player]
	local state = index and states[index]
	if not state then
		return 0, 0, 0
	end
	return state.lockedUntil, state.cooldownUntil, state.protectedUntil
end

-- Posição do mundo da estante (centro) do jogador.
function PlotService.shelfPosition(player: Player): Vector3?
	local plot = PlotService.getPlot(player)
	if not plot then
		return nil
	end
	local s = MapLayout.Local.Shelf
	return (plot.cframe * CFrame.new(s[1] + 2, F + 3, s[2])).Position
end

-- Transformações espaço local do plot <-> mundo (para fitas da Pista).
function PlotService.toWorldFn(index: number): (number, number, number) -> (number, number, number)
	local _, _, yaw = MapLayout.plot(index)
	return function(x, z, rot)
		local wx, wz = MapLayout.toWorld(index, x, z)
		return wx, wz, rot + yaw
	end
end

function PlotService.toLocalFn(index: number): (number, number, number) -> (number, number, number)
	local _, _, yaw = MapLayout.plot(index)
	return function(x, z, rot)
		local lx, lz = MapLayout.toLocal(index, x, z)
		return lx, lz, rot - yaw
	end
end

-- =========================================================================
-- Visual (botões, cofre, estante, portão)
-- =========================================================================
function PlotService.refresh(player: Player)
	local index = playerPlot[player]
	local data = dataOf(player)
	if not index or not data then
		return
	end
	local plot = plots[index]
	local nextLevel = data.BaseLevel + 1
	local spec = Config.BaseLevels[nextLevel]
	plot.buyPad.label.Text = if spec
		then string.format("🧱 Nível %d\n💰 %s", nextLevel, Format.number(spec.Price))
		else "🏆 MAX"
	PlotBuilder.setShelfCapacity(plot, Services.EconomyService.getSlots(player))
end

local function updateVaultLabel(index: number, player: Player)
	local data = dataOf(player)
	if not data then
		return
	end
	local capacity = Services.EconomyService.getVaultCapacity(player)
	local text = string.format("💰 %s / %s", Format.number(data.VaultCash), Format.number(capacity))
	if data.VaultCash >= capacity then
		text ..= "  CHEIO"
	end
	local state = states[index]
	if state.lastVaultLabel ~= text then
		state.lastVaultLabel = text
		plots[index].vault.label.Text = text
	end
end

local function updateGate(index: number)
	local plot = plots[index]
	local state = states[index]
	local now = Clock.now()
	local text
	local locked = owners[index] ~= nil and now < state.lockedUntil
	if not owners[index] then
		text = ""
	elseif locked then
		text = "🔒 " .. Format.time(state.lockedUntil - now)
	elseif now < state.protectedUntil then
		text = "🛡️ " .. Format.time(state.protectedUntil - now)
	elseif now < state.cooldownUntil then
		text = "🔓 ⏳" .. Format.time(state.cooldownUntil - now)
	else
		text = "🔓"
	end
	if state.lastGateLabel ~= text then
		state.lastGateLabel = text
		plot.gate.label.Text = text
		for _, laser in plot.gate.lasers do
			laser.Transparency = if locked then 0.15 else 1
		end
		plot.model:SetAttribute("LockedUntil", state.lockedUntil)
		plot.model:SetAttribute("ProtectedUntil", state.protectedUntil)
	end
end

-- =========================================================================
-- Dono do plot
-- =========================================================================
local function buildTrackPickups(index: number, fromLevel: number, toLevel: number)
	local list = {}
	for level = fromLevel, toLevel do
		for _, spawn in PlotBuilder.trackSpawns(level) do
			local wx, wz = MapLayout.toWorld(index, spawn.lx, spawn.lz)
			table.insert(list, { kind = spawn.kind, position = Vector3.new(wx, spawn.y, wz), vip = false })
		end
	end
	Services.PickupService.addGroup("plot" .. index, list, index)
end

function PlotService.onPlayerAdded(player: Player)
	for index, plot in plots do
		if not owners[index] then
			owners[index] = player
			playerPlot[player] = index
			if plot.model:GetAttribute("Bot") then -- sobra do /stress
				plot.model:SetAttribute("Bot", nil)
				PlotBuilder.clearLevels(plot)
			end
			local colorName = Config.BaseColors[index] or "Medium stone grey"
			PlotBuilder.setOwner(plot, player.DisplayName, player.UserId, colorName)
			plot.model:SetAttribute("OwnerId", player.UserId)
			player:SetAttribute("PlotIndex", index)
			player:SetAttribute("BaseColor", BrickColor.new(colorName).Color)
			player:SetAttribute("BaseColorName", colorName)
			player.RespawnLocation = plot.spawn
			local state = newState()
			state.protectedUntil = Clock.now() + Config.Lock.NewbieProtection
			states[index] = state
			padArmed[player] = {}
			updateGate(index)
			return
		end
	end
	player:SetAttribute("BaseColor", Color3.new(1, 1, 1))
	padArmed[player] = {}
end

function PlotService.onPlayerLoaded(player: Player, profile)
	local index = playerPlot[player]
	if not index then
		return
	end
	local plot = plots[index]
	local level = math.clamp(profile.Data.BaseLevel, 1, #Config.BaseLevels)
	profile.Data.BaseLevel = level
	for l = 1, level do
		PlotBuilder.buildLevel(plot, l, false)
	end
	buildTrackPickups(index, 1, level)
	PlotService.refresh(player)
	updateVaultLabel(index, player)
end

function PlotService.onPlayerRemoving(player: Player)
	local index = playerPlot[player]
	padArmed[player] = nil
	lastTeleport[player] = nil
	lastPushNotice[player] = nil
	for _, state in states do
		state.invaders[player] = nil
	end
	if not index then
		return
	end
	local plot = plots[index]
	playerPlot[player] = nil
	owners[index] = nil
	states[index] = newState()
	Services.PickupService.removeGroup("plot" .. index)
	PlotBuilder.clearLevels(plot)
	PlotBuilder.setOwner(plot, nil, nil, nil)
	PlotBuilder.setShelfCapacity(plot, 0)
	plot.model:SetAttribute("OwnerId", nil)
	plot.buyPad.label.Text = ""
	plot.vault.label.Text = ""
	updateGate(index)
end

-- Reconstrói a base do zero (rebirth).
function PlotService.rebuild(player: Player)
	local index = playerPlot[player]
	local data = dataOf(player)
	if not index or not data then
		return
	end
	local plot = plots[index]
	Services.PickupService.removeGroup("plot" .. index)
	PlotBuilder.clearLevels(plot)
	for l = 1, data.BaseLevel do
		PlotBuilder.buildLevel(plot, l, true)
	end
	buildTrackPickups(index, 1, data.BaseLevel)
	PlotService.refresh(player)
end

-- =========================================================================
-- Níveis
-- =========================================================================
-- free = produto InstantBaseLevel (não cobra Cash).
function PlotService.buyLevel(player: Player, free: boolean?): (boolean, string?)
	local index = playerPlot[player]
	local data = dataOf(player)
	if not index or not data then
		return false, "no_plot"
	end
	local nextLevel = data.BaseLevel + 1
	local spec = Config.BaseLevels[nextLevel]
	if not spec then
		return false, "max_base"
	end
	if not free then
		if data.Cash < spec.Price then
			return false, "not_enough_cash"
		end
		data.Cash -= spec.Price
	end
	data.BaseLevel = nextLevel
	PlotBuilder.buildLevel(plots[index], nextLevel, true)
	buildTrackPickups(index, nextLevel, nextLevel)
	PlotService.refresh(player)
	Services.EconomyService.markDirty(player)
	Net.fire("Notify", player, "toast_level_built", { n = nextLevel }, "gold")
	Net.fireAll("Fx", "build", { plot = index, level = nextLevel })
	return true, nil
end

-- =========================================================================
-- Porta laser
-- =========================================================================
local function pushOut(player: Player, index: number, noticeKey: string?)
	local character = player.Character
	if not character then
		return
	end
	local ox, oz = MapLayout.point(index, "GateOutside")
	local cx, cz = MapLayout.plot(index)
	local from = Vector3.new(ox, F + 3, oz)
	local away = Vector3.new(ox - cx, 0, oz - cz).Unit
	character:PivotTo(CFrame.lookAt(from, from + away))
	if noticeKey and os.clock() - (lastPushNotice[player] or 0) > 3 then
		lastPushNotice[player] = os.clock()
		Net.fire("Notify", player, noticeKey, nil, "warn")
	end
	Services.TheftService.onPushedOut(player)
end

-- seconds/ignoreCooldown: usados pelos produtos LockBase5/30.
function PlotService.lock(player: Player, seconds: number?, ignoreCooldown: boolean?): (boolean, string?)
	local index = playerPlot[player]
	local data = dataOf(player)
	if not index or not data then
		return false, "no_plot"
	end
	local state = states[index]
	local now = Clock.now()
	if not ignoreCooldown then
		if now < state.lockedUntil then
			return false, "already_locked"
		end
		if now < state.cooldownUntil then
			return false, "lock_cooldown"
		end
	end
	local spec = Config.BaseLevels[data.BaseLevel]
	local duration = seconds or (Config.Lock.Seconds + (if spec then spec.LockBonus else 0))
	state.lockedUntil = math.max(state.lockedUntil, now) + duration
	state.cooldownUntil = if ignoreCooldown then state.lockedUntil else state.lockedUntil + Config.Lock.Cooldown
	updateGate(index)
	-- Quem está dentro (e não é o dono) sai.
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if other ~= player and root and MapLayout.plotAt(root.Position.X, root.Position.Z) == index then
			pushOut(other, index, "toast_base_closed")
		end
	end
	Net.fire("Notify", player, "toast_base_locked", { t = Format.time(state.lockedUntil - now) }, "good")
	Net.fireAll("Fx", "lock", { plot = index })
	Services.EconomyService.markDirty(player)
	return true, nil
end

-- =========================================================================
-- Cofre
-- =========================================================================
local function collectVault(player: Player, index: number)
	local amount = Services.EconomyService.collectVault(player)
	if amount > 0 then
		local door = plots[index].vault.door
		Net.fire("Notify", player, "toast_vault_collected", { n = Format.number(amount) }, "gold")
		Net.fireAll(
			"Fx",
			"vault",
			{ position = door.Position, amount = amount, color = player:GetAttribute("BaseColor") }
		)
	end
end

local function stealVault(thief: Player, index: number)
	local owner = owners[index]
	local state = states[index]
	if not owner or not PlotService.isOpen(index) or os.clock() - state.vaultStealAt < Config.Vault.StealCooldown then
		return
	end
	local amount = Services.EconomyService.stealFromVault(thief, owner)
	if amount <= 0 then
		return
	end
	state.vaultStealAt = os.clock()
	Net.fire("Notify", thief, "toast_vault_steal", { n = Format.number(amount), name = owner.DisplayName }, "gold")
	Net.fire("Alert", owner, "vault", { name = thief.DisplayName, amount = amount, plot = index })
	Net.fireAll("Fx", "vault", {
		position = plots[index].vault.door.Position,
		amount = amount,
		color = thief:GetAttribute("BaseColor"),
	})
end

-- =========================================================================
-- Loop (4 Hz): botões, cofre, invasão, laser de defesa, portões, plataformas
-- =========================================================================
local function near(root: BasePart, target: Vector3, radius: number): boolean
	local p = root.Position
	return MapLayout.distanceXZ(p.X, p.Z, target.X, target.Z) <= radius and math.abs(p.Y - target.Y) < 7
end

local function pad(player: Player, key: string, inside: boolean, action: () -> ())
	local armed = padArmed[player]
	if not armed then
		return
	end
	if inside then
		if armed[key] ~= false then
			armed[key] = false -- precisa sair do botão para apertar de novo
			action()
		end
	else
		armed[key] = true
	end
end

local function handleInvader(player: Player, root: BasePart, index: number)
	local owner = owners[index]
	if not owner or owner == player then
		return
	end
	local state = states[index]
	local now = Clock.now()
	if now < state.lockedUntil then
		pushOut(player, index, "toast_base_closed")
		return
	end
	if now < state.protectedUntil then
		pushOut(player, index, "toast_base_protected")
		return
	end

	local record = state.invaders[player]
	if not record then
		record = { since = os.clock(), anchor = root.Position, alertAt = -math.huge }
		state.invaders[player] = record
	end
	-- Alerta para o dono
	if os.clock() - record.alertAt > Config.Theft.AlertCooldown then
		record.alertAt = os.clock()
		local ownerData = dataOf(owner)
		if not ownerData or ownerData.Settings.Alerts ~= false then
			Net.fire("Alert", owner, "invasion", { name = player.DisplayName, plot = index })
		end
	end
	-- Laser de defesa (nível 5+): invasor parado por IdleSeconds é empurrado.
	local plot = plots[index]
	if plot.level >= Config.DefenseLaserLevel and plot.turret then
		if (root.Position - record.anchor).Magnitude > Config.DefenseLaser.IdleTolerance then
			record.anchor = root.Position
			record.since = os.clock()
		elseif os.clock() - record.since >= Config.DefenseLaser.IdleSeconds then
			Net.fireAll("Fx", "laser", { from = plot.turret.Position, to = root.Position })
			pushOut(player, index, "toast_laser_pushed")
			state.invaders[player] = nil
		end
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root then
			continue
		end
		local pos = root.Position
		local inside = MapLayout.plotAt(pos.X, pos.Z)
		-- limpa registros de invasão de outras bases
		for index, state in states do
			if index ~= inside then
				state.invaders[player] = nil
			end
		end
		if not inside then
			continue
		end
		local plot = plots[inside]
		if owners[inside] == player then
			-- Dono: cofre, botão de compra e botão de trancar
			if near(root, plot.vault.door.Position, Config.Vault.CollectRadius) then
				collectVault(player, inside)
			end
			pad(player, "buy", near(root, plot.buyPad.top.Position, 3.2), function()
				local ok, reason = PlotService.buyLevel(player, false)
				if not ok then
					Net.fire("Notify", player, "reason_" .. tostring(reason), nil, "warn")
				end
			end)
			pad(player, "lock", near(root, plot.lockPad.top.Position, 3.2), function()
				local ok, reason = PlotService.lock(player, nil, false)
				if not ok then
					Net.fire("Notify", player, "reason_" .. tostring(reason), nil, "warn")
				end
			end)
		else
			handleInvader(player, root, inside)
			local owner = owners[inside]
			if owner and owners[inside] and near(root, plot.vault.door.Position, Config.Vault.CollectRadius) then
				stealVault(player, inside)
			end
		end
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function PlotService.init(services)
	Services = services
	plots = services.Map.plots
	for index in plots do
		states[index] = newState()
	end
end

function PlotService.start()
	Net.handle("BuyBaseLevel", function(player)
		return PlotService.buyLevel(player, false)
	end)
	Net.handle("LockBase", function(player)
		if not PlotService.isInsideOwnPlot(player) then
			return false, "not_in_base"
		end
		return PlotService.lock(player, nil, false)
	end)
	Net.handle("Teleport", function(player, destination)
		if not Net.check.oneOf(destination, { "base", "city" }) then
			return false, "unknown"
		end
		if os.clock() - (lastTeleport[player] or -math.huge) < Config.TeleportCooldown then
			return false, "teleport_cooldown"
		end
		if Services.RecordingService.isRecording(player) then
			return false, "recording"
		end
		if Services.TheftService.isCarrying(player) then
			return false, "carrying"
		end
		local character = player.Character
		if not character or not rootOf(player) then
			return false, "dead"
		end
		lastTeleport[player] = os.clock()
		local target = if destination == "base"
			then PlotService.getSpawnCFrame(player)
			else Services.Map.cityTeleport * CFrame.new(math.random(-4, 4), 0, 0)
		pcall(player.RequestStreamAroundAsync, player, target.Position, 2)
		character:PivotTo(target)
		return true, nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PlotService] tick: " .. tostring(err))
			end
		end
	end)
	-- Portões, cofres e plataformas móveis
	task.spawn(function()
		local moverPhase = false
		local lastMover = os.clock()
		while true do
			task.wait(0.5)
			for index in plots do
				updateGate(index)
				local owner = owners[index]
				if owner then
					updateVaultLabel(index, owner)
				end
			end
			if os.clock() - lastMover >= 4.5 then
				lastMover = os.clock()
				moverPhase = not moverPhase
				for _, plot in plots do
					for _, mover in plot.movers do
						mover.constraint.TargetPosition = if moverPhase then mover.range else 0
					end
				end
			end
		end
	end)
end

return PlotService
