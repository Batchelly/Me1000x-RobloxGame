--[[
	MapBuilder.luau
	Orquestra a construção do mundo da v2. MapBuilder.build(seed) é determinístico: a mesma
	semente gera o mesmo mapa (mapas semanais: troque Config.MapSeed).

		LightingSetup  iluminação (Future, Atmosphere, ColorCorrection, SunRays)
		DecorBuilder   chão de grama, caminhos de tijolo, montanhas e linhas de árvores
		PlotBuilder    8 terrenos de tycoon em anel nas bordas
		CityBuilder    Cidade de Blocos no centro (praça, parque, obras, castelo, bairro)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)

local CityBuilder = require(script.Parent.CityBuilder)
local DecorBuilder = require(script.Parent.DecorBuilder)
local LightingSetup = require(script.Parent.LightingSetup)
local PlotBuilder = require(script.Parent.PlotBuilder)

local MapBuilder = {}

export type SpawnPoint = {
	kind: string, -- "Coin" | "Gem" | "Chest"
	position: Vector3,
	vip: boolean,
}

export type MapInfo = {
	root: Folder,
	seed: number,
	spawns: { SpawnPoint },
	plots: { PlotBuilder.Plot },
	vipZone: { cframe: CFrame, size: Vector3 },
	vipDoor: BasePart,
	boardLabels: { Frame },
	cityTeleport: CFrame,
	fallbackSpawn: CFrame,
	partCount: number,
}

function MapBuilder.setupLighting()
	LightingSetup.apply()
end

function MapBuilder.build(seed: number?): MapInfo
	local mapSeed = seed or Config.MapSeed
	local rng = Random.new(mapSeed)

	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	-- O Baseplate padrão do place (cinza, topo em y = 0) briga com a grama no mesmo plano (z-fighting).
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = workspace

	local spawns: { SpawnPoint } = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { root }

	local ctx = {
		rng = rng,
		root = root,
		spawns = spawns,
		info = { boardLabels = {} } :: { [string]: any },
	}

	function ctx.folder(name: string): Folder
		local existing = root:FindFirstChild(name)
		if existing then
			return existing :: Folder
		end
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end

	-- Ponto de spawn de coletável. Ignora pontos colados em outro (< 2,5 studs).
	function ctx.addSpawn(kind: string, position: Vector3, vip: boolean?)
		for _, other in spawns do
			if (other.position - position).Magnitude < 2.5 then
				return
			end
		end
		table.insert(spawns, { kind = kind, position = position, vip = vip == true })
	end

	-- Ponto de spawn na superfície mais alta em (x, z).
	function ctx.addSpawnOnSurface(kind: string, x: number, z: number, vip: boolean?)
		local result = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), rayParams)
		local y = if result then result.Position.Y else 0
		ctx.addSpawn(kind, Vector3.new(x, y + 2.5, z), vip)
	end

	DecorBuilder.ground(ctx)

	local plotsFolder = ctx.folder("Plots")
	local plots = {}
	for index = 1, MapLayout.plotCount() do
		plots[index] = PlotBuilder.create(plotsFolder, index)
	end

	DecorBuilder.paths(ctx)
	CityBuilder.build(ctx)
	DecorBuilder.borders(ctx)

	local partCount = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount > Config.MaxPartsBudget then
		warn(string.format("[MapBuilder] %d Parts no mapa (orçamento: %d)", partCount, Config.MaxPartsBudget))
	end

	return {
		root = root,
		seed = mapSeed,
		spawns = spawns,
		plots = plots,
		vipZone = ctx.info.vipZone,
		vipDoor = ctx.info.vipDoor,
		boardLabels = ctx.info.boardLabels,
		cityTeleport = ctx.info.cityTeleport,
		fallbackSpawn = ctx.info.cityTeleport,
		partCount = partCount,
	}
end

return MapBuilder
