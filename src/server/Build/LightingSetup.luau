--[[
	LightingSetup.luau
	Iluminação da v2: Lighting.Technology = Future (no default.project.json; não é editável
	por script), Atmosphere leve, ColorCorrection levemente quente e SunRays sutil.
	O ciclo dia/noite de 12 min roda no cliente (EnvironmentController), a partir do relógio
	do servidor, então todos veem a mesma hora sem tráfego de rede.
]]

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

function LightingSetup.apply()
	Lighting.ClockTime = 14
	Lighting.GlobalShadows = true
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ShadowSoftness = 0.3
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "WarmTint"
	correction.TintColor = Color3.fromRGB(255, 246, 232)
	correction.Saturation = 0.08
	correction.Contrast = 0.05
	correction.Brightness = 0.01
	correction.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.6
	rays.Parent = Lighting

	-- Skybox clássico (texturas que vêm com o cliente do Roblox).
	local sky = Instance.new("Sky")
	sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
	sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
	sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
	sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
	sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
	sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
	sky.Parent = Lighting
end

return LightingSetup
