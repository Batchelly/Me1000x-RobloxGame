--[[
	Counter.luau
	Número com animação de contagem (ex.: Cash subindo de 1.2K para 1.5K).

	local counter = Counter.new(label, Format.number)
	counter:set(1500)
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Theme = require(Ui.Theme)

local Counter = {}
Counter.__index = Counter

function Counter.new(label: TextLabel, format: (number) -> string, prefix: string?)
	local value = Instance.new("NumberValue")
	local self = setmetatable({ Label = label, _value = value, _target = 0, _tween = nil :: Tween? }, Counter)
	value.Changed:Connect(function(current)
		label.Text = (prefix or "") .. format(math.floor(current + 0.5))
	end)
	label.Text = (prefix or "") .. format(0)
	return self
end

function Counter:set(target: number, instant: boolean?)
	if target == self._target then
		return
	end
	local grew = target > self._target
	self._target = target
	if self._tween then
		self._tween:Cancel()
	end
	if instant then
		self._value.Value = target
		return
	end
	local tween = TweenService:Create(self._value, Theme.Tween.Count, { Value = target })
	self._tween = tween
	tween:Play()
	if grew then
		-- leve "pulo" do texto quando o valor sobe
		local label: TextLabel = self.Label
		local size = label.TextSize
		label.TextSize = size + 4
		TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = size }):Play()
	end
end

return Counter
