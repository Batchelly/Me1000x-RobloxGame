--[[
	T.luau: mini runner de testes em Luau (rodado pelo Lune).
	Uso:
		T.describe("Grupo", function()
			T.it("faz algo", function()
				T.eq(1 + 1, 2)
			end)
		end)
]]

local T = {}

local passed, failed = 0, 0
local failures: { string } = {}
local prefix = ""

function T.describe(name: string, fn: () -> ())
	local previous = prefix
	prefix = if previous == "" then name else previous .. " > " .. name
	fn()
	prefix = previous
end

function T.it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	local full = prefix .. " > " .. name
	if ok then
		passed += 1
		print("  ✔ " .. full)
	else
		failed += 1
		table.insert(failures, full .. "\n      " .. tostring(err))
		print("  ✘ " .. full)
	end
end

local function fail(message: string)
	error(message, 3)
end

function T.eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		fail(
			string.format(
				"%sesperado %s, veio %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(actual)
			)
		)
	end
end

function T.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		fail(
			string.format(
				"%sesperado %s ± %s, veio %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(tolerance),
				tostring(actual)
			)
		)
	end
end

function T.truthy(value: any, message: string?)
	if not value then
		fail(message or "esperado valor verdadeiro")
	end
end

function T.falsy(value: any, message: string?)
	if value then
		fail(message or ("esperado valor falso, veio " .. tostring(value)))
	end
end

function T.summary(): number
	print(string.format("\n%d passaram, %d falharam", passed, failed))
	for _, failure in failures do
		print("✘ " .. failure)
	end
	return failed
end

return T
