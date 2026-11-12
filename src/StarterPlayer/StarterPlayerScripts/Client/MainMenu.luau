--!strict
-- MainMenu (LocalScript): точка входа клиентского меню.
-- Rojo превращает папку MainMenu в LocalScript, а соседние .luau-файлы
-- становятся его дочерними ModuleScript'ами.

local Players = game:GetService("Players")

local MenuController = require(script.MenuController)
local LightFlicker = require(script.LightFlicker)
local AudioController = require(script.AudioController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

LightFlicker.start() -- мерцание огня светильников
AudioController.start() -- фоновая музыка: и в меню, и в игре
MenuController.start(playerGui)
