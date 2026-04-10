-- Nemo.lua

---------------------------------------------------------------------------
-- Saved Variables
---------------------------------------------------------------------------
NemoDB = NemoDB or {}

-- Default settings
local DEFAULT_SETTINGS = {
    opacity        = 0.88,
    scale          = 1.0,
    frameWidth     = 280,
    frameHeight    = 360,
    locked         = false,
    accentColor    = { 0.86, 0.71, 0.19 },
    showTotal      = true,
    autoShow       = true,
    autoHide       = true,
    hideDelay      = 45,
    -- Saved position (nil = use default)
    anchorPoint    = nil,
    anchorX        = nil,
    anchorY        = nil,
    totalFishingTime = 0,
    showMinimap    = true,
    fontKey        = "Friz Quadrata",
    sortMode       = "count",  -- "count" or "recent"
}

-- Accent color presets for the picker
local COLOR_PRESETS = {
    { name = "Ocean",    color = { 0.30, 0.75, 0.95 } },
    { name = "Ember",    color = { 0.95, 0.45, 0.25 } },
    { name = "Jade",     color = { 0.30, 0.85, 0.55 } },
    { name = "Violet",   color = { 0.65, 0.40, 0.95 } },
    { name = "Rose",     color = { 0.92, 0.45, 0.60 } },
    { name = "Frost",    color = { 0.70, 0.88, 0.95 } },
    { name = "Blood",    color = { 0.85, 0.15, 0.20 } },
    { name = "Gold",     color = { 0.86, 0.71, 0.19 } }
}

local NEMO_FONT = "Fonts\\FRIZQT__.TTF"
---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local VOIDSTORM_MAP_ID = 2405

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local isFishing = false
local hideGeneration = 0
local settings
local wasVortexChannel = false
local silentMode = false
local silentCatches = {}  -- { [itemName] = count } accumulated while silent mode is on
local quietMode = false
local quietModeSavedHeight = nil
local fishingLootOpen = false
local isCompressedOcean = false   -- true when fishing from a Hyper-Compressed Ocean toy
local isAnglersAnomaly = false    -- true when fishing from Angler's Anomaly (void hole outside Voidstorm)

-- Session tracking (resets each login)
local session = {
    catches       = 0,       -- Total items caught this session
    unique        = {},      -- Set of unique item names caught this session
    fishStart     = nil,     -- GetTime() when current fishing bout started
    totalTime     = 0,       -- Accumulated fishing time in seconds
    recentCatches = {},      -- Last 3 catches (name, icon, count) for minimap tooltip
}

-- Spell IDs for standard fishing casts
local FISHING_SPELLS = {
    [131474] = true, [131490] = true, [243756] = true,
}

-- Quality colors matching WoW's standard item quality tiers
local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },   -- Poor (gray)
    [1] = { 1.00, 1.00, 1.00 },   -- Common (white)
    [2] = { 0.12, 1.00, 0.00 },   -- Uncommon (green)
    [3] = { 0.00, 0.44, 0.87 },   -- Rare (blue)
    [4] = { 0.64, 0.21, 0.93 },   -- Epic (purple)
    [5] = { 1.00, 0.50, 0.00 },   -- Legendary (orange)
}

-- Items to ignore when fishing (auto-awarded, not actual catches)
local ITEM_BLACKLIST = {
    ["Community Coupon"] = true,
}

---------------------------------------------------------------------------
-- LOCALS
---------------------------------------------------------------------------
local sessionText
local totalFishingTimeText
local FlashMinimapIcon
local PrintSessionSummary
local footerBg

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------

local function RecordRecentCatch(name, icon, count)
    table.insert(session.recentCatches, 1, { name = name, icon = icon, count = count })
    if #session.recentCatches > 3 then
        session.recentCatches[4] = nil
    end
end

local function GetCurrentMapId()
    return C_Map.GetBestMapForUnit("player")
end

local function GetCurrentZoneName()
    local mapId = GetCurrentMapId()
    if mapId then
        local info = C_Map.GetMapInfo(mapId)
        if info then return info.name end
    end
    return "Unknown"
end

-- Returns the user's chosen accent color (r, g, b)
-- Falls back to default blue if settings haven't loaded yet
local function GetAccent()
    if not settings then return 0.86, 0.71, 0.19 end
    return settings.accentColor[1], settings.accentColor[2], settings.accentColor[3]
end

local function FillDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                for i, val in pairs(v) do target[k][i] = val end
            else
                target[k] = v
            end
        end
    end
end

local function FormatFishingTime(seconds)
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

local function FormatNumber(n)
    local formatted = tostring(n)
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function GetTotalFishingTime()
    local fishTime = session.totalTime
    if session.fishStart then
        fishTime = fishTime + (GetTime() - session.fishStart)
    end
    return fishTime
end

local function UpdateTimerText()
    if not settings.showTotal then
        sessionText:SetText("")
        totalFishingTimeText:SetText("")
        return
    end

    if session.catches > 0 then
        local timeStr = FormatFishingTime(GetTotalFishingTime())
        sessionText:SetText("Session: " .. FormatNumber(session.catches) .. " caught  ·  " .. timeStr)
    else
        sessionText:SetText("")
    end

    local liveDelta = session.fishStart and (GetTime() - session.fishStart) or 0
    local liveTotal = (settings.totalFishingTime or 0) + liveDelta
    totalFishingTimeText:SetText("Total fishing time: " .. FormatFishingTime(liveTotal))
end

-- snapshot the current fishing sessions time into session and persistent totals
local function SnapshotFishingTime()
    if not session.fishStart then return end
    local delta = GetTime() - session.fishStart
    session.totalTime = session.totalTime + delta
    settings.totalFishingTime = (settings.totalFishingTime or 0) + delta
    session.fishStart = nil
end

local LSM = LibStub("LibSharedMedia-3.0")

LSM:Register("font", "Friz Quadrata", "Fonts\\FRIZQT__.TTF")

local locale = GetLocale()
-- WoW built-in CJK/Cyrillic fonts (only present on localized clients)
if locale == "zhCN" then
    LSM:Register("font", "AR CrystalzcuheiGBK",  "Fonts\\ARHei.ttf")
    LSM:Register("font", "AR ZhongkaiGBK",        "Fonts\\ARKai_T.ttf")
elseif locale == "zhTW" then
    LSM:Register("font", "AR Heiti2 Medium",       "Fonts\\bHEI00M.ttf")
    LSM:Register("font", "AR Leisu Demi",          "Fonts\\blei00d.TTF")
    LSM:Register("font", "AR Kaiti Medium",        "Fonts\\bKAI00M.ttf")
elseif locale == "koKR" then
    LSM:Register("font", "2002",                   "Fonts\\2002.TTF")
    LSM:Register("font", "K_Pagetext",             "Fonts\\K_Pagetext.TTF")
elseif locale == "ruRU" then
    LSM:Register("font", "Friz Quadrata CYR",      "Fonts\\FRIZQT___CYR.TTF")
end

local function GetFont()
    if not settings then return NEMO_FONT end
    return LSM:Fetch("font", settings.fontKey) or NEMO_FONT
end

local ApplyFont

---------------------------------------------------------------------------
-- MAIN FRAME
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "NemoFrame", UIParent, "BackdropTemplate")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetResizeBounds(220, 200, 500, 700)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

local topStripe = frame:CreateTexture(nil, "OVERLAY")
topStripe:SetHeight(2)
topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)

local function ApplyFrameStyle()
    local r, g, b = GetAccent()

    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    frame:SetBackdropColor(0.03, 0.06, 0.14, quietMode and 0 or settings.opacity)
    frame:SetBackdropBorderColor(0.2, 0.25, 0.35, quietMode and 0 or 0.8)
    frame:SetScale(settings.scale)
    frame:SetWidth(settings.frameWidth)
    frame:SetHeight(quietMode and 32 or settings.frameHeight)

    topStripe:SetColorTexture(r, g, b)
end



---------------------------------------------------------------------------
-- TITLE BAR
---------------------------------------------------------------------------

local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetHeight(32)
titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function()
    if not settings.locked then frame:StartMoving() end
end)
titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()

    local point, _, _, x, y = frame:GetPoint()
    settings.anchorPoint = point
    settings.anchorX = x
    settings.anchorY = y
end)

local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0, 0, 0, 0)

local fishIcon = titleBar:CreateTexture(nil, "ARTWORK")
fishIcon:SetSize(16, 16)
fishIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
fishIcon:SetTexture("Interface\\AddOns\\Nemo\\Textures\\hook")

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", fishIcon, "RIGHT", 6, 0)
titleText:SetFont(NEMO_FONT, 17, "")
titleText:SetText("Nemo")

local zoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
zoneText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -4)
zoneText:SetFont(NEMO_FONT, 13, "")

local zoneTotalCount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
zoneTotalCount:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
zoneTotalCount:SetPoint("TOP", titleBar, "BOTTOM", 0, -4)
zoneTotalCount:SetFont(NEMO_FONT, 12, "")


local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
closeIcon:SetAllPoints()
closeIcon:SetTexture("Interface\\AddOns\\Nemo\\Textures\\close")
closeIcon:SetVertexColor(0.5, 0.5, 0.5)

closeBtn:SetScript("OnEnter", function()
    closeIcon:SetVertexColor(1, 0.3, 0.3)
end)

closeBtn:SetScript("OnLeave", function()
    closeIcon:SetVertexColor(0.5, 0.5, 0.5)
end)

local gearBtn = CreateFrame("Button", nil, titleBar)
gearBtn:SetSize(16, 16)
gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
gearIcon:SetAllPoints()
gearIcon:SetTexture("Interface\\AddOns\\Nemo\\Textures\\settings")
gearIcon:SetVertexColor(0.6, 0.6, 0.6)
gearBtn:SetScript("OnEnter", function()
    gearIcon:SetVertexColor(1, 1, 1)
end)
gearBtn:SetScript("OnLeave", function()
    gearIcon:SetVertexColor(0.6, 0.6, 0.6)
end)

-- Minimize button (normal mode → quiet mode)
local minimizeBtn = CreateFrame("Button", nil, titleBar)
minimizeBtn:SetSize(20, 16)
minimizeBtn:SetPoint("RIGHT", gearBtn, "LEFT", -4, 0)
local minimizeText = minimizeBtn:CreateFontString(nil, "OVERLAY")
minimizeText:SetAllPoints()
minimizeText:SetFont(NEMO_FONT, 13, "OUTLINE")
minimizeText:SetText("[–]")
minimizeText:SetTextColor(0.5, 0.5, 0.5)
minimizeBtn:SetScript("OnEnter", function() minimizeText:SetTextColor(1, 1, 1) end)
minimizeBtn:SetScript("OnLeave", function() minimizeText:SetTextColor(0.5, 0.5, 0.5) end)

-- Restore button (quiet mode → normal mode), parented to titleBar
local restoreBtn = CreateFrame("Button", nil, titleBar)
restoreBtn:SetSize(20, 16)
local restoreText = restoreBtn:CreateFontString(nil, "OVERLAY")
restoreText:SetAllPoints()
restoreText:SetFont(NEMO_FONT, 13, "OUTLINE")
restoreText:SetText("[+]")
restoreText:SetTextColor(0.5, 0.5, 0.5)
restoreBtn:SetScript("OnEnter", function() restoreText:SetTextColor(1, 1, 1) end)
restoreBtn:SetScript("OnLeave", function() restoreText:SetTextColor(0.5, 0.5, 0.5) end)
restoreBtn:Hide()

local sep = frame:CreateTexture(nil, "ARTWORK")
sep:SetHeight(1)
sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -54)
sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -54)
sep:SetColorTexture(0.15, 0.25, 0.45, 0.4)

---------------------------------------------------------------------------
-- SCROLL FRAME
---------------------------------------------------------------------------

local scrollFrame = CreateFrame("ScrollFrame", "NemoScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -56)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

-- Style the scrollbar to be less obtrusive
local scrollBar = NemoScrollFrameScrollBar
if scrollBar then
    scrollBar:Hide()
    scrollBar.Show = function() end -- Override show so nothing can bring it back
end

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(240, 1)
scrollFrame:SetScrollChild(content)

frame:SetScript("OnSizeChanged", function(self, width, height)
    content:SetWidth(width - 12)
end)

---------------------------------------------------------------------------
-- RESIZE HANDLE
---------------------------------------------------------------------------

local resizer = CreateFrame("Button", nil, frame)
resizer:SetSize(16, 16)
resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

local resizeIcon = resizer:CreateTexture(nil, "ARTWORK")
resizeIcon:SetAllPoints()
resizeIcon:SetTexture("Interface\\AddOns\\Nemo\\Textures\\resize")
resizeIcon:SetVertexColor(0.4, 0.4, 0.4)

resizer:SetScript("OnMouseDown", function()
    if not settings.locked then
        frame:StartSizing("BOTTOMRIGHT")
    end
end)
resizer:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    settings.frameWidth = frame:GetWidth()
    settings.frameHeight = frame:GetHeight()
end)

---------------------------------------------------------------------------
-- FOOTER STATS
---------------------------------------------------------------------------
local footerFrame = CreateFrame("Frame", nil, frame)
footerFrame:SetHeight(34)
footerFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
footerFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

footerBg = footerFrame:CreateTexture(nil, "BACKGROUND")
footerBg:SetAllPoints()
footerBg:SetColorTexture(0, 0, 0, 0)

local footerSep = footerFrame:CreateTexture(nil, "ARTWORK")
footerSep:SetHeight(1)
footerSep:SetPoint("TOPLEFT", footerFrame, "TOPLEFT", 6, 0)
footerSep:SetPoint("TOPRIGHT", footerFrame, "TOPRIGHT", -6, 0)
footerSep:SetColorTexture(0.15, 0.25, 0.45, 0.4)

-- Session stats
sessionText = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 22)
sessionText:SetTextColor(0.45, 0.45, 0.45)
sessionText:SetFont(NEMO_FONT, 12, "")

-- Total Fishing Time
totalFishingTimeText = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totalFishingTimeText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 8)
totalFishingTimeText:SetTextColor(0.45, 0.45, 0.45)
totalFishingTimeText:SetFont(NEMO_FONT, 12, "")

---------------------------------------------------------------------------
-- ROW RENDERING
---------------------------------------------------------------------------

local rowPool = {}

local function GetRow(index)
    if rowPool[index] then
        rowPool[index]:Show()
        return rowPool[index]
    end

    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 28))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.04)
    row.highlight:Hide()
    row.itemName = nil
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.itemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemId then
                GameTooltip:SetItemByID(self.itemId)
            elseif self.currencyId then
                GameTooltip:SetCurrencyByID(self.currencyId) --[[@as any]]
            else
                -- Fallback for old data without stored IDs
                GameTooltip:SetText(self.itemName)
                local _, link = C_Item.GetItemInfo(self.itemName)
                if link then
                    GameTooltip:SetHyperlink(link)
                end
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetFont(GetFont(), 14, "")

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetFont(GetFont(), 13, "")

    rowPool[index] = row
    return row
end

local function HideAllRows()
    for _, row in ipairs(rowPool) do row:Hide() end
end

ApplyFont = function()
    local font = GetFont()
    titleText:SetFont(font, 17, "")
    zoneText:SetFont(font, 13, "")
    zoneTotalCount:SetFont(font, 12, "")
    minimizeText:SetFont(font, 13, "OUTLINE")
    restoreText:SetFont(font, 13, "OUTLINE")
    sessionText:SetFont(font, 12, "")
    totalFishingTimeText:SetFont(font, 12, "")
    for _, row in ipairs(rowPool) do
        row.name:SetFont(font, 14, "")
        row.count:SetFont(font, 13, "")
    end
end

---------------------------------------------------------------------------
-- DISPLAY LOGIC
---------------------------------------------------------------------------

local function GetCurrentZoneCatches()
    local mapId = GetCurrentMapId()
    if not mapId then return {} end
    local zoneData = NemoDB.catches and NemoDB.catches[mapId]
    if not zoneData then return {} end

    local sorted = {}
    for itemName, data in pairs(zoneData) do
        table.insert(sorted, {
            name = itemName, count = data.count or 0,
            icon = data.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            quality = data.quality or 1,
            itemId = data.itemId,
            currencyId = data.currencyId,
            lastCaught = data.lastCaught or 0,
        })
    end

    if settings.sortMode == "recent" then
        table.sort(sorted, function(a, b)
            if a.lastCaught ~= b.lastCaught then return a.lastCaught > b.lastCaught end
            return a.name < b.name
        end)
    else
        table.sort(sorted, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
    end

    return sorted
end

local function RefreshDisplay()
    HideAllRows()

    local zoneName = GetCurrentZoneName()
    local r, g, b = GetAccent()

    topStripe:Hide()

    titleText:SetTextColor(r, g, b)
    fishIcon:SetVertexColor(r, g, b)
    zoneText:SetText(zoneName)
    zoneText:SetTextColor(r, g, b)

    local catches = GetCurrentZoneCatches()

    local total = 0
    local unique = #catches
    for _, c in ipairs(catches) do total = total + c.count end

    if quietMode then
        -- Hide everything except the title bar
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        scrollFrame:Hide()
        sep:Hide()
        resizer:Hide()
        footerFrame:Hide()
        titleText:Hide()
        gearBtn:Hide()
        closeBtn:Hide()
        minimizeBtn:Hide()

        -- Restyle title bar for compact mode
        titleBg:SetColorTexture(0.08, 0.08, 0.12, 0.92)
        fishIcon:SetVertexColor(r, g, b)
        fishIcon:SetAlpha(1.0)

        -- Re-parent text onto titleBar so it draws above titleBg
        zoneText:SetParent(titleBar)
        zoneText:ClearAllPoints()
        zoneText:SetPoint("LEFT", fishIcon, "RIGHT", 6, 0)
        zoneText:SetText(zoneName)
        zoneText:SetTextColor(r, g, b)
        zoneText:Show()

        -- Catch total on the right side of title bar
        zoneTotalCount:SetParent(titleBar)
        zoneTotalCount:ClearAllPoints()
        zoneTotalCount:SetPoint("RIGHT", restoreBtn, "LEFT", -6, 0)
        zoneTotalCount:SetText(FormatNumber(total) .. " caught")
        zoneTotalCount:SetTextColor(1, 1, 1)
        zoneTotalCount:Show()

        -- Show restore [+] button at the right edge of the bar
        restoreBtn:ClearAllPoints()
        restoreBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
        restoreBtn:Show()
    else
        -- Restore normal layout
        frame:SetHeight(settings.frameHeight)
        frame:SetBackdropColor(0.03, 0.06, 0.14, settings.opacity)
        frame:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.8)
        scrollFrame:Show()
        sep:Show()
        footerFrame:Show()
        titleText:Show()
        gearBtn:Show()
        closeBtn:Show()
        minimizeBtn:Show()
        restoreBtn:Hide()
        titleBg:SetColorTexture(0, 0, 0, 0)
        fishIcon:SetAlpha(1.0)

        -- Restore text back to main frame
        zoneText:SetParent(frame)
        zoneText:ClearAllPoints()
        zoneText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -4)

        zoneTotalCount:SetParent(frame)
        zoneTotalCount:ClearAllPoints()
        zoneTotalCount:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
        zoneTotalCount:SetPoint("TOP", titleBar, "BOTTOM", 0, -4)

        if #catches == 0 then
            local row = GetRow(1)
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
            row.name:SetText("No catches here yet...")
            row.name:SetTextColor(0.4, 0.4, 0.4)
            row.count:SetText("")
            row.itemName = nil
            content:SetHeight(28)
        else
            for i, catch in ipairs(catches) do
                local row = GetRow(i)
                row.icon:SetTexture(catch.icon)
                row.name:SetText(catch.name)
                row.itemName = catch.name
                row.itemId = catch.itemId
                row.currencyId = catch.currencyId

                local color = QUALITY_COLORS[catch.quality] or QUALITY_COLORS[1]
                row.name:SetTextColor(color[1], color[2], color[3])

                row.count:SetText(FormatNumber(catch.count))
                row.count:SetTextColor(1, 1, 1, 0.9)
            end
            content:SetHeight(#catches * 28)
        end
    end

    if not quietMode and settings.showTotal then
        zoneTotalCount:SetText(FormatNumber(total) .. " caught · " .. FormatNumber(unique) .. " unique")
        zoneTotalCount:SetTextColor(0.5, 0.5, 0.5)
    end

    if not quietMode then
        UpdateTimerText()
    end
end

frame.RefreshDisplay = RefreshDisplay

local function ToggleQuietMode()
    quietMode = not quietMode
    local r, g, b = GetAccent()
    local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    if quietMode then
        if silentMode then
            silentMode = false
            wipe(silentCatches)
        end
        if not quietModeSavedHeight then
            quietModeSavedHeight = settings.frameHeight
        end
        frame:SetHeight(32)
        RefreshDisplay()
        if not frame:IsShown() then frame:Show() end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF" .. hex .. "Nemo|r: Quiet mode |cFF00FF00enabled|r. Showing compact view.")
    else
        frame:SetHeight(quietModeSavedHeight or settings.frameHeight)
        quietModeSavedHeight = nil
        resizer:SetShown(not settings.locked)
        RefreshDisplay()
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF" .. hex .. "Nemo|r: Quiet mode |cFFFF4444disabled|r. Full view restored.")
    end
end

minimizeBtn:SetScript("OnClick", ToggleQuietMode)
restoreBtn:SetScript("OnClick", ToggleQuietMode)

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

local settingsFrame = CreateFrame("Frame", "NemoSettingsFrame", UIParent, "BackdropTemplate")
settingsFrame:SetSize(300, 340)
settingsFrame:SetPoint("CENTER")
settingsFrame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
settingsFrame:SetBackdropColor(0.03, 0.06, 0.14, 0.96)
settingsFrame:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.8)
settingsFrame:SetMovable(true)
settingsFrame:EnableMouse(true)
settingsFrame:RegisterForDrag("LeftButton")
settingsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
settingsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
settingsFrame:SetFrameStrata("DIALOG")
settingsFrame:Hide()

local sTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sTitle:SetPoint("TOPLEFT", 12, -10)
sTitle:SetText("Nemo Settings")

local sClose = CreateFrame("Button", nil, settingsFrame)
sClose:SetSize(16, 16)
sClose:SetPoint("TOPRIGHT", -8, -8)
sClose:SetNormalFontObject("GameFontNormalSmall")
sClose:SetText("x")
sClose:GetFontString():SetTextColor(0.5, 0.5, 0.5)
sClose:SetScript("OnClick", function() settingsFrame:Hide() end)

local function CreateSlider(parent, label, min, max, step, yOffset, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(260, 40)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetTextColor(0.8, 0.8, 0.8)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -14)
    slider:SetSize(240, 14)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")

    local function UpdateLabel()
        local val = slider:GetValue()
        text:SetText(label .. ": " .. string.format("%.0f%%", val * 100))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        setter(value)
        UpdateLabel()
        ApplyFrameStyle()
        RefreshDisplay()
    end)

    slider.getter = getter
    slider.UpdateLabel = UpdateLabel

    return slider
end

local opacitySlider = CreateSlider(settingsFrame, "Background Opacity",
    0.2, 1.0, 0.05, -36,
    function() return settings.opacity end,
    function(v) settings.opacity = v end
)

local scaleSlider = CreateSlider(settingsFrame, "Frame Scale",
    0.6, 1.5, 0.05, -86,
    function() return settings.scale end,
    function(v) settings.scale = v end
)

local colorLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
colorLabel:SetPoint("TOPLEFT", 16, -226)
colorLabel:SetText("Accent Color")
colorLabel:SetTextColor(0.8, 0.8, 0.8)

for i, preset in ipairs(COLOR_PRESETS) do
    local btn = CreateFrame("Button", nil, settingsFrame)
    local col = math.floor((i - 1) % 4)
    local row = math.floor((i - 1) / 4)
    btn:SetSize(52, 24)
    btn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT",
        16 + (col * 62), -242 - (row * 30))

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(preset.color[1], preset.color[2], preset.color[3], 0.8)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("CENTER")
    btnText:SetText(preset.name)
    btnText:SetTextColor(0, 0, 0)
    btnText:SetShadowOffset(0, 0)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(1, 1, 1, 0.3)
    border:Hide()

    btn:SetScript("OnEnter", function() border:Show() end)
    btn:SetScript("OnLeave", function() border:Hide() end)
    btn:SetScript("OnClick", function()
        settings.accentColor = { preset.color[1], preset.color[2], preset.color[3] }
        ApplyFrameStyle()
        RefreshDisplay()
        local r, g, b = GetAccent()
        sTitle:SetTextColor(r, g, b)
    end)
end

local lockCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
lockCheck:SetSize(24, 24)
lockCheck:SetPoint("TOPLEFT", 12, -310)
lockCheck.text:SetText(" Lock frame position")
lockCheck.text:SetFontObject("GameFontNormalSmall")
lockCheck.text:SetTextColor(0.8, 0.8, 0.8)
lockCheck:SetScript("OnClick", function(self)
    settings.locked = self:GetChecked()
    resizer:SetShown(not settings.locked)
end)

local totalCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
totalCheck:SetSize(24, 24)
totalCheck:SetPoint("TOPLEFT", 12, -336)
totalCheck.text:SetText(" Show catch totals")
totalCheck.text:SetFontObject("GameFontNormalSmall")
totalCheck.text:SetTextColor(0.8, 0.8, 0.8)
totalCheck:SetScript("OnClick", function(self)
    settings.showTotal = self:GetChecked()
    RefreshDisplay()
end)

local autoShowCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
autoShowCheck:SetSize(24, 24)
autoShowCheck:SetPoint("TOPLEFT", 12, -362)
autoShowCheck.text:SetText(" Auto-show when fishing")
autoShowCheck.text:SetFontObject("GameFontNormalSmall")
autoShowCheck.text:SetTextColor(0.8, 0.8, 0.8)
autoShowCheck:SetScript("OnClick", function(self)
    settings.autoShow = self:GetChecked()
end)

local autoHideCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
autoHideCheck:SetSize(24, 24)
autoHideCheck:SetPoint("TOPLEFT", 12, -388)
autoHideCheck.text:SetText(" Auto-hide after idle / on combat")
autoHideCheck.text:SetFontObject("GameFontNormalSmall")
autoHideCheck.text:SetTextColor(0.8, 0.8, 0.8)

-- Hide delay slider (nested under auto-hide)
local hideDelayContainer = CreateFrame("Frame", nil, settingsFrame)
hideDelayContainer:SetSize(240, 40)
hideDelayContainer:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 36, -412)

local hideDelayLabel = hideDelayContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hideDelayLabel:SetPoint("TOPLEFT", 0, 0)
hideDelayLabel:SetTextColor(0.6, 0.6, 0.6)

local hideDelaySlider = CreateFrame("Slider", nil, hideDelayContainer, "OptionsSliderTemplate")
hideDelaySlider:SetPoint("TOPLEFT", 0, -14)
hideDelaySlider:SetSize(220, 14)
hideDelaySlider:SetMinMaxValues(25, 120)
hideDelaySlider:SetValueStep(5)
hideDelaySlider:SetObeyStepOnDrag(true)
hideDelaySlider.Low:SetText("")
hideDelaySlider.High:SetText("")

local function UpdateHideDelayLabel()
    hideDelayLabel:SetText("Auto-hide delay: " .. string.format("%.0fs", hideDelaySlider:GetValue()))
end

hideDelaySlider:SetScript("OnValueChanged", function(self, value)
    settings.hideDelay = value
    UpdateHideDelayLabel()
end)

-- Font selector
local fontLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fontLabel:SetPoint("TOPLEFT", 16, -136)
fontLabel:SetText("Font")
fontLabel:SetTextColor(0.8, 0.8, 0.8)

local fontButton = CreateFrame("Button", nil, settingsFrame, "BackdropTemplate")
fontButton:SetSize(260, 22)
fontButton:SetPoint("TOPLEFT", 16, -152)
fontButton:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
fontButton:SetBackdropColor(0.1, 0.1, 0.15, 1)
fontButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

local fontButtonText = fontButton:CreateFontString(nil, "OVERLAY")
fontButtonText:SetPoint("LEFT", 8, 0)
fontButtonText:SetFont(NEMO_FONT, 12, "")
fontButtonText:SetTextColor(0.9, 0.9, 0.9)
fontButtonText:SetText("Friz Quadrata")

local fontButtonArrow = fontButton:CreateFontString(nil, "OVERLAY")
fontButtonArrow:SetPoint("RIGHT", -8, 0)
fontButtonArrow:SetFont(NEMO_FONT, 11, "")
fontButtonArrow:SetText("v")
fontButtonArrow:SetTextColor(0.5, 0.5, 0.5)

fontButton:SetScript("OnEnter", function()
    fontButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
end)
fontButton:SetScript("OnLeave", function()
    fontButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
end)

-- Font dropdown catcher (click-outside-to-close)
local fontDropdownCatcher = CreateFrame("Button", nil, UIParent)
fontDropdownCatcher:SetAllPoints(UIParent)
fontDropdownCatcher:SetFrameStrata("DIALOG")
fontDropdownCatcher:Hide()
fontDropdownCatcher:SetScript("OnClick", function()
    fontDropdownCatcher:Hide()
end)

-- Font dropdown list
local fontDropdown = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
fontDropdown:SetSize(260, 200)
fontDropdown:SetPoint("TOPLEFT", fontButton, "BOTTOMLEFT", 0, -2)
fontDropdown:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
fontDropdown:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
fontDropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
fontDropdown:SetClipsChildren(true)
fontDropdown:Hide()

-- Ensure dropdown draws above settingsFrame
fontDropdown:SetScript("OnShow", function(self)
    self:SetFrameLevel(settingsFrame:GetFrameLevel() + 10)
end)

local fontScrollOffset = 0
local fontRowPool = {}
local FONT_ROW_HEIGHT = 22
local FONT_VISIBLE_ROWS = 9

local function RenderFontDropdown()
    local fonts = LSM:List("font")
    local maxOffset = math.max(0, #fonts - FONT_VISIBLE_ROWS)
    if fontScrollOffset > maxOffset then fontScrollOffset = maxOffset end
    if fontScrollOffset < 0 then fontScrollOffset = 0 end

    for i = 1, FONT_VISIBLE_ROWS do
        local fontIndex = i + fontScrollOffset
        local fontName = fonts[fontIndex]

        if not fontRowPool[i] then
            local row = CreateFrame("Button", nil, fontDropdown)
            row:SetHeight(FONT_ROW_HEIGHT)
            row:SetPoint("TOPLEFT", fontDropdown, "TOPLEFT", 2, -((i - 1) * FONT_ROW_HEIGHT) - 2)
            row:SetPoint("RIGHT", fontDropdown, "RIGHT", -2, 0)

            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints()
            row.highlight:SetColorTexture(1, 1, 1, 0.06)
            row.highlight:Hide()

            row.label = row:CreateFontString(nil, "OVERLAY")
            row.label:SetPoint("LEFT", 8, 0)
            row.label:SetPoint("RIGHT", -8, 0)
            row.label:SetJustifyH("LEFT")

            row:SetScript("OnEnter", function(self) self.highlight:Show() end)
            row:SetScript("OnLeave", function(self) self.highlight:Hide() end)

            fontRowPool[i] = row
        end

        local row = fontRowPool[i]
        if fontName then
            local fontPath = LSM:Fetch("font", fontName)
            if not pcall(row.label.SetFont, row.label, fontPath, 13, "") then
                row.label:SetFont(NEMO_FONT, 13, "")
            end
            row.label:SetText(fontName)

            if fontName == settings.fontKey then
                local r, g, b = GetAccent()
                row.label:SetTextColor(r, g, b)
            else
                row.label:SetTextColor(0.85, 0.85, 0.85)
            end

            row:SetScript("OnClick", function()
                settings.fontKey = fontName
                ApplyFont()
                fontButtonText:SetText(fontName)
                fontButtonText:SetFont(GetFont(), 12, "")
                fontDropdown:Hide()
                fontDropdownCatcher:Hide()
                RenderFontDropdown()
            end)
            row:Show()
        else
            row:Hide()
        end
    end
end

fontDropdown:SetScript("OnMouseWheel", function(self, delta)
    fontScrollOffset = fontScrollOffset - (delta * 3)
    RenderFontDropdown()
end)

fontButton:SetScript("OnClick", function()
    if fontDropdown:IsShown() then
        fontDropdown:Hide()
        fontDropdownCatcher:Hide()
    else
        fontScrollOffset = 0
        -- Scroll to current font so it's visible
        local fonts = LSM:List("font")
        for i, name in ipairs(fonts) do
            if name == settings.fontKey then
                fontScrollOffset = math.max(0, i - math.floor(FONT_VISIBLE_ROWS / 2))
                break
            end
        end
        fontDropdownCatcher:Show()
        fontDropdownCatcher:SetFrameLevel(settingsFrame:GetFrameLevel() + 5)
        fontDropdown:Show()
        RenderFontDropdown()
    end
end)

-- Close dropdown when catcher is clicked
fontDropdownCatcher:SetScript("OnClick", function()
    fontDropdown:Hide()
    fontDropdownCatcher:Hide()
end)

-- Sort by dropdown
local SORT_OPTIONS = {
    { key = "count",  label = "Most Caught" },
    { key = "recent", label = "Most Recent" },
}

local SORT_LABELS = {}
for _, opt in ipairs(SORT_OPTIONS) do SORT_LABELS[opt.key] = opt.label end

local sortLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sortLabel:SetPoint("TOPLEFT", 16, -180)
sortLabel:SetText("Sort by")
sortLabel:SetTextColor(0.8, 0.8, 0.8)

local sortButton = CreateFrame("Button", nil, settingsFrame, "BackdropTemplate")
sortButton:SetSize(260, 22)
sortButton:SetPoint("TOPLEFT", 16, -196)
sortButton:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
sortButton:SetBackdropColor(0.1, 0.1, 0.15, 1)
sortButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

local sortButtonText = sortButton:CreateFontString(nil, "OVERLAY")
sortButtonText:SetPoint("LEFT", 8, 0)
sortButtonText:SetFont(NEMO_FONT, 12, "")
sortButtonText:SetTextColor(0.9, 0.9, 0.9)
sortButtonText:SetText("Most Caught")

local sortButtonArrow = sortButton:CreateFontString(nil, "OVERLAY")
sortButtonArrow:SetPoint("RIGHT", -8, 0)
sortButtonArrow:SetFont(NEMO_FONT, 11, "")
sortButtonArrow:SetText("v")
sortButtonArrow:SetTextColor(0.5, 0.5, 0.5)

sortButton:SetScript("OnEnter", function()
    sortButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
end)
sortButton:SetScript("OnLeave", function()
    sortButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
end)

local sortDropdownCatcher = CreateFrame("Button", nil, UIParent)
sortDropdownCatcher:SetAllPoints(UIParent)
sortDropdownCatcher:SetFrameStrata("DIALOG")
sortDropdownCatcher:Hide()

local sortDropdown = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
sortDropdown:SetSize(260, #SORT_OPTIONS * 22 + 4)
sortDropdown:SetPoint("TOPLEFT", sortButton, "BOTTOMLEFT", 0, -2)
sortDropdown:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
sortDropdown:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
sortDropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
sortDropdown:Hide()

sortDropdown:SetScript("OnShow", function(self)
    self:SetFrameLevel(settingsFrame:GetFrameLevel() + 10)
end)

for i, opt in ipairs(SORT_OPTIONS) do
    local row = CreateFrame("Button", nil, sortDropdown)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", sortDropdown, "TOPLEFT", 2, -((i - 1) * 22) - 2)
    row:SetPoint("RIGHT", sortDropdown, "RIGHT", -2, 0)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:Hide()

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", 8, 0)
    label:SetFont(NEMO_FONT, 13, "")
    label:SetText(opt.label)

    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)

    row:SetScript("OnShow", function()
        local r, g, b = GetAccent()
        if settings.sortMode == opt.key then
            label:SetTextColor(r, g, b)
        else
            label:SetTextColor(0.85, 0.85, 0.85)
        end
    end)

    row:SetScript("OnClick", function()
        settings.sortMode = opt.key
        sortButtonText:SetText(opt.label)
        sortDropdown:Hide()
        sortDropdownCatcher:Hide()
        if frame:IsShown() then RefreshDisplay() end
    end)
end

sortButton:SetScript("OnClick", function()
    if sortDropdown:IsShown() then
        sortDropdown:Hide()
        sortDropdownCatcher:Hide()
    else
        sortDropdownCatcher:Show()
        sortDropdownCatcher:SetFrameLevel(settingsFrame:GetFrameLevel() + 5)
        sortDropdown:Show()
    end
end)

sortDropdownCatcher:SetScript("OnClick", function()
    sortDropdown:Hide()
    sortDropdownCatcher:Hide()
end)

settingsFrame:SetScript("OnHide", function()
    fontDropdown:Hide()
    fontDropdownCatcher:Hide()
    sortDropdown:Hide()
    sortDropdownCatcher:Hide()
end)

local function SetHideDelayVisible(show)
    if show then
        hideDelayContainer:Show()
        settingsFrame:SetHeight(466)
    else
        hideDelayContainer:Hide()
        settingsFrame:SetHeight(426)
    end
end

hideDelayContainer:Hide()

autoHideCheck:SetScript("OnClick", function(self)
    settings.autoHide = self:GetChecked()
    SetHideDelayVisible(settings.autoHide)
end)

local function OpenSettings()
    opacitySlider:SetValue(settings.opacity)
    opacitySlider.UpdateLabel()
    scaleSlider:SetValue(settings.scale)
    scaleSlider.UpdateLabel()
    lockCheck:SetChecked(settings.locked)
    totalCheck:SetChecked(settings.showTotal)
    autoShowCheck:SetChecked(settings.autoShow)
    autoHideCheck:SetChecked(settings.autoHide)
    hideDelaySlider:SetValue(settings.hideDelay)
    UpdateHideDelayLabel()
    SetHideDelayVisible(settings.autoHide)
    fontButtonText:SetText(settings.fontKey)
    fontButtonText:SetFont(GetFont(), 12, "")
    fontDropdown:Hide()
    fontDropdownCatcher:Hide()
    sortButtonText:SetText(SORT_LABELS[settings.sortMode] or "Most Caught")
    sortDropdown:Hide()
    sortDropdownCatcher:Hide()
    local r,g,b = GetAccent()
    sTitle:SetTextColor(r,g,b)
    settingsFrame:Show()
end

gearBtn:SetScript("OnClick", function()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
       OpenSettings()
    end
end)

---------------------------------------------------------------------------
-- TOOLTIP CACHING
---------------------------------------------------------------------------
local tooltipCache = {}

local function InvalidateTooltipCache()
    wipe(tooltipCache)
end

---------------------------------------------------------------------------
-- LOOT CAPTURE (Items)
---------------------------------------------------------------------------

local function OnLootMessage(event, msg)
    if not isFishing then return end

    -- If the player is in combat, this loot is from a kill, not fishing.
    if UnitAffectingCombat("player") then return end

    local itemLink = msg:match("|c.-|Hitem:.-|h%[.-%]|h|r")
    if not itemLink then return end

    local itemName = itemLink:match("%[(.-)%]")
    if not itemName then return end
    itemName = itemName:gsub("%s*|A.-|a", "")
    if ITEM_BLACKLIST[itemName] then return end

    -- Check for a stack count (e.g. "x5" at the end)
    local countStr = msg:match("x(%d+)")
    local lootCount = tonumber(countStr) or 1

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    local _, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink)

    local mapId = GetCurrentMapId()
    if not mapId then return end

    if not NemoDB.catches then NemoDB.catches = {} end
    if not NemoDB.catches[mapId] then NemoDB.catches[mapId] = {} end

    if not NemoDB.catches[mapId][itemName] then
        NemoDB.catches[mapId][itemName] = {
            count = 0,
            icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            quality = quality or 1,
        }
    end

    local entry = NemoDB.catches[mapId][itemName]
    entry.count = entry.count + lootCount
    entry.lastCaught = time()
    if isCompressedOcean then
        entry.compressedOceanCount = (entry.compressedOceanCount or 0) + lootCount
    end
    if isAnglersAnomaly then
        entry.anglersAnomalyCount = (entry.anglersAnomalyCount or 0) + lootCount
    end
    if icon then entry.icon = icon end
    if quality then entry.quality = quality end
    if itemId then entry.itemId = itemId end

    session.catches = session.catches + lootCount
    session.unique[itemName] = true
    RecordRecentCatch(itemName, icon or entry.icon, lootCount)

    InvalidateTooltipCache()

    if silentMode then
        silentCatches[itemName] = (silentCatches[itemName] or 0) + lootCount
        FlashMinimapIcon()
    elseif frame:IsShown() then
        RefreshDisplay()
    end
end

---------------------------------------------------------------------------
-- LOOT CAPTURE (Currency)
-- Currency drops (e.g. Shard of Dundun from Voidstorm vortexes) use
-- CHAT_MSG_CURRENCY instead of CHAT_MSG_LOOT, with plain text format:
--   "You receive currency: [Name]x1"
---------------------------------------------------------------------------

local function OnCurrencyMessage(event, msg)
    if not isFishing then return end
    if UnitAffectingCombat("player") then return end

    local currencyName = msg:match("%[(.-)%]")
    if not currencyName then return end
    if ITEM_BLACKLIST[currencyName] then return end

    local currencyIdStr = msg:match("|Hcurrency:(%d+)")
    local icon, quality
    if currencyIdStr then
        local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyIdStr) --[[@as number]])
        if info then
            icon = info.iconFileID
            quality = info.quality or 1
        end
    end

    local countStr = msg:match("x(%d+)")
    local lootCount = tonumber(countStr) or 1

    local mapId = GetCurrentMapId()
    if not mapId then return end

    if not NemoDB.catches then NemoDB.catches = {} end
    if not NemoDB.catches[mapId] then NemoDB.catches[mapId] = {} end

    if not NemoDB.catches[mapId][currencyName] then
        NemoDB.catches[mapId][currencyName] = {
            count = 0,
            icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            quality = quality or 1,
        }
    end

    local entry = NemoDB.catches[mapId][currencyName]
    entry.count = entry.count + lootCount
    entry.lastCaught = time()
    if isCompressedOcean then
        entry.compressedOceanCount = (entry.compressedOceanCount or 0) + lootCount
    end
    if isAnglersAnomaly then
        entry.anglersAnomalyCount = (entry.anglersAnomalyCount or 0) + lootCount
    end
    if icon then entry.icon = icon end
    if quality then entry.quality = quality end
    if currencyIdStr then entry.currencyId = tonumber(currencyIdStr) end

    session.catches = session.catches + lootCount
    session.unique[currencyName] = true
    RecordRecentCatch(currencyName, entry.icon, lootCount)

    InvalidateTooltipCache()

    if silentMode then
        silentCatches[currencyName] = (silentCatches[currencyName] or 0) + lootCount
        FlashMinimapIcon()
    elseif frame:IsShown() then
        RefreshDisplay()
    end
end

---------------------------------------------------------------------------
-- FISHING STATE
---------------------------------------------------------------------------

local function OnFishingDetected()
    isFishing = true
    fishingLootOpen = true

    if not session.fishStart then
        session.fishStart = GetTime()
    end

    if not silentMode and settings.autoShow and not frame:IsShown() then
        RefreshDisplay()
        frame:Show()
    end

    if settings.autoHide then
        hideGeneration = hideGeneration + 1
        local myGeneration = hideGeneration
        C_Timer.After(settings.hideDelay, function()
            if hideGeneration == myGeneration and settings.autoHide then
                -- Pause the fishing timer
                SnapshotFishingTime()
                isFishing = false
                frame:Hide()
            end
        end)
    end
end

local function OnSpellcastSucceeded(event, unit, castGUID, spellId)
    if unit ~= "player" then return end
    if FISHING_SPELLS[spellId] then OnFishingDetected() end
end

---------------------------------------------------------------------------
-- VOIDSTORM VORTEX DETECTION (Voidstorm + Angler's Anomaly)
-- Oceanic Vortexes dont trigger UNIT_SPELLCAST_SUCCEEDED when
-- interacted with, because of course they dont.  They DO, however, use
-- UNIT_SPELLCAST_CHANNEL_START when you start 'fishing' from the vortex.
-- We use this to set a wasVortexChannel flag and then check for it in
-- LOOT_READY (or the vortex's base name [Hyper-Compressed Ocean Target]) to
-- identify vortex catches and set isFishing to true for the loot handlers.
---------------------------------------------------------------------------

local function OnLootReady()
    -- UnitName("target") returns a tainted string during LOOT_READY that cannot be
    -- compared, indexed, or converted. Rely on wasVortexChannel flag instead, which is
    -- set by UNIT_SPELLCAST_CHANNEL_START when "Void Hole Fishing" is detected.
    if wasVortexChannel then
        isFishing = true
        fishingLootOpen = true
        wasVortexChannel = false
        if not session.fishStart then
            session.fishStart = GetTime()
        end
        if not silentMode and settings.autoShow and not frame:IsShown() then
            RefreshDisplay()
            frame:Show()
        end
    end
end

local function OnZoneChanged()
    if frame:IsShown() then RefreshDisplay() end
end

-- Tick the session timer display every second while frame is visible
local tickAccumulator = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    if not session.fishStart then return end  -- Only tick while actively fishing
    tickAccumulator = tickAccumulator + elapsed
    if tickAccumulator >= 1.0 then
        tickAccumulator = 0
        if self:IsShown() then UpdateTimerText() end
    end
end)

---------------------------------------------------------------------------
-- BAG TOOLTIP HOOK
-- When hovering over an item in your bags, if catch data for
-- that item, we inject a section showing which zones you caught it in
-- and how many times, sorted by most to least.
---------------------------------------------------------------------------

local function BuildItemZoneLookup(itemName)
    if tooltipCache[itemName] then return tooltipCache[itemName] end

    local zones = {}

    if not NemoDB.catches then return zones end

    for mapId, zoneData in pairs(NemoDB.catches) do
        if zoneData[itemName] then
            local zoneName = "Unknown"
            local info = C_Map.GetMapInfo(mapId)
            if info then zoneName = info.name end

            local entry = zoneData[itemName]
            local totalCount = entry.count or 0
            local oceanCount = entry.compressedOceanCount or 0
            local anomalyCount = entry.anglersAnomalyCount or 0
            local normalCount = totalCount - oceanCount - anomalyCount

            if oceanCount > 0 then
                table.insert(zones, {
                    name  = zoneName .. " |cFF4CBFF0(Hyper-Compressed Ocean)|r",
                    count = oceanCount,
                })
            end
            if anomalyCount > 0 then
                table.insert(zones, {
                    name  = zoneName .. " |cFF4CBFF0(Angler's Anomaly)|r",
                    count = anomalyCount,
                })
            end
            if normalCount > 0 then
                table.insert(zones, {
                    name  = zoneName,
                    count = normalCount,
                })
            end
        end
    end

    table.sort(zones, function(a, b) return a.count > b.count end)
    tooltipCache[itemName] = zones
    return zones
end

local function OnTooltipSetItem(tooltip, data)
    if not NemoDB.catches then return end

    local itemName
    if tooltip.GetItem then
        local name = tooltip:GetItem()
        itemName = name
    end

    if not itemName then return end

    local zones = BuildItemZoneLookup(itemName)
    if #zones == 0 then return end

    local r, g, b = GetAccent()
    tooltip:AddLine(" ")
    tooltip:AddLine("Nemo - Caught in:", r, g, b)

    for _, zone in ipairs(zones) do
        tooltip:AddDoubleLine(
            "  " .. zone.name,
            FormatNumber(zone.count) .. "x",
            0.7, 0.7, 0.7,
            r, g, b
        )
    end

    local total = 0
    for _, z in ipairs(zones) do total = total + z.count end
    if #zones > 1 then
        tooltip:AddDoubleLine(
            "  Total",
            FormatNumber(total) .. "x",
            0.5, 0.5, 0.5,
            0.5, 0.5, 0.5
        )
    end


    tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(
        Enum.TooltipDataType.Item, OnTooltipSetItem
    )
end

local function ResetAllData() 
    NemoDB.catches = {}
    InvalidateTooltipCache()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF4CBFF0Nemo|r: All catch data wiped.")
    if frame:IsShown() then RefreshDisplay() end
end

StaticPopupDialogs["NEMO_RESET_CONFIRM"] = {
    text = "Are you sure you want to wipe ALL of your catch data? This cannot be undone.",
    button1 = "Yes, wipe it",
    button2 = "No, keep it",
    OnAccept = function()
        ResetAllData()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
}

---------------------------------------------------------------------------
-- MINIMAP BUTTON (LibDBIcon)
---------------------------------------------------------------------------

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local nemoLDB = LDB:NewDataObject("Nemo", {
    type  = "launcher",
    icon  = "Interface\\AddOns\\Nemo\\Textures\\hook",
    label = "Nemo",
    OnClick = function(_, button)
        if button == "LeftButton" then
            if silentMode then
                PrintSessionSummary()
            elseif frame:IsShown() then
                frame:Hide()
            else
                RefreshDisplay()
                frame:Show()
            end
        end
    end,
    OnTooltipShow = function(tooltip)
        local r, g, b = GetAccent()
        tooltip:AddLine("Nemo", r, g, b)

        if #session.recentCatches > 0 then
            tooltip:AddLine(" ")
            tooltip:AddLine("Recent catches:", 0.7, 0.7, 0.7)
            for _, catch in ipairs(session.recentCatches) do
                tooltip:AddDoubleLine(
                    "  " .. catch.name,
                    FormatNumber(catch.count) .. "x",
                    1, 1, 1,
                    0.7, 0.7, 0.7
                )
            end
        else
            tooltip:AddLine("No catches this session", 0.5, 0.5, 0.5)
        end

        tooltip:AddLine(" ")
        if silentMode then
            tooltip:AddLine("Silent mode active", 0.4, 0.8, 0.4)
            tooltip:AddLine("Click to print session stats", 0.5, 0.5, 0.5)
        else
            tooltip:AddLine("Click to toggle window", 0.5, 0.5, 0.5)
        end
    end,
})

local function InitMinimapButton()
    if not NemoDB.minimap then
        NemoDB.minimap = { hide = not settings.showMinimap }
    end
    LDBIcon:Register("Nemo", nemoLDB, NemoDB.minimap)

    local btn = LDBIcon:GetMinimapButton("Nemo")
    if btn and btn.icon then
        -- Always set the minimap icon to gold, regardless of accent color chosen
        btn.icon:SetVertexColor(0.86, 0.71, 0.19)
    end
end

FlashMinimapIcon = function()
    local btn = LDBIcon:GetMinimapButton("Nemo")
    if not btn or not btn.icon then return end

    local icon = btn.icon
    local flashes = 0
    local maxFlashes = 3
    local elapsed = 0
    local bright = true

    btn:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 then
            elapsed = 0
            if bright then
                icon:SetVertexColor(1, 1, 1)
                bright = false
            else
                icon:SetVertexColor(0.86, 0.71, 0.19)
                bright = true
                flashes = flashes + 1
            end
            if flashes >= maxFlashes then
                icon:SetVertexColor(0.86, 0.71, 0.19)
                self:SetScript("OnUpdate", nil)
            end
        end
    end)
end

PrintSessionSummary = function()
    local r, g, b = GetAccent()
    local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

    -- Count silent mode catches
    local silentTotal = 0
    local sorted = {}
    for name, count in pairs(silentCatches) do
        silentTotal = silentTotal + count
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(x, y) return x.count > y.count end)

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cFF%sNemo|r: Silent mode - %s caught since enabled.",
        hex, FormatNumber(silentTotal)))

    for _, catch in ipairs(sorted) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cFF%s·|r %s x%s", hex, catch.name, FormatNumber(catch.count)))
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cFF888888Type /nemo silent to disable silent mode.|r")
end

---------------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "Nemo" then
            if not NemoDB.catches and not NemoDB.settings then
                local oldData = {}
                local hadData = false
                local zoneCount = 0
                for k, v in pairs(NemoDB) do
                    if type(k) == "number" and type(v) == "table" then
                        oldData[k] = v
                        hadData = true
                        zoneCount = zoneCount + 1
                    end
                end
                if hadData then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cFF4CBFF0Nemo|r: Migrating v1 data (" .. zoneCount .. " zones)...")
                    wipe(NemoDB)
                    NemoDB.catches = oldData
                    NemoDB.settings = {}
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cFF4CBFF0Nemo|r: Migration complete.")
                end
            end

            if not NemoDB.catches  then NemoDB.catches  = {} end
            if not NemoDB.settings then NemoDB.settings = {} end

            FillDefaults(NemoDB.settings, DEFAULT_SETTINGS)
            local DEPRECATED_KEYS = {
                "alertAnchorY", "alertAnchorX", "alertAnchorPoint", "alertLocked"
            }
            for _, key in ipairs(DEPRECATED_KEYS) do
                NemoDB.settings[key] = nil
            end

            for mapId, zoneData in pairs(NemoDB.catches) do
                local renames = {} -- {oldKey, cleanKey } pairs to process
                for itemName, data in pairs(zoneData) do
                    local clean = itemName:gsub("%s*|A.-|a", "")
                    if clean ~= itemName then
                        table.insert(renames, {old = itemName, clean = clean, data = data})
                    end
                end
                for _, rename in ipairs(renames) do
                    if zoneData[rename.clean] then
                        zoneData[rename.clean].count = zoneData[rename.clean].count + rename.data.count
                    else
                        zoneData[rename.clean] = rename.data
                    end
                    zoneData[rename.old] = nil
                end
            end
            settings = NemoDB.settings

            ApplyFrameStyle()
            ApplyFont()
            resizer:SetShown(not settings.locked)

            if settings.anchorPoint then
                frame:ClearAllPoints()
                frame:SetPoint(settings.anchorPoint, UIParent, settings.anchorPoint,
                    settings.anchorX or 0, settings.anchorY or 0)
            else
                frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
            end

            InitMinimapButton()

            local zoneCount = 0
            for _ in pairs(NemoDB.catches) do zoneCount = zoneCount + 1 end

            local r, g, b = GetAccent()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFF%02x%02x%02xNemo|r: Loaded. %d zones tracked. /nemo to toggle.",
                r * 255, g * 255, b * 255, zoneCount))
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellcastSucceeded(event, ...)

    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(event, ...)

    elseif event == "CHAT_MSG_CURRENCY" then
        OnCurrencyMessage(event, ...)

    elseif event == "LOOT_READY" then
        OnLootReady()

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        OnZoneChanged()
    elseif event == "LOOT_CLOSED" then
        if fishingLootOpen then
            C_Timer.After(0.1, function()
                isFishing = false
                fishingLootOpen = false
                isCompressedOcean = false
                isAnglersAnomaly = false
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
            SnapshotFishingTime()
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        if unit == "player" then
            local name = UnitChannelInfo("player")
            if name == "Void Hole Fishing" or name == "Compressed Ocean Fishing" then
                wasVortexChannel = true
                isCompressedOcean = (name == "Compressed Ocean Fishing")
                if name == "Void Hole Fishing" then
                    local mapId = C_Map.GetBestMapForUnit("player")
                    isAnglersAnomaly = (mapId ~= VOIDSTORM_MAP_ID)
                end
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SnapshotFishingTime()
        if settings.autoHide then
            isFishing = false
            frame:Hide()
        end
    end
end)

---------------------------------------------------------------------------
-- SLASH COMMANDS
---------------------------------------------------------------------------

SLASH_NEMO1 = "/nemo"

SlashCmdList["NEMO"] = function(input)
    local cmd = strlower(strtrim(input or ""))

    if cmd == "settings" or cmd == "config" or cmd == "options" then
        if settingsFrame:IsShown() then
            settingsFrame:Hide()
        else
            OpenSettings()
        end

    elseif cmd == "reset" then
        StaticPopup_Show("NEMO_RESET_CONFIRM")
    elseif cmd == "zone" then
        local mapId = GetCurrentMapId()
        local name = GetCurrentZoneName()
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cFF4CBFF0Nemo|r: %s (mapId: %s)", name, tostring(mapId)))

    elseif strsub(cmd, 1, 6) == "remove" then
        local itemName = strtrim(strsub(input, 8))

        if itemName == "" then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF4CBFF0Nemo|r: Usage: /nemo remove Item Name Here")
            return
        end

        local removed = 0
        if NemoDB.catches then
            for mapId, zoneData in pairs(NemoDB.catches) do
                if zoneData[itemName] then
                    zoneData[itemName] = nil
                    removed = removed + 1
                end
            end
        end

        if removed > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFF4CBFF0Nemo|r: Removed \"%s\" from %d zone(s).", itemName, removed))
            InvalidateTooltipCache()
            if frame:IsShown() then RefreshDisplay() end
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFF4CBFF0Nemo|r: \"%s\" not found in any zone. (Name is case-sensitive!)", itemName))
        end

    elseif cmd == "silent" then
        silentMode = not silentMode
        local r, g, b = GetAccent()
        local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
        if silentMode then
            if quietMode then
                quietMode = false
                frame:SetHeight(quietModeSavedHeight or settings.frameHeight)
                quietModeSavedHeight = nil
                resizer:SetShown(not settings.locked)
                RefreshDisplay()
            end
            wipe(silentCatches)
            frame:Hide()
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF" .. hex .. "Nemo|r: Silent mode |cFF00FF00enabled|r. Window hidden, minimap icon will flash on catches.")
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF" .. hex .. "Nemo|r: Silent mode |cFFFF4444disabled|r. Normal mode restored.")
        end

    elseif cmd == "quiet" then
        ToggleQuietMode()

    elseif cmd == "session" then
        local timeStr = FormatFishingTime(GetTotalFishingTime())
        local sessionUnique = 0
        for _ in pairs(session.unique) do sessionUnique = sessionUnique + 1 end

        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cFF4CBFF0Nemo|r: Session - %s caught, %s unique, %s fishing",
            FormatNumber(session.catches), FormatNumber(sessionUnique), timeStr))

    else
        if silentMode then
            PrintSessionSummary()
        elseif frame:IsShown() then
            frame:Hide()
        else
            RefreshDisplay()
            frame:Show()
        end
    end
end