--[[
	IconButton.luau
	Botão só com ícone (barra lateral). Tooltip ao passar o mouse e badge de notificação.

	local b = IconButton.new({ Icon = "Shop", Tooltip = "Loja", Size = 64, OnClick = ..., Parent = bar })
	b:setBadge(true)          -- "!" vermelho
	b:setBadge(true, "3")     -- número
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Hooks = require(Ui.Hooks)
local Theme = require(Ui.Theme)
local Button = require(script.Parent.Button)

local IconButton = {}
IconButton.__index = IconButton

export type Props = {
	Icon: string,
	Tooltip: string?,
	Size: number?,
	OnClick: (() -> ())?,
	Parent: Instance?,
	LayoutOrder: number?,
	Color: Color3?,
	TooltipSide: string?, -- "right" (padrão) | "left" | "top"
}

function IconButton.new(props: Props)
	local size = props.Size or 64
	local instance = Builder.create("TextButton", {
		Name = props.Icon,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = props.Color or Theme.Colors.bg,
		BackgroundTransparency = if props.Color then 0 else Theme.PanelTransparency,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
	})
	Builder.corner(instance, Theme.Radius.M)
	Builder.stroke(instance)
	if props.Color then
		Builder.gradient(instance)
	end
	Button.attachMotion(instance)
	Builder.icon(props.Icon, math.floor(size * 0.58), {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}).Parent =
		instance

	local badge = Builder.label({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.danger,
		Text = "!",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 16,
		Visible = false,
		ZIndex = 3,
		Parent = instance,
	})
	Builder.corner(badge, 12)

	local tooltip: TextLabel? = nil
	if props.Tooltip then
		local side = props.TooltipSide or "right"
		local tip = Builder.label({
			Name = "Tooltip",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 32),
			AnchorPoint = if side == "left"
				then Vector2.new(1, 0.5)
				elseif side == "top" then Vector2.new(0.5, 1)
				else Vector2.new(0, 0.5),
			Position = if side == "left"
				then UDim2.new(0, -10, 0.5, 0)
				elseif side == "top" then UDim2.new(0.5, 0, 0, -8)
				else UDim2.new(1, 10, 0.5, 0),
			BackgroundTransparency = 0.1,
			BackgroundColor3 = Theme.Colors.bg,
			Text = props.Tooltip,
			FontFace = Theme.Fonts.Bold,
			TextSize = 18,
			TextWrapped = false,
			Visible = false,
			ZIndex = 10,
			Parent = instance,
		})
		Builder.corner(tip, 8)
		Builder.padding(tip, 8)
		tooltip = tip
		instance.MouseEnter:Connect(function()
			tip.Visible = true
		end)
		instance.MouseLeave:Connect(function()
			tip.Visible = false
		end)
	end

	instance.Activated:Connect(function()
		if props.OnClick then
			Hooks.click()
			props.OnClick()
		end
	end)
	if props.Parent then
		instance.Parent = props.Parent
	end
	return setmetatable({ Instance = instance, Badge = badge, Tooltip = tooltip }, IconButton)
end

-- Troca o ícone (nome de Config.Icons / Theme.Emoji).
function IconButton:setIcon(name: string)
	local old = self.Instance:FindFirstChild("Icon")
	if old and old:GetAttribute("IconName") == name then
		return
	end
	local size = if old then (old :: GuiObject).Size else UDim2.fromOffset(36, 36)
	if old then
		old:Destroy()
	end
	local icon = Builder.icon(name, size.X.Offset, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	icon:SetAttribute("IconName", name)
	icon.Parent = self.Instance
end

function IconButton:setBadge(visible: boolean, text: string?)
	local badge: TextLabel = self.Badge
	if visible and not badge.Visible then
		badge.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(badge, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(24, 24) })
			:Play()
	end
	badge.Visible = visible
	badge.Text = text or "!"
end

return IconButton
