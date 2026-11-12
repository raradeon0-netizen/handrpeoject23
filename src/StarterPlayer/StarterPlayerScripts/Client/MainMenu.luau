--!strict
-- MainMenu (LocalScript): точка входа клиентского меню.
-- Rojo превращает папку MainMenu в LocalScript, а соседние .luau-файлы
-- становятся его дочерними ModuleScript'ами.

local Players = game:GetService("Players")

local MenuController = require(script.MenuController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

MenuController.start(playerGui)
