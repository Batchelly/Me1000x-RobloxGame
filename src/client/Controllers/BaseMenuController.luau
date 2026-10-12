--[[
	BaseMenuController.luau
	- Menu "SUA BASE": nível atual (1..6), linha do tempo dos níveis, o que o próximo nível
	  constrói, botões Construir (Cash) e Construir agora (Robux), e proteção (Trancar grátis,
	  Trancar 5 min / 30 min).
	- Tela "SUAS FITAS": cada fita com cor, mini-mapa do trajeto, zona (Cidade/Pista), renda
	  por minuto e botões Regravar e Excluir. No modo "substituir" (estante cheia ao gravar),
	  cada fita ganha o botão Substituir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Path = require(Shared.Path)

local Ui = script.Parent.Parent.Ui
local Builder = require(Ui.Builder)
local I18n = require(Ui.I18n)
local Theme = require(Ui.Theme)
local Button = require(Ui.Components.Button)
local Modal = require(Ui.Components.Modal)

local BaseMenuController = {}

local Controllers
local baseModal: Modal.Modal
local clonesModal: Modal.Modal
local refs = {} :: { [string]: any }
local replaceCallback: ((number) -> ())? = nil
local renderedKey = ""

-- =========================================================================
-- Menu da Base
-- =========================================================================
local function buildBase()
	baseModal = Modal.new({ Title = I18n.t("base_title"), Icon = "🏠", Size = Vector2.new(660, 420) })
	local content = baseModal.content
	refs.level = Builder.label({
		Text = "",
		FontFace = Theme.Fonts.Heavy,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, 0, 0, 36),
		Parent = content,
	})
	refs.stats = Builder.label({
		Text = "",
		TextSize = 17,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 36),
		Parent = content,
	})

	-- Linha do tempo dos níveis
	local timeline = Builder.create("Frame", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = content,
	})
	Builder.list(timeline, 10, true)
	refs.dots = {}
	for level = 1, #Config.BaseLevels do
		local dot = Builder.label({
			Text = tostring(level),
			FontFace = Theme.Fonts.Heavy,
			TextSize = 18,
			Size = UDim2.fromOffset(44, 44),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Colors.bgLighter,
			LayoutOrder = level,
			Parent = timeline,
		})
		Builder.corner(dot, 22)
		Builder.stroke(dot)
		refs.dots[level] = dot
	end

	-- Próximo nível
	local next = Builder.create("Frame", {
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Theme.Colors.bgLight,
		Parent = content,
	})
	Builder.corner(next, Theme.Radius.M)
	Builder.stroke(next)
	refs.nextTitle = Builder.label({
		Text = "",
		FontFace = Theme.Fonts.Bold,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 28),
		Parent = next,
	})
	refs.nextDesc = Builder.label({
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(0.55, -16, 0, 76),
		Parent = next,
	})
	refs.build = Button.new({
		Text = "",
		Variant = "success",
		Size = UDim2.fromOffset(240, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		TextSize = 19,
		OnClick = function()
			local ok, reason = Net.invoke("BuyBaseLevel")
			if not ok then
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = next,
	})
	refs.instant = Button.new({
		Text = "",
		Variant = "warning",
		Size = UDim2.fromOffset(240, 46),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		TextSize = 18,
		OnClick = function()
			local state = Controllers.StateController.get()
			if state then
				Controllers.HudController.promptProduct("InstantBaseLevel" .. (state.baseLevel + 1))
			end
		end,
		Parent = next,
	})

	-- Proteção
	Builder.label({
		Text = "🛡️ " .. I18n.t("base_lock_section"),
		FontFace = Theme.Fonts.Bold,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 228),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = content,
	})
	local row = Builder.create("Frame", {
		Position = UDim2.fromOffset(0, 258),
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		Parent = content,
	})
	Builder.list(row, 10, true)
	Button.new({
		Text = "🔒 " .. I18n.t("btn_lock"),
		Variant = "danger",
		Size = UDim2.fromOffset(190, 64),
		LayoutOrder = 1,
		OnClick = function()
			local ok, reason = Net.invoke("LockBase")
			if not ok then
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = row,
	})
	for i, key in { "LockBase5", "LockBase30" } do
		Button.new({
			Text = Config.Products[key].Icon .. " " .. I18n.t("product_" .. key .. "_name") .. "\n" .. I18n.t(
				"price_robux",
				{ price = Config.Products[key].Price }
			),
			Variant = "warning",
			Size = UDim2.fromOffset(190, 64),
			TextSize = 17,
			LayoutOrder = i + 1,
			OnClick = function()
				Controllers.HudController.promptProduct(key)
			end,
			Parent = row,
		})
	end
end

local function refreshBase(state)
	local level = state.baseLevel or 1
	refs.level.Text = I18n.t("base_level", { n = level }) .. " / " .. #Config.BaseLevels
	refs.stats.Text = I18n.t("base_slots", { n = state.slots })
		.. "  ·  "
		.. I18n.t("base_vault", { n = Format.number(state.vaultCapacity) })
	for l, dot in refs.dots do
		dot.BackgroundColor3 = if l <= level
			then Theme.Colors.success
			elseif l == level + 1 then Theme.Colors.primary
			else Theme.Colors.bgLighter
		dot.TextColor3 = if l <= level then Theme.Colors.textDark else Theme.Colors.text
	end
	local nextLevel = level + 1
	if state.nextLevelPrice then
		refs.nextTitle.Text = "🧱 " .. I18n.t("base_next", { n = nextLevel })
		refs.nextDesc.Text = I18n.t("base_level_" .. nextLevel)
		refs.build:setButton(
			I18n.t("base_build", { price = Format.number(state.nextLevelPrice) }),
			state.cash >= state.nextLevelPrice
		)
		local product = Config.Products["InstantBaseLevel" .. nextLevel]
		refs.instant.Instance.Visible = product ~= nil
		if product then
			refs.instant:setText(I18n.t("base_instant", { price = product.Price }))
			refs.instant:setEnabled(product.Id ~= 0)
			if product.Id == 0 then
				refs.instant:setText(I18n.t("soon"))
			end
		end
	else
		refs.nextTitle.Text = I18n.t("base_max")
		refs.nextDesc.Text = I18n.t("base_level_" .. level)
		refs.build:setText(I18n.t("max"))
		refs.build:setEnabled(false)
		refs.instant.Instance.Visible = false
	end
end

function BaseMenuController.openBase()
	local state = Controllers.StateController.get()
	if state then
		refreshBase(state)
	end
	baseModal.open()
end

-- =========================================================================
-- Fitas
-- =========================================================================
local function miniMap(parent: Instance, cloneId: number, color: Color3)
	local frame = Builder.create("Frame", {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Theme.Colors.bg,
		Parent = parent,
	})
	Builder.corner(frame, 10)
	local path = Controllers.CloneRenderer.getPath(cloneId)
	if not path then
		return frame
	end
	local points = Path.preview(path, 28)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, #points, 2 do
		minX, maxX = math.min(minX, points[i]), math.max(maxX, points[i])
		minZ, maxZ = math.min(minZ, points[i + 1]), math.max(maxZ, points[i + 1])
	end
	local span = math.max(maxX - minX, maxZ - minZ, 1)
	for i = 1, #points, 2 do
		local x = 6 + (points[i] - minX) / span * 52
		local z = 6 + (points[i + 1] - minZ) / span * 52
		local dot = Builder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, z),
			Size = UDim2.fromOffset(if i == 1 then 7 else 4, if i == 1 then 7 else 4),
			BackgroundColor3 = if i == 1 then Theme.Colors.text else color,
			BorderSizePixel = 0,
			Parent = frame,
		})
		Builder.corner(dot, 4)
	end
	return frame
end

local function buildClones()
	clonesModal = Modal.new({ Title = I18n.t("clones_title"), Icon = "📼", Size = Vector2.new(720, 420) })
	local list = Builder.create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = clonesModal.content,
	})
	local layout = Builder.list(list, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	refs.list = list
	clonesModal.onClose(function()
		replaceCallback = nil
	end)
end

local function cloneRow(list: Instance, info, replacing: boolean)
	local row = Builder.create("Frame", {
		Name = "Row" .. info.slot,
		Size = UDim2.new(1, -12, 0, 80),
		BackgroundColor3 = Theme.Colors.bgLight,
		LayoutOrder = info.slot,
		Parent = list,
	})
	Builder.corner(row, Theme.Radius.S)
	local stroke = Builder.stroke(row)
	if info.golden then
		stroke.Color = Theme.Colors.gold
		stroke.Transparency = 0
	elseif info.transit or info.fallen then
		stroke.Color = Theme.Colors.danger
		stroke.Transparency = 0.2
	end
	local tapeColor = BrickColor.new(info.tapeColor or "Black").Color
	local swatch = Builder.create("Frame", {
		Size = UDim2.new(0, 8, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = tapeColor,
		Parent = row,
	})
	Builder.corner(swatch, 4)
	local map = miniMap(row, info.cloneId, tapeColor)
	map.Position = UDim2.fromOffset(24, 8)

	local status = if info.transit
		then I18n.t("clone_transit")
		elseif info.fallen then I18n.t("clone_fallen")
		else I18n.t("clone_active")
	if info.golden then
		status ..= "  " .. I18n.t("clone_golden")
	end
	Builder.label({
		Text = string.format("#%d  %s", info.slot, info.label or ""),
		FontFace = Theme.Fonts.Bold,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Position = UDim2.fromOffset(98, 8),
		Size = UDim2.new(1, -350, 0, 26),
		Parent = row,
	})
	local zone = I18n.t(if info.zone == "track" then "clone_zone_track" else "clone_zone_city")
	local origin = if info.origin then "  ·  " .. I18n.t("clone_from", { name = info.origin }) else ""
	Builder.label({
		Text = zone .. "  ·  " .. status .. origin,
		TextSize = 15,
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Position = UDim2.fromOffset(98, 36),
		Size = UDim2.new(1, -350, 0, 20),
		Parent = row,
	})
	Builder.label({
		Text = "💰 " .. I18n.t("clone_rate", { n = Format.number(info.rate or 0) }),
		FontFace = Theme.Fonts.Bold,
		TextSize = 15,
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(98, 56),
		Size = UDim2.new(1, -350, 0, 18),
		Parent = row,
	})

	local slot = info.slot
	if replacing then
		Button.new({
			Text = I18n.t("replace"),
			Variant = "danger",
			Size = UDim2.fromOffset(220, 64),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			OnClick = function()
				local callback = replaceCallback
				replaceCallback = nil
				clonesModal.close()
				if callback then
					callback(slot)
				end
			end,
			Parent = row,
		})
		return
	end
	Button.new({
		Text = "⏺ " .. I18n.t("clone_rerecord"),
		Variant = "primary",
		Size = UDim2.fromOffset(120, 64),
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -136, 0.5, 0),
		OnClick = function()
			clonesModal.close()
			Net.send("Record", "rerecord", slot)
		end,
		Parent = row,
	})
	local confirm = false
	local delete
	delete = Button.new({
		Text = "🗑 " .. I18n.t("clone_delete"),
		Variant = "ghost",
		Size = UDim2.fromOffset(120, 64),
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		OnClick = function()
			if not confirm then
				confirm = true
				delete:setText(I18n.t("clone_delete_confirm"))
				delete:setVariant("danger")
				task.delay(3, function()
					if confirm and delete.Instance.Parent then
						confirm = false
						delete:setText("🗑 " .. I18n.t("clone_delete"))
						delete:setVariant("ghost")
					end
				end)
				return
			end
			local ok, reason = Net.invoke("DeleteClone", slot)
			if not ok then
				Controllers.NotifyController.reason(reason)
			end
		end,
		Parent = row,
	})
end

local function refreshClones(state, force: boolean?)
	-- Evita recriar a lista inteira a cada StateSync quando nada mudou.
	local parts = { tostring(replaceCallback ~= nil) }
	for _, info in state.clones do
		table.insert(
			parts,
			string.format(
				"%d:%s:%s:%s:%s:%d",
				info.slot,
				tostring(info.fallen),
				tostring(info.transit),
				tostring(info.golden),
				info.label or "",
				info.rate or 0
			)
		)
	end
	local key = table.concat(parts, "|")
	if key == renderedKey and not force then
		return
	end
	renderedKey = key

	local list: ScrollingFrame = refs.list
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	clonesModal.title.Text = if replaceCallback
		then "📼  " .. I18n.t("replace_title")
		else "📼  " .. I18n.t("clones_title")
	if #state.clones == 0 then
		local empty =
			Builder.create("Frame", { Size = UDim2.new(1, -12, 0, 80), BackgroundTransparency = 1, Parent = list })
		Builder.label({ Text = I18n.t("clones_empty"), TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = empty })
		return
	end
	for _, info in state.clones do
		cloneRow(list, info, replaceCallback ~= nil)
	end
end

-- onReplace: quando definido, a tela vira "qual fita substituir?"
function BaseMenuController.openClones(onReplace: ((number) -> ())?)
	replaceCallback = onReplace
	local state = Controllers.StateController.get()
	if state then
		refreshClones(state, true)
	end
	clonesModal.open()
end

function BaseMenuController.init(controllers)
	Controllers = controllers
	buildBase()
	buildClones()
end

function BaseMenuController.start()
	Controllers.StateController.changed:Connect(function(state)
		if baseModal.isOpen() then
			refreshBase(state)
		end
		if clonesModal.isOpen() then
			refreshClones(state, false)
		end
	end)
end

return BaseMenuController
