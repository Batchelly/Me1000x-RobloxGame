--[[
	ProgressRing.luau
	Anel de progresso circular sem imagens: duas metades com ClipsDescendants, cada uma com
	um anel (UICorner + UIStroke) e um UIGradient de borda dura no stroke. Girar o gradiente
	revela uma fatia do anel no sentido horário, começando no topo.

	local ring = ProgressRing.new(parent, 160, 8, Theme.Colors.danger)
	ring:set(0.25)
]]

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)

local ProgressRing = {}
ProgressRing.__index = ProgressRing

local HARD_EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local function half(container: Frame, size: number, thickness: number, color: Color3, left: boolean): UIGradient
	local clip = Builder.create("Frame", {
		Name = if left then "Left" else "Right",
		Size = UDim2.fromScale(0.5, 1),
		Position = if left then UDim2.new() else UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = container,
	})
	local inner = size - thickness * 2
	local ring = Builder.create("Frame", {
		Size = UDim2.fromOffset(inner, inner),
		Position = UDim2.fromOffset(if left then thickness else thickness - size / 2, thickness),
		BackgroundTransparency = 1,
		Parent = clip,
	})
	Builder.corner(ring, inner)
	local stroke = Builder.create("UIStroke", {
		Thickness = thickness,
		Color = color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})
	return Builder.create("UIGradient", { Transparency = HARD_EDGE, Parent = stroke })
end

function ProgressRing.new(parent: Instance, size: number, thickness: number, color: Color3)
	local container = Builder.create("Frame", {
		Name = "ProgressRing",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local self = setmetatable({
		Instance = container,
		_left = half(container, size, thickness, color, true),
		_right = half(container, size, thickness, color, false),
	}, ProgressRing)
	self:set(0)
	return self
end

-- alpha 0..1 (horário, a partir do topo)
function ProgressRing:set(alpha: number)
	local a = math.clamp(alpha, 0, 1)
	self._right.Rotation = math.min(a, 0.5) * 360
	self._left.Rotation = 180 + math.max(a - 0.5, 0) * 360
end

function ProgressRing:setColor(color: Color3)
	for _, gradient in { self._left, self._right } do
		(gradient.Parent :: UIStroke).Color = color
	end
end

return ProgressRing
