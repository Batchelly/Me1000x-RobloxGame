--[[
	CloneRenderer.luau
	Renderiza TODOS os clones localmente. O servidor só manda os dados (caminho comprimido,
	início do loop, estado). Cada frame:

		fase = (Clock.now() - startTime) % duração -> Path.sample -> CFrame

	Desempenho (8 jogadores x 30 clones = 240):
	- Modelo R6 ancorado (só o HumanoidRootPart), movido com workspace:BulkMoveTo.
	- Humanoid com EvaluateStateMachine = false (sem física).
	- Animação procedural barata (C0 dos Motor6D) só até Config.CloneAnimDistance.
	- Só Config.MaxRenderedClones (120) mais próximos têm modelo completo; o resto vira um
	  "fantasma" de 1 Part na cor do torso. Reordenado a cada Config.LodUpdateInterval.
	- Modelos ficam em pool por dono (cache por HumanoidDescription) e são reaproveitados.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Path = require(Shared.Path)

local CloneRenderer = {}

local GHOST_SIZE = Vector3.new(2, 5, 1)
local GHOST_OFFSET = CFrame.new(0, -0.5, 0)
local LIE_DOWN = CFrame.Angles(math.pi / 2, 0, 0)
local FALLEN_GREY = Color3.fromRGB(140, 140, 140)
local GOLD = Color3.fromRGB(255, 215, 0)
local JUMP_POSE_TIME = 0.6
local MAX_NEW_MODELS_PER_PASS = 20 -- espalha o custo de :Clone() ao spawnar muitos clones

type ModelData = {
	model: Model,
	root: BasePart,
	ownerId: number,
	joints: { [string]: Motor6D },
	c0: { [string]: CFrame },
	parts: { BasePart },
	colors: { Color3 },
	clothing: { Instance },
	label: TextLabel,
	highlight: Highlight?,
	grey: boolean,
}

type Rec = {
	id: number,
	ownerId: number,
	ownerName: string,
	slot: number,
	golden: boolean,
	fallen: boolean,
	fallenPhase: number,
	transit: boolean,
	label: string,
	startTime: number,
	color: Color3,
	debug: boolean,
	path: Path.PathData,
	mode: string, -- "none" | "full" | "ghost"
	data: ModelData?,
	ghost: BasePart?,
	x: number?,
	y: number?,
	z: number?,
	dist2: number,
	speed: number,
	animT: number,
	airTimer: number,
}

local templates: Folder
local world: Folder
local recs: { [number]: Rec } = {}
local removedIds: { [number]: boolean } = {} -- evita ressuscitar clones pelo snapshot atrasado
local list: { Rec } = {}
local pools: { [number]: { ModelData } } = {}
local ghostPool: { BasePart } = {}
local lodDirty = true
local maxRendered = Config.MaxRenderedClones
local lastLod = 0
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- =========================================================================
-- Modelos (pool por dono)
-- =========================================================================
local JOINTS = {
	rs = "Right Shoulder",
	ls = "Left Shoulder",
	rh = "Right Hip",
	lh = "Left Hip",
}

local function buildModelData(model: Model, ownerId: number): ModelData?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local torso = model:FindFirstChild("Torso")
	local joints, c0 = {}, {}
	if torso then
		for key, name in JOINTS do
			local motor = torso:FindFirstChild(name)
			if motor and motor:IsA("Motor6D") then
				joints[key] = motor
				c0[key] = motor.C0
			end
		end
	end
	local parts, colors, clothing = {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			table.insert(parts, d)
			table.insert(colors, d.Color)
		elseif d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			table.insert(clothing, d)
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CloneTag"
	billboard.Adornee = root
	billboard.Size = UDim2.fromOffset(170, 40)
	billboard.StudsOffset = Vector3.new(0, 3.3, 0)
	billboard.MaxDistance = Config.CloneLabelDistance
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = model

	return {
		model = model,
		root = root,
		ownerId = ownerId,
		joints = joints,
		c0 = c0,
		parts = parts,
		colors = colors,
		clothing = clothing,
		label = label,
		highlight = nil,
		grey = false,
	}
end

local function setGrey(data: ModelData, grey: boolean)
	if data.grey == grey then
		return
	end
	data.grey = grey
	for i, part in data.parts do
		part.Color = if grey then FALLEN_GREY else data.colors[i]
	end
	for _, item in data.clothing do
		item.Parent = if grey then nil else data.model
	end
end

local function resetPose(data: ModelData)
	for key, motor in data.joints do
		motor.C0 = data.c0[key]
	end
end

local function applyVisuals(rec: Rec)
	local data = rec.data
	if data then
		local prefix = if rec.fallen then "⚠️ " elseif rec.golden then "⭐ " else ""
		local name = if rec.debug then string.format("%s #%d", rec.ownerName, rec.slot - 1000) else rec.label
		data.label.Text = prefix .. name
		data.label.TextColor3 = if rec.fallen then Color3.fromRGB(255, 120, 120) else rec.color
		setGrey(data, rec.fallen)
		if rec.fallen then
			resetPose(data)
		end
		if rec.golden and not rec.fallen then
			if not data.highlight then
				local highlight = Instance.new("Highlight")
				highlight.FillColor = GOLD
				highlight.FillTransparency = 0.55
				highlight.OutlineColor = Color3.fromRGB(255, 240, 120)
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = data.model
				data.highlight = highlight
			end
		elseif data.highlight then
			data.highlight:Destroy()
			data.highlight = nil
		end
	end
	local ghost = rec.ghost
	if ghost then
		local template = templates:FindFirstChild(tostring(rec.ownerId))
		local ghostColor = template and template:GetAttribute("GhostColor")
		ghost.Color = if rec.fallen
			then FALLEN_GREY
			elseif rec.golden then GOLD
			elseif typeof(ghostColor) == "Color3" then ghostColor
			else rec.color
	end
end

local function acquireModel(rec: Rec, allowNew: boolean): ModelData?
	local pool = pools[rec.ownerId]
	local data = pool and table.remove(pool)
	if not data then
		if not allowNew then
			return nil
		end
		local template = templates:FindFirstChild(tostring(rec.ownerId))
		if not template then
			return nil
		end
		local model = template:Clone() :: Model
		data = buildModelData(model, rec.ownerId)
		if not data then
			model:Destroy()
			return nil
		end
	end
	local final = data :: ModelData
	resetPose(final)
	final.model.Parent = world
	return final
end

local function releaseModel(data: ModelData)
	setGrey(data, false)
	if data.highlight then
		data.highlight:Destroy()
		data.highlight = nil
	end
	data.model.Parent = nil
	local pool = pools[data.ownerId]
	if not pool then
		pool = {}
		pools[data.ownerId] = pool
	end
	table.insert(pool, data)
end

local function acquireGhost(): BasePart
	local ghost = table.remove(ghostPool)
	if not ghost then
		local part = Instance.new("Part")
		part.Name = "CloneGhost"
		part.Size = GHOST_SIZE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = Config.GhostTransparency
		ghost = part
	end
	local final = ghost :: BasePart
	final.Parent = world
	return final
end

local function releaseGhost(ghost: BasePart)
	ghost.Parent = nil
	table.insert(ghostPool, ghost)
end

-- Troca o nível de detalhe do clone. Retorna false se não conseguiu (sem template/limite).
local function setMode(rec: Rec, mode: string, allowNew: boolean?): boolean
	if rec.mode == mode then
		return true
	end
	local data: ModelData? = nil
	if mode == "full" then
		data = acquireModel(rec, allowNew ~= false)
		if not data then
			return false
		end
	end
	if rec.data then
		releaseModel(rec.data)
		rec.data = nil
	end
	if rec.ghost then
		releaseGhost(rec.ghost)
		rec.ghost = nil
	end
	rec.mode = mode
	if mode == "full" then
		rec.data = data
	elseif mode == "ghost" then
		rec.ghost = acquireGhost()
	end
	applyVisuals(rec)
	return true
end

-- =========================================================================
-- LOD: os N mais próximos da câmera ganham modelo completo
-- =========================================================================
local function updateLod()
	lastLod = os.clock()
	lodDirty = false
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		return a.dist2 < b.dist2
	end)
	local full = 0
	local created = 0
	for _, rec in sorted do
		local want = "ghost"
		if rec.transit then
			want = "none" -- fita sendo roubada: o clone some até voltar
		elseif full < maxRendered and templates:FindFirstChild(tostring(rec.ownerId)) then
			want = "full"
		end
		if want == "full" then
			if rec.mode == "full" then
				full += 1
			else
				local pooled = pools[rec.ownerId] ~= nil and #pools[rec.ownerId] > 0
				local allowNew = created < MAX_NEW_MODELS_PER_PASS
				if setMode(rec, "full", allowNew) then
					full += 1
					if not pooled then
						created += 1
					end
				else
					setMode(rec, "ghost")
					lodDirty = true -- tenta de novo no próximo frame
				end
			end
		else
			setMode(rec, want)
		end
	end
end

-- =========================================================================
-- Animação procedural (estilo Animate R6 clássico)
-- =========================================================================
local function animate(rec: Rec, dt: number)
	local data = rec.data :: ModelData
	local joints, c0 = data.joints, data.c0
	if not joints.rs or not joints.ls or not joints.rh or not joints.lh then
		return
	end
	if rec.airTimer > 0 then
		joints.rs.C0 = c0.rs * CFrame.Angles(0, 0, math.pi)
		joints.ls.C0 = c0.ls * CFrame.Angles(0, 0, -math.pi)
		joints.rh.C0 = c0.rh
		joints.lh.C0 = c0.lh
		return
	end
	local amplitude = math.clamp(rec.speed / 14, 0.08, 1)
	local frequency = if rec.speed > 1 then 9 else 2
	rec.animT += dt
	local angle = amplitude * math.sin(rec.animT * frequency)
	joints.rs.C0 = c0.rs * CFrame.Angles(0, 0, angle)
	joints.ls.C0 = c0.ls * CFrame.Angles(0, 0, angle)
	joints.rh.C0 = c0.rh * CFrame.Angles(0, 0, -angle)
	joints.lh.C0 = c0.lh * CFrame.Angles(0, 0, -angle)
end

-- =========================================================================
-- Frame
-- =========================================================================
local function step(dt: number)
	local now = Clock.now()
	local camera = workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
	local cx, cy, cz = cameraPos.X, cameraPos.Y, cameraPos.Z
	local animDistSq = Config.CloneAnimDistance * Config.CloneAnimDistance
	local n = 0
	table.clear(moveParts)
	table.clear(moveCFrames)

	for _, rec in list do
		local cf: CFrame
		if rec.fallen then
			local x, y, z, yaw = Path.sample(rec.path, rec.fallenPhase)
			rec.x, rec.y, rec.z = x, y, z
			rec.speed = 0
			rec.airTimer = 0
			cf = CFrame.new(x, y - 2.5, z) * CFrame.Angles(0, yaw, 0) * LIE_DOWN
		else
			local phase = Path.phase(rec.path, now - rec.startTime)
			local x, y, z, yaw, flags = Path.sample(rec.path, phase)
			local px, py, pz = rec.x, rec.y, rec.z
			if px and py and pz and dt > 0 then
				local dx, dz = x - px, z - pz
				local horizontal = math.sqrt(dx * dx + dz * dz) / dt
				if horizontal < 80 then -- ignora o "pulo" de volta ao início do loop
					rec.speed += (horizontal - rec.speed) * math.min(1, dt * 8)
				end
				if bit32.band(flags, Path.FLAG_JUMP) ~= 0 or math.abs(y - py) / dt > 12 then
					rec.airTimer = JUMP_POSE_TIME
				end
			end
			rec.airTimer = math.max(0, rec.airTimer - dt)
			rec.x, rec.y, rec.z = x, y, z
			cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end

		local dx, dy, dz = (rec.x :: number) - cx, (rec.y :: number) - cy, (rec.z :: number) - cz
		rec.dist2 = dx * dx + dy * dy + dz * dz

		if rec.mode == "full" and rec.data then
			n += 1
			moveParts[n] = rec.data.root
			moveCFrames[n] = cf
			if not rec.fallen and rec.dist2 <= animDistSq then
				animate(rec, dt)
			end
		elseif rec.mode == "ghost" and rec.ghost then
			n += 1
			moveParts[n] = rec.ghost
			moveCFrames[n] = cf * GHOST_OFFSET
		end
	end

	if n > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if lodDirty or os.clock() - lastLod >= Config.LodUpdateInterval then
		updateLod()
	end
end

-- =========================================================================
-- Rede
-- =========================================================================
local function removeClone(id: number)
	removedIds[id] = true
	local rec = recs[id]
	if not rec then
		return
	end
	setMode(rec, "none")
	recs[id] = nil
	local index = table.find(list, rec)
	if index then
		table.remove(list, index)
	end
end

local function addClone(info: any)
	if type(info) ~= "table" or type(info.id) ~= "number" then
		return
	end
	local path = Path.decode(info.path)
	if not path then
		return
	end
	if recs[info.id] then
		removeClone(info.id)
	end
	local rec: Rec = {
		id = info.id,
		ownerId = info.ownerId,
		ownerName = info.ownerName,
		slot = info.slot,
		golden = info.golden == true,
		fallen = info.fallen == true,
		fallenPhase = info.fallenPhase or 0,
		transit = info.transit == true,
		label = if type(info.label) == "string" then info.label else "",
		startTime = info.startTime,
		color = if typeof(info.color) == "Color3" then info.color else Color3.new(1, 1, 1),
		debug = info.debug == true,
		path = path,
		mode = "none",
		data = nil,
		ghost = nil,
		x = nil,
		y = nil,
		z = nil,
		dist2 = math.huge,
		speed = 0,
		animT = math.random() * 10,
		airTimer = 0,
	}
	recs[rec.id] = rec
	table.insert(list, rec)
	lodDirty = true
end

local function updateClone(id: number, patch: any)
	local rec = recs[id]
	if not rec or type(patch) ~= "table" then
		return
	end
	for _, key in { "fallen", "fallenPhase", "startTime", "golden", "transit" } do
		if patch[key] ~= nil then
			(rec :: any)[key] = patch[key]
		end
	end
	applyVisuals(rec)
	lodDirty = true
end

function CloneRenderer.loadSnapshot(infos: any)
	if type(infos) ~= "table" then
		return
	end
	for _, info in infos do
		if type(info) == "table" and not removedIds[info.id] then
			addClone(info)
		end
	end
end

-- Configurações: quantos clones com modelo completo (30/60/120).
function CloneRenderer.setMaxRendered(value: number)
	maxRendered = math.clamp(value, 10, Config.MaxRenderedClones)
	lodDirty = true
end

-- Caminho decodificado de um clone (mini-mapa da fita).
function CloneRenderer.getPath(cloneId: number): Path.PathData?
	local rec = recs[cloneId]
	return rec and rec.path
end

function CloneRenderer.count(): number
	return #list
end

function CloneRenderer.init(_controllers)
	templates = ReplicatedStorage:WaitForChild("CloneTemplates") :: Folder
	world = Instance.new("Folder")
	world.Name = "ClientClones"
	world.Parent = workspace

	Net.connect("CloneAdded", addClone)
	Net.connect("CloneRemoved", removeClone)
	Net.connect("CloneUpdated", updateClone)

	templates.ChildAdded:Connect(function()
		lodDirty = true
	end)
	templates.ChildRemoved:Connect(function(child)
		local ownerId = tonumber(child.Name)
		if ownerId and pools[ownerId] then
			for _, data in pools[ownerId] do
				data.model:Destroy()
			end
			pools[ownerId] = nil
		end
		lodDirty = true
	end)
end

function CloneRenderer.start()
	RunService:BindToRenderStep("MeX1000Clones", Enum.RenderPriority.Camera.Value + 1, step)
end

return CloneRenderer
