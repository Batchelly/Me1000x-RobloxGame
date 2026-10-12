--[[
	SoundController.luau
	Áudio do jogo em 3 SoundGroups (Music, Ambient, SFX), com volume no menu Configurações.
	- Música: playlist da Cidade em ordem aleatória com crossfade de 2 s; faixa calma dentro
	  da própria base; faixa animada durante a Chuva de Moedas. Começa com fade-in depois que
	  o jogo carrega (nunca alta de repente). IDs em Config.Music (vazio = sem música).
	- Ambiente: pássaros e vento de dia, grilos à noite (DayNight), água 3D perto da fonte,
	  do lago e do fosso (Parts com a tag "WaterSound").
	- Efeitos: Config.Sfx (clique, moeda, construção, sirene, laser, tapa, rebirth...).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Clock)
local Config = require(Shared.Config)
local DayNight = require(Shared.DayNight)
local MapLayout = require(Shared.MapLayout)

local Ui = script.Parent.Parent.Ui
local Hooks = require(Ui.Hooks)

local SoundController = {}

local Controllers
local player = Players.LocalPlayer

local groups: { [string]: SoundGroup } = {}
local sfxTemplates: { [string]: Sound } = {}
local currentMusic: Sound? = nil
local currentZone = ""
local playlist: { string } = {}
local playlistIndex = 0
local ambient: { [string]: Sound } = {}
local started = false

local function makeGroup(name: string, volume: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = "MeX1000_" .. name
	group.Volume = volume
	group.Parent = SoundService
	groups[name] = group
	return group
end

local function newSound(id: string, group: SoundGroup, parent: Instance?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.SoundGroup = group
	sound.Parent = parent or SoundService
	return sound
end

-- =========================================================================
-- Efeitos
-- =========================================================================
function SoundController.play(name: string, options: { volume: number?, pitch: number?, at: Vector3? }?)
	local template = sfxTemplates[name]
	if not template then
		return
	end
	local opts = options or {}
	local sound = template:Clone()
	sound.Volume = opts.volume or 0.8
	sound.PlaybackSpeed = opts.pitch or 1
	if opts.at then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = opts.at
		attachment.Parent = workspace.Terrain
		sound.RollOffMaxDistance = 120
		sound.Parent = attachment
		task.delay(6, function()
			attachment:Destroy()
		end)
	else
		sound.Parent = SoundService
		task.delay(6, function()
			sound:Destroy()
		end)
	end
	sound:Play()
end

-- =========================================================================
-- Música
-- =========================================================================
local function fadeTo(sound: Sound, volume: number, seconds: number): Tween
	local tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = volume })
	tween:Play()
	return tween
end

local function crossfadeTo(id: string, looped: boolean, seconds: number)
	local old = currentMusic
	currentMusic = nil
	if old then
		fadeTo(old, 0, seconds).Completed:Once(function()
			old:Destroy()
		end)
	end
	if id == "" then
		return
	end
	local sound = newSound(id, groups.Music)
	sound.Looped = looped
	sound.Volume = 0
	sound:Play()
	fadeTo(sound, 1, seconds)
	currentMusic = sound
end

local function nextCityTrack(): string
	if #playlist == 0 then
		return ""
	end
	playlistIndex += 1
	if playlistIndex > #playlist then
		playlistIndex = 1
		-- embaralha de novo (ordem aleatória)
		for i = #playlist, 2, -1 do
			local j = math.random(1, i)
			playlist[i], playlist[j] = playlist[j], playlist[i]
		end
	end
	return playlist[playlistIndex]
end

local function zoneNow(): string
	local state = Controllers.StateController.get()
	if state and Controllers.StateController.timeLeft("coinRainLeft") > 0 and Config.Music.CoinRainTrack ~= "" then
		return "rain"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plot = player:GetAttribute("PlotIndex")
	if
		root
		and plot
		and MapLayout.plotAt(root.Position.X, root.Position.Z) == plot
		and Config.Music.BaseTrack ~= ""
	then
		return "base"
	end
	return "city"
end

local function updateMusic()
	local zone = zoneNow()
	if zone ~= currentZone then
		currentZone = zone
		local fade = if started then Config.Audio.ZoneFade else Config.Audio.FadeIn
		if zone == "base" then
			crossfadeTo(Config.Music.BaseTrack, true, fade)
		elseif zone == "rain" then
			crossfadeTo(Config.Music.CoinRainTrack, true, fade)
		else
			crossfadeTo(nextCityTrack(), false, fade)
		end
		started = true
		return
	end
	-- Playlist da cidade: crossfade antes do fim da faixa.
	local music = currentMusic
	if zone == "city" and music and music.TimeLength > 0 then
		if music.TimePosition >= music.TimeLength - Config.Audio.Crossfade or not music.IsPlaying then
			crossfadeTo(nextCityTrack(), false, Config.Audio.Crossfade)
		end
	end
end

-- =========================================================================
-- Ambiente
-- =========================================================================
local function ambientLoop(name: string): Sound?
	local id = Config.Ambient[name]
	if not id or id == "" then
		return nil
	end
	local sound = newSound(id, groups.Ambient)
	sound.Looped = true
	sound.Volume = 0
	sound:Play()
	ambient[name] = sound
	return sound
end

local function attachWater(part: Instance)
	if not part:IsA("BasePart") or Config.Ambient.Water == "" or part:FindFirstChild("WaterLoop") then
		return
	end
	local sound = newSound(Config.Ambient.Water, groups.Ambient, part)
	sound.Name = "WaterLoop"
	sound.Looped = true
	sound.Volume = 0.6
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 60
	sound:Play()
end

local function updateAmbient()
	local night =
		DayNight.nightAmount(DayNight.clockTime(Clock.now(), Config.DayNight.CycleSeconds, Config.DayNight.DayFraction))
	if ambient.DayBirds then
		ambient.DayBirds.Volume = 0.5 * (1 - night)
	end
	if ambient.Wind then
		ambient.Wind.Volume = 0.3
	end
	if ambient.NightCrickets then
		ambient.NightCrickets.Volume = 0.5 * night
	end
end

-- =========================================================================
-- Configurações
-- =========================================================================
function SoundController.applySettings(settings)
	if type(settings) ~= "table" then
		return
	end
	groups.Music.Volume = settings.Music or Config.DefaultSettings.Music
	groups.Ambient.Volume = settings.Ambient or Config.DefaultSettings.Ambient
	groups.SFX.Volume = settings.Sfx or Config.DefaultSettings.Sfx
end

function SoundController.init(controllers)
	Controllers = controllers
	makeGroup("Music", Config.DefaultSettings.Music)
	makeGroup("Ambient", Config.DefaultSettings.Ambient)
	makeGroup("SFX", Config.DefaultSettings.Sfx)
	for name, id in Config.Sfx do
		if id ~= "" then
			local sound = newSound(id, groups.SFX, script)
			sound.Name = name
			sfxTemplates[name] = sound
		end
	end
	for _, id in Config.Music.Tracks do
		if id ~= "" then
			table.insert(playlist, id)
		end
	end
	Hooks.click = function()
		SoundController.play("Click", { volume = 0.45, pitch = 1.1 })
	end
	Hooks.sfx = function(name: string)
		SoundController.play(name)
	end
end

function SoundController.start()
	-- Volumes salvos são aplicados pelo SettingsController (applySettings).
	for _, part in CollectionService:GetTagged("WaterSound") do
		attachWater(part)
	end
	CollectionService:GetInstanceAddedSignal("WaterSound"):Connect(attachWater)

	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		task.wait(2) -- música só depois que o jogo carrega, com fade-in
		ambientLoop("DayBirds")
		ambientLoop("Wind")
		ambientLoop("NightCrickets")
		while true do
			updateMusic()
			updateAmbient()
			task.wait(0.5)
		end
	end)
end

return SoundController
