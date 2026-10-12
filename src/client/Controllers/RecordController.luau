--[[
	RecordController.luau
	Botão GRAVAR (HUD ou tecla R): anel de progresso no próprio botão, chip "GRAVANDO" no topo
	e rastro visual (Trail + bolinhas) durante a gravação. Quem grava de verdade é o servidor
	(RecordingService); aqui é só pedido + feedback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local I18n = require(Ui.I18n)
local Theme = require(Ui.Theme)

local RecordController = {}

local Controllers
local player = Players.LocalPlayer

local recording = false
local startedAt = 0
local duration = 0
local zone = "city"
local trail: Trail? = nil
local trailAttachments: { Attachment } = {}
local crumbs: { BasePart } = {}
local crumbFolder: Folder
local lastCrumb = 0
local requestPending = false

local function ownColor(): Color3
	local color = player:GetAttribute("BaseColor")
	return if typeof(color) == "Color3" then color else Theme.Colors.danger
end

local function clearTrail()
	if trail then
		trail:Destroy()
		trail = nil
	end
	for _, attachment in trailAttachments do
		attachment:Destroy()
	end
	table.clear(trailAttachments)
	for _, crumb in crumbs do
		local tween = TweenService:Create(crumb, TweenInfo.new(1.2), { Transparency = 1, Size = Vector3.zero })
		tween:Play()
		task.delay(1.3, function()
			crumb:Destroy()
		end)
	end
	table.clear(crumbs)
end

local function makeTrail()
	clearTrail()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 1.5
	t.Color = ColorSequence.new(ownColor())
	t.Transparency = NumberSequence.new(0.2, 1)
	t.LightEmission = 0.5
	t.FaceCamera = true
	t.Parent = root
	trail = t
	trailAttachments = { a0, a1 }
end

local function dropCrumb()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local crumb = Instance.new("Part")
	crumb.Shape = Enum.PartType.Ball
	crumb.Size = Vector3.new(0.7, 0.7, 0.7)
	crumb.Anchored = true
	crumb.CanCollide = false
	crumb.CanQuery = false
	crumb.CanTouch = false
	crumb.CastShadow = false
	crumb.Material = Enum.Material.Neon
	crumb.Color = ownColor()
	crumb.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.4, 0))
	crumb.Parent = crumbFolder
	table.insert(crumbs, crumb)
end

local function setRecording(value: boolean)
	recording = value
	Controllers.HudController.setRecording(value, 0, duration, zone)
	if value then
		makeTrail()
	else
		clearTrail()
	end
end

-- Pede ao servidor para começar/parar. replaceSlot = fita a substituir (estante cheia).
function RecordController.toggle(replaceSlot: number?)
	if requestPending then
		return
	end
	requestPending = true
	task.delay(0.4, function()
		requestPending = false
	end)
	Net.send("Record", if replaceSlot then "start" else "toggle", replaceSlot)
end

function RecordController.isRecording(): boolean
	return recording
end

local function onRecordState(status: string, data: any)
	local Notify = Controllers.NotifyController
	if status == "start" then
		duration = data.duration
		zone = data.zone or "city"
		-- Converte o início do relógio do servidor para o relógio local.
		startedAt = os.clock() - math.max(0, Clock.now() - data.startedAt)
		setRecording(true)
		Controllers.SoundController.play("Open", { pitch = 1.4 })
	elseif status == "need_replace" then
		Notify.show(I18n.t("reason_need_replace"), "warn")
		Controllers.BaseMenuController.openClones(function(slot)
			RecordController.toggle(slot)
		end)
	else
		setRecording(false)
		if status == "done" then
			Notify.show(I18n.t("toast_clone_created", { slot = data.slot }), "good")
			Controllers.SoundController.play("Build", { pitch = 1.2 })
		elseif status == "short" then
			Notify.show(I18n.t("toast_record_short", { s = data.min }), "warn")
		elseif status == "invalid" then
			Notify.show(I18n.t("toast_record_invalid"), "warn")
		elseif status == "died" then
			Notify.show(I18n.t("toast_record_died"), "warn")
		else
			Notify.show(I18n.t("toast_record_cancel"), "warn")
		end
	end
end

function RecordController.init(controllers)
	Controllers = controllers
	crumbFolder = Instance.new("Folder")
	crumbFolder.Name = "RecordCrumbs"
	crumbFolder.Parent = workspace
end

function RecordController.start()
	Net.connect("RecordState", onRecordState)
	RunService.RenderStepped:Connect(function()
		if not recording then
			return
		end
		local elapsed = os.clock() - startedAt
		local left = math.max(0, duration - elapsed)
		Controllers.HudController.setRecording(true, elapsed / math.max(duration, 0.1), left, zone)
		if os.clock() - lastCrumb >= 0.25 then
			lastCrumb = os.clock()
			dropCrumb()
		end
	end)
	-- Personagem novo: garante que o rastro antigo some.
	player.CharacterAdded:Connect(function()
		if recording then
			setRecording(false)
		end
	end)
end

return RecordController
