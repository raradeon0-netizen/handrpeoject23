--!strict
-- BuildHudController: логика строительной панели.
-- Показывает/прячет панель, подсвечивает выбор и держит масштаб
-- в синхроне с настройками меню (ScaleSettings).
--
-- Выбор состоит из двух частей:
--   * форма — что ставим или чем режем. Выбирается в каталоге «Блоки»
--     (кнопка на панели или клавиша B): базовые формы и составные античные блоки;
--   * инструмент (Вырезать / Снос / Покраска) — необязательный; без него идёт
--     обычная установка выбранной формы.
-- «Вырезать» режет формой выбранной фигуры, поэтому при нём форма остаётся
-- выбранной и её можно менять (дверь — «Стена», окно — «Блок» и т.д.).
-- Резак работает только базовыми формами: выбор составного блока при резаке
-- выключает резак и переходит к установке этого блока.
-- Механики строительства здесь нет: выбор отдаётся сигналом SelectionChanged,
-- на него подписан BuildController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BuildSlots = require(ReplicatedStorage.Shared.BuildSlots)
local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BlockCatalog = require(ReplicatedStorage.Shared.BlockCatalog)
local BuildHudView = require(script.Parent.BuildHudView)
local BlockPickerController = require(script.Parent.BlockPickerController)
local PaintMenuController = require(script.Parent.PaintMenuController)
local TopHudController = require(script.Parent.TopHudController)
local ScaleSettings = require(script.Parent.ScaleSettings)
local Theme = require(script.Parent.Theme)

export type BuildHud = {
	show: () -> (), -- плавно выдвинуть панель
	hide: () -> (), -- плавно убрать панель (и закрыть каталог)
	getSelection: () -> (string?, string?), -- (id формы, id инструмента)
	SelectionChanged: RBXScriptSignal, -- (shapeId: string?, toolId: string?)
	setFaction: (factionId: string?) -> (), -- отметить ★ «родные» блоки фракции
}

-- Инструменты, которым нужна форма (резак режет формой выбранной фигуры).
local SHAPE_TOOLS: { [string]: boolean } = {
	Carve = true,
}

local DEFAULT_CARVE_SHAPE = "Block"

local BuildHudController = {}

local function isPrefab(shapeId: string?): boolean
	local shape = if shapeId then BuildConfig.Shapes[shapeId] else nil
	return shape ~= nil and shape.prefab == true
end

function BuildHudController.start(playerGui: PlayerGui): BuildHud
	local view = BuildHudView.build(playerGui)
	local picker = BlockPickerController.new(view.gui)
	PaintMenuController.attach(view.gui)
	TopHudController.attach(playerGui) -- верхняя панель: время суток и сохранение

	local shapeId: string? = nil
	local toolId: string? = nil
	local visible = false
	local selectionChanged = Instance.new("BindableEvent")
	local catalogSlot = BuildSlots.ById[BuildConfig.CatalogSlotId]

	-- Шаг 1. Масштаб: берём текущий и следим за изменениями из настроек меню.
	view.uiScale.Scale = ScaleSettings.get()
	ScaleSettings.Changed:Connect(function(scale: number, instant: boolean)
		if instant then
			view.uiScale.Scale = scale
		else
			TweenService:Create(view.uiScale, Theme.TweenInfo, { Scale = scale }):Play()
		end
	end)

	-- Шаг 2. Подсветка: золотистая обводка + полоска внизу кнопки
	-- (фон кнопок занят hover-эффектом UIFactory, поэтому выделяем обводкой).
	local function setHighlighted(id: string, selected: boolean)
		local button = view.slotButtons[id]
		local stroke = if button then button:FindFirstChildOfClass("UIStroke") else nil
		if stroke then
			stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
			stroke.Thickness = if selected then Theme.StrokeThickness + 2 else Theme.StrokeThickness
		end
		local bar = view.selectionBars[id]
		if bar then
			bar.Visible = selected
		end
	end

	local function refresh()
		-- Форма подсвечена, когда она реально используется: в установке или как форма резака.
		local shapeInUse = shapeId ~= nil and (toolId == nil or SHAPE_TOOLS[toolId :: string] == true)
		for _, slot in BuildSlots.List do
			local selected = if slot.kind == "Catalog" then shapeInUse or picker.isOpen() else slot.id == toolId
			setHighlighted(slot.id, selected)
		end

		-- Подпись кнопки «Блоки» — текущая форма.
		local description = view.descriptionLabels[BuildConfig.CatalogSlotId]
		if description and catalogSlot then
			description.Text = if shapeInUse and shapeId
				then BlockCatalog.displayName(shapeId) .. " · B"
				else catalogSlot.description
		end

		picker.setSelected(if shapeInUse then shapeId else nil)
		picker.setCarving(toolId == BuildConfig.CarveSlotId)
	end

	local function fire()
		refresh()
		selectionChanged:Fire(shapeId, toolId)
	end

	local function toggleCatalog()
		PaintMenuController.close() -- каталог и меню покраски занимают одно место
		picker.toggle()
		refresh()
	end

	-- Клик по плитке каталога.
	picker.ShapePicked:Connect(function(pickedId: string)
		local currentTool = toolId
		if currentTool ~= nil and SHAPE_TOOLS[currentTool] then
			if isPrefab(pickedId) then
				toolId = nil -- составной блок резаком не берётся: переходим к установке
			end
			shapeId = pickedId -- иначе меняем форму резака, режим остаётся
		elseif currentTool ~= nil then
			toolId = nil -- из «Сноса»/«Покраски» сразу в установку этой формы
			shapeId = pickedId
		elseif shapeId == pickedId then
			shapeId = nil -- повторный выбор снимает форму (призрак прячется)
		else
			shapeId = pickedId
		end
		picker.close()
		PaintMenuController.close()
		fire()
	end)

	local function onSlotClicked(slot: BuildSlots.Slot)
		if slot.kind == "Catalog" then
			toggleCatalog()
			return
		end
		local isPaint = slot.id == BuildConfig.PaintSlotId
		if isPaint and toolId == slot.id and not PaintMenuController.isOpen() then
			-- Инструмент уже включён, меню закрыто после выбора кисти: открываем его снова.
			picker.close()
			PaintMenuController.open()
			refresh()
			return
		end
		if toolId == slot.id then
			toolId = nil -- повторный клик выключает инструмент
		else
			toolId = slot.id
			if SHAPE_TOOLS[slot.id] and (shapeId == nil or isPrefab(shapeId)) then
				shapeId = DEFAULT_CARVE_SHAPE -- резаку нужна базовая форма: по умолчанию «Блок»
			end
		end
		if isPaint and toolId == slot.id then
			picker.close()
			PaintMenuController.open()
		else
			PaintMenuController.close()
		end
		fire()
	end

	for _, slot in BuildSlots.List do
		local button = view.slotButtons[slot.id]
		if button then
			button.Activated:Connect(function()
				onSlotClicked(slot)
			end)
		end
	end

	-- Клавиша B: открыть/закрыть каталог (только пока панель на экране).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not visible or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == BuildConfig.Keys.OpenCatalog then
			toggleCatalog()
		end
	end)

	-- Шаг 3. Появление и скрытие панели.
	local function show()
		visible = true
		TopHudController.show()
		view.panel.Position = BuildHudView.PanelHiddenPosition
		view.gui.Enabled = true
		TweenService:Create(view.panel, Theme.TweenInfo, { Position = BuildHudView.PanelShownPosition }):Play()
		refresh()
	end

	local function hide()
		visible = false
		picker.close()
		PaintMenuController.close()
		TopHudController.hide()
		local tween = TweenService:Create(view.panel, Theme.TweenInfo, { Position = BuildHudView.PanelHiddenPosition })
		tween.Completed:Once(function()
			if not visible then
				view.gui.Enabled = false
			end
		end)
		tween:Play()
	end

	refresh()

	return {
		show = show,
		hide = hide,
		getSelection = function(): (string?, string?)
			return shapeId, toolId
		end,
		SelectionChanged = selectionChanged.Event,
		setFaction = function(factionId: string?)
			picker.setFaction(factionId)
			PaintMenuController.setFaction(factionId)
		end,
	}
end

return BuildHudController
