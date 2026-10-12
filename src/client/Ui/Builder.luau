--[[
	Builder.luau
	Helpers de baixo nível para montar UI por código (sem .rbxm): create, cantos, contornos,
	gradientes, layouts, textos e ícones (ImageLabel com Config.Icons ou emoji de fallback).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(script.Parent.Theme)

local Builder = {}

function Builder.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Builder.corner(parent: Instance, radius: number?): UICorner
	return Builder.create("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.M), Parent = parent })
end

-- Contorno fino semitransparente (padrão do design system).
function Builder.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Builder.create("UIStroke", {
		Thickness = thickness or 1.5,
		Color = color or Theme.Colors.stroke,
		Transparency = transparency or Theme.StrokeTransparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Gradiente suave de cima para baixo (claro -> um pouco mais escuro).
function Builder.gradient(parent: Instance, strength: number?): UIGradient
	local s = strength or 0.18
	return Builder.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1 - s, 1 - s, 1 - s)),
		Parent = parent,
	})
end

function Builder.padding(parent: Instance, pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return Builder.create("UIPadding", {
		PaddingTop = p,
		PaddingBottom = p,
		PaddingLeft = p,
		PaddingRight = p,
		Parent = parent,
	})
end

function Builder.list(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	return Builder.create("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

function Builder.grid(parent: Instance, cell: Vector2, gap: number?): UIGridLayout
	return Builder.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap or 10, gap or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = parent,
	})
end

-- Texto padrão (Builder Sans Medium, branco).
function Builder.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.text,
		TextSize = 20,
		TextWrapped = true,
		RichText = false,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Builder.create("TextLabel", defaults)
end

-- Ícone: ImageLabel se houver ID em Config.Icons, senão emoji.
function Builder.icon(name: string, size: number, props: { [string]: any }?): GuiObject
	local id = Config.Icons[name]
	local icon
	if type(id) == "string" and id ~= "" then
		icon = Builder.create("ImageLabel", {
			BackgroundTransparency = 1,
			Image = id,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(size, size),
		})
	else
		icon = Builder.label({
			Text = Theme.Emoji[name] or "•",
			TextSize = math.floor(size * 0.8),
			Size = UDim2.fromOffset(size, size),
		})
	end
	if props then
		for key, value in props do
			(icon :: any)[key] = value
		end
	end
	return icon
end

-- Painel de vidro escuro (fundo #151A2B a 15% de transparência, canto e borda clara).
function Builder.glass(props: { [string]: any }): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = Builder.create("Frame", defaults)
	Builder.corner(frame, Theme.Radius.M)
	Builder.stroke(frame)
	return frame
end

return Builder
