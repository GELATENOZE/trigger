    -- ========== ПЕРЕМЕННЫЕ ==========
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()
local VirtualInput = game:GetService("VirtualInputManager")

-- Состояния
local TriggerbotEnabled = false
local EspEnabled = false

-- Подключения и списки
local ESPHighlights = {}
local RenderConnectionESP = nil
local RenderConnectionTrigger = nil
local CanShoot = true

-- ========== ФУНКЦИЯ УВЕДОМЛЕНИЙ ==========
local function SendNotify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 2
        })
    end)
end

-- ========== ПОЛУЧЕНИЕ ВРАГОВ ==========
local function GetEnemies()
    local enemies = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local team = LocalPlayer.Team
            if team and player.Team ~= team then
                table.insert(enemies, player)
            elseif not team then
                table.insert(enemies, player)
            end
        end
    end
    return enemies
end

-- ========== ПРОВЕРКА: ПРИНАДЛЕЖИТ ЛИ ЧАСТЬ ВРАГУ ==========
local function IsEnemyPart(part)
    if not part then return nil end
    local enemies = GetEnemies()
    for _, enemy in pairs(enemies) do
        if enemy.Character and part:IsDescendantOf(enemy.Character) then
            return enemy
        end
    end
    return nil
end

-- ========== ФУНКЦИЯ ВЫСТРЕЛА ==========
local function ClickMouse()
    if not CanShoot then return end
    CanShoot = false
    
    if mouse1press and mouse1release then
        mouse1press()
        task.wait(0.01)
        mouse1release()
    else
        pcall(function()
            VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.01)
            VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
    
    task.wait(0.01)
    CanShoot = true
end

-- ========== TRIGGERBOT (РАБОТАЕТ В ПРИЦЕЛЕ) ==========
local function DoTriggerbot()
    if not TriggerbotEnabled then return end
    
    -- 1. Метод: Проверка через мышь/центр экрана (быстрый Raycast под прицелом)
    local mouseTarget = Mouse.Target
    if mouseTarget then
        local enemy = IsEnemyPart(mouseTarget)
        if enemy then
            ClickMouse()
            return
        end
    end
    
    -- 2. Метод: Проверка через экранные координаты с учетом GuiInset (для прицелов со смещением)
    local mousePos = UserInputService:GetMouseLocation()
    local enemies = GetEnemies()
    local closestDist = 15 -- Зона срабатывания вокруг перекрестья
    
    for _, enemy in pairs(enemies) do
        local character = enemy.Character
        if character then
            for _, partName in ipairs({"Head", "UpperTorso", "HumanoidRootPart"}) do
                local part = character:FindFirstChild(partName)
                if part then
                    local vector, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and vector.Z > 0 then
                        local screenPos = Vector2.new(vector.X, vector.Y)
                        local dist = (screenPos - mousePos).Magnitude
                        
                        if dist < closestDist then
                            -- Проверка видимости через Raycast (игнорируя наше оружие и камеру)
                            local rayParams = RaycastParams.new()
                            rayParams.FilterType = Enum.RaycastFilterType.Exclude
                            rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
                            rayParams.IgnoreWater = true
                            
                            local rayResult = Workspace:Raycast(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position), rayParams)
                            if rayResult and rayResult.Instance:IsDescendantOf(character) then
                                ClickMouse()
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ========== ESP (красный контур) ==========
local function UpdateESP()
    if not EspEnabled then
        for _, highlight in pairs(ESPHighlights) do
            pcall(function() highlight:Destroy() end)
        end
        ESPHighlights = {}
        return
    end
    
    for i = #ESPHighlights, 1, -1 do
        local highlight = ESPHighlights[i]
        if not highlight or not highlight.Parent or not highlight.Adornee or not highlight.Adornee.Parent then
            pcall(function() highlight:Destroy() end)
            table.remove(ESPHighlights, i)
        end
    end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local team = LocalPlayer.Team
            local isEnemy = (team and player.Team ~= team) or not team
            
            if isEnemy then
                local hasHighlight = false
                for _, highlight in pairs(ESPHighlights) do
                    if highlight.Adornee == player.Character then
                        hasHighlight = true
                        break
                    end
                end
                
                if not hasHighlight then
                    local highlight = Instance.new("Highlight")
                    highlight.FillColor = Color3.fromRGB(255, 0, 0)
                    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
                    highlight.FillTransparency = 0.8
                    highlight.OutlineTransparency = 0.2
                    highlight.Adornee = player.Character
                    highlight.Parent = player.Character
                    table.insert(ESPHighlights, highlight)
                end
            end
        end
    end
end

-- ========== ОЧИСТКА ПРИ ВЫХОДЕ ИГРОКА ==========
Players.PlayerRemoving:Connect(function(player)
    for i = #ESPHighlights, 1, -1 do
        local highlight = ESPHighlights[i]
        if highlight and highlight.Adornee == player.Character then
            pcall(function() highlight:Destroy() end)
            table.remove(ESPHighlights, i)
        end
    end
end)

-- ========== ОБРАБОТКА БИНДОВ (X и Z) ==========
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Переключение ESP (Клавиша X)
    if input.KeyCode == Enum.KeyCode.X then
        EspEnabled = not EspEnabled
        
        if EspEnabled then
            UpdateESP()
            RenderConnectionESP = RunService.RenderStepped:Connect(UpdateESP)
            SendNotify("ESP", "Подсветка ВКЛЮЧЕНА ✅")
        else
            if RenderConnectionESP then
                RenderConnectionESP:Disconnect()
                RenderConnectionESP = nil
            end
            UpdateESP()
            SendNotify("ESP", "Подсветка ВЫКЛЮЧЕНА ❌")
        end
    end
    
    -- Переключение Triggerbot (Клавиша Z)
    if input.KeyCode == Enum.KeyCode.Z then
        TriggerbotEnabled = not TriggerbotEnabled
        
        if TriggerbotEnabled then
            RenderConnectionTrigger = RunService.RenderStepped:Connect(DoTriggerbot)
            SendNotify("Triggerbot", "Авто-выстрел ВКЛЮЧЕН ✅")
        else
            if RenderConnectionTrigger then
                RenderConnectionTrigger:Disconnect()
                RenderConnectionTrigger = nil
            end
            SendNotify("Triggerbot", "Авто-выстрел ВЫКЛЮЧЕН ❌")
        end
    end
end)

-- ========== СТАРТОВОЕ УВЕДОМЛЕНИЕ ==========
SendNotify("Rivals Script", "Загружен!\n[X] - ESP\n[Z] - Triggerbot")
