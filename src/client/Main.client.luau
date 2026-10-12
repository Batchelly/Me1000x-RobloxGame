--[[
	Main.client.luau
	Ponto de entrada do cliente: monta a UI por código, liga os controllers e pede ao
	servidor o estado inicial + todos os clones existentes (Hello).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Controllers = script.Parent:WaitForChild("Controllers")
local Ui = script.Parent:WaitForChild("Ui")
local Root = require(Ui:WaitForChild("Root"))

local ORDER = {
	"StateController",
	"SoundController", -- registra os ganchos de som da UI (Hooks)
	"NotifyController",
	"HudController",
	"ShopController",
	"BaseMenuController",
	"PanelsController",
	"SettingsController",
	"RecordController",
	"CloneRenderer",
	"WorldFxController",
	"BaseController",
	"EnvironmentController",
	"CharacterAnimator",
	"SprintController",
}

Root.init()

local loaded: { [string]: any } = {}
for _, name in ORDER do
	loaded[name] = require(Controllers:WaitForChild(name))
end
-- init: monta UI e conecta eventos (antes do Hello, para não perder CloneAdded).
for _, name in ORDER do
	local controller = loaded[name]
	if controller.init then
		controller.init(loaded)
	end
end
for _, name in ORDER do
	local controller = loaded[name]
	if controller.start then
		controller.start()
	end
end

-- Estado inicial + snapshot dos clones do servidor.
task.spawn(function()
	for _ = 1, 5 do
		local result = Net.invoke("Hello")
		if type(result) == "table" then
			loaded.CloneRenderer.loadSnapshot(result.clones)
			loaded.StateController.set(result.state)
			local state = result.state
			if state and state.cloneCount == 0 and state.rebirths == 0 then
				loaded.NotifyController.showKey("toast_welcome", nil, "gold")
			end
			return
		end
		task.wait(2)
	end
end)
