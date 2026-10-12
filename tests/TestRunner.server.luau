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

if not RunService:IsStudio() or script:GetAttribute("Disabled") then
	return
end

local TestEZ = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("TestEZ"))

-- Deixa o jogo terminar de subir antes (os specs só usam módulos puros de Shared).
task.defer(function()
	local results = TestEZ.TestBootstrap:run({ script.Parent }, TestEZ.Reporters.TextReporterQuiet)
	if results.failureCount > 0 or #results.errors > 0 then
		warn(string.format("[Tests] %d teste(s) falharam: veja o Output acima", results.failureCount))
	end
end)
