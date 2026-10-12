--[[
	Card.luau
	Cartão de loja em grade: ícone, nome, descrição curta e preço em botão. Pode ter o
	selo "MAIS POPULAR".

	local card = Card.new({ Icon = "💰", Title = "...", Desc = "...", ButtonText = "99 R$",
		Variant = "warning", Popular = true, OnClick = ..., Parent = grid, LayoutOrder = 1 })
	card:setButton("✔ Comprado", false)
]]

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Theme = require(Ui.Theme)
local Button = require(script.Parent.Button)

local Card = {}
Card.__index = Card

export type Props = {
	Icon: string,
	Title: string,
	Desc: string,
	ButtonText: string,
	Variant: string?,
	Popular: boolean?,
	OnClick: (() -> ())?,
	Parent: Instance?,
	LayoutOrder: number?,
}

function Card.new(props: Props)
	local frame = Builder.create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Colors.bgLight,
		BackgroundTransparency = 0.05,
		LayoutOrder = props.LayoutOrder or 0,
	})
	Builder.corner(frame, Theme.Radius.M)
	local stroke = Builder.stroke(frame, if props.Popular then 2.5 else 1.5)
	if props.Popular then
		stroke.Color = Theme.Colors.warning
		stroke.Transparency = 0
	end

	Builder.label({
		Name = "Icon",
		Text = props.Icon,
		TextSize = 40,
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.fromOffset(0, 14),
		Parent = frame,
	})
	local title = Builder.label({
		Name = "Title",
		Text = props.Title,
		FontFace = Theme.Fonts.Bold,
		TextSize = 20,
		TextScaled = false,
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 66),
		Parent = frame,
	})
	local desc = Builder.label({
		Name = "Desc",
		Text = props.Desc,
		TextSize = 15,
		TextColor3 = Theme.Colors.textDim,
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 92),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	local button = Button.new({
		Text = props.ButtonText,
		Variant = props.Variant or "primary",
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 10, 1, -54),
		TextSize = 19,
		OnClick = props.OnClick,
		Parent = frame,
	})

	if props.Popular then
		local ribbon = Builder.label({
			Name = "Popular",
			Text = I18n.t("popular"),
			FontFace = Theme.Fonts.Heavy,
			TextSize = 13,
			TextColor3 = Theme.Colors.textDark,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.warning,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			ZIndex = 3,
			Parent = frame,
		})
		Builder.corner(ribbon, 12)
	end

	if props.Parent then
		frame.Parent = props.Parent
	end
	return setmetatable({ Instance = frame, Button = button, Title = title, Desc = desc }, Card)
end

function Card:setButton(text: string, enabled: boolean, variant: string?)
	self.Button:setText(text)
	if variant then
		self.Button:setVariant(variant)
	end
	self.Button:setEnabled(enabled)
end

function Card:setDesc(text: string)
	self.Desc.Text = text
end

return Card
