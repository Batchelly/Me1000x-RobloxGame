--[[
	Toggle.luau
	Interruptor liga/desliga (pílula com bolinha).
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Hooks = require(Ui.Hooks)
local Theme = require(Ui.Theme)

local Toggle = {}
Toggle.__index = Toggle

export type Props = {
	Value: boolean,
	OnChanged: (boolean) -> (),
	Parent: Instance?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
}

function Toggle.new(props: Props)
	local button = Builder.create("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(76, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Theme.Colors.disabled,
	})
	Builder.corner(button, 20)
	local knob = Builder.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(0, 4, 0.5, 0),
		BackgroundColor3 = Theme.Colors.text,
		Parent = button,
	})
	Builder.corner(knob, 16)

	local self = setmetatable({ Instance = button, Value = props.Value }, Toggle)
	local function render(animate: boolean)
		local info = if animate then Theme.Tween.Fast else TweenInfo.new(0)
		TweenService:Create(button, info, {
			BackgroundColor3 = if self.Value then Theme.Colors.success else Theme.Colors.disabled,
		}):Play()
		TweenService:Create(knob, info, {
			Position = if self.Value then UDim2.new(1, -36, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
		}):Play()
	end
	render(false)
	button.Activated:Connect(function()
		Hooks.click()
		self.Value = not self.Value
		render(true)
		props.OnChanged(self.Value)
	end)
	self.set = function(_, value: boolean)
		self.Value = value
		render(false)
	end
	if props.Parent then
		button.Parent = props.Parent
	end
	return self
end

return Toggle
