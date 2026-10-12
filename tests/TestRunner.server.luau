--[[
	TestRunner.server.luau
	Roda todos os *.spec deste folder com o TestEZ ao dar Play no Studio (servidor).
	Em servidores publicados não faz nada. Resultado no Output:
		"Test results: ... N passed, M failed, K skipped" (só lista os testes que falharam)

	Para desligar temporariamente: marque o atributo "Disabled" = true neste Script.
	Fora do Studio, os mesmos specs rodam com: lune run test
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if not RunService:IsStudio() then
	return
end

-- Se o place tiver cópias antigas da pasta Tests (sobra de sessão antiga do Rojo), só a primeira
-- cópia a rodar continua, e "Disabled" em qualquer cópia desliga todas.
if ServerScriptService:GetAttribute("TestRunnerClaimed") then
	return
end
ServerScriptService:SetAttribute("TestRunnerClaimed", true)

local runners = {}
for _, inst in ServerScriptService:GetDescendants() do
	if inst:IsA("Script") and inst.Name == "TestRunner" then
		table.insert(runners, inst)
	end
end
if #runners > 1 then
	warn(string.format("[Tests] %d cópias de TestRunner no place: reconecte o Rojo para apagar as antigas", #runners))
end
for _, runner in runners do
	if runner:GetAttribute("Disabled") then
		return
	end
end

local TestEZ = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("TestEZ"))

-- Deixa o jogo terminar de subir antes (os specs só usam módulos puros de Shared).
task.defer(function()
	local results = TestEZ.TestBootstrap:run({ script.Parent }, TestEZ.Reporters.TextReporterQuiet)
	if results.failureCount > 0 or #results.errors > 0 then
		warn(string.format("[Tests] %d teste(s) falharam: veja o Output acima", results.failureCount))
	end
end)
