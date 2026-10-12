--[[
	CityBuilder.luau
	"Cidade de Blocos", o mapa compartilhado no centro (-115..115), onde todos disputam
	moedas. Ruas cinza-escuro com faixa amarela, calçadas claras, praça de tijolo e 4 bairros
	com rotas de valor diferente:

		Praça Central (centro)   fonte, bancos, postes, canteiros, coreto, ranking. FÁCIL.
		Parque (noroeste)        lago com ponte, árvores, playground, pedras de pular. FÁCIL/MÉDIO.
		Canteiro de Obras (NE)   guindaste, andaimes, vigas, esteiras. DIFÍCIL, mais gemas.
		Castelo (sudoeste)       muralhas, torre com o BAÚ, ponte levadiça, bandeiras, sala VIP.
		Bairro (sudeste)         prédios com parkour de telhado, carros, hidrantes. MÉDIO.

	Convenção: -Z = "norte". O chão do mundo fica em y = 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Prefabs = require(script.Parent.Prefabs)

local CityBuilder = {}

local CITY = Config.Map.CityHalf
local RING_W = Config.Map.RingRoadWidth
local COIN = 2.5
local ROAD = "Dark stone grey"
local SIDEWALK = "Light stone grey"
local LEGO = { "Bright red", "Bright yellow", "Bright blue", "Bright green" }

local function lego(i: number): string
	return LEGO[(i - 1) % #LEGO + 1]
end

-- =========================================================================
-- Ruas
-- =========================================================================
local function buildRoads(ctx)
	local folder = ctx.folder("Roads")
	local block = Prefabs.block
	local ringCenter = CITY + RING_W / 2
	local ringLength = (CITY + RING_W) * 2

	-- Rua em anel em volta da cidade
	for _, sign in { -1, 1 } do
		block(folder, Vector3.new(ringLength, 0.2, RING_W), CFrame.new(0, 0.1, sign * ringCenter), ROAD, {
			name = "RingRoad",
			smooth = true,
		})
		block(folder, Vector3.new(RING_W, 0.2, ringLength), CFrame.new(sign * ringCenter, 0.1, 0), ROAD, {
			name = "RingRoad",
			smooth = true,
		})
		-- calçada interna
		block(folder, Vector3.new(CITY * 2, 0.3, 3), CFrame.new(0, 0.15, sign * (CITY - 1.5)), SIDEWALK, {
			name = "Sidewalk",
		})
		block(folder, Vector3.new(3, 0.3, CITY * 2), CFrame.new(sign * (CITY - 1.5), 0.15, 0), SIDEWALK, {
			name = "Sidewalk",
		})
	end
	-- Faixa amarela tracejada no anel
	local dash = Vector3.new(6, 0.05, 0.6)
	for t = -CITY - 4, CITY + 4, 14 do
		for _, sign in { -1, 1 } do
			block(folder, dash, CFrame.new(t, 0.225, sign * ringCenter), "Bright yellow", {
				name = "Stripe",
				smooth = true,
				noQuery = true,
			})
			block(folder, Vector3.new(0.6, 0.05, 6), CFrame.new(sign * ringCenter, 0.225, t), "Bright yellow", {
				name = "Stripe",
				smooth = true,
				noQuery = true,
			})
		end
	end

	-- Avenidas em cruz (da praça até o anel)
	local armLength = CITY - 32
	local armCenter = 32 + armLength / 2
	for _, sign in { -1, 1 } do
		block(folder, Vector3.new(12, 0.2, armLength), CFrame.new(0, 0.1, sign * armCenter), ROAD, {
			name = "Avenue",
			smooth = true,
		})
		block(folder, Vector3.new(armLength, 0.2, 12), CFrame.new(sign * armCenter, 0.1, 0), ROAD, {
			name = "Avenue",
			smooth = true,
		})
		for _, side in { -1, 1 } do
			block(folder, Vector3.new(3, 0.3, armLength), CFrame.new(side * 7.5, 0.15, sign * armCenter), SIDEWALK, {
				name = "Sidewalk",
			})
			block(folder, Vector3.new(armLength, 0.3, 3), CFrame.new(sign * armCenter, 0.15, side * 7.5), SIDEWALK, {
				name = "Sidewalk",
			})
		end
		for d = 38, CITY - 6, 10 do
			block(folder, Vector3.new(0.6, 0.05, 5), CFrame.new(0, 0.225, sign * d), "Bright yellow", {
				name = "Stripe",
				smooth = true,
				noQuery = true,
			})
			block(folder, Vector3.new(5, 0.05, 0.6), CFrame.new(sign * d, 0.225, 0), "Bright yellow", {
				name = "Stripe",
				smooth = true,
				noQuery = true,
			})
		end
		-- moedas nas avenidas (rota fácil)
		for d = 40, CITY - 10, 10 do
			ctx.addSpawn("Coin", Vector3.new(0, 0.2 + COIN, sign * d))
			ctx.addSpawn("Coin", Vector3.new(sign * d, 0.2 + COIN, 0))
		end
	end

	-- Postes nas avenidas e no anel
	local lamps = ctx.folder("Lamps")
	for _, sign in { -1, 1 } do
		for i, d in { 50, 75, 100 } do
			local side = if i % 2 == 0 then 1 else -1
			Prefabs.lamp(lamps, Vector3.new(side * 8, 0.3, sign * d))
			Prefabs.lamp(lamps, Vector3.new(sign * d, 0.3, side * 8))
		end
		for _, t in { -60, 60 } do
			Prefabs.lamp(lamps, Vector3.new(t, 0.3, sign * (CITY - 1.5)))
			Prefabs.lamp(lamps, Vector3.new(sign * (CITY - 1.5), 0.3, t))
		end
	end
end

-- =========================================================================
-- Praça Central
-- =========================================================================
local function buildPlaza(ctx)
	local folder = ctx.folder("Plaza")
	local block = Prefabs.block
	block(folder, Vector3.new(64, 0.3, 64), CFrame.new(0, 0.15, 0), "Brick yellow", {
		name = "PlazaFloor",
		material = Enum.Material.Brick,
		smooth = true,
	})

	-- Fonte
	local fountain = Prefabs.model(folder, "Fountain")
	for _, sign in { -1, 1 } do
		block(fountain, Vector3.new(14, 1.6, 1), CFrame.new(0, 1.1, sign * 6.5), "Medium stone grey")
		block(fountain, Vector3.new(1, 1.6, 12), CFrame.new(sign * 6.5, 1.1, 0), "Medium stone grey")
	end
	local water = block(fountain, Vector3.new(12, 0.6, 12), CFrame.new(0, 1.2, 0), "Bright blue", {
		name = "Water",
		smooth = true,
		material = Enum.Material.Glass,
		transparency = 0.35,
		canCollide = false,
	})
	water:AddTag("WaterSound")
	block(
		fountain,
		Vector3.new(5, 2, 2),
		CFrame.new(0, 2.8, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"Medium stone grey",
		{ shape = Enum.PartType.Cylinder, name = "Column" }
	)
	block(
		fountain,
		Vector3.new(0.6, 6, 6),
		CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		"Medium stone grey",
		{ shape = Enum.PartType.Cylinder, name = "Bowl" }
	)
	local spout = block(fountain, Vector3.new(1, 1, 1), CFrame.new(0, 6.6, 0), "Bright blue", {
		name = "Spout",
		material = Enum.Material.Glass,
		transparency = 0.4,
		canCollide = false,
		smooth = true,
	})
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	spray.LightEmission = 0.3
	spray.Size = NumberSequence.new(0.35, 0.1)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Rate = 35
	spray.Speed = NumberRange.new(9, 13)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = spout

	-- Bancos virados para a fonte
	for i = 0, 5 do
		local angle = math.rad(30 + i * 60)
		local pos = Vector3.new(math.cos(angle) * 15, 0.3, math.sin(angle) * 15)
		Prefabs.bench(folder, CFrame.lookAt(pos, Vector3.new(0, 0.3, 0)))
	end
	-- Postes nos cantos e canteiros
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		Prefabs.lamp(folder, Vector3.new(corner[1] * 28, 0.3, corner[2] * 28))
		Prefabs.flowerBed(folder, CFrame.new(corner[1] * 18, 0.3, corner[2] * 28), ctx.rng)
	end

	-- Coreto (sudeste da praça)
	local bandstand = Prefabs.model(folder, "Bandstand")
	block(
		bandstand,
		Vector3.new(1, 12, 12),
		CFrame.new(22, 0.8, 22) * CFrame.Angles(0, 0, math.pi / 2),
		"Institutional white",
		{ shape = Enum.PartType.Cylinder, name = "Stage" }
	)
	for _, offset in { Vector2.new(4, 4), Vector2.new(-4, 4), Vector2.new(4, -4), Vector2.new(-4, -4) } do
		block(bandstand, Vector3.new(0.6, 6, 0.6), CFrame.new(22 + offset.X, 4.3, 22 + offset.Y), "Institutional white")
	end
	block(
		bandstand,
		Vector3.new(0.8, 13, 13),
		CFrame.new(22, 7.7, 22) * CFrame.Angles(0, 0, math.pi / 2),
		"Bright red",
		{ shape = Enum.PartType.Cylinder, name = "Roof" }
	)
	block(bandstand, Vector3.new(4, 1.4, 4), CFrame.new(22, 8.8, 22), "Bright red")
	ctx.addSpawn("Coin", Vector3.new(22, 1.3 + COIN, 22))

	-- Placa de ranking (noroeste da praça), duas faces
	local boardCf = CFrame.lookAt(Vector3.new(-22, 10, -22), Vector3.new(0, 10, 0))
	for _, x in { -9, 9 } do
		block(folder, Vector3.new(1, 3.6, 1), boardCf * CFrame.new(x, -6.2, 0), "Black", { name = "BoardLeg" })
	end
	local board = block(folder, Vector3.new(24, 14, 1), boardCf, "Black", { name = "RankingBoard", smooth = true })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		local frame = Instance.new("Frame")
		frame.Name = "Content"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(21, 26, 43)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		gui.Parent = board
		table.insert(ctx.info.boardLabels, frame)
	end

	-- Placas de direção nas saídas da praça
	Prefabs.arrowSign(folder, CFrame.new(9, 0.3, -36), "🌳 Parque · 🏗️ Obras")
	Prefabs.arrowSign(folder, CFrame.new(-9, 0.3, 36) * CFrame.Angles(0, math.pi, 0), "🏰 Castelo · 🏘️ Bairro")
	Prefabs.arrowSign(
		folder,
		CFrame.new(36, 0.3, 9) * CFrame.Angles(0, -math.pi / 2, 0),
		"🏗️ Obras · 🏘️ Bairro"
	)
	Prefabs.arrowSign(
		folder,
		CFrame.new(-36, 0.3, -9) * CFrame.Angles(0, math.pi / 2, 0),
		"🌳 Parque · 🏰 Castelo"
	)

	-- Anel de moedas em volta da fonte
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		ctx.addSpawn("Coin", Vector3.new(math.cos(angle) * 10, 0.3 + COIN, math.sin(angle) * 10))
	end

	ctx.info.cityTeleport = CFrame.lookAt(Vector3.new(0, 3.6, 22), Vector3.new(0, 3.6, 0))
end

-- =========================================================================
-- Parque (noroeste: x < 0, z < 0)
-- =========================================================================
local function buildPark(ctx)
	local folder = ctx.folder("Park")
	local block = Prefabs.block
	local rng = ctx.rng

	-- Lago com praia
	block(
		folder,
		Vector3.new(38, 0.2, 30),
		CFrame.new(-72, 0.1, -74),
		"Brick yellow",
		{ name = "Beach", smooth = true }
	)
	local lake = block(folder, Vector3.new(34, 0.4, 26), CFrame.new(-72, 0.2, -74), "Bright blue", {
		name = "Lake",
		smooth = true,
		material = Enum.Material.Glass,
		transparency = 0.3,
		canCollide = false,
	})
	lake:AddTag("WaterSound")

	-- Ponte sobre o lago (rampas + tabuleiro)
	local bridge = Prefabs.model(folder, "Bridge")
	Prefabs.wedge(
		bridge,
		Vector3.new(6, 3, 8),
		CFrame.new(-54, 1.5, -74) * CFrame.Angles(0, -math.pi / 2, 0),
		"Reddish brown"
	)
	block(bridge, Vector3.new(28, 1, 6), CFrame.new(-72, 2.5, -74), "Reddish brown", { name = "Deck" })
	Prefabs.wedge(
		bridge,
		Vector3.new(6, 3, 8),
		CFrame.new(-90, 1.5, -74) * CFrame.Angles(0, math.pi / 2, 0),
		"Reddish brown"
	)
	for _, side in { -1, 1 } do
		block(bridge, Vector3.new(28, 0.4, 0.4), CFrame.new(-72, 4.6, -74 + side * 2.8), "Black", { name = "Rail" })
	end
	for _, x in { -64, -72, -80 } do
		ctx.addSpawn("Coin", Vector3.new(x, 3 + COIN, -74))
	end
	ctx.addSpawn("Gem", Vector3.new(-76, 3 + COIN, -74))

	-- Pedras de pular (da praça até o lago)
	for i = 1, 10 do
		local a = 34 + i * 3.4
		local b = 38 + i * 2.6
		local height = 1 + (i % 4) * 1.4
		block(
			folder,
			Vector3.new(height, 4, 4),
			CFrame.new(-a, height / 2, -b) * CFrame.Angles(0, 0, math.pi / 2),
			"Medium stone grey",
			{ shape = Enum.PartType.Cylinder, name = "Stone" }
		)
		ctx.addSpawn("Coin", Vector3.new(-a, height + COIN, -b))
	end

	-- Playground: areia, escorregador e balanço
	local playground = Prefabs.model(folder, "Playground")
	block(playground, Vector3.new(24, 0.3, 18), CFrame.new(-32, 0.15, -97), "Brick yellow", {
		name = "Sand",
		material = Enum.Material.Sand,
		smooth = true,
	})
	block(playground, Vector3.new(4, 1, 4), CFrame.new(-24, 5.5, -95), "Bright red", { name = "SlideTop" })
	for _, offset in { Vector2.new(-1.6, -1.6), Vector2.new(1.6, -1.6), Vector2.new(-1.6, 1.6), Vector2.new(1.6, 1.6) } do
		block(playground, Vector3.new(0.5, 5, 0.5), CFrame.new(-24 + offset.X, 2.5, -95 + offset.Y), "Bright yellow")
	end
	local ladder = Instance.new("TrussPart")
	ladder.Anchored = true
	ladder.Size = Vector3.new(2, 6, 2)
	ladder.CFrame = CFrame.new(-21, 3, -95)
	ladder.BrickColor = BrickColor.new("Bright blue")
	ladder.Parent = playground
	Prefabs.wedge(
		playground,
		Vector3.new(3, 6, 10),
		CFrame.new(-31, 3, -95) * CFrame.Angles(0, math.pi / 2, 0),
		"Bright yellow",
		{ name = "Slide", smooth = true }
	)
	for _, x in { -36, -44 } do
		block(playground, Vector3.new(0.6, 8, 0.6), CFrame.new(x, 4, -103), "Bright blue")
	end
	block(playground, Vector3.new(9, 0.6, 0.6), CFrame.new(-40, 8, -103), "Bright blue")
	for _, x in { -38.5, -41.5 } do
		block(playground, Vector3.new(1.6, 0.3, 1), CFrame.new(x, 2, -103), "Bright red", { name = "Seat" })
		block(
			playground,
			Vector3.new(0.15, 6, 0.15),
			CFrame.new(x, 5, -103),
			"Black",
			{ name = "Rope", noQuery = true }
		)
	end
	ctx.addSpawn("Coin", Vector3.new(-24, 6 + COIN, -95))
	ctx.addSpawn("Coin", Vector3.new(-30, 0.3 + COIN, -102))
	ctx.addSpawn("Coin", Vector3.new(-40, 0.3 + COIN, -97))

	-- Árvores e arbustos
	local placed = 0
	local tries = 0
	while placed < 16 and tries < 200 do
		tries += 1
		local x, z = -rng:NextNumber(14, 110), -rng:NextNumber(14, 110)
		local inLake = x > -94 and x < -50 and z > -92 and z < -56
		local inPlayground = x > -48 and x < -16 and z > -110 and z < -84
		local inTrail = x > -76 and x < -34 and z > -70 and z < -38
		local nearPlaza = x > -36 and z > -36
		if not (inLake or inPlayground or inTrail or nearPlaza) then
			local sizes = { "S", "M", "L" }
			Prefabs.tree(folder, Vector3.new(x, 0, z), sizes[rng:NextInteger(1, 3)])
			placed += 1
		end
	end
	for _ = 1, 6 do
		Prefabs.bush(folder, Vector3.new(-rng:NextNumber(40, 110), 0, -rng:NextNumber(14, 34)))
	end
	Prefabs.flowerBed(folder, CFrame.new(-100, 0, -60), rng)
	Prefabs.flowerBed(folder, CFrame.new(-50, 0, -108), rng)
end

-- =========================================================================
-- Canteiro de Obras (nordeste: x > 0, z < 0) - rota difícil, mais gemas
-- =========================================================================
local function buildConstruction(ctx)
	local folder = ctx.folder("Construction")
	local block = Prefabs.block
	local rng = ctx.rng

	block(folder, Vector3.new(100, 0.2, 72), CFrame.new(62, 0.1, -76), "Nougat", { name = "Dirt", smooth = true })
	block(folder, Vector3.new(72, 0.2, 28), CFrame.new(76, 0.1, -26), "Nougat", { name = "Dirt", smooth = true })

	-- 1) Escada de caixas
	for k = 1, 3 do
		for level = 0, k - 1 do
			Prefabs.crate(folder, Vector3.new(36 + 4 * k, 0.2 + level * 4, -46), 4)
		end
		ctx.addSpawn("Coin", Vector3.new(36 + 4 * k, 0.2 + k * 4 + COIN, -46))
	end

	-- 2) Andaime A (topo 12)
	local scaffold = Prefabs.model(folder, "Scaffold")
	block(scaffold, Vector3.new(8, 0.6, 8), CFrame.new(58, 11.9, -46), "Bright yellow", { name = "Board" })
	for _, offset in { Vector2.new(-3.7, -3.7), Vector2.new(3.7, -3.7), Vector2.new(-3.7, 3.7), Vector2.new(3.7, 3.7) } do
		block(scaffold, Vector3.new(0.5, 12, 0.5), CFrame.new(58 + offset.X, 6, -46 + offset.Y), "Medium stone grey")
	end
	ctx.addSpawn("Coin", Vector3.new(56, 12.2 + COIN, -46))
	ctx.addSpawn("Gem", Vector3.new(60, 12.2 + COIN, -46))

	-- 3) Viga do andaime até o esqueleto do prédio
	local a, b = Vector3.new(62, 12, -46), Vector3.new(75, 12, -63)
	local length = (b - a).Magnitude
	block(folder, Vector3.new(2, 1, length), CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0), "Bright red", {
		name = "Beam",
	})
	for i = 1, 4 do
		ctx.addSpawn("Coin", a:Lerp(b, i / 5) + Vector3.new(0, COIN, 0))
	end

	-- 4) Esqueleto do prédio: colunas, andares (topo 12, 22, 32) e treliças
	local skeleton = Prefabs.model(folder, "Skeleton")
	for _, x in { 75, 86, 97 } do
		for _, z in { -85, -74, -63 } do
			block(skeleton, Vector3.new(1.5, 32, 1.5), CFrame.new(x, 16, z), "Bright red", { name = "Column" })
		end
	end
	block(skeleton, Vector3.new(24, 1, 24), CFrame.new(86, 11.5, -74), "Medium stone grey", { name = "Floor1" })
	block(skeleton, Vector3.new(12, 1, 24), CFrame.new(80, 21.5, -74), "Medium stone grey", { name = "Floor2" })
	block(skeleton, Vector3.new(12, 1, 12), CFrame.new(92, 31.5, -80), "Medium stone grey", { name = "Floor3" })
	for _, spec in { { 87, 17, -70 }, { 85, 27, -80 } } do
		local truss = Instance.new("TrussPart")
		truss.Anchored = true
		truss.Size = Vector3.new(2, 10, 2)
		truss.CFrame = CFrame.new(spec[1], spec[2], spec[3])
		truss.BrickColor = BrickColor.new("Bright yellow")
		truss.Parent = skeleton
	end
	for _, p in
		{ Vector3.new(80, 12, -80), Vector3.new(92, 12, -80), Vector3.new(80, 12, -68), Vector3.new(92, 12, -68) }
	do
		ctx.addSpawn("Coin", p + Vector3.new(0, COIN, 0))
	end
	for _, p in { Vector3.new(77, 22, -84), Vector3.new(77, 22, -74), Vector3.new(77, 22, -64) } do
		ctx.addSpawn("Coin", p + Vector3.new(0, COIN, 0))
	end
	ctx.addSpawn("Gem", Vector3.new(90, 32 + COIN, -83))
	ctx.addSpawn("Gem", Vector3.new(94, 32 + COIN, -83))
	ctx.addSpawn("Gem", Vector3.new(92, 32 + COIN, -77))

	-- 5) Guindaste (decorativo, marco visual)
	local crane = Prefabs.model(folder, "Crane")
	local tower = Instance.new("TrussPart")
	tower.Anchored = true
	tower.Size = Vector3.new(3, 56, 3)
	tower.CFrame = CFrame.new(104, 28, -104)
	tower.BrickColor = BrickColor.new("Bright yellow")
	tower.Parent = crane
	block(crane, Vector3.new(52, 2, 2), CFrame.new(84, 57, -104), "Bright yellow", { name = "Jib" })
	block(crane, Vector3.new(4, 4, 4), CFrame.new(104, 60, -104), "Bright yellow", { name = "Cab" })
	block(crane, Vector3.new(6, 3, 3), CFrame.new(112, 57, -104), "Medium stone grey", { name = "Counterweight" })
	block(crane, Vector3.new(0.2, 14, 0.2), CFrame.new(66, 49, -104), "Black", { name = "Cable", noQuery = true })
	block(crane, Vector3.new(10, 1, 2), CFrame.new(66, 41.5, -104), "Bright red", { name = "Load" })

	-- 6) Esteiras, cones e caixas
	Prefabs.conveyor(folder, Vector3.new(6, 0.4, 30), CFrame.new(28, 0.4, -72), Vector3.new(0, 0, Config.ConveyorSpeed))
	Prefabs.conveyor(
		folder,
		Vector3.new(30, 0.4, 6),
		CFrame.new(60, 0.4, -100),
		Vector3.new(Config.ConveyorSpeed, 0, 0)
	)
	for i = 0, 3 do
		ctx.addSpawn("Coin", Vector3.new(28, 0.6 + COIN, -82 + i * 7))
	end
	for i = 0, 2 do
		ctx.addSpawn("Coin", Vector3.new(50 + i * 9, 0.6 + COIN, -100))
	end
	for _ = 1, 10 do
		Prefabs.cone(folder, Vector3.new(rng:NextNumber(14, 70), 0.2, -rng:NextNumber(14, 36)))
	end
	for _ = 1, 5 do
		Prefabs.crate(folder, Vector3.new(rng:NextNumber(40, 70), 0.2, -rng:NextNumber(56, 70)), rng:NextInteger(2, 3))
	end
end

-- =========================================================================
-- Castelo de Blocos (sudoeste: x < 0, z > 0)
-- =========================================================================
local function buildCastle(ctx)
	local folder = ctx.folder("Castle")
	local block = Prefabs.block
	local stone = "Medium stone grey"
	local wallH = 12

	-- Muralhas (portão no muro norte, de frente para a avenida)
	block(folder, Vector3.new(27.5, wallH, 3), CFrame.new(-91.25, wallH / 2, 41.5), stone, { name = "Wall" })
	block(folder, Vector3.new(27.5, wallH, 3), CFrame.new(-53.75, wallH / 2, 41.5), stone, { name = "Wall" })
	block(folder, Vector3.new(65, wallH, 3), CFrame.new(-72.5, wallH / 2, 103.5), stone, { name = "Wall" })
	block(folder, Vector3.new(3, wallH, 65), CFrame.new(-103.5, wallH / 2, 72.5), stone, { name = "Wall" })
	block(folder, Vector3.new(3, wallH, 65), CFrame.new(-41.5, wallH / 2, 72.5), stone, { name = "Wall" })
	block(folder, Vector3.new(12, 3, 3), CFrame.new(-72.5, wallH - 1.5, 41.5), stone, { name = "GateArch" })
	-- Ameias
	for i = 0, 3 do
		local t = -97 + i * 16
		block(folder, Vector3.new(2, 2.5, 3), CFrame.new(t, wallH + 1.25, 103.5), stone, { name = "Merlon" })
		block(folder, Vector3.new(3, 2.5, 2), CFrame.new(-103.5, wallH + 1.25, 48 + i * 16), stone, { name = "Merlon" })
	end
	-- Torres dos cantos com topo colorido + bandeiras com as cores das bases
	local corners = { { -100, 45 }, { -45, 45 }, { -100, 100 }, { -45, 100 } }
	for i, c in corners do
		block(folder, Vector3.new(10, 18, 10), CFrame.new(c[1], 9, c[2]), stone, { name = "Tower" })
		block(folder, Vector3.new(11, 2, 11), CFrame.new(c[1], 19, c[2]), lego(i), { name = "TowerCap" })
		Prefabs.flag(folder, Vector3.new(c[1], 20, c[2]), Config.BaseColors[i], 8)
	end
	for i, x in { -90, -82, -62, -54 } do
		Prefabs.flag(folder, Vector3.new(x, wallH, 41.5), Config.BaseColors[i + 4], 7)
	end
	-- Escada para o alto da muralha (lado de dentro do muro norte)
	for s = 1, 6 do
		block(folder, Vector3.new(4, 2 * s, 3), CFrame.new(-96 + s * 3, s, 44.5), stone, { name = "WallStairs" })
	end
	-- Moedas no alto das muralhas
	for i = 0, 2 do
		ctx.addSpawn("Coin", Vector3.new(-92 + i * 5, wallH + COIN, 41.5))
		ctx.addSpawn("Coin", Vector3.new(-63 + i * 5, wallH + COIN, 41.5))
	end
	for i = 0, 3 do
		ctx.addSpawn("Coin", Vector3.new(-41.5, wallH + COIN, 55 + i * 10))
		ctx.addSpawn("Coin", Vector3.new(-103.5, wallH + COIN, 55 + i * 10))
	end

	-- Fosso e ponte levadiça
	local moat = block(folder, Vector3.new(72, 0.4, 6), CFrame.new(-72.5, 0.2, 35), "Bright blue", {
		name = "Moat",
		smooth = true,
		material = Enum.Material.Glass,
		transparency = 0.3,
		canCollide = false,
	})
	moat:AddTag("WaterSound")
	block(folder, Vector3.new(10, 0.6, 8), CFrame.new(-72.5, 0.5, 35), "Reddish brown", { name = "Drawbridge" })
	for _, x in { -77, -68 } do
		block(
			folder,
			Vector3.new(0.3, 0.3, 12),
			CFrame.new(x, 6, 37) * CFrame.Angles(math.rad(-50), 0, 0),
			"Black",
			{ name = "Chain", noQuery = true }
		)
	end

	-- Torre principal (espiral) com o Baú no topo
	local keep = Prefabs.model(folder, "Keep")
	local center = Vector3.new(-66, 0, 66)
	local stepRise = 3.4
	local stepCount = 24
	local towerTop = stepRise * (stepCount + 1)
	block(
		keep,
		Vector3.new(8, towerTop - 1, 8),
		CFrame.new(center + Vector3.new(0, (towerTop - 1) / 2, 0)),
		stone,
		{ name = "Column" }
	)
	for i = 0, stepCount - 1 do
		local angle = i * math.rad(30)
		local top = stepRise * (i + 1)
		local offset = Vector3.new(math.cos(angle) * 9, top - 0.6, math.sin(angle) * 9)
		block(
			keep,
			Vector3.new(10, 1.2, 6),
			CFrame.new(center + offset) * CFrame.Angles(0, -angle, 0),
			lego(i + 1),
			{ name = "Step" }
		)
		local coinPos = center + Vector3.new(math.cos(angle) * 10, top + COIN, math.sin(angle) * 10)
		if i == 11 or i == 21 then
			ctx.addSpawn("Gem", coinPos)
		elseif i % 2 == 1 then
			ctx.addSpawn("Coin", coinPos)
		end
	end
	block(keep, Vector3.new(12, 1, 12), CFrame.new(center + Vector3.new(0, towerTop - 0.5, 0)), "Bright yellow", {
		name = "Top",
	})
	ctx.addSpawn("Chest", center + Vector3.new(0, towerTop + 1.6, 0))
	Prefabs.flag(keep, center + Vector3.new(4.5, towerTop, 4.5), "Bright red", 10)

	-- Sala VIP (canto sudoeste do pátio), com teto e porta VIP de frente para o pátio
	local vip = Prefabs.model(folder, "VIP")
	local vc = Vector3.new(-91, 0, 91)
	block(vip, Vector3.new(19, 0.4, 19), CFrame.new(vc + Vector3.new(0, 0.2, 0)), "Institutional white")
	block(vip, Vector3.new(20, 12, 1), CFrame.new(vc + Vector3.new(0, 6, -10)), "Bright yellow", { name = "Wall" })
	block(vip, Vector3.new(1, 12, 7), CFrame.new(vc + Vector3.new(10, 6, -6.5)), "Bright yellow", { name = "Wall" })
	block(vip, Vector3.new(1, 12, 7), CFrame.new(vc + Vector3.new(10, 6, 6.5)), "Bright yellow", { name = "Wall" })
	block(vip, Vector3.new(1, 2, 6), CFrame.new(vc + Vector3.new(10, 11, 0)), "Black", { name = "Lintel" })
	block(vip, Vector3.new(22, 1, 22), CFrame.new(vc + Vector3.new(0, 12.5, 0)), "Bright yellow", { name = "Roof" })
	local door = block(vip, Vector3.new(1, 10, 6), CFrame.new(vc + Vector3.new(10, 5, 0)), "Bright yellow", {
		name = "VipDoor",
		smooth = true,
		transparency = 0.4,
		material = Enum.Material.ForceField,
	})
	door:AddTag("VipDoor")
	local sign = block(vip, Vector3.new(0.4, 2, 6), CFrame.new(vc + Vector3.new(10.7, 13.5, 0)), "Black", {
		name = "VipSign",
		smooth = true,
	})
	Prefabs.surfaceLabel(sign, Enum.NormalId.Right, "👑 VIP", BrickColor.new("Bright yellow").Color, 30)
	for gx = 0, 3 do
		for gz = 0, 3 do
			ctx.addSpawn("Coin", vc + Vector3.new(-6 + gx * 4, 0.4 + COIN, -6 + gz * 4), true)
		end
	end
	ctx.addSpawn("Gem", vc + Vector3.new(-7, 0.4 + COIN, 7), true)
	ctx.addSpawn("Gem", vc + Vector3.new(7, 0.4 + COIN, 7), true)
	ctx.info.vipZone = { cframe = CFrame.new(vc + Vector3.new(0, 6, 0)), size = Vector3.new(18, 12, 18) }
	ctx.info.vipDoor = door

	-- Moedas no pátio
	for _, p in { Vector3.new(-90, 0, 55), Vector3.new(-55, 0, 55), Vector3.new(-50, 0, 90), Vector3.new(-80, 0, 70) } do
		ctx.addSpawnOnSurface("Coin", p.X, p.Z)
	end
end

-- =========================================================================
-- Bairro (sudeste: x > 0, z > 0) - parkour de telhado
-- =========================================================================
local function buildNeighborhood(ctx)
	local folder = ctx.folder("Neighborhood")
	local block = Prefabs.block
	local rng = ctx.rng

	-- Rua local com calçadas
	block(folder, Vector3.new(104, 0.2, 8), CFrame.new(61, 0.1, 62), ROAD, { name = "Street", smooth = true })
	for _, side in { -1, 1 } do
		block(folder, Vector3.new(104, 0.3, 2.5), CFrame.new(61, 0.15, 62 + side * 5.25), SIDEWALK, {
			name = "Sidewalk",
		})
	end

	-- Fileira norte: prédios que sobem de 4 em 4 studs (rota de telhado)
	local wallColors = { "Brick yellow", "Bright orange", "Light stone grey", "Sand blue" }
	local heights = { 8, 12, 16, 20 }
	for i, h in heights do
		local x = 24 + (i - 1) * 21
		Prefabs.building(folder, CFrame.new(x, 0.3, 36), Vector3.new(16, h, 20), wallColors[i], lego(i))
		local roof = h + 0.3 + 0.8
		if i == 3 then
			ctx.addSpawn("Gem", Vector3.new(x, roof + COIN, 36))
		elseif i == 4 then
			ctx.addSpawn("Gem", Vector3.new(x - 3, roof + COIN, 36))
			ctx.addSpawn("Gem", Vector3.new(x + 3, roof + COIN, 36))
		end
		ctx.addSpawn("Coin", Vector3.new(x - 4, roof + COIN, 32))
		ctx.addSpawn("Coin", Vector3.new(x + 4, roof + COIN, 40))
	end
	Prefabs.trampoline(folder, Vector3.new(24, 0.9, 20))

	-- Fileira sul (decorativa) e lojinha
	Prefabs.building(folder, CFrame.new(30, 0.3, 86), Vector3.new(20, 12, 22), "Bright red", "Black")
	Prefabs.building(folder, CFrame.new(56, 0.3, 86), Vector3.new(18, 24, 22), "Light stone grey", "Bright blue")
	Prefabs.building(folder, CFrame.new(82, 0.3, 88), Vector3.new(22, 8, 18), "Bright yellow", "Bright red")
	Prefabs.building(folder, CFrame.new(104, 0.3, 30), Vector3.new(14, 10, 16), "Bright green", "Black")

	-- Carros estacionados, hidrantes, caixas de correio, lixeiras e postes
	local carColors = { "Bright red", "Bright blue", "Bright yellow", "Bright green", "Institutional white", "Black" }
	for i = 0, 5 do
		local side = if i % 2 == 0 then -1 else 1
		Prefabs.car(
			folder,
			CFrame.new(20 + i * 16, 0.2, 62 + side * 2.4) * CFrame.Angles(0, math.pi / 2, 0),
			carColors[i + 1]
		)
	end
	for _, x in { 18, 48, 78, 106 } do
		Prefabs.hydrant(folder, Vector3.new(x, 0.3, 56))
		Prefabs.mailbox(folder, CFrame.new(x + 6, 0.3, 68))
		Prefabs.trashCan(folder, Vector3.new(x + 10, 0.3, 56))
	end
	Prefabs.lamp(folder, Vector3.new(36, 0.3, 56))
	Prefabs.lamp(folder, Vector3.new(86, 0.3, 68))

	for i = 0, 5 do
		ctx.addSpawn("Coin", Vector3.new(16 + i * 17, 0.2 + COIN, 62))
	end
	for _ = 1, 4 do
		Prefabs.tree(folder, Vector3.new(rng:NextNumber(14, 110), 0, rng:NextNumber(102, 112)), "S")
	end
end

function CityBuilder.build(ctx)
	buildRoads(ctx)
	buildPlaza(ctx)
	buildPark(ctx)
	buildConstruction(ctx)
	buildCastle(ctx)
	buildNeighborhood(ctx)
end

return CityBuilder
