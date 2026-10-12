--[[
	Button.luau
	Botão principal do design system: cantos arredondados, gradiente suave, contorno fino,
	hover 1,04 / press 0,96 com tween e som de clique.

	local button = Button.new({
		Text = "Comprar", Variant = "success", Size = UDim2.fromOffset(160, 56),
		OnClick = function() ... end, Parent = frame,
	})
	button:setText("..."); button:setEnabled(false); button:setVariant("danger")
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Hooks = require(Ui.Hooks)
local Theme = require(Ui.Theme)

local Button = {}
Button.__index = Button

export type Props = {
	Text: string?,
	Variant: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	OnClick: (() -> ())?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	Radius: number?,
	Name: string?,
}

-- Liga hover/press com escala em qualquer GuiButton.
function Button.attachMotion(button: GuiButton): UIScale
	local scale = Builder.create("UIScale", { Parent = button })
	local hovering = false
	local function to(value: number)
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		hovering = true
		if not button:GetAttribute("Disabled") then
			to(Theme.HoverScale)
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		if not button:GetAttribute("Disabled") then
			to(Theme.PressScale)
		end
	end)
	button.MouseButton1Up:Connect(function()
		to(if hovering then Theme.HoverScale else 1)
	end)
	return scale
end

function Button.new(props: Props)
	local variant = Theme.Variants[props.Variant or "primary"] or Theme.Variants.primary
	local instance = Builder.create("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(180, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = variant.bg,
		AutoButtonColor = false,
		Text = props.Text or "",
		FontFace = Theme.Fonts.Bold,
		TextSize = props.TextSize or 22,
		TextColor3 = variant.text,
		TextWrapped = true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	Builder.corner(instance, props.Radius or Theme.Radius.S)
	Builder.stroke(instance, 1.5, Theme.Colors.stroke, 0.75)
	Builder.gradient(instance)
	Button.attachMotion(instance)

	local self = setmetatable({ Instance = instance, _variant = props.Variant or "primary", _enabled = true }, Button)
	instance.Activated:Connect(function()
		if self._enabled and props.OnClick then
			Hooks.click()
			props.OnClick()
		end
	end)
	if props.Parent then
		instance.Parent = props.Parent
	end
	return self
end

function Button:setText(text: string)
	self.Instance.Text = text
end

function Button:setVariant(name: string)
	self._variant = name
	if self._enabled then
		local variant = Theme.Variants[name] or Theme.Variants.primary
		self.Instance.BackgroundColor3 = variant.bg
		self.Instance.TextColor3 = variant.text
	end
end

function Button:setEnabled(enabled: boolean)
	self._enabled = enabled
	self.Instance:SetAttribute("Disabled", not enabled)
	if enabled then
		self:setVariant(self._variant)
	else
		self.Instance.BackgroundColor3 = Theme.Colors.disabled
		self.Instance.TextColor3 = Theme.Colors.textDim
	end
end

-- Texto + habilitado de uma vez.
function Button:setButton(text: string, enabled: boolean)
	self:setText(text)
	self:setEnabled(enabled)
end

return Button
