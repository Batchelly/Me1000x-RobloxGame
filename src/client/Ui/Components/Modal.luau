--[[
	Modal.luau
	Menu modal central: fundo escurecido, painel de vidro com título e botão fechar.
	Abrir/fechar com tween (escala 0,92 -> 1 e transparência, 0,18 s, Quint Out) usando um
	CanvasGroup. Enquanto houver modal aberto o jogo ganha BlurEffect (Root).

	local modal = Modal.new({ Title = "LOJA", Size = Vector2.new(760, 420), Icon = "🛒" })
	modal.content  -- Frame onde vai o conteúdo
	modal.open(); modal.close(); modal.onClose(fn)
]]

local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent
local Builder = require(Ui.Builder)
local Hooks = require(Ui.Hooks)
local Root = require(Ui.Root)
local Theme = require(Ui.Theme)
local Button = require(script.Parent.Button)

local Modal = {}

export type Props = {
	Title: string,
	Size: Vector2,
	Icon: string?,
	Accent: Color3?,
}

export type Modal = {
	overlay: Frame,
	content: Frame,
	title: TextLabel,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onClose: (() -> ()) -> (),
	onOpen: (() -> ()) -> (),
}

local HEADER = 72

function Modal.new(props: Props): Modal
	local overlay = Builder.create("Frame", {
		Name = "Modal_" .. props.Title,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Active = true,
		ZIndex = 20,
		Parent = Root.gui(),
	})
	local holder = Builder.create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.Size.X, props.Size.Y),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	Root.registerScale(Builder.create("UIScale", { Parent = holder }))

	local group = Builder.create("CanvasGroup", {
		Name = "Group",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = holder,
	})
	local animScale = Builder.create("UIScale", { Scale = 0.92, Parent = group })

	local body = Builder.create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.05,
		Parent = group,
	})
	Builder.corner(body, Theme.Radius.L)
	Builder.stroke(body, 1.5)

	local accent = Builder.create("Frame", {
		Name = "Accent",
		Size = UDim2.new(1, -40, 0, 4),
		Position = UDim2.fromOffset(20, HEADER - 4),
		BackgroundColor3 = props.Accent or Theme.Colors.primary,
		BorderSizePixel = 0,
		Parent = body,
	})
	Builder.corner(accent, 2)
	local title = Builder.label({
		Name = "Title",
		Text = (if props.Icon then props.Icon .. "  " else "") .. props.Title,
		FontFace = Theme.Fonts.Heavy,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, HEADER - 8),
		Position = UDim2.fromOffset(24, 4),
		Parent = body,
	})

	local content = Builder.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -32, 1, -(HEADER + 16)),
		Position = UDim2.fromOffset(16, HEADER + 8),
		BackgroundTransparency = 1,
		Parent = body,
	})

	local openCallbacks: { () -> () } = {}
	local closeCallbacks: { () -> () } = {}
	local isOpen = false
	local modal: Modal

	local function tween(target: number)
		TweenService:Create(group, Theme.Tween.Open, { GroupTransparency = 1 - target }):Play()
		TweenService:Create(animScale, Theme.Tween.Open, { Scale = 0.92 + 0.08 * target }):Play()
		return TweenService:Create(overlay, Theme.Tween.Open, { BackgroundTransparency = 1 - 0.55 * target })
	end

	modal = {
		overlay = overlay,
		content = content,
		title = title,
		open = function()
			if isOpen then
				return
			end
			Root.beforeOpen(modal)
			isOpen = true
			overlay.Visible = true
			tween(1):Play()
			Hooks.sfx("Open")
			Root.modalStateChanged()
			for _, callback in openCallbacks do
				task.spawn(callback)
			end
		end,
		close = function()
			if not isOpen then
				return
			end
			isOpen = false
			local out = tween(0)
			out:Play()
			out.Completed:Once(function()
				if not isOpen then
					overlay.Visible = false
				end
			end)
			Root.modalStateChanged()
			for _, callback in closeCallbacks do
				task.spawn(callback)
			end
		end,
		isOpen = function()
			return isOpen
		end,
		onClose = function(callback)
			table.insert(closeCallbacks, callback)
		end,
		onOpen = function(callback)
			table.insert(openCallbacks, callback)
		end,
	}

	Button.new({
		Text = "✕",
		Variant = "ghost",
		Size = UDim2.fromOffset(64, 56),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		TextSize = 26,
		OnClick = function()
			modal.close()
		end,
		Parent = body,
	})
	-- Clicar fora do painel fecha.
	overlay.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		local pos, size = holder.AbsolutePosition, holder.AbsoluteSize
		if p.X < pos.X or p.Y < pos.Y or p.X > pos.X + size.X or p.Y > pos.Y + size.Y then
			modal.close()
		end
	end)

	Root.registerModal(modal)
	return modal
end

return Modal
