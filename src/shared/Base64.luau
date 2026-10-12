--[[
	Base64.luau
	buffer <-> string Base64. Usado para salvar gravações (buffers binários) no DataStore,
	que só aceita strings UTF-8 válidas. Módulo puro (testável no Lune).
]]

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD = string.byte("=")

local encodeTable = buffer.create(64)
local decodeTable = buffer.create(256)
buffer.fill(decodeTable, 0, 255)
for i = 1, 64 do
	local byte = string.byte(ALPHABET, i)
	buffer.writeu8(encodeTable, i - 1, byte)
	buffer.writeu8(decodeTable, byte, i - 1)
end

function Base64.encode(input: buffer): string
	local len = buffer.len(input)
	local out = buffer.create(math.ceil(len / 3) * 4)
	local o = 0
	for i = 0, len - 1, 3 do
		local b1 = buffer.readu8(input, i)
		local b2 = if i + 1 < len then buffer.readu8(input, i + 1) else 0
		local b3 = if i + 2 < len then buffer.readu8(input, i + 2) else 0
		local n = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2, 8), b3)
		buffer.writeu8(out, o, buffer.readu8(encodeTable, bit32.band(bit32.rshift(n, 18), 63)))
		buffer.writeu8(out, o + 1, buffer.readu8(encodeTable, bit32.band(bit32.rshift(n, 12), 63)))
		buffer.writeu8(
			out,
			o + 2,
			if i + 1 < len then buffer.readu8(encodeTable, bit32.band(bit32.rshift(n, 6), 63)) else PAD
		)
		buffer.writeu8(out, o + 3, if i + 2 < len then buffer.readu8(encodeTable, bit32.band(n, 63)) else PAD)
		o += 4
	end
	return buffer.tostring(out)
end

-- Retorna nil se a string não for Base64 válido.
function Base64.decode(text: string): buffer?
	local len = #text
	if len % 4 ~= 0 then
		return nil
	end
	if len == 0 then
		return buffer.create(0)
	end
	local input = buffer.fromstring(text)
	local padding = 0
	if buffer.readu8(input, len - 1) == PAD then
		padding += 1
	end
	if buffer.readu8(input, len - 2) == PAD then
		padding += 1
	end
	local outLen = (len // 4) * 3 - padding
	local out = buffer.create(outLen)
	local o = 0
	for i = 0, len - 1, 4 do
		local n = 0
		for j = 0, 3 do
			local c = buffer.readu8(input, i + j)
			local v
			if c == PAD then
				if i + j < len - padding then
					return nil
				end
				v = 0
			else
				v = buffer.readu8(decodeTable, c)
				if v == 255 then
					return nil
				end
			end
			n = bit32.bor(bit32.lshift(n, 6), v)
		end
		if o < outLen then
			buffer.writeu8(out, o, bit32.band(bit32.rshift(n, 16), 255))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 8), 255))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.band(n, 255))
		end
		o += 3
	end
	return out
end

return Base64
