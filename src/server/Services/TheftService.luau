--[[
	TheftService.luau
	Fitas na estante e roubo (inspirado no Steal a Brainrot):
	- Cada clone tem uma fita física na estante da base do dono (vaga = slot).
	- Invasor com a porta aberta pega a fita (ProximityPrompt), carrega nas costas com -30% de
	  velocidade (passe FastThief ignora) e precisa levá-la até a estante DA PRÓPRIA base.
	  Entregou: o clone passa para ele (com o caminho original) e os 2 perfis são salvos na hora.
	- Tapa (dono ou qualquer um) derruba o ladrão: a fita volta voando para a estante.
	- Ladrão saiu do jogo / morreu / demorou demais: a fita volta para o dono.
	- Fitas douradas não podem ser roubadas. No máximo 1 fita roubada por base a cada 3 min.
	- Produto RecoverTape: devolve uma cópia da última fita roubada.
	Tudo validado no servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Net = require(Shared.Net)

local Prefabs = require(script.Parent.Parent.Build.Prefabs)

local TheftService = {}

type Tape = { model: Model, prompt: ProximityPrompt, clone: any }
type Carry = { clone: any, victim: Player, startedAt: number, weld: WeldConstraint? }

local Services
local tapes: { [number]: Tape } = {} -- [cloneId]
local carrying: { [Player]: Carry } = {}
local lastTapeSteal: { [Player]: number } = {} -- [vítima] = os.clock()
local lastSlap: { [Player]: number } = {}
local tapesFolder: Folder

local F = MapLayout.FLOOR_TOP

-- CFrame da vaga `slot` na estante do dono do clone.
local function shelfCFrame(player: Player, slot: number): CFrame?
	local plot = Services.PlotService.getPlot(player)
	if not plot or slot < 1 or slot > Config.MaxClonesPerPlayer then
		return nil
	end
	local lx, height, lz = MapLayout.shelfSlot(slot)
	return plot.cframe * CFrame.new(lx, F + height, lz)
end

local function setTapeAnchored(model: Model, anchored: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
			part.Massless = not anchored
			part.CanCollide = false
		end
	end
end

-- =========================================================================
-- Fitas na estante
-- =========================================================================
function TheftService.onCloneAdded(clone)
	local cf = shelfCFrame(clone.owner, clone.slot)
	if not cf then
		return
	end
	local model = Prefabs.tape(cf, clone.tapeColor, clone.label, clone.golden)
	model:SetAttribute("CloneId", clone.id)
	model:SetAttribute("OwnerId", clone.ownerId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pegar fita"
	prompt.ObjectText = clone.label
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = Config.Theft.PickupRadius
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("OwnerId", clone.ownerId)
	prompt:AddTag("TapePrompt")
	prompt.Enabled = not clone.golden
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		local ok, reason = TheftService.take(player, clone.id)
		if not ok and reason then
			Net.fire("Notify", player, "reason_" .. reason, nil, "warn")
		end
	end)
	model.Parent = tapesFolder
	tapes[clone.id] = { model = model, prompt = prompt, clone = clone }
end

function TheftService.onCloneRemoved(clone)
	local tape = tapes[clone.id]
	tapes[clone.id] = nil
	for thief, carry in carrying do
		if carry.clone == clone then
			carrying[thief] = nil
			Services.EconomyService.applyMovement(thief)
			Services.EconomyService.markDirty(thief)
		end
	end
	if tape then
		tape.model:Destroy()
	end
end

function TheftService.onCloneUpdated(clone)
	local tape = tapes[clone.id]
	if not tape then
		return
	end
	local body = tape.model.PrimaryPart
	if body then
		body.BrickColor = BrickColor.new(if clone.golden then "Bright yellow" else "Black")
		body.Material = if clone.golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	tape.prompt.Enabled = not clone.golden
end

-- =========================================================================
-- Roubo
-- =========================================================================
function TheftService.isCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?, humanoid
end

function TheftService.take(thief: Player, cloneId: number): (boolean, string?)
	local tape = tapes[cloneId]
	if not tape then
		return false, "not_found"
	end
	local clone = tape.clone
	local victim: Player = clone.owner
	if victim == thief or clone.debug then
		return false, nil
	end
	if clone.golden then
		return false, "golden_tape"
	end
	if clone.transit or carrying[thief] then
		return false, "carrying"
	end
	local victimIndex = Services.PlotService.getPlotIndex(victim)
	if not victimIndex or not Services.PlotService.isOpen(victimIndex) then
		return false, "base_closed"
	end
	if os.clock() - (lastTapeSteal[victim] or -math.huge) < Config.Theft.BaseCooldown then
		return false, "base_cooldown"
	end
	if not Services.DataService.get(thief) or not Services.PlotService.getPlotIndex(thief) then
		return false, "no_plot"
	end
	if Services.CloneService.count(thief) >= Services.EconomyService.getSlots(thief) then
		return false, "shelf_full"
	end
	if Services.RecordingService.isRecording(thief) then
		return false, "recording"
	end
	local root, humanoid = rootOf(thief)
	local torso = thief.Character and thief.Character:FindFirstChild("Torso") :: BasePart?
	if not root or not humanoid or not torso then
		return false, "dead"
	end
	local body = tape.model.PrimaryPart :: BasePart
	if (root.Position - body.Position).Magnitude > Config.Theft.PickupRadius + 2 then
		return false, "too_far"
	end
	if MapLayout.plotAt(root.Position.X, root.Position.Z) ~= victimIndex then
		return false, "too_far"
	end

	-- Pega: a fita vai para as costas do ladrão.
	lastTapeSteal[victim] = os.clock()
	Services.CloneService.setTransit(clone, true)
	tape.prompt.Enabled = false
	setTapeAnchored(tape.model, false)
	tape.model:PivotTo(torso.CFrame * CFrame.new(0, 0, 0.9) * CFrame.Angles(0, math.pi / 2, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = body
	weld.Parent = body
	-- as outras partes da fita ficam presas ao corpo dela
	for _, part in tape.model:GetDescendants() do
		if part:IsA("BasePart") and part ~= body then
			local inner = Instance.new("WeldConstraint")
			inner.Part0 = body
			inner.Part1 = part
			inner.Parent = part
		end
	end
	carrying[thief] = { clone = clone, victim = victim, startedAt = os.clock(), weld = weld }
	if not Services.MonetizationService.ownsPass(thief, "FastThief") then
		humanoid.WalkSpeed = Services.EconomyService.getWalkSpeed(thief) * Config.Theft.CarrySpeedMultiplier
	end
	Net.fire("Notify", thief, "toast_tape_carry", nil, "info")
	Net.fire("Alert", victim, "taken", { name = thief.DisplayName, slot = clone.slot, plot = victimIndex })
	Services.EconomyService.markDirty(thief)
	return true, nil
end

-- A fita volta voando para a estante do dono.
local function returnTape(thief: Player, notifyThiefKey: string?)
	local carry = carrying[thief]
	if not carry then
		return
	end
	carrying[thief] = nil
	local clone = carry.clone
	local tape = tapes[clone.id]
	if tape then
		local from = tape.model:GetPivot().Position
		for _, d in tape.model:GetDescendants() do
			if d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		setTapeAnchored(tape.model, true)
		local target = shelfCFrame(clone.owner, clone.slot)
		if target then
			tape.model:PivotTo(target)
			Net.fireAll("Fx", "tapeReturn", { from = from, to = target.Position, color = clone.tapeColor })
		end
		tape.prompt.Enabled = not clone.golden
	end
	Services.CloneService.setTransit(clone, false)
	Services.EconomyService.applyMovement(thief)
	Services.EconomyService.markDirty(thief)
	if notifyThiefKey and thief.Parent then
		Net.fire("Notify", thief, notifyThiefKey, nil, "warn")
	end
	if clone.owner.Parent then
		Net.fire("Notify", clone.owner, "toast_tape_returned", nil, "good")
	end
end

function TheftService.drop(thief: Player, reasonKey: string?)
	returnTape(thief, reasonKey)
end

-- Base trancada/laser empurrou o ladrão: ele continua carregando (já saiu com a fita).
function TheftService.onPushedOut(_player: Player) end

local function deliver(thief: Player, carry: Carry)
	local clone = carry.clone
	local victim = carry.victim
	local slot = Services.CloneService.freeSlot(thief, Services.EconomyService.getSlots(thief))
	if not slot then
		returnTape(thief, "reason_shelf_full")
		return
	end
	carrying[thief] = nil
	-- guarda a fita para o produto RecoverTape da vítima
	local victimProfile = Services.DataService.get(victim)
	if victimProfile then
		local saved = Services.CloneService.serialize(clone)
		saved.F = nil
		victimProfile.Data.LastStolen = saved
	end
	local stolenSlot = clone.slot
	local created = Services.CloneService.transfer(clone, thief, slot)
	Services.EconomyService.applyMovement(thief)
	if created then
		Net.fire("Notify", thief, "toast_tape_delivered", { slot = slot }, "gold")
	end
	if victim.Parent then
		Net.fire("Alert", victim, "stolen", { name = thief.DisplayName, slot = stolenSlot })
	end
	-- Salva os dois perfis na hora (lock de sessão garante que não duplica).
	task.spawn(Services.DataService.save, thief, false)
	if victim.Parent then
		task.spawn(Services.DataService.save, victim, false)
	end
	Services.EconomyService.markDirty(thief)
	Services.EconomyService.markDirty(victim)
end

-- Produto RecoverTape: recria a última fita roubada.
function TheftService.recover(player: Player): boolean
	local profile = Services.DataService.get(player)
	local saved = profile and profile.Data.LastStolen
	if not saved then
		return false
	end
	local slot = Services.CloneService.freeSlot(player, Config.MaxClonesPerPlayer)
	if not slot then
		return false
	end
	local created = Services.CloneService.createFromSaved(player, slot, saved)
	if created then
		profile.Data.LastStolen = nil
		Net.fire("Notify", player, "toast_recovered", nil, "gold")
		Services.EconomyService.markDirty(player)
		return true
	end
	return false
end

-- =========================================================================
-- Tapa
-- =========================================================================
local function slap(player: Player)
	if os.clock() - (lastSlap[player] or -math.huge) < Config.Slap.Cooldown then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	lastSlap[player] = os.clock()
	local look = root.CFrame.LookVector
	local best: Player? = nil
	local bestDistance = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = rootOf(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				if distance <= Config.Slap.Range and distance < bestDistance then
					local flat = Vector3.new(offset.X, 0, offset.Z)
					if flat.Magnitude < 1 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > 0.2 then
						best, bestDistance = other, distance
					end
				end
			end
		end
	end
	Net.fireAll("Fx", "slap", { userId = player.UserId, hit = best ~= nil })
	if best then
		local direction = Vector3.new(look.X, 0, look.Z).Unit
		Net.fire("Slapped", best, direction * Config.Slap.Knockback + Vector3.new(0, 30, 0), Config.Slap.StunSeconds)
		Net.fire("Notify", best, "toast_slapped", { name = player.DisplayName }, "warn")
		if carrying[best] then
			returnTape(best, "toast_tape_dropped")
		end
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function TheftService.init(services)
	Services = services
	tapesFolder = Instance.new("Folder")
	tapesFolder.Name = "Tapes"
	tapesFolder.Parent = workspace
end

function TheftService.start()
	Net.on("Slap", function(player)
		slap(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for thief, carry in table.clone(carrying) do
				local root = rootOf(thief)
				if not root or not thief.Parent then
					returnTape(thief, nil)
				elseif os.clock() - carry.startedAt > Config.Theft.MaxCarrySeconds then
					returnTape(thief, "toast_tape_dropped")
				else
					local shelf = Services.PlotService.shelfPosition(thief)
					if shelf and (root.Position - shelf).Magnitude <= Config.Theft.DeliverRadius then
						deliver(thief, carry)
					end
				end
			end
		end
	end)
end

function TheftService.onPlayerRemoving(player: Player)
	returnTape(player, nil)
	lastSlap[player] = nil
	lastTapeSteal[player] = nil
end

return TheftService
