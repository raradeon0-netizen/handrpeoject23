--!strict
-- PaintMenuController: логика меню «Покраска / Скрижали».
--   * хранит «кисть» — что сделает ЛКМ по блоку: покрасить материалом, повесить скрижаль
--     или очистить грань от скрижалей;
--   * BuildHudController открывает и закрывает меню, BuildController читает кисть (getBrush)
--     и отправляет действие на сервер.
-- Как и BuildSettingsController, модуль один на клиента: кисть переживает закрытие меню.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PaintCatalog = require(ReplicatedStorage.Shared.PaintCatalog)
local PaintMenuView = require(script.Parent.PaintMenuView)
local Theme = require(script.Parent.Theme)

export type BrushKind = "Material" | "Tablet" | "Erase"

export type Brush = {
	kind: BrushKind,
	id: string?, -- id материала или скрижали (у «Очистить грань» — nil)
}

local HINTS: { [string]: string } = {
	[PaintMenuView.MaterialsTabId] = "Выберите материал, затем ЛКМ по блоку или детали составного блока",
	[PaintMenuView.TabletsTabId] = "Выберите скрижаль, затем ЛКМ по грани блока. ★ — скрижаль вашей фракции",
}

local PaintMenuController = {}

local changed = Instance.new("BindableEvent")

-- Срабатывает при смене кисти.
PaintMenuController.Changed = changed.Event

local view: PaintMenuView.View? = nil
local opened = false
local tabId = PaintMenuView.MaterialsTabId
local brush: Brush? = nil
local factionId: string? = nil

local function setStroke(button: GuiObject, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
		stroke.Thickness = if selected then Theme.StrokeThickness + 2 else Theme.StrokeThickness
	end
end

local function isBrush(kind: BrushKind, id: string?): boolean
	local b = brush
	return b ~= nil and b.kind == kind and b.id == id
end

local function refresh()
	local v = view
	if not v then
		return
	end
	for id, button in v.tabButtons do
		setStroke(button, id == tabId)
	end
	for id, page in v.pages do
		page.Visible = id == tabId
	end
	v.hintLabel.Text = HINTS[tabId] or ""

	for id, button in v.materialTiles do
		setStroke(button, isBrush("Material", id))
	end
	for _, tablet in PaintCatalog.Tablets do
		local tile = v.tabletTiles[tablet.id]
		if tile then
			local featured = tablet.factionId == factionId
			tile.star.Visible = featured
			tile.button.LayoutOrder = if featured then 0 else table.find(PaintCatalog.Tablets, tablet) or 1
			setStroke(tile.button, isBrush("Tablet", tablet.id))
		end
	end
	setStroke(v.eraseButton, isBrush("Erase", nil))
end

function PaintMenuController.close()
	opened = false
	local v = view
	if v then
		v.frame.Visible = false
	end
end

function PaintMenuController.open()
	local v = view
	if not v or opened then
		return
	end
	opened = true
	v.frame.Position = PaintMenuView.HiddenPosition
	v.frame.Visible = true
	TweenService:Create(v.frame, Theme.TweenInfo, { Position = PaintMenuView.ShownPosition }):Play()
end

function PaintMenuController.isOpen(): boolean
	return opened
end

function PaintMenuController.getBrush(): Brush?
	return brush
end

-- Отмечает ★ скрижаль фракции участка и ставит её первой.
function PaintMenuController.setFaction(value: string?)
	factionId = value
	refresh()
end

-- Выбор кисти закрывает меню: дальше игрок кликает по блокам.
local function pick(kind: BrushKind, id: string?)
	brush = { kind = kind, id = id }
	refresh()
	PaintMenuController.close()
	changed:Fire()
end

-- Создаёт окно внутри ScreenGui строительной панели (один раз).
function PaintMenuController.attach(gui: ScreenGui)
	if view then
		return
	end
	local created = PaintMenuView.build(gui)
	view = created

	for id, button in created.tabButtons do
		button.Activated:Connect(function()
			tabId = id
			refresh()
		end)
	end
	for id, button in created.materialTiles do
		button.Activated:Connect(function()
			pick("Material", id)
		end)
	end
	for id, tile in created.tabletTiles do
		tile.button.Activated:Connect(function()
			pick("Tablet", id)
		end)
	end
	created.eraseButton.Activated:Connect(function()
		pick("Erase", nil)
	end)
	created.closeButton.Activated:Connect(PaintMenuController.close)

	refresh()
end

return PaintMenuController
