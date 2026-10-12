-- Base64, Format, SpatialHash e Strings.
local T = require("./lib/T")
local Base64 = require("../src/shared/Base64")
local Format = require("../src/shared/Format")
local SpatialHash = require("../src/shared/SpatialHash")
local Strings = require("../src/shared/Strings")

T.describe("Base64", function()
	T.it("vetores conhecidos (RFC 4648)", function()
		local cases = {
			[""] = "",
			f = "Zg==",
			fo = "Zm8=",
			foo = "Zm9v",
			foob = "Zm9vYg==",
			fooba = "Zm9vYmE=",
			foobar = "Zm9vYmFy",
		}
		for input, expected in cases do
			T.eq(Base64.encode(buffer.fromstring(input)), expected, input)
			T.eq(buffer.tostring(Base64.decode(expected) :: buffer), input, expected)
		end
	end)

	T.it("ida e volta com bytes aleatórios (todos os tamanhos 0..64)", function()
		math.randomseed(42)
		for len = 0, 64 do
			local buf = buffer.create(len)
			for i = 0, len - 1 do
				buffer.writeu8(buf, i, math.random(0, 255))
			end
			local decoded = Base64.decode(Base64.encode(buf)) :: buffer
			T.eq(buffer.tostring(decoded), buffer.tostring(buf), "len " .. len)
		end
	end)

	T.it("rejeita entrada inválida", function()
		T.falsy(Base64.decode("abc"), "tamanho não múltiplo de 4")
		T.falsy(Base64.decode("ab!d"), "caractere inválido")
		T.falsy(Base64.decode("a=bc"), "padding no meio")
	end)
end)

T.describe("Format", function()
	T.it("abrevia números", function()
		T.eq(Format.number(0), "0")
		T.eq(Format.number(999), "999")
		T.eq(Format.number(1000), "1K")
		T.eq(Format.number(1234), "1.2K")
		T.eq(Format.number(3456789), "3.4M")
		T.eq(Format.number(120500), "120K")
		T.eq(Format.number(1e9), "1B")
		T.eq(Format.number(-1500), "-1.5K")
		T.eq(Format.number(999999), "999K") -- 3 dígitos significativos
	end)

	T.it("tempo", function()
		T.eq(Format.time(65), "1:05")
		T.eq(Format.time(0), "0:00")
		T.eq(Format.time(3600 + 5 * 60), "1h 05m")
		T.eq(Format.minutes(45), "45min")
		T.eq(Format.minutes(200), "3h 20min")
	end)

	T.it("multiplicador", function()
		T.eq(Format.multiplier(1), "x1")
		T.eq(Format.multiplier(1.5), "x1.5")
		T.eq(Format.multiplier(2.25), "x2.25")
	end)
end)

T.describe("SpatialHash", function()
	T.it("encontra só itens das células próximas", function()
		local hash = SpatialHash.new(8)
		hash:insert("a", 1, 1)
		hash:insert("b", 9, 1)
		hash:insert("c", -20, -20)
		hash:insert("d", 100, 100)
		local found = {}
		hash:queryRect(0, 0, 10, 4, function(item)
			found[item] = true
		end)
		T.truthy(found.a)
		T.truthy(found.b)
		T.falsy(found.c)
		T.falsy(found.d)
		local negative = {}
		hash:queryRect(-24, -24, -16, -16, function(item)
			negative[item] = true
		end)
		T.truthy(negative.c, "coordenadas negativas")
	end)
end)

T.describe("Strings", function()
	T.it("PT e EN têm as mesmas chaves", function()
		for key in Strings.pt do
			T.truthy(Strings.en[key], "falta em EN: " .. key)
		end
		for key in Strings.en do
			T.truthy(Strings.pt[key], "falta em PT: " .. key)
		end
	end)

	T.it("placeholders e idioma", function()
		T.eq(Strings.get("pt", "toast_rebirth_other", { name = "Ana", n = 3 }), "Ana fez Rebirth #3!")
		T.eq(Strings.get("en", "toast_rebirth_other", { name = "Ana", n = 3 }), "Ana did Rebirth #3!")
		T.eq(Strings.langFor("pt-br"), "pt")
		T.eq(Strings.langFor("en-us"), "en")
		T.eq(Strings.get("pt", "chave_inexistente"), "chave_inexistente")
	end)
end)

return nil
