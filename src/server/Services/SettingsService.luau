--[[
	SettingsService.luau
	Menu Configurações: volumes (música, ambiente, efeitos), quantidade de clones visíveis e
	alertas de invasão. Salvo no perfil (DataStore). O cliente aplica localmente; o servidor
	só valida e guarda (e usa Alerts para decidir se manda alertas de invasão).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local SettingsService = {}

local Services

local function volume(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
end

-- Valida o que veio do cliente e devolve uma tabela limpa.
function SettingsService.sanitize(input: any, current: any): { [string]: any }
	local base = if type(current) == "table" then current else Config.DefaultSettings
	if type(input) ~= "table" then
		return table.clone(base)
	end
	local quality = input.CloneQuality
	if not table.find(Config.CloneQualityOptions, quality) then
		quality = base.CloneQuality
	end
	return {
		Music = volume(input.Music, base.Music),
		Ambient = volume(input.Ambient, base.Ambient),
		Sfx = volume(input.Sfx, base.Sfx),
		CloneQuality = quality,
		Alerts = if type(input.Alerts) == "boolean" then input.Alerts else base.Alerts,
	}
end

function SettingsService.init(services)
	Services = services
end

function SettingsService.start()
	Net.handle("SaveSettings", function(player, input)
		local profile = Services.DataService.get(player)
		if not profile then
			return false, "not_loaded"
		end
		profile.Data.Settings = SettingsService.sanitize(input, profile.Data.Settings)
		Services.EconomyService.markDirty(player)
		return true, nil
	end)
end

return SettingsService
