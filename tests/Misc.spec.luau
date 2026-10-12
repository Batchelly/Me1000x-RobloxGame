-- Base64, Format, SpatialHash e Strings.
local load = require(if script then script.Parent.lib.load else "./lib/load")
local Base64 = load("Base64")
local Format = load("Format")
local SpatialHash = load("SpatialHash")
local Strings = load("Strings")

return function()
	describe("Base64", function()
		it("vetores conhecidos (RFC 4648)", function()
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
				expect(Base64.encode(buffer.fromstring(input))).to.equal(expected)
				expect(buffer.tostring(Base64.decode(expected) :: buffer)).to.equal(input)
			end
		end)

		it("ida e volta com bytes aleatórios (todos os tamanhos 0..64)", function()
			math.randomseed(42)
			for len = 0, 64 do
				local buf = buffer.create(len)
				for i = 0, len - 1 do
					buffer.writeu8(buf, i, math.random(0, 255))
				end
				local decoded = Base64.decode(Base64.encode(buf)) :: buffer
				expect(buffer.tostring(decoded)).to.equal(buffer.tostring(buf))
			end
		end)

		it("rejeita entrada inválida", function()
			expect(Base64.decode("abc")).never.to.be.ok() -- tamanho não múltiplo de 4
			expect(Base64.decode("ab!d")).never.to.be.ok() -- caractere inválido
			expect(Base64.decode("a=bc")).never.to.be.ok() -- padding no meio
		end)
	end)

	describe("Format", function()
		it("abrevia números", function()
			expect(Format.number(0)).to.equal("0")
			expect(Format.number(999)).to.equal("999")
			expect(Format.number(1000)).to.equal("1K")
			expect(Format.number(1234)).to.equal("1.2K")
			expect(Format.number(3456789)).to.equal("3.4M")
			expect(Format.number(120500)).to.equal("120K")
			expect(Format.number(1e9)).to.equal("1B")
			expect(Format.number(-1500)).to.equal("-1.5K")
			expect(Format.number(999999)).to.equal("999K") -- 3 dígitos significativos
		end)

		it("tempo", function()
			expect(Format.time(65)).to.equal("1:05")
			expect(Format.time(0)).to.equal("0:00")
			expect(Format.time(3600 + 5 * 60)).to.equal("1h 05m")
			expect(Format.minutes(45)).to.equal("45min")
			expect(Format.minutes(200)).to.equal("3h 20min")
		end)

		it("multiplicador", function()
			expect(Format.multiplier(1)).to.equal("x1")
			expect(Format.multiplier(1.5)).to.equal("x1.5")
			expect(Format.multiplier(2.25)).to.equal("x2.25")
		end)
	end)

	describe("SpatialHash", function()
		it("encontra só itens das células próximas", function()
			local hash = SpatialHash.new(8)
			hash:insert("a", 1, 1)
			hash:insert("b", 9, 1)
			hash:insert("c", -20, -20)
			hash:insert("d", 100, 100)
			local found = {}
			hash:queryRect(0, 0, 10, 4, function(item)
				found[item] = true
			end)
			expect(found.a).to.equal(true)
			expect(found.b).to.equal(true)
			expect(found.c).never.to.be.ok()
			expect(found.d).never.to.be.ok()
		end)

		it("funciona com coordenadas negativas", function()
			local hash = SpatialHash.new(8)
			hash:insert("c", -20, -20)
			local found = {}
			hash:queryRect(-24, -24, -16, -16, function(item)
				found[item] = true
			end)
			expect(found.c).to.equal(true)
		end)
	end)

	describe("Strings", function()
		it("PT e EN têm as mesmas chaves", function()
			local missing = {}
			for key in Strings.pt do
				if not Strings.en[key] then
					table.insert(missing, "falta em EN: " .. key)
				end
			end
			for key in Strings.en do
				if not Strings.pt[key] then
					table.insert(missing, "falta em PT: " .. key)
				end
			end
			table.sort(missing)
			expect(table.concat(missing, ", ")).to.equal("")
		end)

		it("placeholders e idioma", function()
			expect(Strings.get("pt", "toast_rebirth_other", { name = "Ana", n = 3 })).to.equal("Ana fez Rebirth #3!")
			expect(Strings.get("en", "toast_rebirth_other", { name = "Ana", n = 3 })).to.equal("Ana did Rebirth #3!")
			expect(Strings.langFor("pt-br")).to.equal("pt")
			expect(Strings.langFor("en-us")).to.equal("en")
			expect(Strings.get("pt", "chave_inexistente")).to.equal("chave_inexistente")
		end)
	end)
end
