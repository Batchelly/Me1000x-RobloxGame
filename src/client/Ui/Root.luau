--[[
	Root.luau
	ScreenGui principal (ScreenInsets = DeviceSafeInsets: respeita notch e barras), containers
	com UIScale automático por tamanho de tela (mobile first) e o registro dos modais
	(só um aberto por vez; BlurEffect no fundo do jogo enquanto houver modal aberto).

	Layout desenhado para ~1100x620. Em telas de toque a escala mínima é 0,9 para que os
	botões de 72 px do desenho fiquem com >= 64 px reais.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Builder = require(script.Parent.Builder)
local Hooks = require(script.Parent.Hooks)

local Root = {}

local gui: ScreenGui
local scales: { UIScale } = {}
local currentScale = 1
local modals: { any } = {}
local blur: BlurEffect

local DESIGN_WIDTH, DESIGN_HEIGHT = 1100, 620

function Root.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function computeScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	local s = math.min(viewport.X / DESIGN_WIDTH, viewport.Y / DESIGN_HEIGHT)
	local minScale = if UserInputService.TouchEnabled then 0.9 else 0.6
	return math.clamp(s, minScale, 1.35)
end

local function applyScale()
	currentScale = computeScale()
	for _, scale in scales do
		scale.Scale = currentScale
	end
end

function Root.scale(): number
	return currentScale
end

function Root.gui(): ScreenGui
	return gui
end

-- Registra um UIScale para seguir a escala da tela.
function Root.registerScale(scale: UIScale)
	scale.Scale = currentScale
	table.insert(scales, scale)
end

-- Frame transparente com UIScale, ancorado num canto/borda da tela.
function Root.container(name: string, anchor: Vector2, position: UDim2, size: UDim2, zIndex: number?): Frame
	local frame = Builder.create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = zIndex or 1,
		Parent = gui,
	})
	Root.registerScale(Builder.create("UIScale", { Parent = frame }))
	return frame
end

-- =========================================================================
-- Modais
-- =========================================================================
local function updateBlur()
	local open = Root.anyModalOpen()
	TweenService:Create(blur, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = if open then 12 else 0 }):Play()
	Hooks.modalChanged(open)
end

function Root.registerModal(modal)
	table.insert(modals, modal)
end

-- Chamado pelo Modal antes de abrir: fecha os outros.
function Root.beforeOpen(modal)
	for _, other in modals do
		if other ~= modal and other.isOpen() then
			other.close()
		end
	end
end

function Root.modalStateChanged()
	updateBlur()
end

function Root.closeAll()
	for _, modal in modals do
		modal.close()
	end
end

function Root.anyModalOpen(): boolean
	for _, modal in modals do
		if modal.isOpen() then
			return true
		end
	end
	return false
end

function Root.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Builder.create("ScreenGui", {
		Name = "MeX1000",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		Parent = playerGui,
	})
	blur = Instance.new("BlurEffect")
	blur.Name = "MeX1000MenuBlur"
	blur.Size = 0
	blur.Parent = Lighting

	applyScale()
	local connection: RBXScriptConnection? = nil
	local function watchCamera()
		if connection then
			connection:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
		end
		applyScale()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

return Root
