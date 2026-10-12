--[[
	TrapService.luau
	Cascas de banana. O jogador coloca uma à frente de onde está olhando. A banana dura
	Config.BananaLifetime (60 s) ou até derrubar 1 clone. Não afeta os clones do próprio
	dono nem clones de quem tem Escudo ativo. Clone derrubado para de gerar até o dono
	regravar (de graça) ou comprar "Consertar todos".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Path = require(Shared.Path)

local Prefabs = require(script.Parent.Parent.Build.Prefabs)

local TrapService = {}

type Banana = {
	owner: Player,
	ownerId: number,
	ownerName: string,
	x: number,
	y: number, -- altura do HumanoidRootPart de quem pisa (chão + ~3)
	z: number,
	position: Vector3,
	expiresAt: number,
	model: Model,
}

local Services
local bananas: { Banana } = {}
local lastPlace: { [Player]: number } = {}
local folder: Folder
local rayParams: RaycastParams

local HIT_HEIGHT = 2.7 -- o caminho do clone é o do HumanoidRootPart, ~3 studs acima do chão

local function removeAt(index: number)
	local banana = table.remove(bananas, index)
	if banana then
		banana.model:Destroy()
	end
end

local function countOwned(player: Player): number
	local n = 0
	for _, banana in bananas do
		if banana.owner == player then
			n += 1
		end
	end
	return n
end

function TrapService.place(player: Player): (boolean, string?)
	local profile = Services.DataService.get(player)
	if not profile then
		return false, "not_loaded"
	end
	if profile.Data.Bananas <= 0 then
		return false, "no_bananas"
	end
	if os.clock() - (lastPlace[player] or 0) < Config.BananaCooldown then
		return false, "banana_cooldown"
	end
	if countOwned(player) >= Config.MaxActiveBananasPerPlayer then
		return false, "banana_max"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return false, "dead"
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local target = root.Position + flat * Config.BananaPlaceDistance
	local hit = workspace:Raycast(target + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rayParams)
	if not hit then
		return false, "no_ground"
	end

	if not Services.EconomyService.useBanana(player) then
		return false, "no_bananas"
	end
	lastPlace[player] = os.clock()

	local position = hit.Position + Vector3.new(0, 0.3, 0)
	local yaw = math.atan2(-flat.X, -flat.Z)
	local model = Prefabs.banana(position, yaw)
	model:SetAttribute("Owner", player.UserId)
	model.Parent = folder

	table.insert(bananas, {
		owner = player,
		ownerId = player.UserId,
		ownerName = player.DisplayName,
		x = position.X,
		y = position.Y + HIT_HEIGHT,
		z = position.Z,
		position = position,
		expiresAt = os.clock() + Config.BananaLifetime,
		model = model,
	})
	Net.fireAll("BananaFx", position, "place")
	return true, nil
end

-- Chamado pelo CloneService para cada clone ativo. Retorna true se o clone caiu.
function TrapService.checkClone(clone, ax: number, ay: number, az: number, bx: number, by: number, bz: number): boolean
	if #bananas == 0 then
		return false
	end
	local radius = Config.BananaRadius
	local radiusSq = radius * radius
	local minX, maxX = math.min(ax, bx) - radius, math.max(ax, bx) + radius
	local minZ, maxZ = math.min(az, bz) - radius, math.max(az, bz) + radius
	for index, banana in bananas do
		if banana.x < minX or banana.x > maxX or banana.z < minZ or banana.z > maxZ then
			continue
		end
		if banana.ownerId == clone.ownerId and not Config.DebugBananasHitOwnClones then
			continue
		end
		if Path.segmentDistanceSq(ax, ay, az, bx, by, bz, banana.x, banana.y, banana.z) > radiusSq then
			continue
		end
		if Services.EconomyService.hasShield(clone.owner) then
			continue -- escudo: a banana continua lá para outro clone
		end

		removeAt(index)
		Services.CloneService.setFallen(clone, true)
		Net.fireAll("BananaFx", banana.position, "hit")
		if not clone.debug then
			Net.fire(
				"Notify",
				clone.owner,
				"toast_clone_fallen",
				{ name = banana.ownerName, slot = clone.slot },
				"warn"
			)
		end
		if banana.owner.Parent and banana.owner ~= clone.owner then
			Net.fire("Notify", banana.owner, "toast_banana_hit", { name = clone.ownerName }, "good")
		end
		return true
	end
	return false
end

function TrapService.tick(_now: number)
	local clock = os.clock()
	for index = #bananas, 1, -1 do
		if clock >= bananas[index].expiresAt then
			removeAt(index)
		end
	end
end

function TrapService.init(services)
	Services = services
	folder = Instance.new("Folder")
	folder.Name = "Bananas"
	folder.Parent = workspace
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { services.Map.root }
end

function TrapService.start()
	Net.handle("PlaceBanana", function(player)
		return TrapService.place(player)
	end)
end

function TrapService.onPlayerRemoving(player: Player)
	lastPlace[player] = nil
	for index = #bananas, 1, -1 do
		if bananas[index].owner == player then
			removeAt(index)
		end
	end
end

-- Usado pelo debug para contar bananas no mapa.
function TrapService.count(): number
	return #bananas
end

return TrapService
