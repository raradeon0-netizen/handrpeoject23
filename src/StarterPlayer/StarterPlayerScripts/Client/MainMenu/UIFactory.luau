--!strict
-- UIFactory: маленькие функции-конструкторы для типовых элементов интерфейса.
-- Все элементы создаются кодом, поэтому интерфейс целиком хранится в git.

local TweenService = game:GetService("TweenService")

local AudioController = require(script.Parent.AudioController)
local Theme = require(script.Parent.Theme)

local UIFactory = {}

-- Добавляет скруглённые углы и обводку в одном стиле.
local function decorate(instance: GuiObject, strokeColor: Color3?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = instance

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or Theme.PanelStroke
	stroke.Thickness = Theme.StrokeThickness
	stroke.Transparency = Theme.StrokeTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
end

-- Полноэкранный Frame («экран» меню). По умолчанию скрыт.
function UIFactory.screen(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.BackgroundColor
	frame.BackgroundTransparency = Theme.BackgroundTransparency
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	return frame
end

-- Центральная панель с обводкой.
function UIFactory.panel(name: string, size: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = size
	frame.BackgroundColor3 = Theme.PanelColor
	frame.BackgroundTransparency = Theme.PanelTransparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	decorate(frame)
	return frame
end

-- Текстовая надпись (заголовок или подпись).
function UIFactory.label(name: string, text: string, textSize: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Font = Theme.Font
	label.TextSize = textSize
	label.TextColor3 = Theme.TextColor
	label.TextWrapped = true
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + 12)
	label.Parent = parent
	return label
end

-- Кнопка с эффектом наведения (плавное осветление).
function UIFactory.button(name: string, text: string, color: Color3, parent: Instance, strokeColor: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Theme.Font
	button.TextSize = 28
	button.TextColor3 = Theme.TextColor
	button.BackgroundColor3 = color
	button.AutoButtonColor = false -- свой hover-эффект ниже
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, 0, 0, 56)
	button.Parent = parent
	decorate(button, strokeColor)

	local hoverColor = color:Lerp(Color3.new(1, 1, 1), 0.15)
	-- Наведение: кнопка светлеет, а кайма становится ярче.
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local function hover(background: Color3, strokeTransparency: number)
		TweenService:Create(button, Theme.HoverTweenInfo, { BackgroundColor3 = background }):Play()
		if stroke then
			TweenService:Create(stroke, Theme.HoverTweenInfo, { Transparency = strokeTransparency }):Play()
		end
	end
	button.Activated:Connect(function()
		AudioController.playSfx("Click")
	end)
	button.MouseEnter:Connect(function()
		hover(hoverColor, 0)
	end)
	button.MouseLeave:Connect(function()
		hover(color, Theme.StrokeTransparency)
	end)

	return button
end

-- Вертикальная раскладка детей с отступами.
function UIFactory.verticalList(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent

	local inner = Instance.new("UIPadding")
	inner.PaddingTop = UDim.new(0, padding)
	inner.PaddingBottom = UDim.new(0, padding)
	inner.PaddingLeft = UDim.new(0, padding)
	inner.PaddingRight = UDim.new(0, padding)
	inner.Parent = parent
end

-- Горизонтальная раскладка детей с отступами (для нижней строительной панели).
function UIFactory.horizontalList(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent

	local inner = Instance.new("UIPadding")
	inner.PaddingTop = UDim.new(0, padding)
	inner.PaddingBottom = UDim.new(0, padding)
	inner.PaddingLeft = UDim.new(0, padding)
	inner.PaddingRight = UDim.new(0, padding)
	inner.Parent = parent
end

return UIFactory
