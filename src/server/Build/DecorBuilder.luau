--[[
	DecorBuilder.luau
	Chão de grama com studs, caminhos de tijolo das bases até a cidade, montanhas de blocos
	em degraus nas bordas e linhas de árvores para fechar o horizonte (nada de "fim do mundo").
	(Nuvens e pássaros são só visuais e ficam no cliente: EnvironmentController.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)

local Prefabs = require(script.Parent.Prefabs)

local DecorBuilder = {}

local GROUND = Config.Map.GroundHalf
local CITY = Config.Map.CityHalf
local RING_OUTER = CITY + Config.Map.RingRoadWidth

-- Chão do mundo: grama verde com studs (uma placa só: barato e sem "xadrez").
function DecorBuilder.ground(ctx)
	local folder = ctx.folder("Ground")
	Prefabs.block(folder, Vector3.new(GROUND * 2 + 80, 2, GROUND * 2 + 80), CFrame.new(0, -1, 0), "Bright green", {
		name = "Grass",
		shadow = false,
	})
end

-- Caminho de tijolo do portão de cada base até a rua em anel.
function DecorBuilder.paths(ctx)
	local folder = ctx.folder("Paths")
	for index = 1, MapLayout.plotCount() do
		local gx, gz = MapLayout.point(index, "Gate")
		local start = Vector3.new(gx, 0, gz)
		local direction = -Vector3.new(gx, 0, gz).Unit
		-- anda até tocar a borda externa da rua em anel (quadrado de lado RING_OUTER)
		local t = 0
		while t < 200 do
			local p = start + direction * t
			if math.max(math.abs(p.X), math.abs(p.Z)) <= RING_OUTER - 1 then
				break
			end
			t += 1
		end
		local finish = start + direction * t
		local length = (finish - start).Magnitude
		if length > 1 then
			Prefabs.block(
				folder,
				Vector3.new(10, 0.3, length),
				CFrame.lookAt((start + finish) / 2, finish) + Vector3.new(0, 0.15, 0),
				"Reddish brown",
				{ name = "BrickPath", material = Enum.Material.Brick, smooth = true }
			)
		end
	end
end

local function nearPlot(x: number, z: number, margin: number): boolean
	return MapLayout.plotAt(x, z, margin) ~= nil
end

local function nearPath(x: number, z: number): boolean
	for index = 1, MapLayout.plotCount() do
		local gx, gz = MapLayout.point(index, "Gate")
		-- distância ao segmento portão -> centro (aprox.: projeta na direção radial)
		local len = math.sqrt(gx * gx + gz * gz)
		local ux, uz = gx / len, gz / len
		local along = x * ux + z * uz
		local across = math.abs(x * uz - z * ux)
		if along > RING_OUTER - 4 and along < len + 4 and across < 9 then
			return true
		end
	end
	return false
end

-- Montanhas de blocos em degraus em volta do mapa + linha de árvores.
function DecorBuilder.borders(ctx)
	local rng = ctx.rng
	local folder = ctx.folder("Mountains")
	local depth = Config.Map.MountainDepth
	local span = GROUND + depth
	local segment = 45
	for side = 1, 4 do
		for t = -span, span, segment do
			-- (along, out): along = posição ao longo do lado; out = distância do centro
			local function place(size: Vector3, out: number, height: number, color: string)
				local along = t + rng:NextNumber(-6, 6)
				local cf
				if side == 1 then
					cf = CFrame.new(along, height / 2, -out)
				elseif side == 2 then
					cf = CFrame.new(along, height / 2, out)
				elseif side == 3 then
					cf = CFrame.new(-out, height / 2, along) * CFrame.Angles(0, math.pi / 2, 0)
				else
					cf = CFrame.new(out, height / 2, along) * CFrame.Angles(0, math.pi / 2, 0)
				end
				Prefabs.block(
					folder,
					Vector3.new(size.X, height, size.Z),
					cf,
					color,
					{ name = "Mountain", shadow = true }
				)
			end
			local h1 = rng:NextNumber(10, 16)
			local h2 = rng:NextNumber(22, 32)
			local h3 = rng:NextNumber(36, 52)
			place(Vector3.new(segment + 8, 0, depth), GROUND + depth / 2, h1, "Earth green")
			place(Vector3.new(segment - 4, 0, depth * 0.6), GROUND + depth * 0.65, h2, "Dark green")
			place(Vector3.new(segment - 16, 0, depth * 0.35), GROUND + depth * 0.8, h3, "Medium stone grey")
			if h3 > 44 then
				place(Vector3.new(segment - 20, 0, depth * 0.3), GROUND + depth * 0.8, h3 + 3, "Institutional white")
			end
		end
	end

	-- Linha de árvores por dentro das montanhas
	local trees = ctx.folder("TreeLine")
	local sizes = { "M", "L", "L" }
	for side = 1, 4 do
		for t = -GROUND + 10, GROUND - 10, 30 do
			local along = t + rng:NextNumber(-6, 6)
			local out = GROUND - rng:NextNumber(4, 12)
			local x, z
			if side == 1 then
				x, z = along, -out
			elseif side == 2 then
				x, z = along, out
			elseif side == 3 then
				x, z = -out, along
			else
				x, z = out, along
			end
			if not nearPlot(x, z, 6) then
				Prefabs.tree(trees, Vector3.new(x, 0, z), sizes[rng:NextInteger(1, #sizes)])
			end
		end
	end

	-- Árvores e arbustos entre as bases (separação natural)
	local between = ctx.folder("BetweenPlots")
	for index = 1, MapLayout.plotCount() do
		local angle = math.rad(Config.Map.PlotAngleOffset + (index - 0.5) * (360 / MapLayout.plotCount()))
		for k = 0, 2 do
			local radius = Config.Map.PlotRadius - 20 + k * 22
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			if not nearPlot(x, z, 4) and not nearPath(x, z) and math.max(math.abs(x), math.abs(z)) > RING_OUTER + 4 then
				Prefabs.tree(between, Vector3.new(x, 0, z), if k == 1 then "L" else "M")
			end
		end
	end
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(RING_OUTER + 8, GROUND - 14)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if
			math.max(math.abs(x), math.abs(z)) > RING_OUTER + 4
			and math.max(math.abs(x), math.abs(z)) < GROUND - 4
			and not nearPlot(x, z, 4)
			and not nearPath(x, z)
		then
			Prefabs.bush(between, Vector3.new(x, 0, z))
		end
	end
end

return DecorBuilder
