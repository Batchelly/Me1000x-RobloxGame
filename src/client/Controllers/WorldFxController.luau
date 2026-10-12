--[[
	WorldFxController.luau
	Efeitos locais do mundo:
	- moedas/gemas girando (só as próximas e ativas);
	- popups "+12" na cor do dono de quem coletou;
	- efeitos de banana;
	- trampolins (a física do personagem é do cliente, então o pulo é aplicado aqui);
	- porta VIP sem colisão para quem tem o passe (o servidor também tira intrusos);
	- tag [VIP] no chat (TextChatService).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local WorldFxController = {}

local player = Players.LocalPlayer

type Spinner = {
	model: Model,
	base: CFrame,
	parts: { BasePart },
	offsets: { CFrame },
	phase: number,
	spin: boolean,
}

local spinners: { [Model]: Spinner } = {}
local spinParts: { BasePart } = {}
local spinCFrames: { CFrame } = {}
local SPIN_DISTANCE = 140
local popupPool: { { attachment: Attachment, gui: BillboardGui, label: TextLabel } } = {}
local activePopups = 0
local MAX_POPUPS = 40

-- =========================================================================
-- Moedas girando
-- =========================================================================
local function trackPickup(model: Instance)
	if not model:IsA("Model") or spinners[model] then
		return
	end
	local pivot = model:GetPivot()
	local parts, offsets = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
		end
	end
	spinners[model] = {
		model = model,
		base = pivot,
		parts = parts,
		offsets = offsets,
		phase = math.random() * math.pi * 2,
		spin = model:GetAttribute("Kind") ~= "Chest",
	}
end

local function untrackPickup(model: Instance)
	spinners[model :: Model] = nil
end

local function spinStep()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	local t = os.clock()
	local n = 0
	table.clear(spinParts)
	table.clear(spinCFrames)
	for model, spinner in spinners do
		if not spinner.spin or model:GetAttribute("Active") == false then
			continue
		end
		local base = spinner.base
		if (base.Position - cameraPos).Magnitude > SPIN_DISTANCE then
			continue
		end
		local angle = t * 2.5 + spinner.phase
		local cf = base * CFrame.new(0, math.sin(angle * 0.8) * 0.25, 0) * CFrame.Angles(0, angle, 0)
		for i, part in spinner.parts do
			n += 1
			spinParts[n] = part
			spinCFrames[n] = cf * spinner.offsets[i]
		end
	end
	if n > 0 then
		workspace:BulkMoveTo(spinParts, spinCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- =========================================================================
-- Popups "+N"
-- =========================================================================
local function getPopup()
	local popup = table.remove(popupPool)
	if popup then
		return popup
	end
	local attachment = Instance.new("Attachment")
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 50)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = attachment
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return { attachment = attachment, gui = gui, label = label }
end

function WorldFxController.popup(position: Vector3, text: string, color: Color3, big: boolean?)
	if activePopups >= MAX_POPUPS then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > Config.PopupMaxDistance then
		return
	end
	activePopups += 1
	local popup = getPopup()
	popup.attachment.WorldPosition = position
	popup.attachment.Parent = workspace.Terrain
	popup.gui.Size = if big then UDim2.fromOffset(220, 80) else UDim2.fromOffset(140, 50)
	popup.gui.StudsOffset = Vector3.new(0, 1.5, 0)
	popup.gui.Parent = popup.attachment
	popup.label.Text = text
	popup.label.TextColor3 = color
	popup.label.TextTransparency = 0
	popup.label.TextStrokeTransparency = 0
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup.gui, info, { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	local fade = TweenService:Create(popup.label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		popup.gui.Parent = nil
		popup.attachment.Parent = nil
		activePopups -= 1
		table.insert(popupPool, popup)
	end)
end

local function onPickupFx(list: any)
	if type(list) ~= "table" then
		return
	end
	for _, fx in list do
		if typeof(fx.pos) == "Vector3" and type(fx.amount) == "number" then
			local prefix = if fx.kind == "Gem" then "💎+" elseif fx.kind == "Chest" then "🎁+" else "+"
			local color = if typeof(fx.color) == "Color3" then fx.color else Color3.new(1, 1, 0)
			WorldFxController.popup(fx.pos, prefix .. Format.number(fx.amount), color, fx.kind == "Chest")
		end
	end
end

local function onBananaFx(position: any, kind: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	if kind == "hit" then
		WorldFxController.popup(
			position + Vector3.new(0, 3, 0),
			"🍌 SPLAT!",
			BrickColor.new("Bright yellow").Color,
			true
		)
	end
end

-- =========================================================================
-- Trampolins e porta VIP
-- =========================================================================
local lastBounce = 0

local function hookTrampoline(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) then
			return
		end
		if os.clock() - lastBounce < 0.3 then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		lastBounce = os.clock()
		local power = part:GetAttribute("Power")
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity =
			Vector3.new(velocity.X, if type(power) == "number" then power else Config.TrampolinePower, velocity.Z)
	end)
end

local function refreshVipDoors()
	local isVip = player:GetAttribute("VIP") == true
	for _, door in CollectionService:GetTagged("VipDoor") do
		if door:IsA("BasePart") then
			door.CanCollide = not isVip
			door.Transparency = if isVip then 0.75 else 0.4
		end
	end
end

local function setupChatTag()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local sender = Players:GetPlayerByUserId(source.UserId)
			if sender and sender:GetAttribute("VIP") == true then
				properties.PrefixText = '<font color="#F5CD30">[VIP]</font> ' .. message.PrefixText
			end
		end
		return properties
	end
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function WorldFxController.init(_controllers) end

function WorldFxController.start()
	for _, model in CollectionService:GetTagged("Pickup") do
		trackPickup(model)
	end
	CollectionService:GetInstanceAddedSignal("Pickup"):Connect(trackPickup)
	CollectionService:GetInstanceRemovedSignal("Pickup"):Connect(untrackPickup)
	RunService.RenderStepped:Connect(spinStep)

	for _, part in CollectionService:GetTagged("Trampoline") do
		hookTrampoline(part)
	end
	CollectionService:GetInstanceAddedSignal("Trampoline"):Connect(hookTrampoline)

	refreshVipDoors()
	CollectionService:GetInstanceAddedSignal("VipDoor"):Connect(refreshVipDoors)
	player:GetAttributeChangedSignal("VIP"):Connect(refreshVipDoors)

	Net.connect("PickupFx", onPickupFx)
	Net.connect("BananaFx", onBananaFx)
	setupChatTag()
end

return WorldFxController
