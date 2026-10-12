--[[
	BaseController.luau
	Lado do cliente das bases:
	- Animação de construção: peças novas (tag "BuildPiece") caem do céu e encaixam com
	  "clique" de Lego.
	- Porta laser: colisão LOCAL para quem não é o dono enquanto a base está trancada ou
	  protegida (o servidor também empurra invasores para fora).
	- Fitas: o prompt "Pegar fita" some para o dono e é traduzido.
	- Alertas (invasão, fita pega, fita roubada, cofre): toast vermelho com oferta, sirene
	  curta e seta na tela apontando para a base.
	- Efeitos (Fx): tapa (bastão de blocos), laser, fita voltando voando, cofre, rebirth
	  (confete), trancar. E o tapa recebido (empurrão + atordoado).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local MapLayout = require(Shared.MapLayout)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Root = require(Ui.Root)
local Theme = require(Ui.Theme)

local BaseController = {}

local Controllers
local player = Players.LocalPlayer
local fxFolder: Folder
local laserPlots: { [BasePart]: Instance } = {}
local arrow: { frame: Frame, label: TextLabel, until_: number } = nil :: any

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function BaseController.isInsideOwnBase(): boolean
	local root = myRoot()
	local plot = player:GetAttribute("PlotIndex")
	return root ~= nil and plot ~= nil and MapLayout.plotAt(root.Position.X, root.Position.Z) == plot
end

local function nearCamera(position: Vector3, distance: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= distance
end

-- =========================================================================
-- Construção animada
-- =========================================================================
local function animatePiece(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance :: BasePart
	local at = part:GetAttribute("BuildAt")
	if type(at) ~= "number" or Clock.now() - at > 3 then
		return
	end
	local order = part:GetAttribute("BuildOrder") or 1
	local target = part.CFrame
	local transparency = part.Transparency
	part.CFrame = target + Vector3.new(0, 45, 0)
	part.Transparency = 1
	task.delay(order * Config.BuildPieceStagger, function()
		if not part.Parent then
			return
		end
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local tween = TweenService:Create(part, info, { CFrame = target, Transparency = transparency })
		tween:Play()
		tween.Completed:Once(function()
			if order % 3 == 1 and nearCamera(target.Position, 160) then
				Controllers.SoundController.play("Build", { at = target.Position, pitch = 0.9 + math.random() * 0.3 })
			end
		end)
	end)
end

-- =========================================================================
-- Porta laser (colisão local) e prompts das fitas
-- =========================================================================
local function plotModelOf(instance: Instance): Instance?
	local current = instance.Parent
	while current and current ~= workspace do
		if current:GetAttribute("PlotIndex") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function trackLaser(instance: Instance)
	if instance:IsA("BasePart") then
		local plot = plotModelOf(instance)
		if plot then
			laserPlots[instance] = plot
		end
	end
end

local function updateLasers()
	local now = Clock.now()
	for laser, plot in laserPlots do
		if not laser.Parent then
			laserPlots[laser] = nil
			continue
		end
		local owner = plot:GetAttribute("OwnerId")
		local locked = (plot:GetAttribute("LockedUntil") or 0) > now
		local protected = (plot:GetAttribute("ProtectedUntil") or 0) > now
		local blocked = owner ~= nil and owner ~= player.UserId and (locked or protected)
		laser.CanCollide = blocked
		laser.Transparency = if locked then 0.15 elseif blocked then 0.7 else 1
	end
end

local function setupTapePrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local prompt = instance :: ProximityPrompt
	prompt.ActionText = I18n.t("prompt_take_tape")
	local function enforce()
		if prompt:GetAttribute("OwnerId") == player.UserId and prompt.Enabled then
			prompt.Enabled = false
		end
	end
	enforce()
	prompt:GetPropertyChangedSignal("Enabled"):Connect(enforce)
end

-- =========================================================================
-- Alertas
-- =========================================================================
local function siren()
	for i = 1, 3 do
		Controllers.SoundController.play("Siren", { pitch = if i % 2 == 1 then 1.6 else 1.25, volume = 0.9 })
		task.wait(0.22)
	end
end

local function showArrow(seconds: number)
	arrow.until_ = os.clock() + seconds
	arrow.frame.Visible = true
end

local function updateArrow()
	if not arrow.frame.Visible then
		return
	end
	local plot = player:GetAttribute("PlotIndex")
	local camera = workspace.CurrentCamera
	local root = myRoot()
	if os.clock() > arrow.until_ or not plot or not camera or not root or BaseController.isInsideOwnBase() then
		arrow.frame.Visible = false
		return
	end
	local bx, bz = MapLayout.plot(plot)
	local toBase = Vector3.new(bx - root.Position.X, 0, bz - root.Position.Z)
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if toBase.Magnitude < 1 or forward.Magnitude < 0.01 then
		return
	end
	toBase, forward = toBase.Unit, forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local angle = math.atan2(toBase:Dot(right), toBase:Dot(forward)) -- 0 = para frente (topo da tela)
	local radius = 150
	arrow.label.Position = UDim2.new(0.5, math.sin(angle) * radius, 0.5, -math.cos(angle) * radius)
	arrow.label.Rotation = math.deg(angle) - 90
end

local function onAlert(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	local Notify = Controllers.NotifyController
	local lockOffer = {
		text = I18n.t("offer_lock", { price = Config.Products.LockBase5.Price }),
		onClick = function()
			Controllers.HudController.promptProduct("LockBase5")
		end,
	}
	if kind == "invasion" then
		Notify.show(I18n.t("toast_invasion", { name = data.name }), "alert", lockOffer)
	elseif kind == "taken" then
		Notify.show(I18n.t("toast_tape_taken", { name = data.name, slot = data.slot }), "alert", lockOffer)
	elseif kind == "stolen" then
		Notify.show(I18n.t("toast_tape_stolen", { name = data.name, slot = data.slot }), "alert", {
			text = I18n.t("offer_recover", { price = Config.Products.RecoverTape.Price }),
			onClick = function()
				Controllers.HudController.promptProduct("RecoverTape")
			end,
		})
	elseif kind == "vault" then
		Notify.show(I18n.t("toast_vault_stolen", { name = data.name, n = Format.number(data.amount or 0) }), "alert")
	end
	task.spawn(siren)
	if kind ~= "stolen" then
		showArrow(8)
	end
end

-- =========================================================================
-- Efeitos
-- =========================================================================
local function fxPart(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = fxFolder
	return part
end

-- Bastão de blocos girando no braço direito por 0,3 s.
local function swing(character: Model, hit: boolean)
	local arm = character:FindFirstChild("Right Arm") :: BasePart?
	if not arm then
		return
	end
	local handle = fxPart(Vector3.new(0.4, 3.2, 0.4), arm.CFrame, BrickColor.new("Reddish brown").Color)
	local head = fxPart(Vector3.new(1.1, 1.4, 1.1), arm.CFrame, BrickColor.new("Bright red").Color)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / 0.3, 0, 1)
		if t >= 1 or not arm.Parent then
			connection:Disconnect()
			handle:Destroy()
			head:Destroy()
			return
		end
		local angle = math.rad(-110 + 200 * t)
		local base = arm.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(angle, 0, 0)
		handle.CFrame = base * CFrame.new(0, -1.6, 0)
		head.CFrame = base * CFrame.new(0, -3.4, 0)
	end)
	Controllers.SoundController.play("Slap", { at = arm.Position, pitch = if hit then 0.75 else 1.2 })
end

function BaseController.localSlapSwing()
	local character = player.Character
	if character then
		swing(character, false)
	end
end

local function confetti()
	local gui = Root.gui()
	local colors =
		{ Theme.Colors.primary, Theme.Colors.success, Theme.Colors.warning, Theme.Colors.danger, Theme.Colors.gold }
	for _ = 1, 70 do
		local piece = Builder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, 0, -20),
			Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20)),
			BackgroundColor3 = colors[math.random(1, #colors)],
			Rotation = math.random(0, 360),
			BorderSizePixel = 0,
			ZIndex = 50,
			Parent = gui,
		})
		local duration = 1.4 + math.random() * 1.2
		local tween =
			TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 1.1),
				Rotation = piece.Rotation + math.random(-360, 360),
			})
		tween:Play()
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

local function onFx(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "slap" then
		if data.userId == player.UserId then
			return -- o próprio jogador já viu o golpe na hora (localSlapSwing)
		end
		local other = Players:GetPlayerByUserId(data.userId)
		if other and other.Character then
			swing(other.Character, data.hit == true)
		end
	elseif kind == "laser" then
		if typeof(data.from) ~= "Vector3" or typeof(data.to) ~= "Vector3" then
			return
		end
		local distance = (data.to - data.from).Magnitude
		local beam = fxPart(
			Vector3.new(0.35, 0.35, distance),
			CFrame.lookAt((data.from + data.to) / 2, data.to),
			Theme.Colors.danger,
			Enum.Material.Neon
		)
		TweenService:Create(beam, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(0.05, 0.05, distance) })
			:Play()
		task.delay(0.4, function()
			beam:Destroy()
		end)
		Controllers.SoundController.play("Laser", { at = data.from, pitch = 1.6 })
	elseif kind == "tapeReturn" then
		if typeof(data.from) ~= "Vector3" or typeof(data.to) ~= "Vector3" then
			return
		end
		local tape = fxPart(
			Vector3.new(0.6, 1.5, 2.6),
			CFrame.new(data.from),
			BrickColor.new(data.color or "Black").Color,
			Enum.Material.Neon
		)
		local alpha = Instance.new("NumberValue")
		alpha.Changed:Connect(function(t)
			local p = data.from:Lerp(data.to, t) + Vector3.new(0, math.sin(t * math.pi) * 10, 0)
			tape.CFrame = CFrame.new(p) * CFrame.Angles(0, t * math.pi * 4, 0)
		end)
		local tween = TweenService:Create(alpha, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Value = 1 })
		tween:Play()
		tween.Completed:Once(function()
			tape:Destroy()
			alpha:Destroy()
		end)
	elseif kind == "vault" then
		if typeof(data.position) == "Vector3" then
			local color = if typeof(data.color) == "Color3" then data.color else Theme.Colors.gold
			Controllers.WorldFxController.popup(
				data.position + Vector3.new(0, 4, 0),
				"💰+" .. Format.number(data.amount or 0),
				color,
				true
			)
			Controllers.SoundController.play("Coin", { at = data.position, pitch = 0.8 })
		end
	elseif kind == "rebirth" then
		if data.userId == player.UserId then
			confetti()
			Controllers.SoundController.play("Rebirth", { pitch = 0.8 })
		else
			local other = Players:GetPlayerByUserId(data.userId)
			local head = other and other.Character and other.Character:FindFirstChild("Head") :: BasePart?
			if head then
				Controllers.WorldFxController.popup(
					head.Position + Vector3.new(0, 2, 0),
					"🔁 REBIRTH!",
					Theme.Colors.success,
					true
				)
			end
		end
	elseif kind == "lock" then
		if type(data.plot) == "number" then
			local gx, gz = MapLayout.point(data.plot, "Gate")
			local position = Vector3.new(gx, 6, gz)
			if nearCamera(position, 150) then
				Controllers.SoundController.play("Laser", { at = position, pitch = 0.7 })
			end
		end
	end
end

-- Levou um tapa: empurrão e alguns instantes sem controle.
local function onSlapped(impulse: any, stun: any)
	local root = myRoot()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or typeof(impulse) ~= "Vector3" then
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = impulse
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	task.delay(if type(stun) == "number" then math.clamp(stun, 0.2, 3) else 1, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function BaseController.init(controllers)
	Controllers = controllers
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFx"
	fxFolder.Parent = workspace

	local frame =
		Root.container("AlertArrow", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(400, 400), 6)
	frame.Visible = false
	local label = Builder.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(80, 80),
		Text = "➤",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 64,
		TextColor3 = Theme.Colors.danger,
		Parent = frame,
	})
	Builder.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(300, 40),
		Text = I18n.t("invasion_arrow"),
		FontFace = Theme.Fonts.Heavy,
		TextSize = 26,
		TextColor3 = Theme.Colors.danger,
		Parent = frame,
	})
	arrow = { frame = frame, label = label, until_ = 0 }
end

function BaseController.start()
	for _, part in CollectionService:GetTagged("BuildPiece") do
		animatePiece(part)
	end
	CollectionService:GetInstanceAddedSignal("BuildPiece"):Connect(animatePiece)
	for _, laser in CollectionService:GetTagged("GateLaser") do
		trackLaser(laser)
	end
	CollectionService:GetInstanceAddedSignal("GateLaser"):Connect(trackLaser)
	for _, prompt in CollectionService:GetTagged("TapePrompt") do
		setupTapePrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("TapePrompt"):Connect(setupTapePrompt)

	Net.connect("Alert", onAlert)
	Net.connect("Fx", onFx)
	Net.connect("Slapped", onSlapped)

	task.spawn(function()
		while true do
			task.wait(0.2)
			updateLasers()
		end
	end)
	RunService.RenderStepped:Connect(updateArrow)
end

return BaseController
