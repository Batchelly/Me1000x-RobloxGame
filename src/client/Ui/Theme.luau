--[[
	Theme.luau
	Design system da UI v2: painéis de vidro escuro, cantos arredondados, contorno fino
	semitransparente, gradiente suave nos botões e a fonte Builder Sans.
]]

local Theme = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

Theme.Colors = {
	bg = hex("151A2B"), -- painel de vidro escuro
	bgLight = hex("1F2640"),
	bgLighter = hex("2A3354"),
	primary = hex("5B6CFF"), -- azul-violeta
	primaryDark = hex("4351D9"),
	success = hex("2ED47A"),
	warning = hex("FFC83D"),
	danger = hex("FF4D5E"),
	gold = hex("FFD54A"),
	text = hex("FFFFFF"),
	textDim = hex("A9B1D6"),
	textDark = hex("1B1F33"),
	stroke = hex("FFFFFF"),
	black = Color3.new(0, 0, 0),
	disabled = hex("4A5170"),
}

Theme.PanelTransparency = 0.15
Theme.StrokeTransparency = 0.82

Theme.Radius = { S = 12, M = 16, L = 20 }

-- Fonte Builder Sans (Bold para títulos, Medium para texto). Fallback: Gotham SSm.
local function family(name: string, weight: Enum.FontWeight): Font
	local ok, font = pcall(Font.new, "rbxasset://fonts/families/" .. name .. ".json", weight)
	if ok then
		return font
	end
	return Font.new("rbxasset://fonts/families/GothamSSm.json", weight)
end

Theme.Fonts = {
	Heavy = family("BuilderSans", Enum.FontWeight.ExtraBold),
	Bold = family("BuilderSans", Enum.FontWeight.Bold),
	Medium = family("BuilderSans", Enum.FontWeight.Medium),
}

-- Animação padrão de abrir/fechar (escala 0,92 -> 1 e transparência, 0,18 s, Quint Out).
Theme.Tween = {
	Open = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Count = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

Theme.HoverScale = 1.04
Theme.PressScale = 0.96

-- Variantes de botão: cor de fundo e cor do texto.
Theme.Variants = {
	primary = { bg = Theme.Colors.primary, text = Theme.Colors.text },
	success = { bg = Theme.Colors.success, text = Theme.Colors.textDark },
	warning = { bg = Theme.Colors.warning, text = Theme.Colors.textDark },
	danger = { bg = Theme.Colors.danger, text = Theme.Colors.text },
	ghost = { bg = Theme.Colors.bgLighter, text = Theme.Colors.text },
	gold = { bg = Theme.Colors.gold, text = Theme.Colors.textDark },
}

-- Emoji de fallback para cada ícone (quando Config.Icons[nome] estiver vazio).
Theme.Emoji = {
	Cash = "💰",
	Shop = "🛒",
	Base = "🏠",
	Clones = "📼",
	Rebirth = "🔁",
	Daily = "🎁",
	Codes = "🎟️",
	Settings = "⚙️",
	Banana = "🍌",
	Slap = "👋",
	Lock = "🔒",
	Vault = "🏦",
	Record = "⏺",
	City = "🏙️",
	Home = "🏠",
}

-- Toasts: cor e ícone por tipo.
Theme.Toasts = {
	good = { color = Theme.Colors.success, icon = "✅" },
	warn = { color = Theme.Colors.danger, icon = "⚠️" },
	gold = { color = Theme.Colors.warning, icon = "⭐" },
	info = { color = Theme.Colors.primary, icon = "💬" },
	alert = { color = Theme.Colors.danger, icon = "🚨" },
}

return Theme
