--[[
	load.luau
	Carrega um módulo de src/shared pelo nome, nos dois ambientes de teste:
	- Studio (TestEZ de verdade): ReplicatedStorage.Shared.<nome>
	- Lune (lune run test): ../../src/shared/<nome>.luau

	Uso nos specs:
		local load = require(if script then script.Parent.lib.load else "./lib/load")
		local Path = load("Path")
]]

return function(name: string): any
	if game then
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild(name))
	end
	return (require :: any)("../../src/shared/" .. name)
end
