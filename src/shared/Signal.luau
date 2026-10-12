--[[
	Signal.luau
	Sinal mínimo (sem BindableEvent) para eventos locais entre controllers.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local entry = { fn = fn }
	table.insert(handlers, entry)
	return {
		Disconnect = function()
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	for _, entry in table.clone(self._handlers) do
		task.spawn(entry.fn, ...)
	end
end

return Signal
