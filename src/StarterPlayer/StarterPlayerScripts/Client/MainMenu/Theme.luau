--!strict
-- Theme: цвета, шрифты и размеры меню. Меняйте стиль здесь, не трогая логику.

local Theme = {
	Font = Enum.Font.Fantasy,
	BodyFont = Enum.Font.Garamond,

	BackgroundColor = Color3.fromRGB(20, 16, 12),
	BackgroundTransparency = 0.15,

	PanelColor = Color3.fromRGB(45, 36, 26),
	PanelStroke = Color3.fromRGB(200, 165, 90), -- «золото»

	TextColor = Color3.fromRGB(245, 230, 200),
	SubTextColor = Color3.fromRGB(200, 185, 155),

	PrimaryButtonColor = Color3.fromRGB(170, 130, 60),
	SecondaryButtonColor = Color3.fromRGB(70, 58, 44),

	PanelTransparency = 0.06, -- панели чуть просвечивают: мир за ними не пропадает
	CornerRadius = UDim.new(0, 8),
	StrokeThickness = 1.5,
	StrokeTransparency = 0.25, -- тонкая приглушённая золотая кайма
	HoverTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	TweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- Варианты размера интерфейса (значение UIScale.Scale) для окна настроек.
	ScaleOptions = {
		{ id = "Small", label = "Маленький", scale = 0.8 },
		{ id = "Standard", label = "Стандартный", scale = 1 },
		{ id = "Large", label = "Большой", scale = 1.2 },
	},
	DefaultScaleId = "Standard",
	SelectedStroke = Color3.fromRGB(255, 245, 215), -- обводка выбранного варианта
}

return Theme
