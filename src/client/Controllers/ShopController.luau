--[[
	ShopController.luau
	Loja: modal com abas Upgrades (Cash), Passes e Produtos (Robux). Cards em grade com
	ícone, nome, descrição curta e preço no botão. Um item por aba tem o selo "MAIS POPULAR".
	IDs zerados em Config mostram "Em breve".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Theme = require(Ui.Theme)
local Card = require(Ui.Components.Card)
local Modal = require(Ui.Components.Modal)
local Tab = require(Ui.Components.Tab)

local ShopController = {}

local Controllers
local modal: Modal.Modal
local tabs
local pages: { [string]: ScrollingFrame } = {}
local currentTab = "upgrades"
local upgradeCards: { [string]: any } = {}
local passCards: { [string]: any } = {}
local productCards: { [string]: any } = {}

local UPGRADE_ICONS = { Record = "⏱️", Speed = "👟" }
local POPULAR_UPGRADE = "Speed"

local function makePage(name: string): ScrollingFrame
	local page = Builder.create("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.textDim,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = modal.content,
	})
	local padding = Builder.padding(page, 6)
	padding.PaddingTop = UDim.new(0, 16) -- espaço para o selo "MAIS POPULAR"
	Builder.grid(page, Vector2.new(220, 196), 14)
	pages[name] = page
	return page
end

local function selectTab(key: string)
	currentTab = key
	tabs:select(key)
	for name, page in pages do
		page.Visible = name == key
	end
end

local function build()
	modal = Modal.new({ Title = I18n.t("shop_title"), Icon = "🛒", Size = Vector2.new(760, 420) })
	tabs = Tab.new(modal.content, {
		{ key = "upgrades", label = I18n.t("tab_upgrades") },
		{ key = "passes", label = I18n.t("tab_passes") },
		{ key = "products", label = I18n.t("tab_products") },
	}, selectTab)

	local upgrades = makePage("upgrades")
	for i, key in Config.UpgradeOrder do
		upgradeCards[key] = Card.new({
			Icon = UPGRADE_ICONS[key] or "⬆",
			Title = I18n.t("upgrade_" .. key .. "_name"),
			Desc = I18n.t("upgrade_" .. key .. "_desc"),
			ButtonText = "",
			Variant = "success",
			Popular = key == POPULAR_UPGRADE,
			LayoutOrder = i,
			OnClick = function()
				local ok, reason = Net.invoke("BuyUpgrade", key)
				if ok then
					Controllers.NotifyController.show(I18n.t("toast_upgrade"), "good")
					Controllers.SoundController.play("Coin", { pitch = 1.3 })
				else
					Controllers.NotifyController.reason(reason)
				end
			end,
			Parent = upgrades,
		})
	end

	local passes = makePage("passes")
	for i, key in Config.PassOrder do
		local info = Config.GamePasses[key]
		passCards[key] = Card.new({
			Icon = info.Icon,
			Title = I18n.t("pass_" .. key .. "_name"),
			Desc = I18n.t("pass_" .. key .. "_desc"),
			ButtonText = "",
			Variant = "warning",
			Popular = info.Popular == true,
			LayoutOrder = i,
			OnClick = function()
				Controllers.HudController.promptPass(key)
			end,
			Parent = passes,
		})
	end

	local products = makePage("products")
	for i, key in Config.ShopProducts do
		local info = Config.Products[key]
		productCards[key] = Card.new({
			Icon = info.Icon,
			Title = I18n.t("product_" .. key .. "_name"),
			Desc = I18n.t("product_" .. key .. "_desc", { amount = "?" }),
			ButtonText = "",
			Variant = "primary",
			Popular = info.Popular == true,
			LayoutOrder = i,
			OnClick = function()
				Controllers.HudController.promptProduct(key)
			end,
			Parent = products,
		})
	end
	selectTab("upgrades")
end

local function refresh(state)
	if not state then
		return
	end
	for key, card in upgradeCards do
		local price = state.prices[key]
		local level = state.upgrades[key] or 0
		card.Title.Text = I18n.t("upgrade_" .. key .. "_name") .. "  ·  " .. I18n.t("level", { n = level })
		if price then
			card:setButton("💰 " .. Format.number(price), state.cash >= price, "success")
		else
			card:setButton(I18n.t("max"), false)
		end
	end
	for key, card in passCards do
		local info = Config.GamePasses[key]
		if state.passes[key] then
			card:setButton(I18n.t("owned"), false)
		elseif info.Id == 0 then
			card:setButton(I18n.t("soon"), false)
		else
			card:setButton(I18n.t("price_robux", { price = info.Price }), true, "warning")
		end
	end
	for key, card in productCards do
		local info = Config.Products[key]
		local amount = state.cashPacks[key]
		if amount then
			card:setDesc(I18n.t("product_" .. key .. "_desc", { amount = Format.number(amount) }))
		end
		if info.Id == 0 then
			card:setButton(I18n.t("soon"), false)
		else
			card:setButton(I18n.t("price_robux", { price = info.Price }), true, "primary")
		end
	end
end

function ShopController.open(tab: string?)
	refresh(Controllers.StateController.get())
	selectTab(tab or currentTab)
	modal.open()
end

function ShopController.init(controllers)
	Controllers = controllers
	build()
end

function ShopController.start()
	Controllers.StateController.changed:Connect(function(state)
		if modal.isOpen() then
			refresh(state)
		end
	end)
end

return ShopController
