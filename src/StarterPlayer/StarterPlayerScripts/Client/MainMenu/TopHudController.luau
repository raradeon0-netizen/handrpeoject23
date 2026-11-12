--!strict
-- TopHudController: логика верхней панели — время суток и сохранение участка.
--   * «День» / «Закат» / «Ночь» переключают освещение (TimeOfDayController);
--   * «Сохранить» и «Загрузить» отправляют запрос на сервер (SaveManager), ответ приходит
--     тем же RemoteEvent и показывается строкой статуса;
--   * «Загрузить» заменяет нынешние постройки, поэтому требует повторного клика.
-- Панель появляется и прячется вместе с нижней строительной панелью (BuildHudController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)
local ScaleSettings = require(script.Parent.ScaleSettings)
local Theme = require(script.Parent.Theme)
local TimeOfDayController = require(script.Parent.TimeOfDayController)
local TopHudView = require(script.Parent.TopHudView)

local STATUS_DURATION = 5
local CONFIRM_DURATION = 4
local LOAD_TEXT = "Загрузить"
local CONFIRM_TEXT = "Заменить?"

local STATUS_COLORS: { [string]: Color3 } = {
	ok = Color3.fromRGB(150, 230, 140),
	error = Color3.fromRGB(255, 130, 110),
	info = Theme.TextColor,
}

local TopHudController = {}

local pauseRequested = Instance.new("BindableEvent")

-- Нажата кнопка «Меню»: меню паузы открывает MenuController.
TopHudController.PauseRequested = pauseRequested.Event

local walkRequested = Instance.new("BindableEvent")

-- Нажата кнопка «Режим»: стройку и прогулку переключает WalkController.
TopHudController.WalkRequested = walkRequested.Event

local view: TopHudView.View? = nil
local visible = false
local statusToken = 0
local confirmToken = 0
local confirming = false

local function setSelected(button: TextButton, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then Theme.SelectedStroke else Theme.PanelStroke
		stroke.Thickness = if selected then Theme.StrokeThickness + 1.5 else Theme.StrokeThickness
	end
end

local function refreshTime()
	local v = view
	if v then
		for id, button in v.timeButtons do
			setSelected(button, id == TimeOfDayController.getCurrent())
		end
	end
end

local function showStatus(kind: string, text: string)
	local v = view
	if not v then
		return
	end
	statusToken += 1
	local token = statusToken
	v.statusLabel.Text = text
	v.statusLabel.TextColor3 = STATUS_COLORS[kind] or Theme.TextColor
	v.statusLabel.Visible = true
	task.delay(STATUS_DURATION, function()
		if statusToken == token then
			v.statusLabel.Visible = false
		end
	end)
end

local function resetConfirm()
	confirming = false
	local v = view
	if v then
		v.loadButton.Text = LOAD_TEXT
	end
end

-- Создаёт панель (один раз) и подключает кнопки.
function TopHudController.attach(playerGui: PlayerGui)
	if view then
		return
	end
	local created = TopHudView.build(playerGui)
	view = created

	created.uiScale.Scale = ScaleSettings.get()
	ScaleSettings.Changed:Connect(function(scale: number, instant: boolean)
		if instant then
			created.uiScale.Scale = scale
		else
			TweenService:Create(created.uiScale, Theme.TweenInfo, { Scale = scale }):Play()
		end
	end)

	for id, button in created.timeButtons do
		button.Activated:Connect(function()
			TimeOfDayController.set(id)
			refreshTime()
		end)
	end

	-- RemoteEvent создаёт сервер при старте; ждём его в фоне, чтобы не задерживать меню.
	local remote: RemoteEvent? = nil
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild(BuildConfig.SaveRemoteName, 30)
		if found and found:IsA("RemoteEvent") then
			remote = found
			found.OnClientEvent:Connect(function(kind: unknown, text: unknown)
				if typeof(kind) == "string" and typeof(text) == "string" then
					showStatus(kind, text)
				end
			end)
		end
	end)

	local function request(action: string, pendingText: string)
		if remote then
			showStatus("info", pendingText)
			remote:FireServer(action)
		else
			showStatus("error", "Сохранение недоступно: сервер не ответил")
		end
	end

	created.saveButton.Activated:Connect(function()
		resetConfirm()
		request("Save", "Сохранение…")
	end)

	created.loadButton.Activated:Connect(function()
		if not confirming then
			-- Первый клик только спрашивает: загрузка заменит всё, что построено сейчас.
			confirming = true
			confirmToken += 1
			local token = confirmToken
			created.loadButton.Text = CONFIRM_TEXT
			showStatus("info", "Загрузка заменит нынешние постройки сохранёнными. Нажмите ещё раз")
			task.delay(CONFIRM_DURATION, function()
				if confirmToken == token then
					resetConfirm()
				end
			end)
			return
		end
		confirmToken += 1
		resetConfirm()
		request("Load", "Загрузка…")
	end)

	created.pauseButton.Activated:Connect(function()
		pauseRequested:Fire()
	end)

	created.walkButton.Activated:Connect(function()
		walkRequested:Fire()
	end)
	TopHudController.setWalkMode(false)

	TimeOfDayController.set(TimeOfDayController.DefaultId, true)
	refreshTime()
end

-- Подпись и подсветка кнопки режима.
function TopHudController.setWalkMode(walking: boolean)
	local v = view
	if v then
		v.walkButton.Text = if walking then "Режим: Прогулка (V)" else "Режим: Стройка (V)"
		setSelected(v.walkButton, walking)
	end
end

function TopHudController.show()
	local v = view
	if not v then
		return
	end
	visible = true
	v.panel.Position = TopHudView.PanelHiddenPosition
	v.gui.Enabled = true
	TweenService:Create(v.panel, Theme.TweenInfo, { Position = TopHudView.PanelShownPosition }):Play()
end

function TopHudController.hide()
	local v = view
	if not v then
		return
	end
	visible = false
	resetConfirm()
	local tween = TweenService:Create(v.panel, Theme.TweenInfo, { Position = TopHudView.PanelHiddenPosition })
	tween.Completed:Once(function()
		if not visible then
			v.gui.Enabled = false
		end
	end)
	tween:Play()
end

return TopHudController
