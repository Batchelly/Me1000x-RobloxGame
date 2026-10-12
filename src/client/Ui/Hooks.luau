--[[
	Hooks.luau
	Ganchos que os componentes de UI chamam sem depender dos controllers (evita require
	circular). O SoundController substitui estas funções no init.
]]

local Hooks = {}

-- Som de clique suave nos botões.
function Hooks.click() end

-- Toca um efeito pelo nome (Config.Sfx).
function Hooks.sfx(_name: string) end

-- Modal abriu/fechou (o Root usa para o BlurEffect).
function Hooks.modalChanged(_anyOpen: boolean) end

return Hooks
