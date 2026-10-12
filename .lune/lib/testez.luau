--[[
	testez.luau
	Executa specs no formato TestEZ fora do Studio (Lune). O TestEZ de verdade depende de
	instâncias do Roblox (script.Parent, TestService), então aqui fica o subconjunto da API
	que os specs do projeto usam, com a mesma semântica:

		describe / it / describeSKIP / itSKIP / describeFOCUS / itFOCUS
		beforeAll / afterAll / beforeEach / afterEach
		expect(v).to.be.ok() / .equal(x) / .near(x, limit?) / .a("type") / .throw("trecho"?)
		modificadores: to, be, been, have, was, at, never

	No Studio quem roda os mesmos arquivos é o TestEZ real (tests/TestRunner.server.luau).
	Se um spec usar algo que não está aqui, ele falha com "matcher não suportado no Lune".
]]

local TestEZ = {}

type Node = {
	phrase: string,
	kind: "describe" | "it",
	fn: (() -> ())?,
	children: { Node },
	parent: Node?,
	skip: boolean,
	focus: boolean,
	beforeAll: { () -> () },
	afterAll: { () -> () },
	beforeEach: { () -> () },
	afterEach: { () -> () },
}

local function newNode(phrase: string, kind: "describe" | "it", parent: Node?): Node
	return {
		phrase = phrase,
		kind = kind,
		fn = nil,
		children = {},
		parent = parent,
		skip = false,
		focus = false,
		beforeAll = {},
		afterAll = {},
		beforeEach = {},
		afterEach = {},
	}
end

-- =========================================================================
-- expect
-- =========================================================================

local CHAIN_KEYS = { to = true, be = true, been = true, have = true, was = true, at = true }

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local matchers = {}

function matchers.ok(value: any)
	return value ~= nil,
		string.format("Expected value %s to be non-nil", show(value)),
		string.format("Expected value %s to be nil", show(value))
end

function matchers.equal(value: any, other: any)
	return value == other,
		string.format(
			"Expected value %s (%s), got %s (%s) instead",
			show(other),
			typeof(other),
			show(value),
			typeof(value)
		),
		string.format("Expected anything but value %s (%s)", show(other), typeof(other))
end

function matchers.near(value: any, other: number, limit: number?)
	local tolerance = limit or 1e-7
	local pass = type(value) == "number" and math.abs(value - other) <= tolerance
	return pass,
		string.format(
			"Expected value to be near %s (within %s) but got %s instead",
			show(other),
			show(tolerance),
			show(value)
		),
		string.format(
			"Expected value to not be near %s (within %s) but got %s instead",
			show(other),
			show(tolerance),
			show(value)
		)
end

function matchers.a(value: any, typeName: string)
	return typeof(value) == typeName,
		string.format("Expected value of type %q, got value %s of type %s", typeName, show(value), typeof(value)),
		string.format("Expected value not of type %q, got value %s of type %s", typeName, show(value), typeof(value))
end
matchers.an = matchers.a

function matchers.throw(value: any, substring: string?)
	local ok, err = pcall(value)
	local message = tostring(err)
	local pass = not ok and (substring == nil or string.find(message, substring, 1, true) ~= nil)
	local detail = if substring then string.format(" containing %q", substring) else ""
	return pass,
		string.format("Expected function to throw an error%s, but %s", detail, if ok then "it did not" else message),
		string.format("Expected function to succeed, but it threw an error%s: %s", detail, message)
end

local Expectation = {}

local function newExpectation(value: any, negated: boolean)
	return setmetatable({ value = value, negated = negated }, Expectation)
end

function Expectation.__index(self: any, key: string): any
	if CHAIN_KEYS[key] then
		return self
	end
	if key == "never" then
		return newExpectation(rawget(self, "value"), not rawget(self, "negated"))
	end
	local matcher = matchers[key]
	if not matcher then
		error(string.format("matcher não suportado no Lune: %q", key), 2)
	end
	return function(...)
		local negated = rawget(self, "negated")
		local pass, positive, negative = matcher(rawget(self, "value"), ...)
		if pass == negated then
			-- nível 2 = a linha do spec que chamou o matcher
			error(if negated then negative else positive, 2)
		end
		return self
	end
end

local function expect(value: any)
	return newExpectation(value, false)
end

-- =========================================================================
-- Planejamento (os corpos de describe rodam agora, como no TestEZ)
-- =========================================================================

local root = newNode("", "describe", nil)
local current = root
local anyFocus = false

local function declare(kind: "describe" | "it", phrase: string, fn: () -> (), flag: string?)
	local node = newNode(phrase, kind, current)
	node.fn = fn
	node.skip = flag == "skip"
	node.focus = flag == "focus"
	if node.focus then
		anyFocus = true
	end
	table.insert(current.children, node)
	if kind == "describe" then
		local previous = current
		current = node
		local ok, err = pcall(fn)
		current = previous
		if not ok then
			-- erro no corpo do describe vira um teste que falha
			local failing = newNode("(erro ao montar o describe)", "it", node)
			failing.fn = function()
				error(err, 0)
			end
			table.insert(node.children, failing)
		end
	end
end

local env = {
	expect = expect,
	describe = function(phrase, fn)
		declare("describe", phrase, fn)
	end,
	describeSKIP = function(phrase, fn)
		declare("describe", phrase, fn, "skip")
	end,
	describeFOCUS = function(phrase, fn)
		declare("describe", phrase, fn, "focus")
	end,
	it = function(phrase, fn)
		declare("it", phrase, fn)
	end,
	itSKIP = function(phrase, fn)
		declare("it", phrase, fn, "skip")
	end,
	itFOCUS = function(phrase, fn)
		declare("it", phrase, fn, "focus")
	end,
	beforeAll = function(fn)
		table.insert(current.beforeAll, fn)
	end,
	afterAll = function(fn)
		table.insert(current.afterAll, fn)
	end,
	beforeEach = function(fn)
		table.insert(current.beforeEach, fn)
	end,
	afterEach = function(fn)
		table.insert(current.afterEach, fn)
	end,
}

-- Registra um spec (a função que o módulo .spec retorna).
function TestEZ.plan(name: string, specFn: any)
	if type(specFn) ~= "function" then
		declare("describe", name, function()
			error(name .. " deve retornar uma função (formato TestEZ)", 0)
		end)
		return
	end
	setfenv(specFn, setmetatable(table.clone(env), { __index = getfenv(specFn) }))
	declare("describe", name, specFn)
end

-- =========================================================================
-- Execução
-- =========================================================================

type Results = { passed: number, failed: number, skipped: number, failures: { string } }

local function isFocused(node: Node): boolean
	local n: Node? = node
	while n do
		if n.focus then
			return true
		end
		n = n.parent
	end
	return false
end

local function hasFocusedDescendant(node: Node): boolean
	for _, child in node.children do
		if child.focus or hasFocusedDescendant(child) then
			return true
		end
	end
	return false
end

local function runHooks(hooks: { () -> () }): (boolean, any)
	for _, hook in hooks do
		local ok, err = pcall(hook)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

local function eachHooks(node: Node, field: "beforeEach" | "afterEach"): { () -> () }
	local chain = {}
	local n: Node? = node
	while n do
		local hooks = (n :: any)[field]
		-- beforeEach de fora para dentro, afterEach de dentro para fora
		if field == "beforeEach" then
			for i = #hooks, 1, -1 do
				table.insert(chain, 1, hooks[i])
			end
		else
			for _, hook in hooks do
				table.insert(chain, hook)
			end
		end
		n = n.parent
	end
	return chain
end

local function runNode(node: Node, path: string, depth: number, skipped: boolean, results: Results)
	local indent = string.rep("  ", depth)
	local fullPath = if path == "" then node.phrase else path .. " > " .. node.phrase
	local skip = skipped or node.skip or (anyFocus and not isFocused(node) and not hasFocusedDescendant(node))

	if node.kind == "it" then
		if skip then
			results.skipped += 1
			print(indent .. "~ " .. node.phrase)
			return
		end
		local ok, err = runHooks(eachHooks(node.parent :: Node, "beforeEach"))
		if ok then
			ok, err = pcall(node.fn :: () -> ())
		end
		local afterOk, afterErr = runHooks(eachHooks(node.parent :: Node, "afterEach"))
		if ok and not afterOk then
			ok, err = false, afterErr
		end
		if ok then
			results.passed += 1
			print(indent .. "✔ " .. node.phrase)
		else
			results.failed += 1
			print(indent .. "✘ " .. node.phrase)
			table.insert(results.failures, fullPath .. "\n    " .. tostring(err))
		end
		return
	end

	if node ~= root then
		print(indent .. node.phrase)
	end
	local ok, err = true, nil
	if not skip then
		ok, err = runHooks(node.beforeAll)
	end
	if not ok then
		results.failed += 1
		table.insert(results.failures, fullPath .. " (beforeAll)\n    " .. tostring(err))
		skip = true
	end
	for _, child in node.children do
		runNode(child, if node == root then "" else fullPath, if node == root then depth else depth + 1, skip, results)
	end
	if not skip then
		local afterOk, afterErr = runHooks(node.afterAll)
		if not afterOk then
			results.failed += 1
			table.insert(results.failures, fullPath .. " (afterAll)\n    " .. tostring(afterErr))
		end
	end
end

function TestEZ.run(): Results
	local results: Results = { passed = 0, failed = 0, skipped = 0, failures = {} }
	runNode(root, "", 0, false, results)
	print(string.format("\n%d passed, %d failed, %d skipped", results.passed, results.failed, results.skipped))
	for _, failure in results.failures do
		print("\n✘ " .. failure)
	end
	return results
end

return TestEZ
