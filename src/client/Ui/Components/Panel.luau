--[[
	Panel.luau
	Painel de vidro escuro com sombra suave. A sombra é um irmão atrás do painel (com
	ZIndexBehavior.Sibling, filhos sempre desenham por cima do pai), deslocado 6 px para baixo.

	local panel = Panel.new({ Size = ..., Position = ..., AnchorPoint = ..., Parent = gui })
	panel.Instance  -- Frame do painel (coloque o conteúdo aqui)
]]

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Theme = require(Ui.Theme)

local Panel = {}

export type Props = {
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	LayoutOrder: number?,
	Radius: number?,
	Name: string?,
	Shadow: boolean?,
}

function Panel.new(props: Props)
	local holder = Builder.create("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder or 0,
	})
	local radius = props.Radius or Theme.Radius.L
	if props.Shadow ~= false then
		local shadow = Builder.create("Frame", {
			Name = "Shadow",
			Size = UDim2.new(1, 8, 1, 8),
			Position = UDim2.fromOffset(-4, 4),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.65,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = holder,
		})
		Builder.corner(shadow, radius + 4)
	end
	local panel = Builder.create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = holder,
	})
	Builder.corner(panel, radius)
	Builder.stroke(panel, 1.5)
	if props.Parent then
		holder.Parent = props.Parent
	end
	return { Holder = holder, Instance = panel }
end

return Panel
