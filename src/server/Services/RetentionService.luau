--[[
	RetentionService.luau
	- Recompensa diária (dia 1..7 crescente; perdeu um dia, volta ao 1).
	- Recompensa por entrar no grupo (Config.GroupId, checado com IsInGroup).
	- Códigos (Config.Codes), uso único por jogador.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local EconomyMath = require(Shared.EconomyMath)
local Net = require(Shared.Net)

local RetentionService = {}

local Services

local function today(): number
	return os.time() // 86400
end

function RetentionService.dailyInfo(player: Player): { available: boolean, day: number }
	local profile = Services.DataService.get(player)
	if not profile then
		return { available = false, day = 1 }
	end
	local daily = profile.Data.Daily
	local available, nextDay = EconomyMath.dailyNext(daily.LastDay, daily.Streak, today(), #Config.DailyRewards)
	return { available = available, day = if available then nextDay else math.max(1, daily.Streak) }
end

function RetentionService.claimDaily(player: Player): (boolean, string?)
	local profile = Services.DataService.get(player)
	if not profile then
		return false, "not_loaded"
	end
	local daily = profile.Data.Daily
	local day = today()
	local available, nextDay = EconomyMath.dailyNext(daily.LastDay, daily.Streak, day, #Config.DailyRewards)
	if not available then
		return false, "daily_claimed"
	end
	daily.Streak = nextDay
	daily.LastDay = day
	Services.EconomyService.grantReward(player, Config.DailyRewards[nextDay], true)
	Net.fire("Notify", player, "toast_daily", { n = nextDay }, "gold")
	return true, nil
end

function RetentionService.claimGroup(player: Player): (boolean, string?)
	local profile = Services.DataService.get(player)
	if not profile then
		return false, "not_loaded"
	end
	if Config.GroupId == 0 then
		return false, "group_disabled"
	end
	if profile.Data.GroupRewardClaimed then
		return false, "group_claimed"
	end
	local ok, member = pcall(function()
		return player:IsInGroup(Config.GroupId)
	end)
	if not ok then
		return false, "error"
	end
	if not member then
		return false, "group_not_member"
	end
	profile.Data.GroupRewardClaimed = true
	Services.EconomyService.grantReward(player, Config.GroupReward, false)
	Net.fire("Notify", player, "toast_group_ok", nil, "gold")
	return true, nil
end

local function normalizeCode(text: string): string
	local trimmed = string.gsub(text, "%s+", "")
	return string.upper(trimmed)
end

function RetentionService.redeemCode(player: Player, text: any): (boolean, string?)
	if not Net.check.string(text, 40) then
		return false, "code_invalid"
	end
	local profile = Services.DataService.get(player)
	if not profile then
		return false, "not_loaded"
	end
	local code = normalizeCode(text)
	local reward = Config.Codes[code]
	if not reward then
		return false, "code_invalid"
	end
	if profile.Data.RedeemedCodes[code] then
		return false, "code_used"
	end
	profile.Data.RedeemedCodes[code] = true
	Services.EconomyService.grantReward(player, reward, false)
	Net.fire("Notify", player, "toast_code_ok", nil, "gold")
	return true, nil
end

function RetentionService.init(services)
	Services = services
end

function RetentionService.start()
	Net.handle("ClaimDaily", function(player)
		local ok, reason = RetentionService.claimDaily(player)
		Services.EconomyService.markDirty(player)
		return ok, reason
	end)
	Net.handle("ClaimGroup", function(player)
		local ok, reason = RetentionService.claimGroup(player)
		Services.EconomyService.markDirty(player)
		return ok, reason
	end)
	Net.handle("RedeemCode", function(player, text)
		local ok, reason = RetentionService.redeemCode(player, text)
		Services.EconomyService.markDirty(player)
		return ok, reason
	end)
end

return RetentionService
