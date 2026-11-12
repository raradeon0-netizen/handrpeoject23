--!strict
-- BlockPickerController: логика каталога блоков.
--   * открыть / закрыть / переключить (кнопка «Блоки», клавиша B, крестик);
--   * вкладки категорий фильтруют плитки, «Все» показывает всё;
--   * «родные» блоки фракции помечены ★ и стоят первыми;
--   * в режиме «Вырезать» составные блоки подписаны «только стройка»
--     (резак режет только базовыми формами);
--   * клик по плитке отдаёт сигнал ShapePicked(shapeId) — что делать, решает BuildHudController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BlockCatalog = require(ReplicatedStorage.Shared.BlockCatalog)
local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local FactionConfig = require(ReplicatedStorage.Shared.FactionConfig)
local BlockPickerView = require(script.Parent.BlockPickerView)
local Theme = require(script.Parent.Theme)

export type Picker = {
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
	setSelected: (shapeId: string?) -> (),
	setCarving: (carving: boolean) -> (),
	setFaction: (factionId: string?) -> (),
	ShapePicked: RBXScriptSignal, -- (shapeId: string)
}

local BlockPickerController = {}

local function setStroke(button: GuiObject, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
		stroke.Thickness = if selected then Theme.StrokeThickness + 2 else Theme.StrokeThickness
	end
end

-- Название фракции для подсказки в заголовке (если FactionConfig его знает).
local function factionTitle(factionId: string): string
	local config = FactionConfig :: any
	local byId = config.ById or config.Factions
	local faction = if type(byId) == "table" then byId[factionId] else nil
	if type(faction) == "table" then
		local name = faction.displayName or faction.name
		if type(name) == "string" then
			return name
		end
	end
	return factionId
end

function BlockPickerController.new(gui: ScreenGui): Picker
	local view = BlockPickerView.build(gui)
	local picked = Instance.new("BindableEvent")

	local opened = false
	local category = BlockCatalog.AllCategoryId
	local selectedId: string? = nil
	local carving = false
	local factionId: string? = nil

	local function refreshTabs()
		for id, tab in view.tabButtons do
			setStroke(tab, id == category)
		end
	end

	local function refreshTiles()
		for _, entry in BlockCatalog.List do
			local tile = view.tiles[entry.id]
			if tile then
				tile.button.Visible = category == BlockCatalog.AllCategoryId or entry.category == category
				local featured = BlockCatalog.isFeatured(entry, factionId)
				tile.star.Visible = featured
				-- Родные блоки фракции — в начале списка.
				tile.button.LayoutOrder = if featured then tile.order - 1000 else tile.order
				local shape = BuildConfig.Shapes[entry.id]
				tile.lock.Visible = carving and shape ~= nil and shape.prefab == true
				setStroke(tile.button, entry.id == selectedId)
			end
		end
	end

	local function open()
		if opened then
			return
		end
		opened = true
		view.frame.Position = BlockPickerView.HiddenPosition
		view.frame.Visible = true
		TweenService:Create(view.frame, Theme.TweenInfo, { Position = BlockPickerView.ShownPosition }):Play()
	end

	local function close()
		opened = false
		view.frame.Visible = false
	end

	local function toggle()
		if opened then
			close()
		else
			open()
		end
	end

	for id, tab in view.tabButtons do
		tab.Activated:Connect(function()
			category = id
			view.scroll.CanvasPosition = Vector2.zero
			refreshTabs()
			refreshTiles()
		end)
	end

	for id, tile in view.tiles do
		tile.button.Activated:Connect(function()
			picked:Fire(id)
		end)
	end

	view.closeButton.Activated:Connect(close)

	refreshTabs()
	refreshTiles()

	return {
		open = open,
		close = close,
		toggle = toggle,
		isOpen = function(): boolean
			return opened
		end,
		setSelected = function(shapeId: string?)
			selectedId = shapeId
			refreshTiles()
		end,
		setCarving = function(value: boolean)
			carving = value
			refreshTiles()
		end,
		setFaction = function(value: string?)
			factionId = value
			view.factionLabel.Text = if value then "★ — блоки фракции «" .. factionTitle(value) .. "»" else ""
			refreshTiles()
		end,
		ShapePicked = picked.Event,
	}
end

return BlockPickerController
