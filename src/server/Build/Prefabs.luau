--[[
	Prefabs.luau
	Peças estilo Lego/Roblox clássico, todas criadas por código (Part/WedgePart/TrussPart).
	Coletáveis, decoração da cidade (postes, bancos, carros...), árvores de 3 tamanhos,
	e as peças da base (fita, estante, cofre, portão laser, botões de tycoon).

	Toda decoração vira Model com ModelStreamingMode = Atomic (StreamingEnabled) e peças
	pequenas têm CastShadow = false (desempenho com Lighting Future).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Prefabs = {}

export type BlockOptions = {
	class: string?,
	shape: Enum.PartType?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	name: string?,
	smooth: boolean?, -- sem studs
	noQuery: boolean?, -- visual puro (sem toque/raycast)
	shadow: boolean?, -- força CastShadow
}

local function applyStudsTexture(part: BasePart)
	if not Config.UseStudsTexture or Config.StudsTextureId == "" then
		return
	end
	local texture = Instance.new("Texture")
	texture.Texture = Config.StudsTextureId
	texture.Face = Enum.NormalId.Top
	texture.StudsPerTileU = 1
	texture.StudsPerTileV = 1
	texture.Transparency = 0.4
	texture.Parent = part
end

-- Bloco ancorado com studs no topo e inlets embaixo.
function Prefabs.block(parent: Instance, size: Vector3, cframe: CFrame, color: string, options: BlockOptions?): BasePart
	local opts: BlockOptions = options or {}
	local part = Instance.new(opts.class or "Part") :: BasePart
	if opts.shape and part:IsA("Part") then
		part.Shape = opts.shape
	end
	part.Name = opts.name or "Block"
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.BrickColor = BrickColor.new(color)
	part.Material = opts.material or Enum.Material.Plastic
	part.Transparency = opts.transparency or 0
	part.CanCollide = if opts.canCollide == nil then true else opts.canCollide
	if opts.shadow ~= nil then
		part.CastShadow = opts.shadow
	else
		part.CastShadow = size.X * size.Y * size.Z > 60 -- peças pequenas não projetam sombra
	end
	if opts.noQuery then
		part.CanTouch = false
		part.CanQuery = false
	end
	if opts.smooth then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	else
		part.TopSurface = Enum.SurfaceType.Studs
		part.BottomSurface = Enum.SurfaceType.Inlet
		if size.X >= 4 and size.Z >= 4 then
			applyStudsTexture(part)
		end
	end
	part.Parent = parent
	return part
end

function Prefabs.wedge(parent: Instance, size: Vector3, cframe: CFrame, color: string, options: BlockOptions?): BasePart
	local opts: BlockOptions = table.clone(options or {})
	opts.class = "WedgePart"
	return Prefabs.block(parent, size, cframe, color, opts)
end

-- Model agrupador (Atomic para StreamingEnabled).
function Prefabs.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent
	return model
end

function Prefabs.surfaceLabel(part: BasePart, face: Enum.NormalId, text: string, color: Color3?, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = part
	return label
end

function Prefabs.billboard(
	parent: Instance,
	text: string,
	size: Vector2,
	offset: Vector3,
	maxDistance: number?
): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(size.X, size.Y)
	billboard.StudsOffset = offset
	billboard.MaxDistance = maxDistance or 90
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	billboard.Parent = parent
	return label
end

local function visualPart(parent: Instance, className: string, size: Vector3, cframe: CFrame, color: string, material)
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.BrickColor = BrickColor.new(color)
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end
Prefabs.visualPart = visualPart

-- =========================================================================
-- Coletáveis (o PickupService cria e controla)
-- =========================================================================
local function pickupModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

-- Moeda: cilindro dourado em pé (o cliente faz girar).
function Prefabs.coin(position: Vector3): Model
	local model = pickupModel("Coin")
	local part = visualPart(
		model,
		"Part",
		Vector3.new(0.4, 2.4, 2.4),
		CFrame.new(position),
		"Bright yellow",
		Enum.Material.Neon
	) :: Part
	part.Shape = Enum.PartType.Cylinder
	part.Name = "Body"
	model.PrimaryPart = part
	return model
end

-- Gema: losango azul feito de 4 wedges.
function Prefabs.gem(position: Vector3): Model
	local model = pickupModel("Gem")
	local center = CFrame.new(position)
	local size = Vector3.new(0.7, 1.1, 0.8)
	local parts = {
		center * CFrame.new(0, 0.55, -0.4),
		center * CFrame.new(0, 0.55, 0.4) * CFrame.Angles(0, math.pi, 0),
		center * CFrame.new(0, -0.55, -0.4) * CFrame.Angles(0, 0, math.pi),
		center * CFrame.new(0, -0.55, 0.4) * CFrame.Angles(0, math.pi, math.pi),
	}
	for i, cf in parts do
		local wedge = visualPart(model, "WedgePart", size, cf, "Bright blue", Enum.Material.Neon)
		wedge.Name = "Wedge" .. i
	end
	local core = visualPart(model, "Part", Vector3.new(0.2, 0.2, 0.2), center, "Bright blue")
	core.Transparency = 1
	core.Name = "Core"
	model.PrimaryPart = core
	return model
end

-- Baú: bloco marrom com tampa e fechadura.
function Prefabs.chest(position: Vector3): Model
	local model = pickupModel("Chest")
	local center = CFrame.new(position)
	local base = visualPart(model, "Part", Vector3.new(4, 2.2, 3), center * CFrame.new(0, -0.5, 0), "Reddish brown")
	base.Name = "Base"
	local lid = visualPart(model, "Part", Vector3.new(4.2, 1, 3.2), center * CFrame.new(0, 1.1, 0), "Dark orange")
	lid.Name = "Lid"
	local lock =
		visualPart(model, "Part", Vector3.new(0.8, 0.9, 0.3), center * CFrame.new(0, 0.4, -1.6), "Bright yellow")
	lock.Name = "Lock"
	model.PrimaryPart = base
	return model
end

-- Banana: Parts amarelas em formato de "C", deitada no chão.
function Prefabs.banana(position: Vector3, yaw: number): Model
	local model = pickupModel("Banana")
	local center = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local radius = 1.1
	local steps = 5
	for i = 0, steps - 1 do
		local angle = math.rad(-70 + i * (140 / (steps - 1)))
		local offset = Vector3.new(math.sin(angle) * radius, 0, -math.cos(angle) * radius)
		local cf = center * CFrame.new(offset) * CFrame.Angles(0, -angle, 0)
		local piece = visualPart(model, "Part", Vector3.new(0.6, 0.5, 0.8), cf, "Bright yellow")
		piece.Name = "Piece" .. i
	end
	for _, angle in { math.rad(-82), math.rad(82) } do
		local offset = Vector3.new(math.sin(angle) * radius, 0, -math.cos(angle) * radius)
		local tip = visualPart(model, "Part", Vector3.new(0.3, 0.3, 0.3), center * CFrame.new(offset), "Brown")
		tip.Name = "Tip"
	end
	local root = visualPart(model, "Part", Vector3.new(0.2, 0.2, 0.2), center, "Bright yellow")
	root.Transparency = 1
	root.Name = "Root"
	model.PrimaryPart = root
	return model
end

-- =========================================================================
-- Natureza
-- =========================================================================
local TREE_SIZES = {
	S = { trunk = 4, leaves = { 6, 4 } },
	M = { trunk = 6, leaves = { 8, 6, 4 } },
	L = { trunk = 9, leaves = { 12, 10, 7, 4 } },
}
local LEAF_COLORS = { "Bright green", "Earth green", "Dark green" }

-- Árvore de blocos em 3 tamanhos ("S", "M", "L").
function Prefabs.tree(parent: Instance, position: Vector3, size: string?, leafColor: string?)
	local spec = TREE_SIZES[size or "M"] or TREE_SIZES.M
	local model = Prefabs.model(parent, "Tree")
	Prefabs.block(
		model,
		Vector3.new(spec.trunk, 1.6, 1.6),
		CFrame.new(position + Vector3.new(0, spec.trunk / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		"Reddish brown",
		{ shape = Enum.PartType.Cylinder, name = "Trunk", shadow = true }
	)
	local color = leafColor or LEAF_COLORS[(math.floor(position.X + position.Z) % #LEAF_COLORS) + 1]
	for i, s in spec.leaves do
		Prefabs.block(
			model,
			Vector3.new(s, 2, s),
			CFrame.new(position + Vector3.new(0, spec.trunk + (i - 1) * 2 + 1, 0)),
			color,
			{ name = "Leaves", shadow = true }
		)
	end
	return model
end

function Prefabs.bush(parent: Instance, position: Vector3)
	local model = Prefabs.model(parent, "Bush")
	Prefabs.block(model, Vector3.new(4, 2, 4), CFrame.new(position + Vector3.new(0, 1, 0)), "Earth green")
	Prefabs.block(model, Vector3.new(2, 1, 2), CFrame.new(position + Vector3.new(0.6, 2.5, 0.4)), "Bright green")
	return model
end

-- =========================================================================
-- Mobiliário urbano
-- =========================================================================

-- Poste de luz: a lâmpada (tag "Lamp") acende à noite pelo cliente (EnvironmentController).
function Prefabs.lamp(parent: Instance, position: Vector3)
	local model = Prefabs.model(parent, "Lamp")
	Prefabs.block(
		model,
		Vector3.new(10, 0.6, 0.6),
		CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		"Black",
		{ shape = Enum.PartType.Cylinder, name = "Pole", smooth = true }
	)
	local head = Prefabs.block(
		model,
		Vector3.new(1.6, 1, 1.6),
		CFrame.new(position + Vector3.new(0, 10.5, 0)),
		"Institutional white",
		{ name = "Bulb", smooth = true, material = Enum.Material.SmoothPlastic }
	)
	Prefabs.block(model, Vector3.new(2.2, 0.4, 2.2), CFrame.new(position + Vector3.new(0, 11.2, 0)), "Black")
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Shadows = false
	light.Enabled = false
	light.Parent = head
	CollectionService:AddTag(head, "Lamp")
	return model
end

function Prefabs.bench(parent: Instance, cframe: CFrame)
	local model = Prefabs.model(parent, "Bench")
	Prefabs.block(model, Vector3.new(6, 0.5, 2), cframe * CFrame.new(0, 1.5, 0), "Reddish brown")
	Prefabs.block(model, Vector3.new(6, 1.6, 0.4), cframe * CFrame.new(0, 2.6, 0.8), "Reddish brown")
	for _, x in { -2.4, 2.4 } do
		Prefabs.block(model, Vector3.new(0.6, 1.3, 1.6), cframe * CFrame.new(x, 0.65, 0), "Black")
	end
	return model
end

local FLOWER_COLORS = { "Bright red", "Bright yellow", "Hot pink", "Bright violet", "Institutional white" }

function Prefabs.flowerBed(parent: Instance, cframe: CFrame, rng: Random)
	local model = Prefabs.model(parent, "Flowers")
	Prefabs.block(model, Vector3.new(6, 1, 3), cframe * CFrame.new(0, 0.5, 0), "Reddish brown")
	for i = 0, 3 do
		local color = FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)]
		Prefabs.block(model, Vector3.new(1, 1, 1), cframe * CFrame.new(-2.2 + i * 1.5, 1.5, 0), color)
	end
	return model
end

function Prefabs.hydrant(parent: Instance, position: Vector3)
	local model = Prefabs.model(parent, "Hydrant")
	Prefabs.block(
		model,
		Vector3.new(2.2, 1.2, 1.2),
		CFrame.new(position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		"Bright red",
		{ shape = Enum.PartType.Cylinder }
	)
	Prefabs.block(model, Vector3.new(1.8, 0.5, 0.5), CFrame.new(position + Vector3.new(0, 1.3, 0)), "Bright red")
	Prefabs.block(model, Vector3.new(0.8, 0.4, 0.8), CFrame.new(position + Vector3.new(0, 2.4, 0)), "Bright yellow")
	return model
end

function Prefabs.trashCan(parent: Instance, position: Vector3)
	local model = Prefabs.model(parent, "Trash")
	Prefabs.block(
		model,
		Vector3.new(2.6, 1.6, 1.6),
		CFrame.new(position + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		"Dark green",
		{ shape = Enum.PartType.Cylinder }
	)
	Prefabs.block(model, Vector3.new(1.8, 0.3, 1.8), CFrame.new(position + Vector3.new(0, 2.75, 0)), "Black")
	return model
end

function Prefabs.mailbox(parent: Instance, cframe: CFrame)
	local model = Prefabs.model(parent, "Mailbox")
	Prefabs.block(model, Vector3.new(0.4, 3, 0.4), cframe * CFrame.new(0, 1.5, 0), "Black")
	Prefabs.block(model, Vector3.new(1.2, 1.2, 2), cframe * CFrame.new(0, 3.5, 0), "Bright blue")
	Prefabs.block(model, Vector3.new(0.2, 0.8, 0.4), cframe * CFrame.new(0.7, 3.8, 0.4), "Bright red")
	return model
end

-- Carrinho de blocos estacionado.
function Prefabs.car(parent: Instance, cframe: CFrame, color: string)
	local model = Prefabs.model(parent, "Car")
	Prefabs.block(model, Vector3.new(5, 1.6, 9), cframe * CFrame.new(0, 1.6, 0), color, { name = "Body" })
	Prefabs.block(model, Vector3.new(4.6, 1.6, 4.6), cframe * CFrame.new(0, 3.2, 0.6), color, { name = "Cabin" })
	Prefabs.block(
		model,
		Vector3.new(4.4, 1.2, 0.2),
		cframe * CFrame.new(0, 3.2, -1.75),
		"Light blue",
		{ name = "Windshield", smooth = true, transparency = 0.3, material = Enum.Material.Glass }
	)
	for _, offset in
		{
			Vector3.new(-2.6, 0.8, -2.8),
			Vector3.new(2.6, 0.8, -2.8),
			Vector3.new(-2.6, 0.8, 2.8),
			Vector3.new(2.6, 0.8, 2.8),
		}
	do
		Prefabs.block(
			model,
			Vector3.new(0.8, 1.6, 1.6),
			cframe * CFrame.new(offset),
			"Black",
			{ shape = Enum.PartType.Cylinder, name = "Wheel", smooth = true }
		)
	end
	return model
end

function Prefabs.cone(parent: Instance, position: Vector3)
	local model = Prefabs.model(parent, "Cone")
	Prefabs.block(model, Vector3.new(1.6, 0.3, 1.6), CFrame.new(position + Vector3.new(0, 0.15, 0)), "Bright orange")
	Prefabs.block(model, Vector3.new(0.8, 1.6, 0.8), CFrame.new(position + Vector3.new(0, 1.1, 0)), "Bright orange", {
		smooth = true,
	})
	return model
end

function Prefabs.crate(parent: Instance, position: Vector3, size: number)
	return Prefabs.block(
		parent,
		Vector3.new(size, size, size),
		CFrame.new(position + Vector3.new(0, size / 2, 0)),
		"Brown",
		{ name = "Crate" }
	)
end

-- Placa com seta para os bairros.
function Prefabs.arrowSign(parent: Instance, cframe: CFrame, text: string)
	local model = Prefabs.model(parent, "ArrowSign")
	Prefabs.block(model, Vector3.new(0.5, 6, 0.5), cframe * CFrame.new(0, 3, 0), "Black")
	local board = Prefabs.block(
		model,
		Vector3.new(7, 1.6, 0.3),
		cframe * CFrame.new(0, 5.8, 0),
		"Bright green",
		{ name = "Board", smooth = true }
	)
	Prefabs.surfaceLabel(board, Enum.NormalId.Front, text, Color3.new(1, 1, 1), 30)
	Prefabs.surfaceLabel(board, Enum.NormalId.Back, text, Color3.new(1, 1, 1), 30)
	return model
end

function Prefabs.flag(parent: Instance, position: Vector3, color: string, height: number?)
	local h = height or 10
	local model = Prefabs.model(parent, "Flag")
	Prefabs.block(model, Vector3.new(0.5, h, 0.5), CFrame.new(position + Vector3.new(0, h / 2, 0)), "Black")
	Prefabs.block(
		model,
		Vector3.new(0.2, 2.4, 4),
		CFrame.new(position + Vector3.new(0, h - 1.4, 2)),
		color,
		{ smooth = true }
	)
	return model
end

-- Prédio/casa de blocos com telhado plano (bom para parkour de telhado).
function Prefabs.building(parent: Instance, cframe: CFrame, size: Vector3, color: string, roofColor: string)
	local model = Prefabs.model(parent, "Building")
	Prefabs.block(model, size, cframe * CFrame.new(0, size.Y / 2, 0), color, { name = "Walls", shadow = true })
	Prefabs.block(
		model,
		Vector3.new(size.X + 1, 0.8, size.Z + 1),
		cframe * CFrame.new(0, size.Y + 0.4, 0),
		roofColor,
		{ name = "Roof" }
	)
	Prefabs.block(
		model,
		Vector3.new(3, 5, 0.3),
		cframe * CFrame.new(0, 2.5, -size.Z / 2 - 0.1),
		"Reddish brown",
		{ name = "Door", smooth = true }
	)
	local floors = math.max(1, math.floor((size.Y - 1) / 6))
	for f = 0, floors - 1 do
		for _, x in { -size.X / 4, size.X / 4 } do
			Prefabs.block(
				model,
				Vector3.new(2.6, 2.4, 0.3),
				cframe * CFrame.new(x, 4 + f * 6, -size.Z / 2 - 0.1),
				"Light blue",
				{ name = "Window", smooth = true, material = Enum.Material.Glass, transparency = 0.2 }
			)
		end
	end
	return model
end

-- Trampolim: o cliente aplica a velocidade vertical ao tocar (física do personagem é do cliente).
function Prefabs.trampoline(parent: Instance, position: Vector3): BasePart
	local part = Prefabs.block(
		parent,
		Vector3.new(6, 1.2, 6),
		CFrame.new(position),
		"Bright blue",
		{ name = "Trampoline", smooth = true }
	)
	part:SetAttribute("Power", Config.TrampolinePower)
	CollectionService:AddTag(part, "Trampoline")
	Prefabs.surfaceLabel(part, Enum.NormalId.Top, "⬆", Color3.new(1, 1, 1), 30)
	return part
end

-- Esteira: Part ancorada com AssemblyLinearVelocity carrega quem está em cima.
function Prefabs.conveyor(parent: Instance, size: Vector3, cframe: CFrame, velocity: Vector3): BasePart
	local part = Prefabs.block(parent, size, cframe, "Black", { name = "Conveyor", smooth = true })
	part.Material = Enum.Material.SmoothPlastic
	part.AssemblyLinearVelocity = velocity
	CollectionService:AddTag(part, "Conveyor")
	local arrows = string.rep("▶ ", math.max(1, math.floor(math.max(size.X, size.Z) / 4)))
	local label = Prefabs.surfaceLabel(part, Enum.NormalId.Top, arrows, BrickColor.new("Bright yellow").Color, 20)
	local localDir = cframe:VectorToObjectSpace(velocity)
	if math.abs(localDir.Z) > math.abs(localDir.X) then
		label.Rotation = if localDir.Z > 0 then 90 else -90
	elseif localDir.X < 0 then
		label.Rotation = 180
	end
	return part
end

-- =========================================================================
-- Peças da base
-- =========================================================================

-- Fita (cartucho VHS de blocos) com a cor e o nome do clone.
function Prefabs.tape(cframe: CFrame, colorName: string, labelText: string, golden: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Tape"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local body = Prefabs.block(
		model,
		Vector3.new(0.6, 1.5, 2.6),
		cframe,
		if golden then "Bright yellow" else "Black",
		{ name = "Body", smooth = true, material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic }
	)
	local stripe = Prefabs.block(
		model,
		Vector3.new(0.1, 0.9, 2.2),
		cframe * CFrame.new(0.33, 0.1, 0),
		colorName,
		{ name = "Label", smooth = true, noQuery = true }
	)
	Prefabs.surfaceLabel(stripe, Enum.NormalId.Right, labelText, Color3.new(1, 1, 1), 60)
	model.PrimaryPart = body
	return model
end

export type ShelfInfo = { model: Model, boards: { Frame } }

-- Estante: 3 prateleiras x 10 vagas. As vagas liberadas aparecem como luzes na frente
-- da prateleira (SurfaceGui, sem Parts extras). `cframe` = centro da base da estante,
-- olhando para dentro do plot (+X local do plot).
function Prefabs.shelf(parent: Instance, cframe: CFrame): ShelfInfo
	local model = Prefabs.model(parent, "Shelf")
	Prefabs.block(model, Vector3.new(0.6, 8, 31), cframe * CFrame.new(-0.9, 4, 0), "Reddish brown", { name = "Back" })
	for _, z in { -15.8, 15.8 } do
		Prefabs.block(model, Vector3.new(2.4, 8, 0.6), cframe * CFrame.new(0, 4, z), "Reddish brown", { name = "Side" })
	end
	local boards = {}
	for row = 0, 2 do
		local board = Prefabs.block(
			model,
			Vector3.new(2.4, 0.4, 31),
			cframe * CFrame.new(0, 0.6 + row * 2.4, 0),
			"Brown",
			{ name = "Board" .. row, smooth = true }
		)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Right
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 26)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		for column = 1, 10 do
			local light = Instance.new("Frame")
			light.Name = "Slot" .. column
			light.LayoutOrder = column
			light.Size = UDim2.fromOffset(34, 6)
			light.BorderSizePixel = 0
			light.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
			light.Parent = frame
		end
		gui.Parent = board
		table.insert(boards, frame)
	end
	return { model = model, boards = boards }
end

export type VaultInfo = { model: Model, label: TextLabel, door: BasePart }

function Prefabs.vault(parent: Instance, cframe: CFrame): VaultInfo
	local model = Prefabs.model(parent, "Vault")
	Prefabs.block(model, Vector3.new(6, 6, 5), cframe * CFrame.new(0, 3, 0), "Dark stone grey", { name = "Body" })
	local door = Prefabs.block(
		model,
		Vector3.new(4.6, 4.6, 0.4),
		cframe * CFrame.new(0, 3, -2.6),
		"Medium stone grey",
		{ name = "Door", smooth = true, material = Enum.Material.DiamondPlate }
	)
	Prefabs.block(
		model,
		Vector3.new(0.4, 1.8, 1.8),
		cframe * CFrame.new(0, 3, -2.95) * CFrame.Angles(0, math.pi / 2, 0),
		"Bright yellow",
		{ shape = Enum.PartType.Cylinder, name = "Dial", smooth = true }
	)
	local label = Prefabs.billboard(model.PrimaryPart or door, "💰 0", Vector2.new(180, 50), Vector3.new(0, 5, 0), 70)
	model.PrimaryPart = door
	return { model = model, label = label, door = door }
end

export type GateInfo = { model: Model, lasers: { BasePart }, label: TextLabel }

-- Portão com porta laser. `cframe` = centro da abertura, olhando para fora da base.
function Prefabs.gate(parent: Instance, cframe: CFrame, colorName: string): GateInfo
	local model = Prefabs.model(parent, "Gate")
	for _, x in { -6, 6 } do
		Prefabs.block(model, Vector3.new(2, 11, 2), cframe * CFrame.new(x, 5.5, 0), colorName, { name = "Pillar" })
	end
	local top =
		Prefabs.block(model, Vector3.new(14, 2, 2.4), cframe * CFrame.new(0, 12, 0), "Black", { name = "Lintel" })
	local lasers = {}
	for i = 0, 3 do
		local laser = Prefabs.block(
			model,
			Vector3.new(10, 0.25, 0.25),
			cframe * CFrame.new(0, 1.5 + i * 2.5, 0),
			"Really red",
			{ name = "Laser", smooth = true, material = Enum.Material.Neon, canCollide = false, transparency = 1 }
		)
		laser.CastShadow = false
		CollectionService:AddTag(laser, "GateLaser")
		table.insert(lasers, laser)
	end
	local label = Prefabs.billboard(top, "🔓", Vector2.new(220, 56), Vector3.new(0, 3, 0), 120)
	return { model = model, lasers = lasers, label = label }
end

export type PadInfo = { model: Model, top: BasePart, label: TextLabel }

-- Botão redondo de tycoon no chão, com texto flutuando em cima.
function Prefabs.buttonPad(parent: Instance, position: Vector3, colorName: string, text: string): PadInfo
	local model = Prefabs.model(parent, "Button")
	Prefabs.block(
		model,
		Vector3.new(0.6, 6, 6),
		CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		"Black",
		{ shape = Enum.PartType.Cylinder, name = "Ring", smooth = true }
	)
	local top = Prefabs.block(
		model,
		Vector3.new(0.5, 4.6, 4.6),
		CFrame.new(position + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		colorName,
		{ shape = Enum.PartType.Cylinder, name = "Top", smooth = true, material = Enum.Material.Neon }
	)
	local label = Prefabs.billboard(top, text, Vector2.new(200, 60), Vector3.new(0, 3, 0), 60)
	return { model = model, top = top, label = label }
end

return Prefabs
