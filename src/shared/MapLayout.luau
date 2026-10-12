--[[
	MapLayout.luau
	Geometria do mapa compartilhada por servidor e cliente. Módulo PURO (só números):
	testável no Lune e usável no cliente mesmo com StreamingEnabled (o cliente não precisa
	que as Parts existam para saber onde fica cada base).

	Plots: 8 terrenos de 70x70 num anel de raio Config.Map.PlotRadius, nos ângulos
	22,5° + 45°*k. Cada plot "olha" para o centro: no espaço LOCAL do plot, -Z aponta
	para a cidade (o portão fica em z = -35) e +Z para as montanhas.

	Convenção de yaw (igual a CFrame.Angles(0, yaw, 0)):
		mundo = centro + R(yaw) * local
		wx = cx + lx*cos(yaw) + lz*sin(yaw)
		wz = cz - lx*sin(yaw) + lz*cos(yaw)
]]

local Config = require(script and script.Parent and script.Parent:FindFirstChild("Config") or "./Config")

local MapLayout = {}

local MAP = Config.Map
MapLayout.PLOT_HALF = MAP.PlotSize / 2
MapLayout.FLOOR_TOP = 0.6 -- topo do piso da base (o chão do mundo fica em y = 0)

-- Pontos importantes no espaço local do plot (x, z).
MapLayout.Local = {
	Gate = { 0, -35 }, -- centro do portão (abertura de 10 studs)
	GateOutside = { 0, -42 }, -- para onde invasores são empurrados
	Spawn = { 0, -22 },
	LockButton = { -9, -29 },
	BuyButton = { 9, -29 },
	Vault = { 25, -22 },
	Shelf = { -30, 0 }, -- estante encostada no muro esquerdo, virada para +X
	Sign = { 0, -40 }, -- placa grande na frente do portão
	Turret = { -29, 29 },
	TrackCenter = { 2, 18 },
}
MapLayout.GATE_WIDTH = 10
MapLayout.SHELF_ROWS = 3
MapLayout.SHELF_COLUMNS = 10

function MapLayout.plotCount(): number
	return MAP.PlotCount
end

-- Centro (x, z) e yaw do plot i (1..8).
function MapLayout.plot(index: number): (number, number, number)
	local angle = math.rad(MAP.PlotAngleOffset + (index - 1) * (360 / MAP.PlotCount))
	local x = math.cos(angle) * MAP.PlotRadius
	local z = math.sin(angle) * MAP.PlotRadius
	-- yaw tal que o LookVector (-sin, 0, -cos) aponte para a origem
	local yaw = math.atan2(x, z)
	return x, z, yaw
end

function MapLayout.toWorld(index: number, lx: number, lz: number): (number, number)
	local cx, cz, yaw = MapLayout.plot(index)
	local c, s = math.cos(yaw), math.sin(yaw)
	return cx + lx * c + lz * s, cz - lx * s + lz * c
end

function MapLayout.toLocal(index: number, wx: number, wz: number): (number, number)
	local cx, cz, yaw = MapLayout.plot(index)
	local c, s = math.cos(yaw), math.sin(yaw)
	local dx, dz = wx - cx, wz - cz
	return dx * c - dz * s, dx * s + dz * c
end

-- Ponto local nomeado -> mundo.
function MapLayout.point(index: number, name: string): (number, number)
	local p = MapLayout.Local[name]
	return MapLayout.toWorld(index, p[1], p[2])
end

-- Índice do plot que contém (wx, wz), ou nil. margin > 0 aumenta a área.
function MapLayout.plotAt(wx: number, wz: number, margin: number?): number?
	local half = MapLayout.PLOT_HALF + (margin or 0)
	for index = 1, MAP.PlotCount do
		local lx, lz = MapLayout.toLocal(index, wx, wz)
		if math.abs(lx) <= half and math.abs(lz) <= half then
			return index
		end
	end
	return nil
end

function MapLayout.inCity(wx: number, wz: number): boolean
	return math.abs(wx) <= MAP.CityHalf and math.abs(wz) <= MAP.CityHalf
end

-- Posição local (x, z) da vaga k (1..30) da estante. A estante fica em x = -30, virada
-- para +X; 3 prateleiras (alturas) x 10 colunas ao longo de Z.
function MapLayout.shelfSlot(k: number): (number, number, number)
	local row = (k - 1) // MapLayout.SHELF_COLUMNS -- 0..2 (altura)
	local column = (k - 1) % MapLayout.SHELF_COLUMNS -- 0..9 (ao longo de z)
	local shelf = MapLayout.Local.Shelf
	local lz = shelf[2] - 13.5 + column * 3
	local height = 1.6 + row * 2.4
	return shelf[1] + 0.6, height, lz
end

-- Distância entre dois pontos no plano XZ.
function MapLayout.distanceXZ(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

return MapLayout
