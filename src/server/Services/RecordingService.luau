--[[
	RecordingService.luau
	O SERVIDOR amostra o HumanoidRootPart do jogador a Config.RecordHz (10 Hz) durante a
	gravação. O cliente só pede "começar/parar": nenhum dado de caminho vem do cliente.

	Regras:
	- Gravação < Config.MinRecordSeconds é descartada.
	- Morreu / trocou de personagem / saiu: cancela.
	- Amostra com teleporte (distância > velocidade máx * dt * 1,5): gravação inválida.
	- Slots cheios: o cliente precisa dizer qual slot substituir (RecordState "need_replace").
	- Eventos de pulo (Humanoid.StateChanged -> Jumping) viram flags na amostra.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Path = require(Shared.Path)

local RecordingService = {}

type Session = {
	slot: number,
	zone: string, -- "city" | "track" (Pista da própria base)
	plotIndex: number?,
	startClock: number,
	duration: number,
	maxSamples: number,
	walkSpeed: number,
	xs: { number },
	ys: { number },
	zs: { number },
	yaws: { number },
	flags: { number },
	jumpPending: boolean,
	root: BasePart,
	character: Model,
	connections: { RBXScriptConnection },
}

local Services
local sessions: { [Player]: Session } = {}
local DT = 1 / Config.RecordHz

local function yawFromCFrame(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function cleanup(player: Player): Session?
	local session = sessions[player]
	if not session then
		return nil
	end
	sessions[player] = nil
	for _, connection in session.connections do
		connection:Disconnect()
	end
	Services.EconomyService.markDirty(player)
	return session
end

function RecordingService.isRecording(player: Player): boolean
	return sessions[player] ~= nil
end

function RecordingService.cancel(player: Player, reason: string)
	if cleanup(player) then
		Net.fire("RecordState", player, reason, nil)
	end
end

local function finish(player: Player)
	local session = cleanup(player)
	if not session then
		return
	end
	local n = #session.xs
	local seconds = (n - 1) * DT
	if seconds < Config.MinRecordSeconds then
		Net.fire("RecordState", player, "short", { min = Config.MinRecordSeconds })
		return
	end
	-- Validação final do caminho inteiro (defesa em profundidade).
	local bad = Path.findTeleport(
		session.xs,
		session.ys,
		session.zs,
		DT,
		session.walkSpeed + Config.HorizontalSpeedSlack,
		Config.MaxVerticalSpeed,
		Config.TeleportTolerance,
		Config.TeleportFlatSlack
	)
	if bad then
		Net.fire("RecordState", player, "invalid", nil)
		return
	end
	local buf =
		Path.encode(session.xs, session.ys, session.zs, session.yaws, session.flags, Config.RecordHz, Config.PathScale)
	local options = { zone = session.zone, localBuffer = nil :: buffer? }
	if session.zone == "track" and session.plotIndex then
		-- Fitas da Pista são salvas no espaço local do plot (rodam em qualquer base).
		options.localBuffer = Path.mapXZ(buf, Services.PlotService.toLocalFn(session.plotIndex))
		if not options.localBuffer then
			options.zone = "city"
		end
	end
	local clone = Services.CloneService.create(player, session.slot, buf, options)
	if clone then
		Net.fire("RecordState", player, "done", { slot = session.slot })
	else
		Net.fire("RecordState", player, "invalid", nil)
	end
end

local function sample(player: Player, session: Session): boolean
	local cf = session.root.CFrame
	local pos = cf.Position
	local n = #session.xs
	if n > 0 then
		local valid = Path.isStepValid(
			session.xs[n],
			session.ys[n],
			session.zs[n],
			pos.X,
			pos.Y,
			pos.Z,
			DT,
			session.walkSpeed + Config.HorizontalSpeedSlack,
			Config.MaxVerticalSpeed,
			Config.TeleportTolerance,
			Config.TeleportFlatSlack
		)
		if not valid then
			cleanup(player)
			Net.fire("RecordState", player, "invalid", nil)
			return false
		end
	end
	table.insert(session.xs, pos.X)
	table.insert(session.ys, pos.Y)
	table.insert(session.zs, pos.Z)
	table.insert(session.yaws, yawFromCFrame(cf))
	table.insert(session.flags, if session.jumpPending then Path.FLAG_JUMP else 0)
	session.jumpPending = false
	return true
end

-- forceSlot = regravar uma fita específica (mesmo com vagas livres).
function RecordingService.begin(player: Player, replaceSlot: number?, forceSlot: boolean?)
	if sessions[player] then
		return
	end
	local EconomyService = Services.EconomyService
	local CloneService = Services.CloneService
	if not Services.DataService.get(player) then
		Net.fire("Notify", player, "reason_not_loaded", nil, "warn")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		Net.fire("Notify", player, "reason_dead", nil, "warn")
		return
	end

	if Services.TheftService.isCarrying(player) then
		Net.fire("Notify", player, "reason_carrying", nil, "warn")
		return
	end

	local slots = EconomyService.getSlots(player)
	local slot = if forceSlot
			and replaceSlot
			and CloneService.getSlot(player, replaceSlot)
		then replaceSlot
		else CloneService.freeSlot(player, slots)
	if not slot then
		if replaceSlot and CloneService.getSlot(player, replaceSlot) then
			slot = replaceSlot
		else
			Net.fire("RecordState", player, "need_replace", nil)
			return
		end
	end

	local duration = EconomyService.getRecordSeconds(player)
	local session: Session = {
		slot = slot :: number,
		zone = if Services.PlotService.isInsideOwnPlot(player) then "track" else "city",
		plotIndex = Services.PlotService.getPlotIndex(player),
		startClock = os.clock(),
		duration = duration,
		maxSamples = math.min(Config.MaxSamples, math.floor(duration * Config.RecordHz) + 1),
		-- O cliente pode correr com Shift (SprintController): a velocidade máxima conta com isso.
		walkSpeed = math.max(humanoid.WalkSpeed, EconomyService.getWalkSpeed(player)) * Config.Sprint.Multiplier,
		xs = {},
		ys = {},
		zs = {},
		yaws = {},
		flags = {},
		jumpPending = false,
		root = root,
		character = character,
		connections = {},
	}
	sessions[player] = session

	table.insert(
		session.connections,
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				session.jumpPending = true
			end
		end)
	)
	table.insert(
		session.connections,
		humanoid.Died:Connect(function()
			RecordingService.cancel(player, "died")
		end)
	)
	table.insert(
		session.connections,
		player.CharacterRemoving:Connect(function()
			RecordingService.cancel(player, "died")
		end)
	)

	sample(player, session)
	Net.fire("RecordState", player, "start", {
		duration = duration,
		slot = slot,
		zone = session.zone,
		startedAt = Clock.now(),
	})
	EconomyService.markDirty(player)
end

function RecordingService.stop(player: Player)
	if sessions[player] then
		finish(player)
	end
end

function RecordingService.toggle(player: Player, replaceSlot: number?)
	if sessions[player] then
		RecordingService.stop(player)
	else
		RecordingService.begin(player, replaceSlot)
	end
end

function RecordingService.init(services)
	Services = services
end

function RecordingService.onPlayerRemoving(player: Player)
	cleanup(player)
end

function RecordingService.start()
	Net.on("Record", function(player, action, replaceSlot)
		if not Net.check.oneOf(action, { "toggle", "start", "stop", "rerecord" }) then
			return
		end
		if replaceSlot ~= nil and not Net.check.int(replaceSlot, 1, Config.MaxClonesPerPlayer) then
			return
		end
		if action == "stop" then
			RecordingService.stop(player)
		elseif action == "start" then
			RecordingService.begin(player, replaceSlot)
		elseif action == "rerecord" then
			if RecordingService.isRecording(player) then
				RecordingService.stop(player)
			else
				RecordingService.begin(player, replaceSlot, true)
			end
		else
			RecordingService.toggle(player, replaceSlot)
		end
	end)

	-- Amostragem em tempo real: a amostra k acontece em startClock + k * dt.
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, session in sessions do
			if not session.root.Parent or not player.Parent then
				RecordingService.cancel(player, "died")
				continue
			end
			local due = math.floor((now - session.startClock) / DT) + 1
			while sessions[player] == session and #session.xs < math.min(due, session.maxSamples) do
				if not sample(player, session) then
					break
				end
			end
			if sessions[player] == session and #session.xs >= session.maxSamples then
				finish(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		cleanup(player)
	end)
end

return RecordingService
