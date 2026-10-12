--[[
	SpatialHash.luau
	Hash espacial 2D (X/Z) para itens estáticos (moedas). Célula padrão de 8 studs.
	Módulo puro (testável no Lune).
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type SpatialHash<T> = typeof(setmetatable(
	{} :: {
		cellSize: number,
		cells: { [number]: { T } },
	},
	SpatialHash
))

local OFFSET = 50000

local function key(cx: number, cz: number): number
	return (cx + OFFSET) * 100000 + (cz + OFFSET)
end

function SpatialHash.new<T>(cellSize: number): SpatialHash<T>
	return setmetatable({ cellSize = cellSize, cells = {} }, SpatialHash) :: any
end

function SpatialHash.insert<T>(self: SpatialHash<T>, item: T, x: number, z: number)
	local size = self.cellSize
	local k = key(math.floor(x / size), math.floor(z / size))
	local cell = self.cells[k]
	if not cell then
		cell = {}
		self.cells[k] = cell
	end
	table.insert(cell, item)
end

-- Remove um item inserido em (x, z). Retorna true se achou.
function SpatialHash.remove<T>(self: SpatialHash<T>, item: T, x: number, z: number): boolean
	local size = self.cellSize
	local k = key(math.floor(x / size), math.floor(z / size))
	local cell = self.cells[k]
	if not cell then
		return false
	end
	local index = table.find(cell, item)
	if not index then
		return false
	end
	table.remove(cell, index)
	if #cell == 0 then
		self.cells[k] = nil
	end
	return true
end

-- Chama fn(item) para cada item nas células que tocam o retângulo.
function SpatialHash.queryRect<T>(
	self: SpatialHash<T>,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	fn: (T) -> ()
)
	local size = self.cellSize
	local cells = self.cells
	for cx = math.floor(minX / size), math.floor(maxX / size) do
		for cz = math.floor(minZ / size), math.floor(maxZ / size) do
			local cell = cells[key(cx, cz)]
			if cell then
				for _, item in cell do
					fn(item)
				end
			end
		end
	end
end

return SpatialHash
