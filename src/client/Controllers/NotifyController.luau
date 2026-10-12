--[[
	NotifyController.luau
	Toasts empilhados no topo, com ícone e cor por tipo. Somem sozinhos em 3 s (ou 6 s
	quando têm botão de oferta). Entram e saem com tween.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Root = require(Ui.Root)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Components.Toast)

local NotifyController = {}

local Controllers
local MAX_TOASTS = 4
local LIFETIME = 3
local container: Frame
local toasts: { Frame } = {}
local order = 0

local function dismiss(toast: Frame)
	local index = table.find(toasts, toast)
	if index then
		table.remove(toasts, index)
	end
	if not toast.Parent then
		return
	end
	local scale = toast:FindFirstChildOfClass("UIScale")
	if scale then
		TweenService:Create(scale, Theme.Tween.Open, { Scale = 0.85 }):Play()
	end
	local tween = TweenService:Create(toast, Theme.Tween.Open, { BackgroundTransparency = 1 })
	tween:Play()
	for _, child in toast:GetDescendants() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			TweenService:Create(child, Theme.Tween.Open, { TextTransparency = 1 }):Play()
		end
	end
	tween.Completed:Wait()
	toast:Destroy()
end

-- action = { text = "...", onClick = fn } para ofertas contextuais.
function NotifyController.show(text: string, style: string?, action: { text: string, onClick: () -> () }?)
	order += 1
	local toast = Toast.create({
		Text = text,
		Style = style,
		ActionText = action and action.text,
		OnAction = action and action.onClick,
		LayoutOrder = order,
	})
	local scale = Builder.create("UIScale", { Scale = 0.85, Parent = toast })
	toast.Parent = container
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	table.insert(toasts, toast)
	while #toasts > MAX_TOASTS do
		task.spawn(dismiss, toasts[1])
	end
	task.delay(if action then LIFETIME * 2 else LIFETIME, dismiss, toast)
	if style == "warn" then
		Controllers.SoundController.play("Error", { volume = 0.4 })
	end
end

function NotifyController.showKey(key: string, args: { [string]: any }?, style: string?)
	local resolved = if args then table.clone(args) else {}
	if type(resolved.itemKey) == "string" then
		resolved.item = I18n.t(resolved.itemKey)
	end
	NotifyController.show(I18n.t(key, resolved), style)
end

function NotifyController.reason(reason: any)
	NotifyController.show(I18n.reason(reason), "warn")
end

function NotifyController.init(controllers)
	Controllers = controllers
	container = Root.container("Toasts", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 118), UDim2.fromOffset(540, 280), 5)
	local layout = Builder.list(container, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	Net.connect("Notify", function(key, args, style)
		if type(key) == "string" then
			NotifyController.showKey(key, if type(args) == "table" then args else nil, style)
		end
	end)
end

return NotifyController
