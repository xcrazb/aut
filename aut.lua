-- =========================================
-- AUTO FARM + GOLDEN MERCHANT
-- Gear + Bait + Egg + Anti-AFK + Place + Craft + Golden Bulk
-- =========================================

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local TS = RS:WaitForChild("TS", 30)
if not TS then warn("[AutoFarm] TS not found!") return end

-- ============ CORE MODULES ============
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

-- Golden merchant module
local tm = require(TS.state["travelling-merchant"])
local travellingMerchants = tm.travellingMerchants

-- ============ REMOTES ============
local rc = RS:WaitForChild("rbxts_include"):WaitForChild("node_modules")
    :WaitForChild("@rbxts"):WaitForChild("remo"):WaitForChild("src")
    :WaitForChild("container")
local placeRemote        = rc:WaitForChild("ponds.placeBuilding")
local selectCraftRemote  = rc:WaitForChild("crafting.selectCraftingItem")
local submitRemote       = rc:WaitForChild("crafting.submitItems")
local startCraftRemote   = rc:WaitForChild("crafting.startCraft")
local collectRemote      = rc:WaitForChild("crafting.collectCraft")
local goldenBuyRemote    = rc:WaitForChild("merchant.purchaseItem")

local purchaseGear = remotes.shop.purchaseGear
local purchaseBait = remotes.shop.purchaseBait
local purchaseEgg  = remotes.shop.purchaseEgg

local GEAR_LIST = {
    "NetMover","FoodScoop","MagnifyingGlass","TeleportWand",
    "StarLock","TradingTicket","BasicAutoFeeder","AdvancedAutoFeeder",
    "SupremeAutoFeeder","ExtremeAutoFeeder","GodlyAutoFeeder",
    "BasicFoodTray","AdvancedFoodTray","SupremeFoodTray",
    "XpCookie","PetToy","PetWhistle","GoldenCookie",
    "EggHatcher","EggIncubator","MutationBeacon","StormHorn",
}
local EGG_WL = {"Tropical", "Exotic"}

-- ============ COLOR ============
local COLOR = {
    ON_BG      = Color3.fromRGB(50, 200, 80),
    ON_TEXT    = Color3.fromRGB(255, 255, 255),
    ON_STROKE  = Color3.fromRGB(30, 140, 50),
    OFF_BG     = Color3.fromRGB(200, 60, 60),
    OFF_TEXT   = Color3.fromRGB(255, 255, 255),
    OFF_STROKE = Color3.fromRGB(140, 30, 30),
}

-- ============ CONFIG ============
local CFG = {
    Interval = 5, BuyAll = true,
    BaitWL = {}, BaitBL = {},
    AfkInt = 300,
    PlaceOn = false, PlaceInt = 300, PlaceType = "SupremeFoodTray",
    PlaceCat = "booster", PlacePos = Vector3.new(10.862998962402344, -0.012000083923339844, -11),
    CraftOn = false, CraftItem = "TimeJumper", CraftCat = "gear",
    CraftMats = {{n="TeleportWand",a=10},{n="MagnifyingGlass",a=25},{n="SupremeAutoFeeder",a=1}},
    CraftMon = 5,
    StockTTL = 1.5,
    BuyDelay = 0.08,
    SchedulerTick = 0.5,
    -- Golden
    GoldenInterval = 3,
    GoldenIdleInterval = 10,
    GoldenBuyDelay = 0.25,
    GoldenBulkLoopDelay = 0.4,
    GoldenMaxPass = 8,
}

local S = {
    gOn=false, gTot=0,
    bOn=false, bTot=0,
    eOn=false, eTot=0,
    aOn=false, aTot=0, aOk=0, aFail=0,
    pRun=false, pCnt=0, pCd=0,
    cRun=false, cAtt=0, cOk=0, cFail=0, cCd=0, cPhase="idle",
    gdOn=false, gdTot=0, gdActive=false,
    minimized=false,
    nextGear=0, nextBait=0, nextEgg=0, nextAfk=0, nextPlace=0, nextGolden=0,
    _stockCache = {},
    fps = 0,
}

local function log(...) if CFG.Debug ~= false then print("[AutoFarm]", ...) end end

-- ============ STOCK ============
local function stockCacheKey(shopType, itemType) return shopType .. "|" .. itemType end

local function getStock(shopType, itemType)
    local k = stockCacheKey(shopType, itemType)
    local now = os.clock()
    local c = S._stockCache[k]
    if c and (now - c.t) < CFG.StockTTL then return c.v end

    local val = 0
    local ok, rs, pi, data = pcall(function()
        return shopRestock(), personalRestockItems(), getPlayerData(player)
    end)
    if ok and rs and data then
        local nowT = os.time()
        local pr = data.personalRestocks and data.personalRestocks[shopType]
        local active = pr and pr.endTime and nowT < pr.endTime
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
        val = math.max(0, avail - bought)
    end

    S._stockCache[k] = {v = val, t = now}
    return val
end

local function invalidateStock(shopType, itemType)
    S._stockCache[stockCacheKey(shopType, itemType)] = nil
end

-- ============ AVAILABLE LIST ============
local function getAvail(shopType, wl, bl)
    local list = {}
    local rs = shopRestock()
    if not rs then return list end
    local shop = rs.availableItems and rs.availableItems[shopType]
    if not shop then return list end
    local wlSet, blSet
    if wl and #wl > 0 then wlSet = {} for _, v in ipairs(wl) do wlSet[v] = true end end
    if bl and #bl > 0 then blSet = {} for _, v in ipairs(bl) do blSet[v] = true end end
    for t, s in pairs(shop) do
        local inc = true
        if wlSet and not wlSet[t] then inc = false end
        if inc and blSet and blSet[t] then inc = false end
        if inc then list[#list+1] = {type=t, stock=s} end
    end
    return list
end

-- ============ BUY HELPERS ============
local function buyGearSafe(t)
    local ok = pcall(purchaseGear, t)
    if ok then invalidateStock(ShopType.Gear, t) end
    return ok
end
local function buyBaitSafe(t)
    local ok = pcall(purchaseBait, t)
    if ok then invalidateStock(ShopType.Bait, t) end
    return ok
end
local function buyEggSafe(t)
    local ok = pcall(purchaseEgg, t)
    if ok then invalidateStock(ShopType.Eggs, t) end
    return ok
end

-- ============ BULK BUY ============
local function bulkGear()
    for _, t in ipairs(GEAR_LIST) do
        if not S.gOn then return end
        local rem = getStock(ShopType.Gear, t)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.gOn then return end
                if not buyGearSafe(t) then break end
                S.gTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

local function bulkBait()
    local list = getAvail(ShopType.Bait, CFG.BaitWL, CFG.BaitBL)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.bOn then return end
        local rem = getStock(ShopType.Bait, it.type)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.bOn then return end
                if not buyBaitSafe(it.type) then break end
                S.bTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

local function bulkEgg()
    local list = getAvail(ShopType.Eggs, EGG_WL, nil)
    if #list == 0 then return end
    for _, it in ipairs(list) do
        if not S.eOn then return end
        local rem = getStock(ShopType.Eggs, it.type)
        if rem > 0 then
            local max = CFG.BuyAll and (rem + 2) or 1
            for a = 1, max do
                if not S.eOn then return end
                if not buyEggSafe(it.type) then break end
                S.eTot += 1
                if a < max then task.wait(CFG.BuyDelay) end
            end
        end
    end
end

-- ============ ANTI-AFK ============
local function doJump()
    S.aTot += 1
    local ch = player.Character
    if not ch then S.aFail += 1 return end
    local h = ch:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then S.aFail += 1 return end
    local cs = h:GetState()
    if cs == Enum.HumanoidStateType.Jumping or cs == Enum.HumanoidStateType.Freefall then
        S.aOk += 1 return
    end
    local ok = pcall(function()
        if h.Sit then h.Sit = false task.wait(0.05) end
        if h.PlatformStand then h.PlatformStand = false task.wait(0.05) end
        h:ChangeState(Enum.HumanoidStateType.Running)
        task.wait(0.05)
        h:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
    if ok then S.aOk += 1 else S.aFail += 1 end
end

-- ============ PLACE ============
local function doPlace()
    S.pCnt += 1
    pcall(function()
        placeRemote:InvokeServer(CFG.PlaceCat, CFG.PlaceType, CFG.PlacePos)
    end)
end

-- ============ CRAFT ============
local CRAFT_TIME_FALLBACK = {DiamondCookie=300, YolkBreaker=600, TimeJumper=600, ShieldLock=1500, NetRetractor=1500}

local function getCraftTime(id, cat)
    if craftingUtils and craftingUtils.getCraftingTime then
        local ok, r = pcall(craftingUtils.getCraftingTime, id, cat)
        if ok and r then return r end
    end
    return CRAFT_TIME_FALLBACK[id] or 600
end

local function getCraftData()
    local data = getPlayerData(player)
    if not data or not data.crafting then return nil end
    local c = data.crafting[CFG.CraftCat]
    if not c or not c.id then return nil end
    return c
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
    S.cAtt += 1
    S.cPhase = "submitting"
    local ok = pcall(function()
        selectCraftRemote:FireServer(CFG.CraftItem, CFG.CraftCat)
    end)
    task.wait(0.3)
    if ok then
        local mats, idx = {}, 1
        for _, m in ipairs(CFG.CraftMats) do
            for _ = 1, m.a do mats[idx] = m.n idx += 1 end
        end
        ok = pcall(function() submitRemote:FireServer(mats, CFG.CraftCat) end)
        task.wait(0.3)
    end
    if ok then
        ok = pcall(function() startCraftRemote:FireServer(CFG.CraftCat) end)
        task.wait(0.3)
    end
    if not ok then
        S.cFail += 1
        S.cPhase = "idle"
        return false
    end
    S.cPhase = "crafting"
    return true
end

local function collectCraft()
    S.cPhase = "collecting"
    local ok = pcall(function() collectRemote:FireServer(CFG.CraftCat) end)
    if ok then S.cOk += 1 end
    S.cPhase = "idle"
    return ok
end

-- ============ GOLDEN MERCHANT ============
local function getGoldenData()
    local data = travellingMerchants()
    if not data then return nil end
    return data.golden
end

local function getGoldenStock()
    local md = getGoldenData()
    if not md or not md.isActive or not md.availableStock then
        return {}, false
    end
    local map = {}
    for k, v in pairs(md.availableStock) do map[k] = v end
    return map, true
end

local function goldenBuyOne(itemName)
    local ok = pcall(function()
        goldenBuyRemote:FireServer("golden", itemName)
    end)
    return ok
end

local function goldenBulkBuy()
    local totalBought = 0
    local pass = 0

    while S.gdOn and pass < CFG.GoldenMaxPass do
        pass += 1
        local map, active = getGoldenStock()
        if not active then break end

        local targets = {}
        for itemName, stock in pairs(map) do
            if stock > 0 then
                table.insert(targets, itemName)
            end
        end

        if #targets == 0 then break end

        for _, itemName in ipairs(targets) do
            if not S.gdOn then break end
            if goldenBuyOne(itemName) then
                totalBought += 1
                S.gdTot += 1
            end
            task.wait(CFG.GoldenBuyDelay)
        end

        task.wait(CFG.GoldenBulkLoopDelay)
    end

    return totalBought
end

-- ============ SCHEDULER ============
local schedulerRunning = false

local function tickScheduler()
    local now = os.clock()

    if S.gOn and now >= S.nextGear then
        S.nextGear = now + CFG.Interval
        task.spawn(bulkGear)
    end
    if S.bOn and now >= S.nextBait then
        S.nextBait = now + CFG.Interval
        task.spawn(bulkBait)
    end
    if S.eOn and now >= S.nextEgg then
        S.nextEgg = now + CFG.Interval
        task.spawn(bulkEgg)
    end
    if S.aOn and now >= S.nextAfk then
        S.nextAfk = now + CFG.AfkInt
        task.spawn(doJump)
    end
    if CFG.PlaceOn and now >= S.nextPlace then
        S.nextPlace = now + CFG.PlaceInt
        task.spawn(doPlace)
    end

    -- Golden merchant
    if S.gdOn and now >= S.nextGolden then
        local interval = S.gdActive and CFG.GoldenInterval or CFG.GoldenIdleInterval
        S.nextGolden = now + interval
        task.spawn(function()
            local _, active = getGoldenStock()
            S.gdActive = active
            if active then
                goldenBulkBuy()
            end
        end)
    end

    -- Craft
    if CFG.CraftOn then
        if isCraftActive() then
            local rem = getCraftRem()
            if rem then
                S.cCd = rem
                S.cPhase = "crafting"
                if rem <= 0 then task.spawn(collectCraft) end
            else
                S.cPhase = "idle"
                S.cCd = 0
            end
        else
            if not S._nextCraftTry or now >= S._nextCraftTry then
                S._nextCraftTry = now + 2
                task.spawn(doCraftOnce)
            end
        end
    else
        S.cCd = 0
    end
end

local function startScheduler()
    if schedulerRunning then return end
    schedulerRunning = true
    task.spawn(function()
        while schedulerRunning do
            tickScheduler()
            task.wait(CFG.SchedulerTick)
        end
    end)
end

-- ============ UI (COMPACT) ============
local old = pg:FindFirstChild("AutoFarmUI")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "AutoFarmUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = pg

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 210, 0, 328)   -- lebih kecil
Main.Position = UDim2.new(0.5, -105, 0.5, -164)
Main.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = sg
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke") ms.Color = Color3.fromRGB(70, 90, 120) ms.Thickness = 1.2 ms.Parent = Main

local MiniBtn = Instance.new("TextButton")
MiniBtn.Size = UDim2.new(0, 56, 0, 28)
MiniBtn.Position = UDim2.new(0, 10, 0, 10)
MiniBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
MiniBtn.Text = "🛒"
MiniBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MiniBtn.Font = Enum.Font.GothamBold
MiniBtn.TextSize = 12
MiniBtn.BorderSizePixel = 0
MiniBtn.Visible = false
MiniBtn.Active = true
MiniBtn.Draggable = true
MiniBtn.Parent = sg
Instance.new("UICorner", MiniBtn).CornerRadius = UDim.new(0, 6)
local mbs = Instance.new("UIStroke") mbs.Color = Color3.fromRGB(70, 200, 70) mbs.Thickness = 1.2 mbs.Parent = MiniBtn

local MiniFps = Instance.new("TextLabel")
MiniFps.Size = UDim2.new(1, 0, 0, 12)
MiniFps.Position = UDim2.new(0, 0, 1, 0)
MiniFps.BackgroundTransparency = 1
MiniFps.Text = "FPS"
MiniFps.TextColor3 = Color3.fromRGB(150, 255, 150)
MiniFps.Font = Enum.Font.GothamBold
MiniFps.TextSize = 9
MiniFps.Parent = MiniBtn

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 32)
Header.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
Header.BorderSizePixel = 0
Header.Parent = Main
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 8, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🛒 AUTO FARM"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 11
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local FpsLabel = Instance.new("TextLabel")
FpsLabel.Size = UDim2.new(0, 46, 0, 20)
FpsLabel.Position = UDim2.new(1, -94, 0, 6)
FpsLabel.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
FpsLabel.BackgroundTransparency = 0.2
FpsLabel.Text = "--"
FpsLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
FpsLabel.Font = Enum.Font.GothamBold
FpsLabel.TextSize = 10
FpsLabel.BorderSizePixel = 0
FpsLabel.Parent = Header
Instance.new("UICorner", FpsLabel).CornerRadius = UDim.new(0, 5)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 20, 0, 20)
MinBtn.Position = UDim2.new(1, -44, 0, 6)
MinBtn.BackgroundColor3 = Color3.fromRGB(80, 130, 200)
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.BorderSizePixel = 0
MinBtn.Parent = Header
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 5)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 20, 0, 20)
CloseBtn.Position = UDim2.new(1, -22, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 10
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local function makeBtn(y, text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 34)
    b.Position = UDim2.new(0, 8, 0, y)
    b.BackgroundColor3 = COLOR.OFF_BG
    b.Text = text
    b.TextColor3 = COLOR.OFF_TEXT
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.BorderSizePixel = 0
    b.Parent = Main
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = b
    local s = Instance.new("UIStroke") s.Color = COLOR.OFF_STROKE s.Thickness = 1.2 s.Parent = b
    return b, s
end

local GearBtn, GearStroke   = makeBtn(40,  "▶ GEAR: OFF")
local BaitBtn, BaitStroke   = makeBtn(78,  "▶ BAIT: OFF")
local EggBtn, EggStroke     = makeBtn(116, "▶ EGG: OFF")
local AfkBtn, AfkStroke     = makeBtn(154, "🦘 ANTI-AFK: OFF")
local PlaceBtn, PlaceStroke = makeBtn(192, "🏗️ PLACE: OFF")
local CraftBtn, CraftStroke = makeBtn(230, "⚙️ CRAFT: OFF")
local GoldenBtn, GoldenStroke = makeBtn(268, "🥇 GOLDEN: OFF")

local function setBtnState(btn, stroke, isOn, onText, offText)
    if isOn then
        btn.BackgroundColor3 = COLOR.ON_BG
        btn.TextColor3 = COLOR.ON_TEXT
        stroke.Color = COLOR.ON_STROKE
        btn.Text = onText
    else
        btn.BackgroundColor3 = COLOR.OFF_BG
        btn.TextColor3 = COLOR.OFF_TEXT
        stroke.Color = COLOR.OFF_STROKE
        btn.Text = offText
    end
end

local function fmt(s)
    s = math.max(0, math.floor(s))
    return string.format("%dm %ds", math.floor(s/60), s%60)
end

local function updateUI()
    setBtnState(GearBtn, GearStroke, S.gOn,
        "⏸ GEAR: ON", "▶ GEAR: OFF")
    setBtnState(BaitBtn, BaitStroke, S.bOn,
        "⏸ BAIT: ON", "▶ BAIT: OFF")
    setBtnState(EggBtn, EggStroke, S.eOn,
        "⏸ EGG: ON", "▶ EGG: OFF")
    setBtnState(AfkBtn, AfkStroke, S.aOn,
        "🦘 ANTI-AFK: ON", "🦘 ANTI-AFK: OFF")
    setBtnState(PlaceBtn, PlaceStroke, CFG.PlaceOn,
        "🏗️ PLACE: ON", "🏗️ PLACE: OFF")

    -- Golden status (teks dinamis)
    if S.gdOn then
        GoldenBtn.BackgroundColor3 = COLOR.ON_BG
        GoldenBtn.TextColor3 = COLOR.ON_TEXT
        GoldenStroke.Color = COLOR.ON_STROKE
        if S.gdActive then
            GoldenBtn.Text = "🥇 GOLDEN: AKTIF"
        else
            GoldenBtn.Text = "🥇 GOLDEN: WAIT"
        end
    else
        GoldenBtn.BackgroundColor3 = COLOR.OFF_BG
        GoldenBtn.TextColor3 = COLOR.OFF_TEXT
        GoldenStroke.Color = COLOR.OFF_STROKE
        GoldenBtn.Text = "🥇 GOLDEN: OFF"
    end

    if CFG.CraftOn then
        CraftBtn.BackgroundColor3 = COLOR.ON_BG
        CraftBtn.TextColor3 = COLOR.ON_TEXT
        CraftStroke.Color = COLOR.ON_STROKE
        if S.cPhase == "submitting" then
            CraftBtn.Text = "⚙️ CRAFT: Submit..."
        elseif S.cPhase == "crafting" then
            CraftBtn.Text = S.cCd > 0 and ("⚙️ CRAFT: " .. fmt(S.cCd)) or "⚙️ CRAFT: Finish"
        elseif S.cPhase == "collecting" then
            CraftBtn.Text = "⚙️ CRAFT: Collect"
        else
            CraftBtn.Text = "⚙️ CRAFT: ON"
        end
    else
        CraftBtn.BackgroundColor3 = COLOR.OFF_BG
        CraftBtn.TextColor3 = COLOR.OFF_TEXT
        CraftStroke.Color = COLOR.OFF_STROKE
        CraftBtn.Text = "⚙️ CRAFT: OFF"
    end
end

-- ============ FPS ============
local frameCount = 0
local fpsAccum = 0
local lastFpsUpdate = os.clock()

RunService.RenderStepped:Connect(function(dt)
    frameCount += 1
    fpsAccum += dt
    local now = os.clock()
    if now - lastFpsUpdate >= 0.5 then
        local fps = math.floor(frameCount / fpsAccum + 0.5)
        S.fps = fps
        local col
        if fps >= 50 then col = Color3.fromRGB(120, 255, 120)
        elseif fps >= 30 then col = Color3.fromRGB(255, 220, 100)
        else col = Color3.fromRGB(255, 100, 100) end

        FpsLabel.Text = tostring(fps)
        FpsLabel.TextColor3 = col

        if MiniBtn.Visible then
            MiniFps.Text = "FPS " .. fps
            MiniFps.TextColor3 = col
        end

        frameCount = 0
        fpsAccum = 0
        lastFpsUpdate = now
    end
end)

-- Update status tiap 1 detik (golden + craft)
task.spawn(function()
    while sg.Parent do
        task.wait(1)
        if S.gdOn then
            local _, active = getGoldenStock()
            S.gdActive = active
        end
        updateUI()
    end
end)

-- ============ EVENTS ============
GearBtn.MouseButton1Click:Connect(function()
    S.gOn = not S.gOn; S.nextGear = 0; updateUI()
end)
BaitBtn.MouseButton1Click:Connect(function()
    S.bOn = not S.bOn; S.nextBait = 0; updateUI()
end)
EggBtn.MouseButton1Click:Connect(function()
    S.eOn = not S.eOn; S.nextEgg = 0; updateUI()
end)
AfkBtn.MouseButton1Click:Connect(function()
    S.aOn = not S.aOn; S.nextAfk = 0; updateUI()
end)
PlaceBtn.MouseButton1Click:Connect(function()
    CFG.PlaceOn = not CFG.PlaceOn; S.nextPlace = 0; updateUI()
end)
CraftBtn.MouseButton1Click:Connect(function()
    CFG.CraftOn = not CFG.CraftOn
    S._nextCraftTry = 0
    if not CFG.CraftOn then S.cPhase = "idle"; S.cCd = 0 end
    updateUI()
end)
GoldenBtn.MouseButton1Click:Connect(function()
    S.gdOn = not S.gdOn; S.nextGolden = 0; updateUI()
end)

local function setMinimized(state)
    S.minimized = state
    Main.Visible = not state
    MiniBtn.Visible = state
end
MinBtn.MouseButton1Click:Connect(function() setMinimized(true) end)
MiniBtn.MouseButton1Click:Connect(function() setMinimized(false) end)

CloseBtn.MouseButton1Click:Connect(function()
    S.gOn = false S.bOn = false S.eOn = false S.aOn = false S.gdOn = false
    CFG.PlaceOn = false CFG.CraftOn = false
    schedulerRunning = false
    sg:Destroy()
end)

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        if sg.Parent then sg.Enabled = not sg.Enabled end
    end
end)

-- ============ INIT ============
updateUI()
startScheduler()
log("GUI loaded! RightCtrl toggle.")
