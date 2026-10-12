--[[
	PlotBuilder.luau
	Constrói os terrenos (plots) de tycoon: a "casca" (chão, cerca, portão laser, placa,
	estante, cofre, botões, SpawnLocation) e as peças de cada nível 1..6, incluindo a
	Pista de Gravação particular.

	Tudo é posicionado no espaço LOCAL do plot (ver MapLayout): -Z aponta para a cidade,
	o portão fica em z = -35, a estante no muro esquerdo (x = -30) e a Pista no fundo.

	Peças construídas com animate = true recebem a tag "BuildPiece" e os atributos
	BuildAt/BuildOrder: o cliente (BaseController) faz os blocos caírem do céu e encaixarem.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)

local Prefabs = require(script.Parent.Prefabs)

local PlotBuilder = {}

local F = MapLayout.FLOOR_TOP
local HALF = MapLayout.PLOT_HALF
local COIN_HEIGHT = 2.5

export type TrackSpawn = { kind: string, lx: number, y: number, lz: number }

export type Mover = { constraint: PrismaticConstraint, range: number }

export type Plot = {
	index: number,
	cframe: CFrame, -- centro do plot no chão (y = 0), olhando para a cidade
	model: Model,
	floor: BasePart,
	accents: { BasePart },
	gate: Prefabs.GateInfo,
	sign: { board: BasePart, name: TextLabel, image: ImageLabel },
	shelf: Prefabs.ShelfInfo,
	vault: Prefabs.VaultInfo,
	lockPad: Prefabs.PadInfo,
	buyPad: Prefabs.PadInfo,
	spawn: SpawnLocation,
	levels: { [number]: Folder },
	movers: { Mover },
	turret: BasePart?,
	level: number,
}

local function at(plot: Plot, lx: number, y: number, lz: number): CFrame
	return plot.cframe * CFrame.new(lx, y, lz)
end

function PlotBuilder.localCFrame(plot: Plot, lx: number, y: number, lz: number): CFrame
	return at(plot, lx, y, lz)
end

-- =========================================================================
-- Casca do plot
-- =========================================================================
local function fenceLine(parent: Instance, plot: Plot, ax: number, az: number, bx: number, bz: number)
	local a = at(plot, ax, 0, az).Position
	local b = at(plot, bx, 0, bz).Position
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (a + b) / 2
	local look = CFrame.lookAt(mid, b)
	for _, h in { 1.6, 3.2 } do
		Prefabs.block(
			parent,
			Vector3.new(0.4, 0.4, length),
			look + Vector3.new(0, h, 0),
			"Institutional white",
			{ name = "Rail", smooth = true }
		)
	end
	local posts = math.max(1, math.floor(length / 10))
	for i = 0, posts do
		local p = a:Lerp(b, i / posts)
		Prefabs.block(parent, Vector3.new(1, 4, 1), CFrame.new(p + Vector3.new(0, 2, 0)), "Institutional white", {
			name = "Post",
		})
	end
end

function PlotBuilder.create(parent: Instance, index: number): Plot
	local cx, cz, yaw = MapLayout.plot(index)
	local cframe = CFrame.new(cx, 0, cz) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model.Parent = parent

	local plot: Plot = {
		index = index,
		cframe = cframe,
		model = model,
		floor = nil :: any,
		accents = {},
		gate = nil :: any,
		sign = nil :: any,
		shelf = nil :: any,
		vault = nil :: any,
		lockPad = nil :: any,
		buyPad = nil :: any,
		spawn = nil :: any,
		levels = {},
		movers = {},
		turret = nil,
		level = 0,
	}

	local shell = Prefabs.model(model, "Shell")
	plot.floor = Prefabs.block(
		shell,
		Vector3.new(HALF * 2, F, HALF * 2),
		at(plot, 0, F / 2, 0),
		"Medium stone grey",
		{ name = "Floor" }
	)

	-- Cerca (com abertura de 10 studs no portão)
	local gap = MapLayout.GATE_WIDTH / 2 + 1
	fenceLine(shell, plot, -HALF, -HALF, -gap, -HALF)
	fenceLine(shell, plot, gap, -HALF, HALF, -HALF)
	fenceLine(shell, plot, HALF, -HALF, HALF, HALF)
	fenceLine(shell, plot, HALF, HALF, -HALF, HALF)
	fenceLine(shell, plot, -HALF, HALF, -HALF, -HALF)

	-- Portão laser (olhando para fora: -Z local)
	plot.gate = Prefabs.gate(shell, at(plot, 0, F, -HALF), "Medium stone grey")
	for _, part in plot.gate.model:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Pillar" then
			table.insert(plot.accents, part)
		end
	end

	-- Placa grande em cima do portão, virada para a cidade: avatar + nome.
	local board = Prefabs.block(
		shell,
		Vector3.new(18, 7, 0.8),
		at(plot, 0, F + 16.5, -HALF) * CFrame.Angles(0, math.pi, 0),
		"Black",
		{ name = "Sign", smooth = true }
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- a placa foi girada 180°: Back aponta para a cidade
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(21, 26, 43)
	frame.Parent = gui
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromOffset(180, 180)
	image.Position = UDim2.fromOffset(15, 15)
	image.BackgroundColor3 = Color3.fromRGB(91, 108, 255)
	image.Image = ""
	image.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 24)
	corner.Parent = image
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -220, 1, -30)
	nameLabel.Position = UDim2.fromOffset(210, 15)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Text = "Livre"
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame
	gui.Parent = board
	plot.sign = { board = board, name = nameLabel, image = image }

	-- SpawnLocation dentro do plot
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = at(plot, MapLayout.Local.Spawn[1], F + 0.1, MapLayout.Local.Spawn[2])
	spawn.BrickColor = BrickColor.new("Institutional white")
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = false -- só vale como RespawnLocation do dono
	spawn.CanCollide = false
	spawn.Parent = shell
	plot.spawn = spawn

	-- Estante, cofre e botões
	local shelfPos = MapLayout.Local.Shelf
	plot.shelf = Prefabs.shelf(shell, at(plot, shelfPos[1], F, shelfPos[2]))
	local vaultPos = MapLayout.Local.Vault
	plot.vault = Prefabs.vault(shell, at(plot, vaultPos[1], F, vaultPos[2]))
	local lockPos = MapLayout.Local.LockButton
	plot.lockPad = Prefabs.buttonPad(shell, at(plot, lockPos[1], F, lockPos[2]).Position, "Bright red", "🔒")
	local buyPos = MapLayout.Local.BuyButton
	plot.buyPad = Prefabs.buttonPad(shell, at(plot, buyPos[1], F, buyPos[2]).Position, "Bright green", "")

	return plot
end

-- =========================================================================
-- Dono
-- =========================================================================
function PlotBuilder.setOwner(plot: Plot, ownerName: string?, userId: number?, colorName: string?)
	local color = colorName or "Medium stone grey"
	for _, part in plot.accents do
		part.BrickColor = BrickColor.new(color)
	end
	plot.floor.BrickColor = BrickColor.new(if ownerName then "Light stone grey" else "Medium stone grey")
	plot.sign.name.Text = ownerName or "Livre"
	plot.sign.image.Image = if userId and userId > 0
		then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=180&h=180", userId)
		else ""
	plot.sign.image.BackgroundColor3 = BrickColor.new(color).Color
	plot.spawn.Enabled = ownerName ~= nil
end

-- =========================================================================
-- Níveis
-- =========================================================================

-- Coletáveis da Pista que cada nível acrescenta (espaço local; y absoluto).
local TRACK_SPAWNS: { [number]: { TrackSpawn } } = {
	[1] = {
		{ kind = "TrackCoin", lx = -10, y = F + COIN_HEIGHT, lz = 8 },
		{ kind = "TrackCoin", lx = -2, y = F + COIN_HEIGHT, lz = 8 },
		{ kind = "TrackCoin", lx = 6, y = F + COIN_HEIGHT, lz = 8 },
		{ kind = "TrackCoin", lx = 14, y = F + COIN_HEIGHT, lz = 8 },
		{ kind = "TrackCoin", lx = 16, y = F + COIN_HEIGHT, lz = 18 },
		{ kind = "TrackCoin", lx = 14, y = F + COIN_HEIGHT, lz = 28 },
		{ kind = "TrackCoin", lx = 6, y = F + COIN_HEIGHT, lz = 28 },
		{ kind = "TrackCoin", lx = -2, y = F + COIN_HEIGHT, lz = 28 },
		{ kind = "TrackCoin", lx = -10, y = F + COIN_HEIGHT, lz = 28 },
		{ kind = "TrackCoin", lx = -12, y = F + COIN_HEIGHT, lz = 18 },
	},
	[2] = {
		{ kind = "TrackCoin", lx = 24, y = F + 4.4 + COIN_HEIGHT, lz = 16 },
		{ kind = "TrackCoin", lx = 28, y = F + 4.4 + COIN_HEIGHT, lz = 20 },
		{ kind = "TrackCoin", lx = -10, y = F + 0.4 + COIN_HEIGHT, lz = 31 },
		{ kind = "TrackCoin", lx = -3, y = F + 0.4 + COIN_HEIGHT, lz = 31 },
		{ kind = "TrackCoin", lx = 4, y = F + 0.4 + COIN_HEIGHT, lz = 31 },
		{ kind = "TrackCoin", lx = 11, y = F + 0.4 + COIN_HEIGHT, lz = 31 },
	},
	[3] = {
		{ kind = "TrackCoin", lx = -8, y = 18 + COIN_HEIGHT, lz = 18.5 },
		{ kind = "TrackCoin", lx = -8, y = 18 + COIN_HEIGHT, lz = 21.5 },
		{ kind = "TrackCoin", lx = 20, y = 10.6 + COIN_HEIGHT, lz = 0 },
		{ kind = "TrackCoin", lx = 28, y = 10.6 + COIN_HEIGHT, lz = 0 },
	},
	[4] = {
		{ kind = "TrackGem", lx = 15, y = 18 + COIN_HEIGHT, lz = 18.5 },
		{ kind = "TrackGem", lx = 17, y = 18 + COIN_HEIGHT, lz = 21.5 },
	},
	[5] = {},
	[6] = {
		{ kind = "TrackChest", lx = 24, y = 10.6 + 1.6, lz = 4 },
	},
}

function PlotBuilder.trackSpawns(level: number): { TrackSpawn }
	return TRACK_SPAWNS[level] or {}
end

-- Builder de um nível: block() local que registra a ordem para a animação.
local function levelBuilder(plot: Plot, folder: Folder, animate: boolean)
	local order = 0
	local buildAt = Clock.now()
	local function mark(part: BasePart)
		if animate then
			order += 1
			part:SetAttribute("BuildAt", buildAt)
			part:SetAttribute("BuildOrder", order)
			CollectionService:AddTag(part, "BuildPiece")
		end
	end
	local function block(size: Vector3, lx: number, y: number, lz: number, color: string, options): BasePart
		local part = Prefabs.block(folder, size, at(plot, lx, y, lz), color, options)
		mark(part)
		return part
	end
	return block, mark
end

local BUILDERS: { [number]: (Plot, Folder, boolean) -> () } = {}

-- Nível 1: borda colorida no chão e a Pista curta (circuito em laranja).
BUILDERS[1] = function(plot, folder, animate)
	local block = levelBuilder(plot, folder, animate)
	local trim = "Bright orange"
	block(Vector3.new(32, 0.2, 4), 2, F + 0.1, 8, trim, { name = "Track" })
	block(Vector3.new(32, 0.2, 4), 2, F + 0.1, 28, trim, { name = "Track" })
	block(Vector3.new(4, 0.2, 16), -12, F + 0.1, 18, trim, { name = "Track" })
	block(Vector3.new(4, 0.2, 16), 16, F + 0.1, 18, trim, { name = "Track" })
end

-- Nível 2: muro baixo, rampa + plataforma e esteira na Pista.
BUILDERS[2] = function(plot, folder, animate)
	local block, mark = levelBuilder(plot, folder, animate)
	local wall = "Brick yellow"
	local gap = MapLayout.GATE_WIDTH / 2 + 1
	local frontLength = HALF - gap
	block(Vector3.new(frontLength, 3, 1), -(gap + frontLength / 2), F + 1.5, -HALF + 1.5, wall, { name = "Wall" })
	block(Vector3.new(frontLength, 3, 1), gap + frontLength / 2, F + 1.5, -HALF + 1.5, wall, { name = "Wall" })
	block(Vector3.new(HALF * 2 - 2, 3, 1), 0, F + 1.5, HALF - 1.5, wall, { name = "Wall" })
	block(Vector3.new(1, 3, HALF * 2 - 4), -HALF + 1.5, F + 1.5, 0, wall, { name = "Wall" })
	block(Vector3.new(1, 3, HALF * 2 - 4), HALF - 1.5, F + 1.5, 0, wall, { name = "Wall" })
	-- Rampa subindo para +X até a plataforma P2
	local ramp = Prefabs.wedge(
		folder,
		Vector3.new(6, 4.4, 8),
		at(plot, 18, F + 2.2, 18) * CFrame.Angles(0, math.pi / 2, 0),
		"Bright blue",
		{ name = "Ramp" }
	)
	mark(ramp)
	block(Vector3.new(8, 1, 8), 26, F + 3.9, 18, "Bright blue", { name = "Platform" })
	local conveyor = Prefabs.conveyor(
		folder,
		Vector3.new(28, 0.4, 4),
		at(plot, 0, F + 0.2, 31),
		plot.cframe:VectorToWorldSpace(Vector3.new(-Config.ConveyorSpeed, 0, 0))
	)
	mark(conveyor)
end

-- Nível 3: segundo andar com escada, trampolim e plataforma alta na Pista.
BUILDERS[3] = function(plot, folder, animate)
	local block, mark = levelBuilder(plot, folder, animate)
	block(Vector3.new(18, 1, 16), 24, 10.1, 1, "Bright red", { name = "SecondFloor" })
	for _, corner in { { 16, -6 }, { 32, -6 }, { 16, 8 }, { 32, 8 } } do
		block(Vector3.new(1, 9.6, 1), corner[1], F + 4.8, corner[2], "Black", { name = "Post" })
	end
	for i = 1, 5 do
		local top = F + 2 * i
		block(Vector3.new(4, top, 2), 18, top / 2, -17 + (i - 1) * 2, "Medium stone grey", { name = "Step" })
	end
	local trampoline = Prefabs.trampoline(folder, at(plot, -8, F + 0.6, 12).Position)
	mark(trampoline)
	block(Vector3.new(6, 1, 6), -8, 17.5, 20, "Bright green", { name = "HighPlatform" })
end

-- Nível 4: torre de vigia e plataforma móvel (PrismaticConstraint) com gemas.
BUILDERS[4] = function(plot, folder, animate)
	local block = levelBuilder(plot, folder, animate)
	for _, corner in { { 26.5, 26.5 }, { 32.5, 26.5 }, { 26.5, 32.5 }, { 32.5, 32.5 } } do
		block(Vector3.new(1, 16, 1), corner[1], F + 8, corner[2], "Reddish brown", { name = "TowerPost" })
	end
	block(Vector3.new(8, 1, 8), 29.5, F + 16, 29.5, "Reddish brown", { name = "TowerFloor" })
	block(Vector3.new(8, 2, 8), 29.5, F + 21, 29.5, "Bright red", { name = "TowerRoof" })
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Size = Vector3.new(2, 16, 2)
	truss.CFrame = at(plot, 25, F + 8, 29.5)
	truss.BrickColor = BrickColor.new("Medium stone grey")
	truss.Parent = folder
	block(Vector3.new(6, 1, 6), 16, 17.5, 20, "Bright yellow", { name = "GemPlatform" })

	-- Plataforma móvel: âncora fixa + plataforma solta presa por PrismaticConstraint (servo).
	local anchor = Prefabs.block(
		folder,
		Vector3.new(1, 1, 1),
		at(plot, -1.6, 17.5, 20),
		"Black",
		{ name = "MoverAnchor", canCollide = false, transparency = 1, noQuery = true }
	)
	local mover = Instance.new("Part")
	mover.Name = "Mover"
	mover.Size = Vector3.new(6, 1, 6)
	mover.CFrame = anchor.CFrame
	mover.BrickColor = BrickColor.new("Bright violet")
	mover.TopSurface = Enum.SurfaceType.Studs
	mover.Anchored = false
	mover.CustomPhysicalProperties = PhysicalProperties.new(2, 1, 0, 1, 1)
	mover.Parent = folder
	local a0 = Instance.new("Attachment")
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Parent = mover
	local prismatic = Instance.new("PrismaticConstraint")
	prismatic.Attachment0 = a0
	prismatic.Attachment1 = a1
	prismatic.ActuatorType = Enum.ActuatorType.Servo
	prismatic.ServoMaxForce = 1e7
	prismatic.Speed = 5
	prismatic.LimitsEnabled = true
	prismatic.LowerLimit = 0
	prismatic.UpperLimit = 11.2
	prismatic.TargetPosition = 0
	prismatic.Parent = mover
	pcall(mover.SetNetworkOwner, mover, nil)
	table.insert(plot.movers, { constraint = prismatic, range = 11.2 })
end

-- Nível 5: telhado sobre a estante e o laser de defesa.
BUILDERS[5] = function(plot, folder, animate)
	local block = levelBuilder(plot, folder, animate)
	block(Vector3.new(11, 1, 34), -29.5, F + 11.5, 0, "Bright blue", { name = "Roof" })
	for _, z in { -16, 16 } do
		block(Vector3.new(1, 11, 1), -24.5, F + 5.5, z, "Black", { name = "RoofPost" })
	end
	local turretPos = MapLayout.Local.Turret
	block(Vector3.new(1, 10, 1), turretPos[1], F + 5, turretPos[2], "Black", { name = "TurretPole" })
	local head = block(Vector3.new(2.4, 2.4, 2.4), turretPos[1], F + 11.2, turretPos[2], "Really red", {
		name = "TurretHead",
		material = Enum.Material.Neon,
		smooth = true,
	})
	plot.turret = head
end

-- Nível 6: base dourada (pilares Neon dourados nos cantos e moldura da placa).
BUILDERS[6] = function(plot, folder, animate)
	local block = levelBuilder(plot, folder, animate)
	for _, corner in
		{ { -HALF + 1, -HALF + 1 }, { HALF - 1, -HALF + 1 }, { -HALF + 1, HALF - 1 }, { HALF - 1, HALF - 1 } }
	do
		block(Vector3.new(2, 8, 2), corner[1], F + 4, corner[2], "Bright yellow", {
			name = "GoldPillar",
			material = Enum.Material.Neon,
			smooth = true,
		})
	end
	block(Vector3.new(19, 0.8, 1), 0, F + 20.4, -HALF, "Bright yellow", {
		name = "GoldFrame",
		material = Enum.Material.Neon,
		smooth = true,
	})
	block(Vector3.new(14.4, 0.6, 2.6), 0, F + 13.2, -HALF, "Bright yellow", {
		name = "GoldLintel",
		material = Enum.Material.Neon,
		smooth = true,
	})
end

-- Constrói o nível `level` (só as peças NOVAS daquele nível).
function PlotBuilder.buildLevel(plot: Plot, level: number, animate: boolean)
	if plot.levels[level] or not BUILDERS[level] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Level" .. level
	folder.Parent = plot.model
	plot.levels[level] = folder
	BUILDERS[level](plot, folder, animate)
	plot.level = math.max(plot.level, level)
end

-- Remove todos os níveis (dono saiu ou fez rebirth).
function PlotBuilder.clearLevels(plot: Plot)
	for level, folder in plot.levels do
		folder:Destroy()
		plot.levels[level] = nil
	end
	table.clear(plot.movers)
	plot.turret = nil
	plot.level = 0
end

-- Liga as luzinhas das vagas liberadas na estante.
function PlotBuilder.setShelfCapacity(plot: Plot, capacity: number)
	for row, frame in plot.shelf.boards do
		for column = 1, MapLayout.SHELF_COLUMNS do
			local k = (row - 1) * MapLayout.SHELF_COLUMNS + column
			local light = frame:FindFirstChild("Slot" .. column) :: Frame?
			if light then
				light.BackgroundColor3 = if k <= capacity
					then Color3.fromRGB(46, 212, 122)
					else Color3.fromRGB(70, 70, 70)
			end
		end
	end
end

return PlotBuilder
