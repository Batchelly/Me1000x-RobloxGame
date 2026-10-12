--[[
	CharacterAnimator.luau
	Fallback de animação R6: o personagem é criado por código
	(CreateHumanoidModelFromDescription). Se ele vier sem o script "Animate", este
	controller toca as animações R6 clássicas pelo Animator.
]]

local Players = game:GetService("Players")

local CharacterAnimator = {}

local player = Players.LocalPlayer

-- Animações R6 padrão do Roblox (as mesmas do Animate clássico).
local ANIMATIONS = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	jump = "rbxassetid://125750702",
	fall = "rbxassetid://180436148",
	climb = "rbxassetid://180436334",
}

local function setup(character: Model)
	task.wait(1)
	if character.Parent == nil or character:FindFirstChild("Animate") then
		return -- já tem o Animate padrão
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks: { [string]: AnimationTrack } = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			track.Looped = name ~= "jump"
			tracks[name] = track
		end
	end

	local current: string? = nil
	local function play(name: string, speed: number?)
		local track = tracks[name]
		if not track then
			return
		end
		if current ~= name then
			if current and tracks[current] then
				tracks[current]:Stop(0.15)
			end
			current = name
			track:Play(0.15)
		end
		track:AdjustSpeed(speed or 1)
	end

	play("idle")
	humanoid.Running:Connect(function(speed)
		if speed > 0.5 then
			play("walk", speed / 16)
		else
			play("idle")
		end
	end)
	humanoid.Jumping:Connect(function(active)
		if active then
			play("jump")
		end
	end)
	humanoid.FreeFalling:Connect(function(active)
		if active then
			play("fall")
		end
	end)
	humanoid.Climbing:Connect(function(speed)
		play("climb", math.max(0.2, speed / 12))
	end)
end

function CharacterAnimator.init(_controllers) end

function CharacterAnimator.start()
	player.CharacterAdded:Connect(function(character)
		task.spawn(setup, character)
	end)
	if player.Character then
		task.spawn(setup, player.Character)
	end
end

return CharacterAnimator
