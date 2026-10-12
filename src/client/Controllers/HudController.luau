--[[
	HudController.luau
	HUD v2 (design system em Ui/):
		topo        : pílula de Cash (contador animado) + chip do multiplicador; linha de
		              status (gravando, chuva de moedas, escudo, clones caídos + "Consertar")
		esquerda    : barra só de ícones com tooltip e badge (Loja, Base, Fitas, Rebirth,
		              Diário, Códigos, Config, Ir para Base/Cidade). No celular vira grade 4x2
		              no topo-esquerdo para não ficar em cima do joystick.
		direita     : cartões (Fitas x/y, Cofre com barra, Bananas, Porta)
		inf.-dir.   : GRAVAR circular com anel de progresso (pulsa quando parado) +
		              Banana, Tapa e Trancar (este só dentro da própria base)
	Atalhos: R gravar, B banana, F tapa, L trancar, T teleporte.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Root = require(Ui.Root)
local Theme = require(Ui.Theme)
local Button = require(Ui.Components.Button)
local Counter = require(Ui.Components.Counter)
local IconButton = require(Ui.Components.IconButton)
local Panel = require(Ui.Components.Panel)
local ProgressRing = require(Ui.Components.ProgressRing)

local HudController = {}

local Controllers
local player = Players.LocalPlayer

local refs = {} :: { [string]: any }
local recording = false
local pulseTween: Tween? = nil

-- =========================================================================
-- Compras (IDs zerados = "em breve")
-- =========================================================================
function HudController.promptProduct(key: string)
	local info = Config.Products[key]
	if not info or info.Id == 0 then
		Controllers.NotifyController.show(I18n.t("soon"), "info")
		return
	end
	MarketplaceService:PromptProductPurchase(player, info.Id)
end

function HudController.promptPass(key: string)
	local info = Config.GamePasses[key]
	if not info or info.Id == 0 then
		Controllers.NotifyController.show(I18n.t("soon"), "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, info.Id)
end

-- =========================================================================
-- Ações
-- =========================================================================
local function placeBanana()
	local ok, reason = Net.invoke("PlaceBanana")
	if ok then
		Controllers.NotifyController.show(I18n.t("toast_banana_placed"), "good")
	else
		Controllers.NotifyController.reason(reason)
	end
end

local function slap()
	Net.send("Slap")
	Controllers.BaseController.localSlapSwing()
end

local function lockBase()
	local ok, reason = Net.invoke("LockBase")
	if not ok then
		Controllers.NotifyController.reason(reason)
	end
end

function HudController.teleport()
	local destination = if Controllers.BaseController.isInsideOwnBase() then "city" else "base"
	local ok, reason = Net.invoke("Teleport", destination)
	if not ok then
		Controllers.NotifyController.reason(reason)
	end
end

-- =========================================================================
-- Construção
-- =========================================================================
local function chip(parent: Instance, order: number, color: Color3): (Frame, TextLabel)
	local frame = Builder.create("Frame", {
		Name = "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 38),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = Theme.PanelTransparency,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	})
	Builder.corner(frame, 19)
	Builder.stroke(frame, 1.5, color, 0.3)
	local padding = Builder.padding(frame, 6)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	Builder.list(frame, 8, true)
	local label = Builder.label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		FontFace = Theme.Fonts.Bold,
		TextSize = 18,
		TextWrapped = false,
		Text = "",
		LayoutOrder = 1,
		Parent = frame,
	})
	return frame, label
end

local function buildTop()
	local top = Root.container("Top", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(620, 110))
	local pill = Panel.new({
		Size = UDim2.fromOffset(330, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Radius = 31,
		Parent = top,
	})
	local body = pill.Instance
	Builder.icon("Cash", 40, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
	}).Parent =
		body
	local cash = Builder.label({
		Name = "Cash",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		Size = UDim2.new(1, -160, 1, -8),
		FontFace = Theme.Fonts.Heavy,
		TextSize = 36,
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0",
		Parent = body,
	})
	refs.cash = Counter.new(cash, Format.number)
	local mult = Builder.label({
		Name = "Multiplier",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(78, 38),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.success,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 20,
		TextColor3 = Theme.Colors.textDark,
		Text = "x1",
		Parent = body,
	})
	Builder.corner(mult, 19)
	Builder.gradient(mult)
	refs.mult = mult

	local row = Builder.create("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = top,
	})
	Builder.list(row, 8, true)
	refs.recordChip, refs.recordChipLabel = chip(row, 1, Theme.Colors.danger)
	refs.rainChip, refs.rainChipLabel = chip(row, 2, Theme.Colors.primary)
	refs.shieldChip, refs.shieldChipLabel = chip(row, 3, Theme.Colors.success)
	refs.fallenChip, refs.fallenChipLabel = chip(row, 4, Theme.Colors.danger)
	local fix = Button.new({
		Text = I18n.t("fix_all", { price = Config.Products.FixAllClones.Price }),
		Variant = "warning",
		Size = UDim2.fromOffset(170, 28),
		TextSize = 15,
		OnClick = function()
			HudController.promptProduct("FixAllClones")
		end,
		Parent = refs.fallenChip,
	})
	fix.Instance.LayoutOrder = 2
end

local MENU = {
	{ icon = "Shop", key = "btn_shop", action = "shop" },
	{ icon = "Base", key = "btn_base", action = "base" },
	{ icon = "Clones", key = "btn_clones", action = "clones" },
	{ icon = "Rebirth", key = "btn_rebirth", action = "rebirth" },
	{ icon = "Daily", key = "btn_daily", action = "daily" },
	{ icon = "Codes", key = "btn_codes", action = "codes" },
	{ icon = "Settings", key = "btn_settings", action = "settings" },
}

local function buildMenu()
	local touch = Root.isTouch()
	local size = 64
	local gap = 8
	local count = #MENU + 1
	local menu
	if touch then
		-- grade 4x2 no topo-esquerdo (longe do joystick)
		menu = Root.container(
			"Menu",
			Vector2.zero,
			UDim2.fromOffset(10, 10),
			UDim2.fromOffset(4 * size + 3 * gap, 2 * size + gap)
		)
		Builder.grid(menu, Vector2.new(size, size), gap)
	else
		menu = Root.container(
			"Menu",
			Vector2.new(0, 0.5),
			UDim2.new(0, 12, 0.5, 0),
			UDim2.fromOffset(size, count * size + (count - 1) * gap)
		)
		Builder.list(menu, gap)
	end
	local actions = {
		shop = function()
			Controllers.ShopController.open()
		end,
		base = function()
			Controllers.BaseMenuController.openBase()
		end,
		clones = function()
			Controllers.BaseMenuController.openClones(nil)
		end,
		rebirth = function()
			Controllers.PanelsController.openRebirth()
		end,
		daily = function()
			Controllers.PanelsController.openDaily()
		end,
		codes = function()
			Controllers.PanelsController.openCodes()
		end,
		settings = function()
			Controllers.SettingsController.open()
		end,
	}
	refs.menu = {}
	for i, item in MENU do
		refs.menu[item.action] = IconButton.new({
			Icon = item.icon,
			Tooltip = I18n.t(item.key),
			Size = size,
			LayoutOrder = i,
			OnClick = actions[item.action],
			Parent = menu,
		})
	end
	refs.teleport = IconButton.new({
		Icon = "Home",
		Tooltip = I18n.t("go_base"),
		Size = size,
		LayoutOrder = count,
		Color = Theme.Colors.primary,
		OnClick = HudController.teleport,
		Parent = menu,
	})
end

local function card(parent: Instance, order: number, icon: string): (Frame, TextLabel)
	local panel = Panel.new({ Size = UDim2.fromOffset(230, 52), LayoutOrder = order, Radius = 16, Parent = parent })
	Builder.icon(icon, 30, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
	}).Parent =
		panel.Instance
	local label = Builder.label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 48, 0.5, 0),
		Size = UDim2.new(1, -56, 1, -8),
		FontFace = Theme.Fonts.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextScaled = false,
		Text = "",
		Parent = panel.Instance,
	})
	return panel.Instance, label
end

local function buildCards()
	local cards =
		Root.container("Cards", Vector2.new(1, 0), UDim2.new(1, -10, 0, 10), UDim2.fromOffset(230, 4 * 52 + 3 * 8))
	local layout = Builder.list(cards, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	local _, clones = card(cards, 1, "Clones")
	refs.clones = clones
	local vaultCard, vault = card(cards, 2, "Vault")
	refs.vault = vault
	vault.Position = UDim2.new(0, 48, 0.5, -6)
	vault.Size = UDim2.new(1, -56, 0, 22)
	local track = Builder.create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 48, 1, -8),
		Size = UDim2.new(1, -60, 0, 6),
		BackgroundColor3 = Theme.Colors.bgLighter,
		Parent = vaultCard,
	})
	Builder.corner(track, 3)
	refs.vaultFill = Builder.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.gold,
		Parent = track,
	})
	Builder.corner(refs.vaultFill, 3)
	local _, bananas = card(cards, 3, "Banana")
	refs.bananas = bananas
	local _, door = card(cards, 4, "Lock")
	refs.door = door
end

local function buildActions()
	local touch = Root.isTouch()
	local actions = Root.container(
		"Actions",
		Vector2.new(1, 1),
		-- No celular, à esquerda do botão de pulo do Roblox.
		if touch then UDim2.new(1, -150, 1, -12) else UDim2.new(1, -16, 1, -16),
		UDim2.fromOffset(260, 236)
	)

	-- GRAVAR circular com anel de progresso
	local holder = Builder.create("Frame", {
		Name = "RecordHolder",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(176, 176),
		BackgroundTransparency = 1,
		Parent = actions,
	})
	local pulse = Builder.create("UIScale", { Parent = holder })
	refs.pulse = pulse
	local record = Builder.create("TextButton", {
		Name = "Record",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = Theme.Colors.danger,
		AutoButtonColor = false,
		Text = "⏺\n" .. I18n.t("btn_record"),
		FontFace = Theme.Fonts.Heavy,
		TextSize = 26,
		TextColor3 = Theme.Colors.text,
		Parent = holder,
	})
	Builder.corner(record, 75)
	Builder.stroke(record, 3, Theme.Colors.stroke, 0.6)
	Builder.gradient(record, 0.25)
	Button.attachMotion(record)
	record.Activated:Connect(function()
		Controllers.RecordController.toggle()
	end)
	refs.record = record
	refs.ring = ProgressRing.new(holder, 176, 7, Theme.Colors.gold)

	refs.recordHint = Builder.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -180),
		Size = UDim2.fromOffset(260, 36),
		FontFace = Theme.Fonts.Heavy,
		Text = "⬇ " .. I18n.t("btn_record") .. "! ⬇",
		TextSize = 24,
		TextColor3 = Theme.Colors.gold,
		Visible = false,
		Parent = actions,
	})

	-- Botões menores à esquerda do GRAVAR
	local column = Builder.create("Frame", {
		Name = "Small",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(72, 3 * 72 + 2 * 8),
		BackgroundTransparency = 1,
		Parent = actions,
	})
	local layout = Builder.list(column, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	refs.lock = IconButton.new({
		Icon = "Lock",
		Tooltip = I18n.t("btn_lock"),
		TooltipSide = "left",
		Size = 72,
		LayoutOrder = 1,
		Color = Theme.Colors.danger,
		OnClick = lockBase,
		Parent = column,
	})
	refs.lock.Instance.Visible = false
	IconButton.new({
		Icon = "Slap",
		Tooltip = I18n.t("btn_slap"),
		TooltipSide = "left",
		Size = 72,
		LayoutOrder = 2,
		Color = Theme.Colors.primary,
		OnClick = slap,
		Parent = column,
	})
	IconButton.new({
		Icon = "Banana",
		Tooltip = I18n.t("btn_banana"),
		TooltipSide = "left",
		Size = 72,
		LayoutOrder = 3,
		Color = Theme.Colors.warning,
		OnClick = placeBanana,
		Parent = column,
	})
end

local function startPulse()
	if pulseTween then
		pulseTween:Cancel()
	end
	refs.pulse.Scale = 1
	pulseTween = TweenService:Create(
		refs.pulse,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.04 }
	)
	pulseTween:Play()
end

-- =========================================================================
-- Atualização
-- =========================================================================
function HudController.setRecording(isRecording: boolean, progress: number?, secondsLeft: number?, zone: string?)
	local button: TextButton = refs.record
	if isRecording then
		button.Text = string.format("⏹\n%d", math.ceil(secondsLeft or 0))
		button.BackgroundColor3 = Theme.Colors.bgLighter
		refs.ring:set(progress or 0)
		refs.recordChip.Visible = true
		refs.recordChipLabel.Text = string.format(
			"⏺ %s %ds · %s",
			I18n.t("recording"),
			math.ceil(secondsLeft or 0),
			I18n.t(if zone == "track" then "record_where_track" else "record_where_city")
		)
		if not recording and pulseTween then
			pulseTween:Cancel()
			refs.pulse.Scale = 1
		end
	else
		button.Text = "⏺\n" .. I18n.t("btn_record")
		button.BackgroundColor3 = Theme.Colors.danger
		refs.ring:set(0)
		refs.recordChip.Visible = false
		if recording then
			startPulse()
		end
	end
	recording = isRecording
end

local function doorText(state): string
	local now = Clock.now()
	if now < state.lockedUntil then
		return I18n.t("door_locked", { t = Format.time(state.lockedUntil - now) })
	elseif now < state.protectedUntil then
		return I18n.t("door_protected", { t = Format.time(state.protectedUntil - now) })
	elseif now < state.cooldownUntil then
		return I18n.t("door_open") .. "  " .. I18n.t("door_cooldown", { t = Format.time(state.cooldownUntil - now) })
	end
	return I18n.t("door_open")
end

local function refreshTimers()
	local StateController = Controllers.StateController
	local state = StateController.get()
	if not state then
		return
	end
	local refill = StateController.timeLeft("bananaRefillLeft")
	refs.bananas.Text = I18n.t("card_bananas")
		.. "  "
		.. state.bananas
		.. (if refill > 0 then "  · " .. I18n.t("banana_refill", { t = Format.time(refill) }) else "")
	local shield = StateController.timeLeft("shieldLeft")
	refs.shieldChip.Visible = shield > 0
	refs.shieldChipLabel.Text = "🛡️ " .. I18n.t("shield", { t = Format.time(shield) })
	local rain = StateController.timeLeft("coinRainLeft")
	refs.rainChip.Visible = rain > 0
	refs.rainChipLabel.Text = I18n.t("coin_rain_active", { t = Format.time(rain) })
	refs.door.Text = I18n.t("card_door") .. "  " .. doorText(state)

	-- Trancar só aparece dentro da própria base; teleporte troca de destino.
	local inside = Controllers.BaseController.isInsideOwnBase()
	refs.lock.Instance.Visible = inside
	local teleport = refs.teleport
	teleport:setIcon(if inside then "City" else "Home")
	if teleport.Tooltip then
		teleport.Tooltip.Text = I18n.t(if inside then "go_city" else "go_base")
	end
end

function HudController.update(state)
	refs.cash:set(state.cash)
	refs.mult.Text = Format.multiplier(state.multiplier)
	refs.clones.Text = I18n.t("card_clones") .. "  " .. I18n.t("clones", { n = state.cloneCount, max = state.slots })
	local capacity = math.max(1, state.vaultCapacity)
	local full = state.vaultCash >= capacity
	refs.vault.Text = string.format(
		"%s  %s / %s%s",
		I18n.t("card_vault"),
		Format.number(state.vaultCash),
		Format.number(capacity),
		if full then "  " .. I18n.t("vault_full") else ""
	)
	refs.vault.TextColor3 = if full then Theme.Colors.danger else Theme.Colors.text
	TweenService:Create(refs.vaultFill, Theme.Tween.Open, {
		Size = UDim2.fromScale(math.clamp(state.vaultCash / capacity, 0, 1), 1),
	}):Play()
	refs.fallenChip.Visible = state.fallenCount > 0
	refs.fallenChipLabel.Text = I18n.t("fallen_warning", { n = state.fallenCount })
	refs.menu.daily:setBadge(state.daily ~= nil and state.daily.available)
	refs.menu.base:setBadge(state.nextLevelPrice ~= nil and state.cash >= state.nextLevelPrice)
	refs.menu.rebirth:setBadge(state.cash >= state.rebirthCost)
	refs.recordHint.Visible = state.cloneCount == 0 and not state.recording
	refreshTimers()
end

function HudController.init(controllers)
	Controllers = controllers
	buildTop()
	buildMenu()
	buildCards()
	buildActions()
end

function HudController.start()
	startPulse()
	Controllers.StateController.changed:Connect(HudController.update)
	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshTimers()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.R then
			Controllers.RecordController.toggle()
		elseif key == Enum.KeyCode.B then
			placeBanana()
		elseif key == Enum.KeyCode.F then
			slap()
		elseif key == Enum.KeyCode.L then
			lockBase()
		elseif key == Enum.KeyCode.T then
			HudController.teleport()
		end
	end)
end

return HudController
