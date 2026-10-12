--[[
	EnvironmentController.luau
	Vida no mundo (tudo local, sem tráfego de rede):
	- Ciclo dia/noite de Config.DayNight.CycleSeconds (12 min) calculado do relógio do servidor
	  (todos os clientes veem a mesma hora). À noite os postes acendem.
	- Nuvens de blocos brancos flutuando devagar.
	- Pássaros simples (corpo + 2 asas) voando em círculos.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local DayNight = require(Shared.DayNight)

local EnvironmentController = {}

local folder: Folder
local lampsOn: boolean? = nil

type Cloud = { parts: { BasePart }, offsets: { CFrame }, position: Vector3, speed: number }
type Bird = {
	body: BasePart,
	wings: { BasePart },
	center: Vector3,
	radius: number,
	speed: number,
	phase: number,
	height: number,
}

local clouds: { Cloud } = {}
local birds: { Bird } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local WRAP = Config.Map.GroundHalf + 120

local function part(size: Vector3, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function makeClouds(rng: Random)
	local white = Color3.fromRGB(248, 248, 252)
	for _ = 1, 14 do
		local cloud: Cloud = {
			parts = {},
			offsets = {},
			position = Vector3.new(rng:NextNumber(-WRAP, WRAP), rng:NextNumber(130, 175), rng:NextNumber(-WRAP, WRAP)),
			speed = rng:NextNumber(2, 4),
		}
		local pieces = rng:NextInteger(3, 5)
		for i = 1, pieces do
			local size = Vector3.new(rng:NextNumber(18, 34), rng:NextNumber(6, 10), rng:NextNumber(14, 24))
			local offset = CFrame.new((i - pieces / 2) * 12, rng:NextNumber(-2, 4), rng:NextNumber(-6, 6))
			table.insert(cloud.parts, part(size, white, 0.08))
			table.insert(cloud.offsets, offset)
		end
		table.insert(clouds, cloud)
	end
end

local function makeBirds(rng: Random)
	for _ = 1, 7 do
		local color = if rng:NextNumber() < 0.5 then Color3.fromRGB(40, 40, 45) else Color3.fromRGB(240, 240, 240)
		local bird: Bird = {
			body = part(Vector3.new(0.8, 0.6, 1.8), color),
			wings = { part(Vector3.new(2.2, 0.15, 1), color), part(Vector3.new(2.2, 0.15, 1), color) },
			center = Vector3.new(rng:NextNumber(-150, 150), 0, rng:NextNumber(-150, 150)),
			radius = rng:NextNumber(30, 80),
			speed = rng:NextNumber(0.25, 0.45) * (if rng:NextNumber() < 0.5 then 1 else -1),
			phase = rng:NextNumber(0, math.pi * 2),
			height = rng:NextNumber(55, 95),
		}
		table.insert(birds, bird)
	end
end

local function setLamps(on: boolean)
	if lampsOn == on then
		return
	end
	lampsOn = on
	for _, bulb in CollectionService:GetTagged("Lamp") do
		if bulb:IsA("BasePart") then
			bulb.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local light = bulb:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = on
			end
		end
	end
end

local function step(dt: number)
	-- Dia/noite
	local clock = DayNight.clockTime(Clock.now(), Config.DayNight.CycleSeconds, Config.DayNight.DayFraction)
	Lighting.ClockTime = clock
	local night = DayNight.nightAmount(clock)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135):Lerp(Color3.fromRGB(70, 75, 110), night)
	setLamps(DayNight.isNight(clock))

	-- Nuvens e pássaros (um BulkMoveTo só)
	local n = 0
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, cloud in clouds do
		local x = cloud.position.X + cloud.speed * dt
		if x > WRAP then
			x = -WRAP
		end
		cloud.position = Vector3.new(x, cloud.position.Y, cloud.position.Z)
		local base = CFrame.new(cloud.position)
		for i, p in cloud.parts do
			n += 1
			moveParts[n] = p
			moveCFrames[n] = base * cloud.offsets[i]
		end
	end
	local t = os.clock()
	for _, bird in birds do
		local angle = bird.phase + t * bird.speed
		local pos = bird.center
			+ Vector3.new(
				math.cos(angle) * bird.radius,
				bird.height + math.sin(t * 0.7 + bird.phase) * 4,
				math.sin(angle) * bird.radius
			)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(bird.speed)
		local body = CFrame.lookAt(pos, pos + tangent)
		local flap = math.sin(t * 9 + bird.phase) * 0.6
		n += 1
		moveParts[n] = bird.body
		moveCFrames[n] = body
		n += 1
		moveParts[n] = bird.wings[1]
		moveCFrames[n] = body * CFrame.new(-1.2, 0, 0) * CFrame.Angles(0, 0, flap)
		n += 1
		moveParts[n] = bird.wings[2]
		moveCFrames[n] = body * CFrame.new(1.2, 0, 0) * CFrame.Angles(0, 0, -flap)
	end
	if n > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnvironmentController.init(_controllers)
	folder = Instance.new("Folder")
	folder.Name = "ClientEnvironment"
	folder.Parent = workspace
	local rng = Random.new(Config.MapSeed)
	makeClouds(rng)
	makeBirds(rng)
end

function EnvironmentController.start()
	RunService.Heartbeat:Connect(step)
	-- postes que chegarem depois (StreamingEnabled) entram no estado atual
	CollectionService:GetInstanceAddedSignal("Lamp"):Connect(function()
		local current = lampsOn
		lampsOn = nil
		setLamps(current == true)
	end)
end

return EnvironmentController
