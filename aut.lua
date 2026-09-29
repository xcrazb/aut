-- Auto Farm: Gear + Bait + Egg + Anti-AFK + Place + Craft
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local TS = RS:WaitForChild("TS", 30)
if not TS then warn("[AutoFarm] TS not found!") return end

local remotes = require(TS:WaitForChild("remotes")).default
local pdm = require(TS:WaitForChild("state"):WaitForChild("player-data"))
local getPlayerData = pdm.getPlayerData
local srm = require(TS:WaitForChild("state"):WaitForChild("shop-restock"))
local shopRestock = srm.shopRestock
local ShopType = srm.ShopType
local personalRestockItems = srm.personalRestockItems

local craftingUtils = nil
pcall(function()
    craftingUtils = require(TS:WaitForChild("utils"):WaitForChild("crafting.utils"))
end)

local rc = RS:WaitForChild("rbxts_include"):WaitForChild("node_modules")
    :WaitForChild("@rbxts"):WaitForChild("remo"):WaitForChild("src")
    :WaitForChild("container")
local placeRemote = rc:WaitForChild("ponds.placeBuilding")
local selectCraftRemote = rc:WaitForChild("crafting.selectCraftingItem")
local submitRemote = rc:WaitForChild("crafting.submitItems")
local startCraftRemote = rc:WaitForChild("crafting.startCraft")
local collectRemote = rc:WaitForChild("crafting.collectCraft")

local GEAR_LIST = {
    {t="NetMover"},{t="FoodScoop"},{t="MagnifyingGlass"},{t="TeleportWand"},
    {t="StarLock"},{t="TradingTicket"},{t="BasicAutoFeeder"},{t="AdvancedAutoFeeder"},
    {t="SupremeAutoFeeder"},{t="ExtremeAutoFeeder"},{t="GodlyAutoFeeder"},
    {t="BasicFoodTray"},{t="AdvancedFoodTray"},{t="SupremeFoodTray"},
    {t="XpCookie"},{t="PetToy"},{t="PetWhistle"},{t="GoldenCookie"},
    {t="EggHatcher"},{t="EggIncubator"},{t="MutationBeacon"},{t="StormHorn"},
}

local EGG_WL = {"Tropical", "Exotic"}

local CFG = {
    Interval = 5, Delay = 0.1, BuyAll = true,
    BaitWL = {}, BaitBL = {},
    AfkInt = 300,
    PlaceOn = false, PlaceInt = 300, PlaceType = "SupremeFoodTray",
    PlaceCat = "booster", PlacePos = Vector3.new(10.862998962402344, -0.012000083923339844, -11),
    CraftOn = false, CraftItem = "TimeJumper", CraftCat = "gear",
    CraftMats = {{n="TeleportWand",a=10},{n="MagnifyingGlass",a=25},{n="SupremeAutoFeeder",a=1}},
    CraftInt = 10, CraftStep = 0.5, CraftMon = 5,
}

local S = {
    gOn=false, gTot=0, gRun=false,
    bOn=false, bTot=0, bRun=false, bDet={},
    eOn=false, eTot=0, eRun=false, eDet={},
    aOn=false, aRun=false, aTot=0, aOk=0, aFail=0,
    pRun=false, pCnt=0, pCd=0,
    cRun=false, cAtt=0, cOk=0, cFail=0, cCd=0, cPhase="idle",
    minimized=false,
}

local function log(...) if CFG.Debug ~= false then print("[AutoFarm]", ...) end end

local function getStock(shopType, itemType)
    local ok, res = pcall(function()
        local rs = shopRestock()
        if not rs then return 0 end
        local pi = personalRestockItems()
        local data = getPlayerData(player)
        if not data then return 0 end
        local now = os.time()
        local pr = data.personalRestocks and data.personalRestocks[shopType]
        local active = pr and pr.endTime and now < pr.endTime
        local uid = tostring(player.UserId)
        local avail
        if active then
            avail = pi[uid] and pi[uid][shopType] and pi[uid][shopType][itemType] or 0
        else
            avail = rs.availableItems and rs.availableItems[shopType] and rs.availableItems[shopType][itemType] or 0
        end
        local bought = 0
        local pur = data.shopPurchases and data.shopPurchases[shopType]
        if pur and pur.purchases then
            if active and pur.currentTimeSlot == pr.timeSlot then
                bought = pur.purchases[itemType] or 0
            elseif not active and pur.currentTimeSlot == rs.currentTimeSlot then
                bought = pur.purchases[itemType] or 0
            end
        end
        return math.max(0, avail - bought)
    end)
    return ok and res or 0
end

local function getAvail(shopType, wl, bl)
    local ok, res = pcall(function()
        local rs = shopRestock()
        if not rs then return {} end
        local shop = rs.availableItems and rs.availableItems[shopType]
        if not shop then return {} end
        local list = {}
        for t, s in pairs(shop) do
            local inc = true
            if wl and #wl > 0 then
                inc = false
                for _, w in ipairs(wl) do if t == w then inc = true break end end
            end
            if bl then
                for _, b in ipairs(bl) do if t == b then inc = false break end end
            end
            if inc then table.insert(list, {type=t, stock=s}) end
        end
        return list
    end)
    return ok and res or {}
end

local function buyGear(t) return pcall(remotes.shop.purchaseGear, t) end
local function buyBait(t) return pcall(remotes.shop.purchaseBait, t) end
local function buyEgg(t) return pcall(remotes.shop.purchaseEgg, t) end

local function bulkGear()
    local b, f, s = 0, 0, 0
    for _, g in ipairs(GEAR_LIST) do
        if not S.gOn then break end
        local rem = getStock(ShopType.Gear, g.t)
        if rem <= 0 then s = s + 1 task.wait(0.02) continue end
        local gb = 0
        for a = 1, (CFG.BuyAll and rem + 3 or 1) do
            if not S.gOn then break end
            if a > 1 then
                local ns = getStock(ShopType.Gear, g.t)
                if ns <= 0 then break end
            end
            if buyGear(g.t) then b = b + 1 gb = gb + 1 S.gTot = S.gTot + 1 else f = f + 1 break end
            task.wait(CFG.Delay)
        end
    end
    return b, f, s
end

local function bulkBait()
    local b, f, s = 0, 0, 0
    local list = getAvail(ShopType.Bait, CFG.BaitWL, CFG.BaitBL)
    S.bDet = list
    if #list == 0 then return 0, 0, 0 end
    for _, it in ipairs(list) do
        if not S.bOn then break end
        local rem = getStock(ShopType.Bait, it.type)
        if rem <= 0 then s = s + 1 task.wait(0.02) continue end
        for a = 1, (CFG.BuyAll and rem + 3 or 1) do
            if not S.bOn then break end
            if a > 1 then
                local ns = getStock(ShopType.Bait, it.type)
                if ns <= 0 then break end
            end
            if buyBait(it.type) then b = b + 1 S.bTot = S.bTot + 1 else f = f + 1 break end
            task.wait(CFG.Delay)
        end
    end
    return b, f, s
end

local function bulkEgg()
    local b, f, s = 0, 0, 0
    local list = getAvail(ShopType.Eggs, EGG_WL, nil)
    S.eDet = list
    if #list == 0 then return 0, 0, 0 end
    for _, it in ipairs(list) do
        if not S.eOn then break end
        local rem = getStock(ShopType.Eggs, it.type)
        if rem <= 0 then s = s + 1 task.wait(0.02) continue end
        for a = 1, (CFG.BuyAll and rem + 3 or 1) do
            if not S.eOn then break end
            if a > 1 then
                local ns = getStock(ShopType.Eggs, it.type)
                if ns <= 0 then break end
            end
            if buyEgg(it.type) then b = b + 1 S.eTot = S.eTot + 1 else f = f + 1 break end
            task.wait(CFG.Delay)
        end
    end
    return b, f, s
end

local function doJump()
    S.aTot = S.aTot + 1
    local ch = player.Character
    if not ch then S.aFail = S.aFail + 1 return end
    local h = ch:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then S.aFail = S.aFail + 1 return end
    local cs = h:GetState()
    if cs == Enum.HumanoidStateType.Jumping or cs == Enum.HumanoidStateType.Freefall then
        S.aOk = S.aOk + 1 return
    end
    local ok = pcall(function()
        if h.Sit then h.Sit = false task.wait(0.05) end
        if h.PlatformStand then h.PlatformStand = false task.wait(0.05) end
        h:ChangeState(Enum.HumanoidStateType.Running)
        task.wait(0.05)
        h:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
    if ok then task.wait(0.15) S.aOk = S.aOk + 1 else S.aFail = S.aFail + 1 end
end

local function doPlace()
    S.pCnt = S.pCnt + 1
    local ok = pcall(function()
        placeRemote:InvokeServer(CFG.PlaceCat, CFG.PlaceType, CFG.PlacePos)
    end)
    if ok then log("[Place] ✅ #" .. S.pCnt) else log("[Place] ❌") end
end

local function getCraftTime(id, cat)
    if craftingUtils and craftingUtils.getCraftingTime then
        local ok, r = pcall(function() return craftingUtils.getCraftingTime(id, cat) end)
        if ok and r then return r end
    end
    local d = {DiamondCookie=300, YolkBreaker=600, TimeJumper=600, ShieldLock=1500, NetRetractor=1500}
    return d[id] or 600
end

local function getCraftData()
    local ok, r = pcall(function()
        local data = getPlayerData(player)
        if not data or not data.crafting then return nil end
        local c = data.crafting[CFG.CraftCat]
        if not c or not c.id then return nil end
        return c
    end)
    return ok and r or nil
end

local function getCraftRem()
    local c = getCraftData()
    if not c or not c.timeStarted then return nil end
    local now = os.time()
    local tt = getCraftTime(c.id, CFG.CraftCat)
    local acc = c.accumulatedProgress or 0
    local lu = c.lastProgressUpdate or c.timeStarted
    local dr = c.depletionRate or 1
    return math.max(0, tt - (acc + (now - lu) * dr))
end

local function isCraftActive()
    local c = getCraftData()
    return c and c.timeStarted ~= nil
end

local function doCraftOnce()
    S.cAtt = S.cAtt + 1
    S.cPhase = "submitting"
    local ok = true
    if not pcall(function() selectCraftRemote:FireServer(CFG.CraftItem, CFG.CraftCat) end) then ok = false end
    task.wait(CFG.CraftStep)
    if ok then
        local mats = {}
        for _, m in ipairs(CFG.CraftMats) do
            for i = 1, m.a do table.insert(mats, m.n) end
        end
        if not pcall(function() submitRemote:FireServer(mats, CFG.CraftCat) end) then ok = false end
        task.wait(CFG.CraftStep)
    end
    if ok then
        if not pcall(function() startCraftRemote:FireServer(CFG.CraftCat) end) then ok = false end
        task.wait(CFG.CraftStep)
    end
    if not ok then S.cFail = S.cFail + 1 S.cPhase = "idle" return false end
    S.cPhase = "crafting"
    return true
end

local function monitorCraft()
    while S.cRun and CFG.CraftOn do
        task.wait(CFG.CraftMon)
        if not S.cRun or not CFG.CraftOn then return false end
        local rem = getCraftRem()
        if rem == nil then S.cPhase = "idle" S.cCd = 0 return false end
        S.cCd = rem
        S.cPhase = "crafting"
        if rem <= 0 then
            S.cPhase = "collecting"
            S.cCd = 0
            task.wait(1)
            if pcall(function() collectRemote:FireServer(CFG.CraftCat) end) then
                S.cOk = S.cOk + 1
                S.cPhase = "idle"
                return true
            else
                S.cPhase = "idle"
                return false
            end
        end
    end
    S.cPhase = "idle"
    S.cCd = 0
    return false
end

local function startCraft()
    if S.cRun then return end
    S.cRun = true
    task.spawn(function()
        while S.cRun and CFG.CraftOn do
            if isCraftActive() then monitorCraft()
            else if doCraftOnce() then monitorCraft() end end
            for i = CFG.CraftInt, 1, -1 do
                if not S.cRun or not CFG.CraftOn then break end
                task.wait(1)
            end
        end
        S.cPhase = "idle"
        S.cCd = 0
        S.cRun = false
    end)
end

local function startAntiAfk()
    if S.aRun then return end
    S.aRun = true
    task.spawn(function()
        while S.aRun and S.aOn do
            for i = CFG.AfkInt, 1, -1 do
                if not S.aRun or not S.aOn then break end
                task.wait(1)
            end
            if not S.aRun or not S.aOn then break end
            doJump()
            task.wait(0.5)
        end
        S.aRun = false
    end)
end

local function startPlace()
    if S.pRun then return end
    S.pRun = true
    task.spawn(function()
        doPlace()
        task.wait(0.5)
        while S.pRun and CFG.PlaceOn do
            for i = CFG.PlaceInt, 1, -1 do
                if not S.pRun or not CFG.PlaceOn then break end
                S.pCd = i
                task.wait(1)
            end
            if not S.pRun or not CFG.PlaceOn then break end
            S.pCd = 0
            doPlace()
            task.wait(0.5)
        end
        S.pRun = false
        S.pCd = 0
    end)
end

local function startGearMon()
    if S.gRun then return end
    S.gRun = true
    task.spawn(function()
        while S.gOn do
            bulkGear()
            for i = CFG.Interval, 1, -1 do
                if not S.gOn then break end
                task.wait(1)
            end
        end
        S.gRun = false
    end)
end

local function startBaitMon()
    if S.bRun then return end
    S.bRun = true
    task.spawn(function()
        while S.bOn do
            bulkBait()
            for i = CFG.Interval, 1, -1 do
                if not S.bOn then break end
                task.wait(1)
            end
        end
        S.bRun = false
    end)
end

local function startEggMon()
    if S.eRun then return end
    S.eRun = true
    task.spawn(function()
        while S.eOn do
            bulkEgg()
            for i = CFG.Interval, 1, -1 do
                if not S.eOn then break end
                task.wait(1)
            end
        end
        S.eRun = false
    end)
end

-- GUI
local old = pg:FindFirstChild("AutoFarmUI")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "AutoFarmUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = pg

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 320, 0, 398)
Main.Position = UDim2.new(0.5, -160, 0.5, -199)
Main.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = sg

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 12)
mc.Parent = Main

local ms = Instance.new("UIStroke")
ms.Color = Color3.fromRGB(70, 90, 120)
ms.Thickness = 1.5
ms.Parent = Main

-- Minimized toggle button (small floating button)
local MiniBtn = Instance.new("TextButton")
MiniBtn.Size = UDim2.new(0, 60, 0, 32)
MiniBtn.Position = UDim2.new(0, 10, 0, 10)
MiniBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
MiniBtn.Text = "🛒 Menu"
MiniBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MiniBtn.Font = Enum.Font.GothamBold
MiniBtn.TextSize = 11
MiniBtn.BorderSizePixel = 0
MiniBtn.Visible = false
MiniBtn.Active = true
MiniBtn.Draggable = true
MiniBtn.Parent = sg

local mbc = Instance.new("UICorner")
mbc.CornerRadius = UDim.new(0, 8)
mbc.Parent = MiniBtn

local mbs = Instance.new("UIStroke")
mbs.Color = Color3.fromRGB(70, 200, 70)
mbs.Thickness = 1.5
mbs.Parent = MiniBtn

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
Header.BorderSizePixel = 0
Header.Parent = Main

local hc = Instance.new("UICorner")
hc.CornerRadius = UDim.new(0, 12)
hc.Parent = Header

local hf = Instance.new("Frame")
hf.Size = UDim2.new(1, 0, 0, 12)
hf.Position = UDim2.new(0, 0, 1, -12)
hf.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
hf.BorderSizePixel = 0
hf.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🛒  AUTO FARM"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 26, 0, 26)
MinBtn.Position = UDim2.new(1, -62, 0, 8)
MinBtn.BackgroundColor3 = Color3.fromRGB(80, 130, 200)
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14
MinBtn.BorderSizePixel = 0
MinBtn.Parent = Header

local minc = Instance.new("UICorner")
minc.CornerRadius = UDim.new(0, 6)
minc.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -32, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Header

local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0, 6)
cc.Parent = CloseBtn

-- Button builder
local function makeBtn(y, text, bg, tc, sc)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -24, 0, 44)
    b.Position = UDim2.new(0, 12, 0, y)
    b.BackgroundColor3 = bg
    b.Text = text
    b.TextColor3 = tc
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.BorderSizePixel = 0
    b.Parent = Main
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = b
    local s = Instance.new("UIStroke")
    s.Color = sc
    s.Thickness = 1
    s.Parent = b
    return b, s
end

local GearBtn, GearStroke = makeBtn(54, "▶  BULK BUY GEAR: OFF", Color3.fromRGB(35,45,35), Color3.fromRGB(100,255,100), Color3.fromRGB(70,200,70))
local BaitBtn, BaitStroke = makeBtn(108, "▶  BULK BUY BAIT: OFF", Color3.fromRGB(45,45,30), Color3.fromRGB(255,230,100), Color3.fromRGB(200,180,70))
local EggBtn, EggStroke = makeBtn(162, "▶  BULK BUY EGG: OFF", Color3.fromRGB(50,30,40), Color3.fromRGB(255,130,200), Color3.fromRGB(200,80,160))
local AfkBtn, AfkStroke = makeBtn(216, "🦘  ANTI-AFK: OFF", Color3.fromRGB(30,40,55), Color3.fromRGB(150,200,255), Color3.fromRGB(60,100,150))
local PlaceBtn, PlaceStroke = makeBtn(270, "🏗️  AUTO PLACE: OFF", Color3.fromRGB(45,35,55), Color3.fromRGB(200,150,255), Color3.fromRGB(130,80,180))
local CraftBtn, CraftStroke = makeBtn(324, "⚙️  AUTO CRAFT: OFF", Color3.fromRGB(30,45,50), Color3.fromRGB(100,220,255), Color3.fromRGB(60,150,180))

local function fmt(s)
    s = math.max(0, math.floor(s))
    return string.format("%dm %ds", math.floor(s/60), s%60)
end

local function updateUI()
    -- Gear
    if S.gOn then
        GearBtn.Text = "⏸  BULK BUY GEAR: ON"
        GearBtn.TextColor3 = Color3.fromRGB(255,100,100)
        GearBtn.BackgroundColor3 = Color3.fromRGB(45,30,30)
        GearStroke.Color = Color3.fromRGB(200,70,70)
    else
        GearBtn.Text = "▶  BULK BUY GEAR: OFF"
        GearBtn.TextColor3 = Color3.fromRGB(100,255,100)
        GearBtn.BackgroundColor3 = Color3.fromRGB(35,45,35)
        GearStroke.Color = Color3.fromRGB(70,200,70)
    end
    -- Bait
    if S.bOn then
        BaitBtn.Text = "⏸  BULK BUY BAIT: ON"
        BaitBtn.TextColor3 = Color3.fromRGB(255,150,100)
        BaitBtn.BackgroundColor3 = Color3.fromRGB(50,40,25)
        BaitStroke.Color = Color3.fromRGB(220,140,70)
    else
        BaitBtn.Text = "▶  BULK BUY BAIT: OFF"
        BaitBtn.TextColor3 = Color3.fromRGB(255,230,100)
        BaitBtn.BackgroundColor3 = Color3.fromRGB(45,45,30)
        BaitStroke.Color = Color3.fromRGB(200,180,70)
    end
    -- Egg
    if S.eOn then
        EggBtn.Text = "⏸  BULK BUY EGG: ON"
        EggBtn.TextColor3 = Color3.fromRGB(255,100,180)
        EggBtn.BackgroundColor3 = Color3.fromRGB(55,30,40)
        EggStroke.Color = Color3.fromRGB(200,60,140)
    else
        EggBtn.Text = "▶  BULK BUY EGG: OFF"
        EggBtn.TextColor3 = Color3.fromRGB(255,130,200)
        EggBtn.BackgroundColor3 = Color3.fromRGB(50,30,40)
        EggStroke.Color = Color3.fromRGB(200,80,160)
    end
    -- AFK
    if S.aOn then
        AfkBtn.Text = "🦘  ANTI-AFK: ON"
        AfkBtn.TextColor3 = Color3.fromRGB(100,255,150)
        AfkBtn.BackgroundColor3 = Color3.fromRGB(30,55,40)
        AfkStroke.Color = Color3.fromRGB(70,200,120)
    else
        AfkBtn.Text = "🦘  ANTI-AFK: OFF"
        AfkBtn.TextColor3 = Color3.fromRGB(150,200,255)
        AfkBtn.BackgroundColor3 = Color3.fromRGB(30,40,55)
        AfkStroke.Color = Color3.fromRGB(60,100,150)
    end
    -- Place
    if CFG.PlaceOn then
        PlaceBtn.Text = S.pCd > 0 and ("🏗️  PLACE: " .. S.pCd .. "s") or "🏗️  PLACE: ON"
        PlaceBtn.TextColor3 = Color3.fromRGB(200,255,200)
        PlaceBtn.BackgroundColor3 = Color3.fromRGB(40,60,45)
        PlaceStroke.Color = Color3.fromRGB(120,200,130)
    else
        PlaceBtn.Text = "🏗️  AUTO PLACE: OFF"
        PlaceBtn.TextColor3 = Color3.fromRGB(200,150,255)
        PlaceBtn.BackgroundColor3 = Color3.fromRGB(45,35,55)
        PlaceStroke.Color = Color3.fromRGB(130,80,180)
    end
    -- Craft
    if CFG.CraftOn then
        if S.cPhase == "submitting" then
            CraftBtn.Text = "⚙️  CRAFT: Submitting..."
            CraftBtn.TextColor3 = Color3.fromRGB(255,200,100)
            CraftBtn.BackgroundColor3 = Color3.fromRGB(50,45,30)
            CraftStroke.Color = Color3.fromRGB(220,170,70)
        elseif S.cPhase == "crafting" then
            CraftBtn.Text = S.cCd > 0 and ("⚙️  CRAFT: " .. fmt(S.cCd)) or "⚙️  CRAFT: Finishing..."
            CraftBtn.TextColor3 = Color3.fromRGB(150,255,255)
            CraftBtn.BackgroundColor3 = Color3.fromRGB(30,60,65)
            CraftStroke.Color = Color3.fromRGB(100,220,255)
        elseif S.cPhase == "collecting" then
            CraftBtn.Text = "⚙️  CRAFT: Collecting..."
            CraftBtn.TextColor3 = Color3.fromRGB(200,255,200)
            CraftBtn.BackgroundColor3 = Color3.fromRGB(40,60,45)
            CraftStroke.Color = Color3.fromRGB(120,200,130)
        else
            CraftBtn.Text = "⚙️  CRAFT: ON — " .. CFG.CraftItem
            CraftBtn.TextColor3 = Color3.fromRGB(150,255,255)
            CraftBtn.BackgroundColor3 = Color3.fromRGB(30,60,65)
            CraftStroke.Color = Color3.fromRGB(100,220,255)
        end
    else
        CraftBtn.Text = "⚙️  AUTO CRAFT: OFF"
        CraftBtn.TextColor3 = Color3.fromRGB(100,220,255)
        CraftBtn.BackgroundColor3 = Color3.fromRGB(30,45,50)
        CraftStroke.Color = Color3.fromRGB(60,150,180)
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        updateUI()
    end
end)

-- Events
GearBtn.MouseButton1Click:Connect(function()
    S.gOn = not S.gOn
    updateUI()
    if S.gOn then startGearMon() end
end)

BaitBtn.MouseButton1Click:Connect(function()
    S.bOn = not S.bOn
    updateUI()
    if S.bOn then startBaitMon() end
end)

EggBtn.MouseButton1Click:Connect(function()
    S.eOn = not S.eOn
    updateUI()
    if S.eOn then startEggMon() end
end)

AfkBtn.MouseButton1Click:Connect(function()
    S.aOn = not S.aOn
    if S.aOn then startAntiAfk() else S.aRun = false end
    updateUI()
end)

PlaceBtn.MouseButton1Click:Connect(function()
    CFG.PlaceOn = not CFG.PlaceOn
    if CFG.PlaceOn then startPlace() else S.pRun = false S.pCd = 0 end
    updateUI()
end)

CraftBtn.MouseButton1Click:Connect(function()
    CFG.CraftOn = not CFG.CraftOn
    if CFG.CraftOn then startCraft()
    else S.cRun = false S.cCd = 0 S.cPhase = "idle" end
    updateUI()
end)

-- Minimize / Restore
local function setMinimized(state)
    S.minimized = state
    Main.Visible = not state
    MiniBtn.Visible = state
end

MinBtn.MouseButton1Click:Connect(function()
    setMinimized(true)
end)

MiniBtn.MouseButton1Click:Connect(function()
    setMinimized(false)
end)

CloseBtn.MouseButton1Click:Connect(function()
    S.gOn = false S.bOn = false S.eOn = false S.aOn = false
    CFG.PlaceOn = false CFG.CraftOn = false
    S.aRun = false S.pRun = false S.cRun = false
    sg:Destroy()
end)

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        if sg.Parent then sg.Enabled = not sg.Enabled end
    end
end)

-- Init
updateUI()
log("GUI loaded! RightCtrl to toggle. — minimize button added.")
log("Egg whitelist: " .. table.concat(EGG_WL, ", "))
