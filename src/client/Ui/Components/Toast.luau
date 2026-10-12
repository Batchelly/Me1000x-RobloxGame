--[[
	Toast.luau
	Notificação com ícone e cor por tipo (good/warn/gold/info/alert) e um botão de ação
	opcional (ofertas contextuais: "Trancar agora (39 R$)", "Recuperar (49 R$)").
]]

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Theme = require(Ui.Theme)
local Button = require(script.Parent.Button)

local Toast = {}

export type Props = {
	Text: string,
	Style: string?,
	ActionText: string?,
	OnAction: (() -> ())?,
	LayoutOrder: number?,
}

function Toast.create(props: Props): Frame
	local style = Theme.Toasts[props.Style or "info"] or Theme.Toasts.info
	local hasAction = props.ActionText ~= nil
	local frame = Builder.create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(540, if hasAction then 64 else 52),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		LayoutOrder = props.LayoutOrder or 0,
	})
	Builder.corner(frame, Theme.Radius.M)
	local stroke = Builder.stroke(frame, 2, style.color, 0.2)
	stroke.Name = "Stroke"
	local bar = Builder.create("Frame", {
		Name = "Bar",
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = style.color,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Builder.corner(bar, 3)
	Builder.label({
		Name = "Icon",
		Text = style.icon,
		TextSize = 24,
		Size = UDim2.new(0, 36, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		Parent = frame,
	})
	Builder.label({
		Name = "Text",
		Text = props.Text,
		FontFace = Theme.Fonts.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, if hasAction then -260 else -70, 1, 0),
		Position = UDim2.fromOffset(58, 0),
		Parent = frame,
	})
	if hasAction then
		Button.new({
			Text = props.ActionText,
			Variant = "warning",
			Size = UDim2.fromOffset(180, 48),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			TextSize = 17,
			OnClick = props.OnAction,
			Parent = frame,
		})
	end
	return frame
end

return Toast
