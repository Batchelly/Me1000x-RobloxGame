--[[
	SprintController.luau
	Correr segurando Shift (esquerdo ou direito). Multiplica a WalkSpeed definida pelo servidor
	(upgrade de velocidade, -30% carregando fita...) por Config.Sprint.Multiplier.
	A física do personagem é do cliente, então mudar a WalkSpeed aqui já vale; o servidor
	conta com o multiplicador na validação de gravação (RecordingService).

	Com SignalBehavior Deferred o WalkSpeed changed chega DEPOIS do nosso próprio set, então
	não dá para usar uma trava booleana: comparamos com o último valor que nós aplicamos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SprintController = {}

local player = Players.LocalPlayer

local shiftHeld = false
local humanoid: Humanoid? = nil
local baseSpeed = Config.BaseWalkSpeed
local applied: number? = nil -- último WalkSpeed que este controller escreveu

local function apply()
	local h = humanoid
	if not h then
		return
	end
	local target = if shiftHeld then baseSpeed * Config.Sprint.Multiplier else baseSpeed
	applied = target
	if h.WalkSpeed ~= target then
		h.WalkSpeed = target
	end
end

local function setShift(held: boolean)
	if shiftHeld == held then
		return
	end
	shiftHeld = held
	apply()
end

local function isShift(input: InputObject): boolean
	return input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not h or character ~= player.Character then
		return
	end
	humanoid = h
	baseSpeed = h.WalkSpeed
	applied = nil
	h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if humanoid ~= h then
			return
		end
		local speed = h.WalkSpeed
		if applied and math.abs(speed - applied) < 0.01 then
			return -- eco do nosso próprio set
		end
		-- Mudança vinda do servidor (upgrade, carga de fita): vira a nova base.
		baseSpeed = speed
		apply()
	end)
	apply()
end

-- FOV sobe só quando está correndo DE VERDADE (Shift + andando no chão), com suavização.
local function updateFov(dt: number)
	local camera = workspace.CurrentCamera
	local h = humanoid
	if not camera then
		return
	end
	local running = shiftHeld
		and h ~= nil
		and h.Health > 0
		and h.MoveDirection.Magnitude > 0.1
		and h.FloorMaterial ~= Enum.Material.Air
	local target = if running then Config.Sprint.FieldOfView else Config.Sprint.NormalFieldOfView
	local current = camera.FieldOfView
	if math.abs(current - target) < 0.05 then
		if current ~= target then
			camera.FieldOfView = target
		end
		return
	end
	camera.FieldOfView = current + (target - current) * math.min(1, dt * 10)
end

function SprintController.start()
	-- Sem checar "processed": o PlayerModule pode afundar o Shift (Shift Lock) e a corrida
	-- nunca começaria. Só ignora quando está digitando numa caixa de texto.
	UserInputService.InputBegan:Connect(function(input)
		if isShift(input) and not UserInputService:GetFocusedTextBox() then
			setShift(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isShift(input) then
			setShift(false)
		end
	end)
	-- Perdeu o foco da janela com Shift apertado: não fica correndo para sempre.
	UserInputService.WindowFocusReleased:Connect(function()
		setShift(false)
	end)
	UserInputService.TextBoxFocused:Connect(function()
		setShift(false)
	end)

	RunService.RenderStepped:Connect(updateFov)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return SprintController
