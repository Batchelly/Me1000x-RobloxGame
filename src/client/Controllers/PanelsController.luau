--[[
	PanelsController.luau
	Modais de Rebirth, Recompensa diária (+ grupo), Códigos e Retorno offline, no design
	system v2. (Base e Fitas ficam no BaseMenuController; Configurações no SettingsController.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Root = require(Ui.Root)
local Theme = require(Ui.Theme)
local Button = require(Ui.Components.Button)
local Modal = require(Ui.Components.Modal)

local PanelsController = {}

local Controllers
local refs = {} :: { [string]: any }
local rebirthModal: Modal.Modal
local dailyModal: Modal.Modal
local codesModal: Modal.Modal
local offlineModal: Modal.Modal
local offlineShownFor: number? = nil
local firstState = true

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	return Builder.label(props)
end

local function rewardText(reward: { [string]: number }, rebirths: number): string
	local parts = {}
	if reward.Cash then
		table.insert(parts, I18n.t("reward_cash", { n = Format.number(reward.Cash * (1 + rebirths)) }))
	end
	if reward.Bananas then
		table.insert(parts, I18n.t("reward_bananas", { n = reward.Bananas }))
	end
	if reward.ShieldSeconds then
		table.insert(parts, I18n.t("reward_shield", { t = Format.time(reward.ShieldSeconds) }))
	end
	return table.concat(parts, "\n")
end

-- =========================================================================
-- Rebirth
-- =========================================================================
local function buildRebirth()
	rebirthModal = Modal.new({
		Title = I18n.t("rebirth_title"),
		Icon = "🔁",
		Size = Vector2.new(540, 400),
		Accent = Theme.Colors.success,
	})
	local content = rebirthModal.content
	Builder.list(content, 10).VerticalAlignment = Enum.VerticalAlignment.Top
	refs.rebirthMult = text(content, {
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.Fonts.Heavy,
		TextSize = 32,
		TextColor3 = Theme.Colors.success,
		LayoutOrder = 1,
		Text = "",
	})
	refs.rebirthCost = text(content, {
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = Theme.Fonts.Bold,
		TextSize = 22,
		LayoutOrder = 2,
		Text = "",
	})
	text(content, {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 18,
		TextColor3 = Theme.Colors.textDim,
		LayoutOrder = 3,
		Text = "➕ " .. I18n.t("rebirth_slot") .. "     ⚠️ " .. I18n.t("rebirth_resets"),
	})
	local bar = Builder.create("Frame", {
		Size = UDim2.new(1, -40, 0, 14),
		BackgroundColor3 = Theme.Colors.bgLighter,
		LayoutOrder = 4,
		Parent = content,
	})
	Builder.corner(bar, 7)
	refs.rebirthFill = Builder.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.success,
		Parent = bar,
	})
	Builder.corner(refs.rebirthFill, 7)
	refs.rebirthButton = Button.new({
		Text = I18n.t("rebirth_button"),
		Variant = "success",
		Size = UDim2.fromOffset(320, 72),
		TextSize = 28,
		LayoutOrder = 5,
		OnClick = function()
			local ok, reason = Net.invoke("Rebirth")
			if ok then
				rebirthModal.close()
			else
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = content,
	})
end

local function refreshRebirth(state)
	refs.rebirthMult.Text = I18n.t("rebirth_mult", {
		a = Format.multiplier(state.multiplier),
		b = Format.multiplier(state.nextMultiplier),
	})
	refs.rebirthCost.Text = I18n.t("rebirth_cost", { cost = Format.number(state.rebirthCost) })
	local progress = math.clamp(state.cash / math.max(1, state.rebirthCost), 0, 1)
	TweenService:Create(refs.rebirthFill, Theme.Tween.Open, { Size = UDim2.fromScale(progress, 1) }):Play()
	if state.cash >= state.rebirthCost then
		refs.rebirthButton:setButton(I18n.t("rebirth_button"), true)
	else
		refs.rebirthButton:setButton(
			I18n.t("rebirth_need", { n = Format.number(state.rebirthCost - state.cash) }),
			false
		)
	end
end

function PanelsController.openRebirth()
	local state = Controllers.StateController.get()
	if state then
		refreshRebirth(state)
	end
	rebirthModal.open()
end

-- =========================================================================
-- Recompensa diária + grupo
-- =========================================================================
local function buildDaily()
	dailyModal = Modal.new({
		Title = I18n.t("daily_title"),
		Icon = "🎁",
		Size = Vector2.new(700, 400),
		Accent = Theme.Colors.warning,
	})
	local content = dailyModal.content
	local row =
		Builder.create("Frame", { Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1, Parent = content })
	Builder.list(row, 8, true)
	refs.dailyBoxes = {}
	for day = 1, #Config.DailyRewards do
		local box = Builder.create("Frame", {
			Size = UDim2.fromOffset(88, 128),
			BackgroundColor3 = Theme.Colors.bgLight,
			LayoutOrder = day,
			Parent = row,
		})
		Builder.corner(box, Theme.Radius.S)
		local stroke = Builder.stroke(box)
		text(box, {
			Size = UDim2.new(1, 0, 0, 30),
			FontFace = Theme.Fonts.Bold,
			TextSize = 18,
			Text = I18n.t("daily_day", { n = day }),
		})
		local reward = text(box, {
			Position = UDim2.fromOffset(4, 32),
			Size = UDim2.new(1, -8, 1, -36),
			TextSize = 15,
			TextScaled = true,
			Text = "",
		})
		refs.dailyBoxes[day] = { box = box, reward = reward, stroke = stroke }
	end
	refs.dailyButton = Button.new({
		Text = I18n.t("daily_claim"),
		Variant = "success",
		Size = UDim2.fromOffset(280, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 144),
		TextSize = 26,
		OnClick = function()
			local ok, reason = Net.invoke("ClaimDaily")
			if ok then
				Controllers.SoundController.play("Coin", { pitch = 0.9 })
			else
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = content,
	})

	local group = Builder.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundColor3 = Theme.Colors.bgLight,
		Visible = Config.GroupId ~= 0,
		Parent = content,
	})
	Builder.corner(group, Theme.Radius.S)
	Builder.stroke(group)
	text(group, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -220, 1, 0),
		FontFace = Theme.Fonts.Bold,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "👥 " .. I18n.t("group_desc"),
	})
	refs.groupButton = Button.new({
		Text = I18n.t("group_claim"),
		Variant = "primary",
		Size = UDim2.fromOffset(180, 64),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		OnClick = function()
			local ok, reason = Net.invoke("ClaimGroup")
			if not ok then
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = group,
	})
end

local function refreshDaily(state)
	local info = state.daily
	for day, box in refs.dailyBoxes do
		box.reward.Text = rewardText(Config.DailyRewards[day], state.rebirths)
		local today = info.available and day == info.day
		local done = (not info.available and day <= info.day) or (info.available and day < info.day)
		box.box.BackgroundColor3 = if today
			then Theme.Colors.primary
			elseif done then Theme.Colors.bgLighter
			else Theme.Colors.bgLight
		box.stroke.Color = if today then Theme.Colors.warning else Theme.Colors.stroke
		box.stroke.Transparency = if today then 0 else Theme.StrokeTransparency
	end
	if info.available then
		refs.dailyButton:setButton(I18n.t("daily_claim"), true)
	else
		refs.dailyButton:setButton(I18n.t("daily_claimed"), false)
	end
	refs.groupButton:setButton(
		if state.groupClaimed then I18n.t("owned") else I18n.t("group_claim"),
		not state.groupClaimed
	)
end

function PanelsController.openDaily()
	local state = Controllers.StateController.get()
	if state then
		refreshDaily(state)
	end
	dailyModal.open()
end

-- =========================================================================
-- Códigos
-- =========================================================================
local function buildCodes()
	codesModal = Modal.new({ Title = I18n.t("codes_title"), Icon = "🎟️", Size = Vector2.new(500, 280) })
	local content = codesModal.content
	local box = Builder.create("TextBox", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.Colors.bgLight,
		PlaceholderText = I18n.t("codes_placeholder"),
		PlaceholderColor3 = Theme.Colors.textDim,
		Text = "",
		FontFace = Theme.Fonts.Bold,
		TextSize = 26,
		TextColor3 = Theme.Colors.text,
		ClearTextOnFocus = false,
		Parent = content,
	})
	Builder.corner(box, Theme.Radius.S)
	Builder.stroke(box, 2, Theme.Colors.primary, 0.3)
	Button.new({
		Text = I18n.t("codes_redeem"),
		Variant = "success",
		Size = UDim2.fromOffset(240, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		TextSize = 24,
		OnClick = function()
			local ok, reason = Net.invoke("RedeemCode", box.Text)
			if ok then
				box.Text = ""
				codesModal.close()
			else
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = content,
	})
end

function PanelsController.openCodes()
	codesModal.open()
end

-- =========================================================================
-- Retorno offline
-- =========================================================================
local function buildOffline()
	offlineModal = Modal.new({
		Title = I18n.t("offline_title"),
		Icon = "🌙",
		Size = Vector2.new(580, 340),
		Accent = Theme.Colors.warning,
	})
	local content = offlineModal.content
	refs.offlineBody = text(content, { Size = UDim2.new(1, 0, 0, 52), TextSize = 20, Text = "" })
	refs.offlineAmount = text(content, {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 76),
		FontFace = Theme.Fonts.Heavy,
		TextSize = 60,
		TextColor3 = Theme.Colors.gold,
		Text = "",
	})
	Button.new({
		Text = I18n.t("offline_collect"),
		Variant = "success",
		Size = UDim2.fromOffset(230, 68),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		TextSize = 26,
		OnClick = function()
			offlineModal.close()
		end,
		Parent = content,
	})
	Button.new({
		Text = I18n.t("offline_double", { price = Config.Products.DoubleOffline.Price }),
		Variant = "warning",
		Size = UDim2.fromOffset(270, 68),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -6),
		TextSize = 22,
		OnClick = function()
			Controllers.HudController.promptProduct("DoubleOffline")
		end,
		Parent = content,
	})
	offlineModal.onClose(function()
		Net.invoke("DismissOffline")
		local state = Controllers.StateController.get()
		if state and state.daily.available then
			task.wait(0.3)
			PanelsController.openDaily()
		end
	end)
end

local function showOffline(offline)
	refs.offlineBody.Text = I18n.t("offline_body", { time = Format.minutes(offline.minutes) })
	refs.offlineAmount.Text = "💰 " .. Format.number(offline.amount)
	offlineModal.open()
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function PanelsController.init(controllers)
	Controllers = controllers
	buildRebirth()
	buildDaily()
	buildCodes()
	buildOffline()
end

function PanelsController.start()
	Controllers.StateController.changed:Connect(function(state)
		if rebirthModal.isOpen() then
			refreshRebirth(state)
		end
		if dailyModal.isOpen() then
			refreshDaily(state)
		end
		-- Comprou "Dobrar": o servidor já creditou e limpou o ganho pendente.
		if offlineModal.isOpen() and not state.offline then
			offlineModal.close()
		end
		if state.offline and offlineShownFor ~= state.offline.amount then
			offlineShownFor = state.offline.amount
			showOffline(state.offline)
		elseif firstState and state.daily.available and not Root.anyModalOpen() then
			PanelsController.openDaily()
		end
		firstState = false
	end)
end

return PanelsController
