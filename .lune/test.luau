--[[
	Roda todos os tests/*.spec.luau (formato TestEZ) fora do Studio:
		lune run test
	Filtro opcional pelo nome do arquivo:
		lune run test Path
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestEZ = require("./lib/testez")

local filter = process.args[1]

local files = {}
for _, file in fs.readDir("tests") do
	local name = string.match(file, "^(.+%.spec)%.luau$")
	if name and (not filter or string.find(string.lower(name), string.lower(filter), 1, true)) then
		table.insert(files, name)
	end
end
table.sort(files)

if #files == 0 then
	print("Nenhum spec encontrado em tests/" .. (if filter then " com o filtro " .. filter else ""))
	process.exit(1)
end

for _, name in files do
	TestEZ.plan(name, (require :: any)("../tests/" .. name))
end

local results = TestEZ.run()
process.exit(if results.failed > 0 then 1 else 0)
