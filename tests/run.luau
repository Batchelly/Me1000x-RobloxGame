--[[
	Testes de lógica pura (sem Roblox). Rode com:
		lune run tests/run
]]

local process = require("@lune/process")
local T = require("./lib/T")

print("Me x1000: testes de lógica pura\n")
require("./Path.spec")
require("./Economy.spec")
require("./Misc.spec")
require("./V2.spec")

local failed = T.summary()
process.exit(if failed > 0 then 1 else 0)
