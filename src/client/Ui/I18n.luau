--[[
	I18n.luau
	Idioma do cliente (PT para "pt-*", EN para o resto) e atalho para Strings.get.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

local I18n = {}

local function detect(): string
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if ok and type(locale) == "string" and locale ~= "" then
		return Strings.langFor(locale)
	end
	local player = Players.LocalPlayer
	return Strings.langFor(player and player.LocaleId or "pt-br")
end

I18n.lang = detect()

function I18n.t(key: string, args: { [string]: any }?): string
	return Strings.get(I18n.lang, key, args)
end

-- Motivo de falha vindo do servidor ("not_enough_cash" -> texto).
function I18n.reason(reason: any): string
	if type(reason) ~= "string" then
		return I18n.t("reason_error")
	end
	local key = "reason_" .. reason
	local text = Strings.get(I18n.lang, key)
	if text == key then
		return I18n.t("reason_error")
	end
	return text
end

return I18n
