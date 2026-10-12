--[[
	CharacterService.luau
	- Personagens R6 por código: Players.CharacterAutoLoads = false e cada spawn usa
	  Players:CreateHumanoidModelFromDescription(desc, R6). Funciona sem mexer nas
	  configurações de avatar do jogo (mas recomendamos também deixar R6 em Game Settings).
	- O jogador nasce na PRÓPRIA base (PlotService.getSpawnCFrame).
	- Sala VIP: o servidor tira da sala quem não tem o passe.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CharacterService = {}

local Services
local map
local descriptions: { [number]: HumanoidDescription } = {}
local spawnVersion: { [Player]: number } = {}
local lastVipWarning: { [Player]: number } = {}

function CharacterService.getColor(player: Player): Color3
	local color = player:GetAttribute("BaseColor")
	return if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
end

-- =========================================================================
-- Avatar
-- =========================================================================
local function noobDescription(): HumanoidDescription
	-- Avatar clássico ("noob") para quem não tem descrição (ex.: jogadores de teste no Studio).
	local desc = Instance.new("HumanoidDescription")
	local yellow = BrickColor.new("Bright yellow").Color
	desc.HeadColor = yellow
	desc.LeftArmColor = yellow
	desc.RightArmColor = yellow
	desc.TorsoColor = BrickColor.new("Bright blue").Color
	desc.LeftLegColor = BrickColor.new("Br. yellowish green").Color
	desc.RightLegColor = BrickColor.new("Br. yellowish green").Color
	return desc
end

-- HumanoidDescription do jogador (com cache). Pode yieldar na primeira chamada.
function CharacterService.getDescription(player: Player): HumanoidDescription
	local cached = descriptions[player.UserId]
	if cached then
		return cached
	end
	local desc: HumanoidDescription? = nil
	if player.UserId > 0 then
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok and result then
			desc = result
		end
	end
	local final = desc or noobDescription()
	descriptions[player.UserId] = final
	return final
end

function CharacterService.spawn(player: Player)
	if not player.Parent then
		return
	end
	local version = (spawnVersion[player] or 0) + 1
	spawnVersion[player] = version

	local desc = CharacterService.getDescription(player)
	if not player.Parent or spawnVersion[player] ~= version then
		return
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not ok or not model then
		warn("[CharacterService] falha ao criar R6 para " .. player.Name .. ": " .. tostring(model))
		if player.Parent then
			player:LoadCharacter()
		end
		return
	end
	-- CreateHumanoidModelFromDescription pode yieldar: o jogador pode ter saído ou respawnado.
	if not player.Parent or spawnVersion[player] ~= version then
		model:Destroy()
		return
	end

	model.Name = player.Name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.JumpPower
		humanoid.WalkSpeed = Services.EconomyService.getWalkSpeed(player)
		humanoid.DisplayName = player.DisplayName
	end

	local old = player.Character
	local spawnCFrame = Services.PlotService.getSpawnCFrame(player)
	pcall(player.RequestStreamAroundAsync, player, spawnCFrame.Position, 2)
	model:PivotTo(spawnCFrame)
	player.Character = model
	model.Parent = workspace
	if old and old ~= model then
		old:Destroy()
	end

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(root.SetNetworkOwner, root, player)
	end

	if humanoid then
		humanoid.Died:Once(function()
			task.wait(Players.RespawnTime)
			if player.Parent and spawnVersion[player] == version then
				CharacterService.spawn(player)
			end
		end)
	end
end

-- =========================================================================
-- Sala VIP
-- =========================================================================
local function isInsideVip(position: Vector3): boolean
	local zone = map.vipZone
	local rel = zone.cframe:PointToObjectSpace(position)
	return math.abs(rel.X) <= zone.size.X / 2
		and math.abs(rel.Y) <= zone.size.Y / 2
		and math.abs(rel.Z) <= zone.size.Z / 2
end

local function enforceVip()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and isInsideVip(root.Position) and not Services.MonetizationService.ownsPass(player, "VIP") then
			character:PivotTo(map.cityTeleport)
			if os.clock() - (lastVipWarning[player] or 0) > 3 then
				lastVipWarning[player] = os.clock()
				Net.fire("Notify", player, "toast_vip_only", nil, "warn")
			end
		end
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function CharacterService.init(services)
	Services = services
	map = services.Map
	Players.CharacterAutoLoads = false
	Players.RespawnTime = Config.RespawnTime
end

function CharacterService.onPlayerAdded(player: Player)
	task.spawn(CharacterService.spawn, player)
end

function CharacterService.onPlayerRemoving(player: Player)
	spawnVersion[player] = nil
	lastVipWarning[player] = nil
	descriptions[player.UserId] = nil
end

function CharacterService.start()
	task.spawn(function()
		while true do
			task.wait(0.5)
			enforceVip()
		end
	end)
end

return CharacterService
