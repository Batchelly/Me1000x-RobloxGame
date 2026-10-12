--[[
	SettingsController.luau
	Menu Configurações: volume de música, ambiente e efeitos, quantidade de clones visíveis
	(30/60/120) e alertas de invasão. Aplica na hora (som e renderização) e salva no perfil
	(SaveSettings) quando o jogador solta o controle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Theme = require(Ui.Theme)
local Button = require(Ui.Components.Button)
local Modal = require(Ui.Components.Modal)
local Slider = require(Ui.Components.Slider)
local Toggle = require(Ui.Components.Toggle)

local SettingsController = {}

local Controllers
local modal: Modal.Modal
local settings = table.clone(Config.DefaultSettings)
local controls = {} :: { [string]: any }
local saveQueued = false

local function save()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(0.4, function()
		saveQueued = false
		Net.invoke("SaveSettings", settings)
	end)
end

local function apply()
	Controllers.SoundController.applySettings(settings)
	Controllers.CloneRenderer.setMaxRendered(settings.CloneQuality)
end

local function row(content: Instance, order: number, labelKey: string): Frame
	local frame = Builder.create("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Theme.Colors.bgLight,
		LayoutOrder = order,
		Parent = content,
	})
	Builder.corner(frame, Theme.Radius.S)
	Builder.label({
		Text = I18n.t(labelKey),
		FontFace = Theme.Fonts.Bold,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.fromScale(0.4, 1),
		Parent = frame,
	})
	return frame
end

local function build()
	modal = Modal.new({ Title = I18n.t("settings_title"), Icon = "⚙️", Size = Vector2.new(580, 420) })
	local content = modal.content
	Builder.list(content, 8).VerticalAlignment = Enum.VerticalAlignment.Top

	for i, entry in { { "Music", "settings_music" }, { "Ambient", "settings_ambient" }, { "Sfx", "settings_sfx" } } do
		local key = entry[1]
		local frame = row(content, i, entry[2])
		controls[key] = Slider.new({
			Value = settings[key],
			Width = 280,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -20, 0.5, 0),
			OnChanged = function(value, final)
				settings[key] = value
				Controllers.SoundController.applySettings(settings)
				if final then
					if key == "Sfx" then
						Controllers.SoundController.play("Coin")
					end
					save()
				end
			end,
			Parent = frame,
		})
	end

	local quality = row(content, 4, "settings_quality")
	local options = Builder.create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(290, 48),
		BackgroundTransparency = 1,
		Parent = quality,
	})
	Builder.list(options, 8, true)
	controls.quality = {}
	for i, value in Config.CloneQualityOptions do
		controls.quality[value] = Button.new({
			Text = tostring(value),
			Variant = "ghost",
			Size = UDim2.fromOffset(88, 48),
			LayoutOrder = i,
			OnClick = function()
				settings.CloneQuality = value
				SettingsController.render()
				apply()
				save()
			end,
			Parent = options,
		})
	end

	local alerts = row(content, 5, "settings_alerts")
	controls.alerts = Toggle.new({
		Value = settings.Alerts,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		OnChanged = function(value)
			settings.Alerts = value
			save()
		end,
		Parent = alerts,
	})
end

function SettingsController.render()
	for _, key in { "Music", "Ambient", "Sfx" } do
		controls[key]:set(settings[key])
	end
	for value, button in controls.quality do
		button:setVariant(if value == settings.CloneQuality then "primary" else "ghost")
	end
	controls.alerts:set(settings.Alerts)
end

function SettingsController.open()
	SettingsController.render()
	modal.open()
end

function SettingsController.init(controllers)
	Controllers = controllers
	build()
end

function SettingsController.start()
	local loaded = false
	Controllers.StateController.changed:Connect(function(state)
		-- Carrega do perfil só uma vez (depois o cliente é a fonte enquanto o jogador mexe).
		if loaded or type(state.settings) ~= "table" then
			return
		end
		loaded = true
		for key, value in state.settings do
			settings[key] = value
		end
		apply()
		SettingsController.render()
	end)
end

return SettingsController
