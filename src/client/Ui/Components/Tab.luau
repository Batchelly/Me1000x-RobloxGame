--[[
	Tab.luau
	Barra de abas (controle segmentado). A aba ativa fica com a cor primária.

	local tabs = Tab.new(parent, { { key = "a", label = "Upgrades" }, ... }, function(key) ... end)
	tabs:select("a")
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Hooks = require(Ui.Hooks)
local Theme = require(Ui.Theme)

local Tab = {}
Tab.__index = Tab

function Tab.new(parent: Instance, items: { { key: string, label: string } }, onSelect: (string) -> ())
	local bar = Builder.create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Theme.Colors.bgLight,
		BackgroundTransparency = 0.2,
		Parent = parent,
	})
	Builder.corner(bar, Theme.Radius.S)
	Builder.padding(bar, 4)
	Builder.list(bar, 4, true)

	local self = setmetatable({ Bar = bar, Buttons = {}, Selected = nil :: string? }, Tab)
	for i, item in items do
		local button = Builder.create("TextButton", {
			Name = item.key,
			Size = UDim2.new(1 / #items, -4, 1, 0),
			BackgroundColor3 = Theme.Colors.primary,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = item.label,
			FontFace = Theme.Fonts.Bold,
			TextSize = 20,
			TextColor3 = Theme.Colors.textDim,
			LayoutOrder = i,
			Parent = bar,
		})
		Builder.corner(button, 10)
		button.Activated:Connect(function()
			Hooks.click()
			self:select(item.key)
			onSelect(item.key)
		end)
		self.Buttons[item.key] = button
	end
	return self
end

function Tab:select(key: string)
	self.Selected = key
	for name, button in self.Buttons do
		local active = name == key
		TweenService:Create(button, Theme.Tween.Fast, {
			BackgroundTransparency = if active then 0 else 1,
			TextColor3 = if active then Theme.Colors.text else Theme.Colors.textDim,
		}):Play()
	end
end

return Tab
