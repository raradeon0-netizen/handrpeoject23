--!strict
-- BuildSettingsController: состояние и логика мини-панели «Точность».
--   * шаг сетки: 4 / 1 / 0.25 студа или 0 (свободное перемещение без сетки);
--   * шаг поворота: 90° / 45° / 15° / 5° (используют клавиши R, T, Y);
--   * «Магнит к центру» — призрак прилипает к центру грани блока под курсором;
--   * показ текущих углов, кнопка «Сброс» и короткие сообщения (notify).
-- Панель создаётся один раз; настройки сохраняются, пока игрок в игре.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local BuildSize = require(ReplicatedStorage.Shared.BuildSize)
local BuildSettingsView = require(script.Parent.BuildSettingsView)
local ScaleSettings = require(script.Parent.ScaleSettings)
local Theme = require(script.Parent.Theme)

export type Settings = {
	gridStep: number, -- студы; 0 = без сетки
	rotationStep: number, -- градусы
	snapToCenter: boolean,
	cutterShape: string, -- id из BuildConfig.CutterShapes
	size: Vector3?, -- свой размер блока / резака; nil = размер недоступен (составной блок и т. п.)
}

export type Angles = {
	yaw: number,
	pitch: number,
	roll: number,
}

local BuildSettingsController = {}

local gridIndex = BuildConfig.DefaultGridIndex
local rotationIndex = BuildConfig.DefaultRotationIndex
local snapToCenter = false
local cutterShape = BuildConfig.CutterCubeId
local carveMode = false

-- Размеры запоминаются отдельно для каждой формы и для полосы резака.
local sizes: { [string]: Vector3 } = {}
local sizeKey: string? = nil
local sizeDefault: Vector3? = nil
local sizeLockZ = false
local sizeMin = Vector3.one * BuildConfig.MinBlockSize
local sizeMax = Vector3.one * BuildConfig.MaxBlockSize

local AXIS_NAMES = { "Ширина X", "Высота Y", "Длина Z" }
local LOCKED_AXIS_NAME = "Толщина Z"

local function axisOf(size: Vector3, axis: number): number
	return if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z
end

-- Текущие значения (одна таблица на всю игру: get() вызывается каждый кадр).
local current: Settings = {
	gridStep = 0,
	rotationStep = 0,
	snapToCenter = false,
	cutterShape = BuildConfig.CutterCubeId,
	size = nil,
}

local changed = Instance.new("BindableEvent")
local resetRequested = Instance.new("BindableEvent")

-- Сигналы: настройки изменились / нажата кнопка «Сброс» (обнулить поворот).
BuildSettingsController.Changed = changed.Event
BuildSettingsController.ResetRotationRequested = resetRequested.Event

local view: BuildSettingsView.View? = nil
local visible = false
local noticeToken = 0

-- Выбранный вариант выделяем обводкой (фон кнопок занят hover-эффектом UIFactory).
local function setSelected(button: TextButton, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
		stroke.Thickness = if selected then Theme.StrokeThickness + 2 else Theme.StrokeThickness
	end
end

local function refresh()
	local grid = BuildConfig.GridOptions[gridIndex]
	current.gridStep = grid.step
	current.rotationStep = BuildConfig.RotationSteps[rotationIndex]
	current.snapToCenter = snapToCenter
	current.cutterShape = cutterShape
	local stored = if sizeKey then sizes[sizeKey] or sizeDefault else nil
	current.size = if stored and sizeLockZ then BuildSize.blade(stored) else stored

	local v = view
	if not v then
		return
	end

	v.gridLabel.Text = string.format("Шаг сетки (студы): %s — %s", grid.label, grid.hint)
	for index, button in v.gridButtons do
		setSelected(button, index == gridIndex)
	end

	v.rotationLabel.Text = string.format("Шаг поворота: %d°", current.rotationStep)
	for index, button in v.rotationButtons do
		setSelected(button, index == rotationIndex)
	end

	v.snapButton.Text = if snapToCenter then "Магнит к центру: ВКЛ" else "Магнит к центру: выкл"
	setSelected(v.snapButton, snapToCenter)

	for index, button in v.cutterButtons do
		setSelected(button, BuildConfig.CutterShapes[index].id == cutterShape)
	end
	v.cutterRow.Visible = carveMode

	local size = current.size
	v.sizeLabel.Text = if size then "Размер (студы)" else "Размер: выберите форму или резак"
	v.sizeResetButton.Visible = size ~= nil
	for axis, row in v.sizeRows do
		local locked = axis == 3 and sizeLockZ
		row.frame.Visible = size ~= nil
		row.label.Text = if locked then LOCKED_AXIS_NAME else AXIS_NAMES[axis]
		row.box.Text = if size then BuildSize.format(axisOf(size, axis)) else ""
		row.box.TextEditable = not locked
		row.minus.Visible = not locked
		row.plus.Visible = not locked
	end
end

-- Новое значение одной оси (1 = X, 2 = Y, 3 = Z) редактируемого размера.
local function setAxis(axis: number, value: number)
	local key, size = sizeKey, current.size
	if not key or not size or (axis == 3 and sizeLockZ) then
		refresh()
		return
	end
	local clamped = BuildSize.clamp(value, axisOf(sizeMin, axis), axisOf(sizeMax, axis))
	sizes[key] = Vector3.new(
		if axis == 1 then clamped else size.X,
		if axis == 2 then clamped else size.Y,
		if axis == 3 then clamped else size.Z
	)
	refresh()
	changed:Fire()
end

-- Кнопки «−» / «+»: шаг равен текущему шагу сетки.
local function nudgeAxis(axis: number, direction: number)
	local size = current.size
	if size then
		local low, high = axisOf(sizeMin, axis), axisOf(sizeMax, axis)
		setAxis(axis, BuildSize.nudge(axisOf(size, axis), current.gridStep, direction, low, high))
	end
end

-- Создаёт панель при первом показе и подключает кнопки.
local function ensureView(): BuildSettingsView.View
	local existing = view
	if existing then
		return existing
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local created = BuildSettingsView.build(playerGui)
	view = created

	-- Масштаб как у меню и нижней панели (ScaleSettings).
	created.uiScale.Scale = ScaleSettings.get()
	ScaleSettings.Changed:Connect(function(scale: number, instant: boolean)
		if instant then
			created.uiScale.Scale = scale
		else
			TweenService:Create(created.uiScale, Theme.TweenInfo, { Scale = scale }):Play()
		end
	end)

	for index, button in created.gridButtons do
		button.Activated:Connect(function()
			gridIndex = index
			refresh()
			changed:Fire()
		end)
	end

	for index, button in created.rotationButtons do
		button.Activated:Connect(function()
			rotationIndex = index
			refresh()
			changed:Fire()
		end)
	end

	created.snapButton.Activated:Connect(function()
		snapToCenter = not snapToCenter
		refresh()
		changed:Fire()
	end)

	for index, button in created.cutterButtons do
		button.Activated:Connect(function()
			cutterShape = BuildConfig.CutterShapes[index].id
			refresh()
			changed:Fire()
		end)
	end

	for axis, row in created.sizeRows do
		row.minus.Activated:Connect(function()
			nudgeAxis(axis, -1)
		end)
		row.plus.Activated:Connect(function()
			nudgeAxis(axis, 1)
		end)
		row.box.FocusLost:Connect(function()
			local value = BuildSize.parse(row.box.Text)
			if value then
				setAxis(axis, value)
			else
				refresh() -- не число: возвращаем прежнее значение
			end
		end)
	end

	created.sizeResetButton.Activated:Connect(function()
		if sizeKey then
			sizes[sizeKey] = nil
			refresh()
			changed:Fire()
		end
	end)

	created.resetButton.Activated:Connect(function()
		resetRequested:Fire()
	end)

	refresh()
	return created
end

-- Текущие настройки (только чтение).
function BuildSettingsController.get(): Settings
	return current
end

-- Показать текущие углы поворота призрака.
function BuildSettingsController.setAngles(angles: Angles)
	local v = view
	if v then
		v.anglesLabel.Text = string.format("Y %d°  ·  X %d°  ·  Z %d°", angles.yaw, angles.pitch, angles.roll)
	end
end

-- Подпись текущего режима (установка / резак / снос).
function BuildSettingsController.setMode(text: string)
	local v = view
	if v then
		v.modeLabel.Text = text
	end
end

-- Короткое сообщение внизу панели; само скрывается через NoticeDuration секунд.
function BuildSettingsController.notify(text: string)
	local v = view
	if not v then
		return
	end
	noticeToken += 1
	local token = noticeToken
	v.noticeLabel.Text = text
	v.noticeLabel.Visible = true
	task.delay(BuildConfig.NoticeDuration, function()
		if noticeToken == token then
			v.noticeLabel.Visible = false
		end
	end)
end

-- Плавно выдвинуть панель (создаёт её при первом вызове).
-- Чей размер сейчас редактируется: key — id формы или полосы резака (у каждой свой запомненный
-- размер), defaultSize — размер по умолчанию, lockZ — ось Z фиксирована (толщина полосы).
-- key = nil — размер недоступен (составной блок, снос, перенос).
-- minSize / maxSize — пределы по осям (по умолчанию — пределы базового блока).
function BuildSettingsController.setSizeTarget(
	key: string?,
	defaultSize: Vector3?,
	lockZ: boolean?,
	minSize: Vector3?,
	maxSize: Vector3?
)
	sizeMin = minSize or Vector3.one * BuildConfig.MinBlockSize
	sizeMax = maxSize or Vector3.one * BuildConfig.MaxBlockSize
	sizeKey = key
	sizeDefault = defaultSize
	sizeLockZ = lockZ == true
	refresh()
end

-- Режим «Вырезать»: показывает переключатель формы резака.
function BuildSettingsController.setCarveMode(active: boolean)
	carveMode = active
	refresh()
end

function BuildSettingsController.show()
	local v = ensureView()
	visible = true
	v.panel.Position = BuildSettingsView.PanelHiddenPosition
	v.gui.Enabled = true
	TweenService:Create(v.panel, Theme.TweenInfo, { Position = BuildSettingsView.PanelShownPosition }):Play()
end

-- Плавно убрать панель.
function BuildSettingsController.hide()
	local v = view
	if not v then
		return
	end
	visible = false
	local tween = TweenService:Create(v.panel, Theme.TweenInfo, { Position = BuildSettingsView.PanelHiddenPosition })
	tween.Completed:Once(function()
		if not visible then
			v.gui.Enabled = false
		end
	end)
	tween:Play()
end

refresh()

return BuildSettingsController
