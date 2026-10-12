--[[
	Slider.luau
	Controle deslizante 0..1 (mouse e toque). OnChanged(valor, final) é chamado durante o
	arraste (final = false) e ao soltar (final = true).
]]

local UserInputService = game:GetService("UserInputService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Theme = require(Ui.Theme)

local Slider = {}
Slider.__index = Slider

export type Props = {
	Value: number,
	Width: number?,
	OnChanged: (number, boolean) -> (),
	Parent: Instance?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
}

function Slider.new(props: Props)
	local width = props.Width or 260
	local holder = Builder.create("TextButton", {
		Name = "Slider",
		Size = UDim2.fromOffset(width, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})
	local track = Builder.create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Theme.Colors.bgLighter,
		Parent = holder,
	})
	Builder.corner(track, 5)
	local fill = Builder.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.primary,
		Parent = track,
	})
	Builder.corner(fill, 5)
	local knob = Builder.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Theme.Colors.text,
		Parent = track,
	})
	Builder.corner(knob, 14)
	Builder.stroke(knob, 2, Theme.Colors.primary, 0)

	local self = setmetatable({ Instance = holder, _value = 0 }, Slider)
	local function render(value: number)
		self._value = value
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
	end
	render(math.clamp(props.Value, 0, 1))

	local dragging = false
	local function fromX(x: number)
		local relative = (x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
		local value = math.clamp(math.floor(relative * 100 + 0.5) / 100, 0, 1)
		render(value)
		props.OnChanged(value, false)
	end
	holder.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			dragging = false
			props.OnChanged(self._value, true)
		end
	end)
	self.set = function(_, value: number)
		render(math.clamp(value, 0, 1))
	end
	if props.Parent then
		holder.Parent = props.Parent
	end
	return self
end

return Slider
