--[[
	LeaderboardService.luau
	- leaderstats (Cash e Rebirths) na lista de jogadores.
	- Placa de ranking na praça: ranking do servidor (Cash) + Top Rebirths global
	  (OrderedDataStore; se indisponível, a coluna global fica vazia).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local LeaderboardService = {}

local Services
local globalStore: OrderedDataStore? = nil
local nameCache: { [number]: string } = {}
local globalRows: { { name: string, value: number } } = {}

type Board = { serverRows: { TextLabel }, globalRows: { TextLabel } }
local boards: { Board } = {}

-- =========================================================================
-- leaderstats
-- =========================================================================
function LeaderboardService.onPlayerLoaded(player: Player, profile)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = math.floor(profile.Data.Cash)
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = profile.Data.Rebirths
	rebirths.Parent = stats
	stats.Parent = player
end

function LeaderboardService.updateStats(player: Player, cash: number, rebirths: number)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local cashValue = stats:FindFirstChild("Cash") :: IntValue?
	local rebirthValue = stats:FindFirstChild("Rebirths") :: IntValue?
	if cashValue then
		cashValue.Value = math.floor(cash)
	end
	if rebirthValue then
		rebirthValue.Value = rebirths
	end
end

local function pushGlobal(userId: number, rebirths: number)
	if not globalStore or rebirths <= 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			(globalStore :: OrderedDataStore):SetAsync(tostring(userId), rebirths)
		end)
	end)
end

function LeaderboardService.onRebirth(player: Player, rebirths: number)
	pushGlobal(player.UserId, rebirths)
end

function LeaderboardService.onPlayerRemoving(player: Player)
	local profile = Services.DataService.get(player)
	if profile then
		pushGlobal(player.UserId, profile.Data.Rebirths)
	end
end

-- =========================================================================
-- Placa
-- =========================================================================
local function makeLabel(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = textSize or 28
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function buildBoard(content: Frame): Board
	local board: Board = { serverRows = {}, globalRows = {} }
	local title =
		makeLabel(content, Strings.get("pt", "board_title"), UDim2.new(0.6, -20, 0, 50), UDim2.fromOffset(16, 8), 36)
	title.TextColor3 = BrickColor.new("Bright yellow").Color
	local globalTitle =
		makeLabel(content, Strings.get("pt", "board_global"), UDim2.new(0.4, -16, 0, 50), UDim2.new(0.6, 0, 0, 8), 32)
	globalTitle.TextColor3 = BrickColor.new("Bright yellow").Color
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(0, 0, 0)
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(0, 4, 1, -20)
	divider.Position = UDim2.new(0.6, -10, 0, 10)
	divider.Parent = content
	for i = 1, Config.Leaderboard.BoardSize do
		table.insert(
			board.serverRows,
			makeLabel(content, "", UDim2.new(0.6, -30, 0, 40), UDim2.fromOffset(16, 60 + (i - 1) * 42))
		)
	end
	for i = 1, 5 do
		table.insert(
			board.globalRows,
			makeLabel(content, "", UDim2.new(0.4, -20, 0, 40), UDim2.new(0.6, 6, 0, 60 + (i - 1) * 42), 26)
		)
	end
	return board
end

local function refreshServer()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local profile = Services.DataService.get(player)
		if profile then
			table.insert(
				entries,
				{ name = player.DisplayName, cash = profile.Data.Cash, rebirths = profile.Data.Rebirths }
			)
		end
	end
	table.sort(entries, function(a, b)
		if a.rebirths ~= b.rebirths then
			return a.rebirths > b.rebirths
		end
		return a.cash > b.cash
	end)
	for _, board in boards do
		for i, row in board.serverRows do
			local entry = entries[i]
			row.Text = if entry
				then string.format("%d. %s  💰%s  🔁%d", i, entry.name, Format.number(entry.cash), entry.rebirths)
				else ""
		end
		for i, row in board.globalRows do
			local entry = globalRows[i]
			row.Text = if entry then string.format("%d. %s  🔁%d", i, entry.name, entry.value) else ""
		end
	end
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local final = if ok and name then name else ("#" .. userId)
	nameCache[userId] = final
	return final
end

local function refreshGlobal()
	if not globalStore then
		return
	end
	local ok, pages = pcall(function()
		return (globalStore :: OrderedDataStore):GetSortedAsync(false, 5)
	end)
	if not ok or not pages then
		return
	end
	local rows = {}
	for _, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(rows, { name = nameFor(userId), value = item.value })
		end
	end
	globalRows = rows
end

-- =========================================================================
-- Ciclo de vida
-- =========================================================================
function LeaderboardService.init(services)
	Services = services
	for _, content in services.Map.boardLabels do
		table.insert(boards, buildBoard(content))
	end
	if not services.DataService.isOffline() then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(Config.Leaderboard.GlobalStoreName)
		end)
		if ok then
			globalStore = store
		end
	end
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			refreshServer()
			task.wait(Config.Leaderboard.ServerRefreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			refreshGlobal()
			task.wait(Config.Leaderboard.GlobalRefreshSeconds)
		end
	end)
end

return LeaderboardService
