--[[
    Nemo.lua v1.0
    
    SLASH COMMANDS:
    /nemo            Toggle the frame
    /nemo settings   Open settings panel
    /nemo reset      Wipe all catch data
    /nemo zone       Show current zone info
    /nemo session    Show session stats
    /nemo remove X   Remove item X from all zones
]]

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
    accentColor    = { 0.30, 0.75, 0.95 },
    showTotal      = true,
    autoShow       = true,
    autoHide       = true,
    hideDelay      = 45,
    -- Saved position (nil = use default)
    anchorPoint    = nil,
    anchorX        = nil,
    anchorY        = nil,
}

-- Accent color presets for the picker
local COLOR_PRESETS = {
    { name = "Ocean",    color = { 0.30, 0.75, 0.95 } },
    { name = "Ember",    color = { 0.95, 0.45, 0.25 } },
    { name = "Jade",     color = { 0.30, 0.85, 0.55 } },
    { name = "Violet",   color = { 0.65, 0.40, 0.95 } },
    { name = "Gold",     color = { 0.94, 0.76, 0.20 } },
    { name = "Rose",     color = { 0.92, 0.45, 0.60 } },
    { name = "Frost",    color = { 0.70, 0.88, 0.95 } },
    { name = "Blood",    color = { 0.85, 0.15, 0.20 } },
}

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

-- Voidstorm map ID used for vortex fishing detection
local VOIDSTORM_MAP_ID = 2405

-- The fishable vortex NPC name (used for LOOT_READY target filtering)
local VORTEX_TARGET_NAME = "Hyper-Compressed Ocean"

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local isFishing = false
local hideGeneration = 0
local settings

-- Session tracking (resets each login)
local session = {
    catches    = 0,       -- Total items caught this session
    unique     = {},      -- Set of unique item names caught this session
    fishStart  = nil,     -- GetTime() when current fishing bout started
    totalTime  = 0,       -- Accumulated fishing time in seconds
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

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------

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
    if not settings then return 0.30, 0.75, 0.95 end
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

local function ApplyFrameStyle()
    local r, g, b = GetAccent()

    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    frame:SetBackdropColor(0.06, 0.06, 0.10, settings.opacity)
    frame:SetBackdropBorderColor(r, g, b, 0.4)
    frame:SetScale(settings.scale)
    frame:SetSize(settings.frameWidth, settings.frameHeight)
end

local topStripe = frame:CreateTexture(nil, "OVERLAY")
topStripe:SetHeight(2)
topStripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
topStripe:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
topStripe:SetColorTexture(0.3, 0.75, 0.95, 0.8)

---------------------------------------------------------------------------
-- TITLE BAR
---------------------------------------------------------------------------

local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetHeight(28)
titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
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

local fishIcon = titleBar:CreateTexture(nil, "ARTWORK")
fishIcon:SetSize(16, 16)
fishIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
fishIcon:SetTexture("Interface\\Icons\\INV_Fishingpole_02")
fishIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Trim icon borders

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", fishIcon, "RIGHT", 6, 0)
titleText:SetText("Nemo")

local zoneText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
zoneText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -2)
zoneText:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -10, -2)

local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
closeBtn:SetNormalFontObject("GameFontNormalSmall")
closeBtn:SetHighlightFontObject("GameFontHighlightSmall")
closeBtn:SetText("x")
closeBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
closeBtn:SetScript("OnClick", function() frame:Hide() end)
closeBtn:SetScript("OnEnter", function(self)
    self:GetFontString():SetTextColor(1, 0.3, 0.3)
end)
closeBtn:SetScript("OnLeave", function(self)
    self:GetFontString():SetTextColor(0.5, 0.5, 0.5)
end)

local gearBtn = CreateFrame("Button", nil, titleBar)
gearBtn:SetSize(16, 16)
gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
gearIcon:SetAllPoints()
gearIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
gearIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
gearIcon:SetDesaturated(true)
gearIcon:SetVertexColor(0.6, 0.6, 0.6)
gearBtn:SetScript("OnEnter", function()
    gearIcon:SetVertexColor(1, 1, 1)
    gearIcon:SetDesaturated(false)
end)
gearBtn:SetScript("OnLeave", function()
    gearIcon:SetVertexColor(0.6, 0.6, 0.6)
    gearIcon:SetDesaturated(true)
end)

local sep = frame:CreateTexture(nil, "ARTWORK")
sep:SetHeight(1)
sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -46)
sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -46)
sep:SetColorTexture(1, 1, 1, 0.08)

---------------------------------------------------------------------------
-- SCROLL FRAME
---------------------------------------------------------------------------

local scrollFrame = CreateFrame("ScrollFrame", "NemoScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 32)

-- Style the scrollbar to be less obtrusive
local scrollBar = NemoScrollFrameScrollBar
if scrollBar then
    scrollBar:SetWidth(8)
end

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(240, 1)
scrollFrame:SetScrollChild(content)

---------------------------------------------------------------------------
-- RESIZE HANDLE
---------------------------------------------------------------------------

local resizer = CreateFrame("Button", nil, frame)
resizer:SetSize(16, 16)
resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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

-- Total catches footer (zone totals)
local footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footerText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 16)
footerText:SetTextColor(0.4, 0.4, 0.4)

-- Session stats
local sessionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 4)
sessionText:SetTextColor(0.35, 0.35, 0.35)

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
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 23))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.02)
    end

    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.04)
    row.highlight:Hide()
    row.itemName = nil
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        -- Show the item tooltip if tehere's an item name
        if self.itemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.itemName)
            local _, link = C_Item.GetItemInfo(self.itemName)
            if link then
                GameTooltip:SetHyperlink(link)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.count:SetJustifyH("RIGHT")

    rowPool[index] = row
    return row
end

local function HideAllRows()
    for _, row in ipairs(rowPool) do row:Hide() end
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
        })
    end

    table.sort(sorted, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    return sorted
end

local function RefreshDisplay()
    HideAllRows()

    local zoneName = GetCurrentZoneName()
    local r, g, b = GetAccent()

    topStripe:SetColorTexture(r, g, b, 0.8)
    titleText:SetTextColor(r, g, b)
    zoneText:SetTextColor(0.55, 0.55, 0.55)
    zoneText:SetText(zoneName)

    local catches = GetCurrentZoneCatches()

    if #catches == 0 then
        local row = GetRow(1)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
        row.name:SetText("No catches here yet...")
        row.name:SetTextColor(0.4, 0.4, 0.4)
        row.count:SetText("")
        row.itemName = nil
        content:SetHeight(23)
        footerText:SetText("")
        return
    end

    local total = 0
    local unique = #catches
    for _, c in ipairs(catches) do total = total + c.count end

    for i, catch in ipairs(catches) do
        local row = GetRow(i)
        row.icon:SetTexture(catch.icon)
        row.name:SetText(catch.name)
        row.itemName = catch.name

        local color = QUALITY_COLORS[catch.quality] or QUALITY_COLORS[1]
        row.name:SetTextColor(color[1], color[2], color[3])

        row.count:SetText(catch.count)
        row.count:SetTextColor(r, g, b, 0.9)
    end

    content:SetHeight(#catches * 23)

    if settings.showTotal then
        local fishTime = session.totalTime
        if session.fishStart then
            fishTime = fishTime + (GetTime() - session.fishStart)
        end

        local timeStr
        if fishTime < 60 then
            timeStr = string.format("%ds", fishTime)
        elseif fishTime < 3600 then
            timeStr = string.format("%dm %ds", math.floor(fishTime / 60), fishTime % 60)
        else
            timeStr = string.format("%dh %dm", math.floor(fishTime / 3600),
                math.floor((fishTime % 3600) / 60))
        end

        local sessionUnique = 0
        for _ in pairs(session.unique) do sessionUnique = sessionUnique + 1 end

        local zoneLine = total .. " caught  ·  " .. unique .. " unique"
        footerText:SetText(zoneLine)

        if session.catches > 0 then
            sessionText:SetText("Session: " .. session.catches .. " caught  ·  " .. timeStr)
        else
            sessionText:SetText("")
        end
    else
        footerText:SetText("")
        sessionText:SetText("")
    end
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

local settingsFrame = CreateFrame("Frame", "NemoSettingsFrame", UIParent, "BackdropTemplate")
settingsFrame:SetSize(300, 340)
settingsFrame:SetPoint("CENTER")
settingsFrame:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
settingsFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.96)
settingsFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
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
colorLabel:SetPoint("TOPLEFT", 16, -140)
colorLabel:SetText("Accent Color")
colorLabel:SetTextColor(0.8, 0.8, 0.8)

for i, preset in ipairs(COLOR_PRESETS) do
    local btn = CreateFrame("Button", nil, settingsFrame)
    local col = math.floor((i - 1) % 4)
    local row = math.floor((i - 1) / 4)
    btn:SetSize(52, 24)
    btn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT",
        16 + (col * 62), -156 - (row * 30))

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
lockCheck:SetPoint("TOPLEFT", 12, -224)
lockCheck.text:SetText(" Lock frame position")
lockCheck.text:SetFontObject("GameFontNormalSmall")
lockCheck.text:SetTextColor(0.8, 0.8, 0.8)
lockCheck:SetScript("OnClick", function(self)
    settings.locked = self:GetChecked()
    resizer:SetShown(not settings.locked)
end)

local totalCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
totalCheck:SetSize(24, 24)
totalCheck:SetPoint("TOPLEFT", 12, -250)
totalCheck.text:SetText(" Show catch totals")
totalCheck.text:SetFontObject("GameFontNormalSmall")
totalCheck.text:SetTextColor(0.8, 0.8, 0.8)
totalCheck:SetScript("OnClick", function(self)
    settings.showTotal = self:GetChecked()
    RefreshDisplay()
end)

local autoShowCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
autoShowCheck:SetSize(24, 24)
autoShowCheck:SetPoint("TOPLEFT", 12, -276)
autoShowCheck.text:SetText(" Auto-show when fishing")
autoShowCheck.text:SetFontObject("GameFontNormalSmall")
autoShowCheck.text:SetTextColor(0.8, 0.8, 0.8)
autoShowCheck:SetScript("OnClick", function(self)
    settings.autoShow = self:GetChecked()
end)

local autoHideCheck = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
autoHideCheck:SetSize(24, 24)
autoHideCheck:SetPoint("TOPLEFT", 12, -302)
autoHideCheck.text:SetText(" Auto-hide after 45s / on combat")
autoHideCheck.text:SetFontObject("GameFontNormalSmall")
autoHideCheck.text:SetTextColor(0.8, 0.8, 0.8)
autoHideCheck:SetScript("OnClick", function(self)
    settings.autoHide = self:GetChecked()
end)

gearBtn:SetScript("OnClick", function()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        opacitySlider:SetValue(settings.opacity)
        opacitySlider.UpdateLabel()
        scaleSlider:SetValue(settings.scale)
        scaleSlider.UpdateLabel()
        -- Sync checkbox states
        lockCheck:SetChecked(settings.locked)
        totalCheck:SetChecked(settings.showTotal)
        autoShowCheck:SetChecked(settings.autoShow)
        autoHideCheck:SetChecked(settings.autoHide)
        local r, g, b = GetAccent()
        sTitle:SetTextColor(r, g, b)
        settingsFrame:Show()
    end
end)

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

    -- Check for a stack count (e.g. "x5" at the end)
    local countStr = msg:match("x(%d+)")
    local lootCount = tonumber(countStr) or 1

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
    if icon then entry.icon = icon end
    if quality then entry.quality = quality end

    session.catches = session.catches + lootCount
    session.unique[itemName] = true

    if frame:IsShown() then RefreshDisplay() end
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

    local countStr = msg:match("x(%d+)")
    local lootCount = tonumber(countStr) or 1

    local mapId = GetCurrentMapId()
    if not mapId then return end

    if not NemoDB.catches then NemoDB.catches = {} end
    if not NemoDB.catches[mapId] then NemoDB.catches[mapId] = {} end

    if not NemoDB.catches[mapId][currencyName] then
        NemoDB.catches[mapId][currencyName] = {
            count = 0,
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            quality = 1,
        }
    end

    local entry = NemoDB.catches[mapId][currencyName]
    entry.count = entry.count + lootCount

    session.catches = session.catches + lootCount
    session.unique[currencyName] = true

    if frame:IsShown() then RefreshDisplay() end
end

---------------------------------------------------------------------------
-- FISHING STATE
---------------------------------------------------------------------------

local function OnFishingDetected()
    isFishing = true

    if not session.fishStart then
        session.fishStart = GetTime()
    end

    if settings.autoShow and not frame:IsShown() then
        RefreshDisplay()
        frame:Show()
    end

    if settings.autoHide then
        hideGeneration = hideGeneration + 1
        local myGeneration = hideGeneration
        C_Timer.After(settings.hideDelay, function()
            if hideGeneration == myGeneration and settings.autoHide then
                -- Pause the fishing timer
                if session.fishStart then
                    session.totalTime = session.totalTime + (GetTime() - session.fishStart)
                    session.fishStart = nil
                end
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
-- VOIDSTORM VORTEX DETECTION
-- Hyper-Compressed Ocean vortexes in Voidstorm (map 2405) don't trigger
-- any spellcast events when right-clicked. Instead, we detect catches via
-- LOOT_READY: when loot opens in Voidstorm and the player either has no
-- target or has the vortex targeted (and is NOT mounted), it's almost
-- certainly a vortex catch. This sets isFishing = true so the normal
-- loot/currency handlers can capture the catch.
-- 
-- It could also be an herbalism/mining node loot, but this is what
-- i've got for now. Maybe Blizzard will fix it in a future patch...
--
-- The mounted check prevents false positives when a player has the vortex
-- targeted (e.g. from a /target macro) but is looting something else
-- (herbs, chests, mining nodes) while flying around.
---------------------------------------------------------------------------

local function OnLootReady()
    local mapId = GetCurrentMapId()
    if mapId ~= VOIDSTORM_MAP_ID then return end

    local targetName = UnitName("target")

    -- Vortex catch if: no target at all, or targeting the vortex while dismounted
    if not targetName or (targetName == VORTEX_TARGET_NAME and not IsMounted()) then
        isFishing = true
        -- Show the catch log if autoShow is enabled
        if settings.autoShow and not frame:IsShown() then
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
        if self:IsShown() then RefreshDisplay() end
    end
end)

---------------------------------------------------------------------------
-- BAG TOOLTIP HOOK
-- When hovering over an item in your bags, if catch data for
-- that item, we inject a section showing which zones you caught it in
-- and how many times, sorted by most to least.
---------------------------------------------------------------------------

local function BuildItemZoneLookup(itemName)
    local zones = {}

    if not NemoDB.catches then return zones end

    for mapId, zoneData in pairs(NemoDB.catches) do
        if zoneData[itemName] then
            local zoneName = "Unknown"
            local info = C_Map.GetMapInfo(mapId)
            if info then zoneName = info.name end

            table.insert(zones, {
                name  = zoneName,
                count = zoneData[itemName].count or 0,
            })
        end
    end

    table.sort(zones, function(a, b) return a.count > b.count end)

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
            zone.count .. "x",
            0.7, 0.7, 0.7,
            r, g, b
        )
    end

    local total = 0
    for _, z in ipairs(zones) do total = total + z.count end
    if #zones > 1 then
        tooltip:AddDoubleLine(
            "  Total",
            total .. "x",
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
                    NemoDB = { catches = oldData, settings = {} }
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cFF4CBFF0Nemo|r: Migration complete.")
                end
            end

            if not NemoDB.catches  then NemoDB.catches  = {} end
            if not NemoDB.settings then NemoDB.settings = {} end

            FillDefaults(NemoDB.settings, DEFAULT_SETTINGS)
            settings = NemoDB.settings
            ApplyFrameStyle()
            resizer:SetShown(not settings.locked)

            if settings.anchorPoint then
                frame:ClearAllPoints()
                frame:SetPoint(settings.anchorPoint, UIParent, settings.anchorPoint,
                    settings.anchorX or 0, settings.anchorY or 0)
            else
                frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
            end

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

    elseif event == "PLAYER_REGEN_DISABLED" then
        if session.fishStart then
            session.totalTime = session.totalTime + (GetTime() - session.fishStart)
            session.fishStart = nil
        end
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
            opacitySlider:SetValue(settings.opacity)
            opacitySlider.UpdateLabel()
            scaleSlider:SetValue(settings.scale)
            scaleSlider.UpdateLabel()
            lockCheck:SetChecked(settings.locked)
            totalCheck:SetChecked(settings.showTotal)
            autoShowCheck:SetChecked(settings.autoShow)
            autoHideCheck:SetChecked(settings.autoHide)
            local r, g, b = GetAccent()
            sTitle:SetTextColor(r, g, b)
            settingsFrame:Show()
        end

    elseif cmd == "reset" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF4CBFF0Nemo|r: Type /nemo resetconfirm to wipe ALL catch data.")

    elseif cmd == "resetconfirm" then
        NemoDB.catches = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cFF4CBFF0Nemo|r: All catch data wiped.")
        if frame:IsShown() then RefreshDisplay() end

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
            if frame:IsShown() then RefreshDisplay() end
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFF4CBFF0Nemo|r: \"%s\" not found in any zone. (Name is case-sensitive!)", itemName))
        end

    elseif cmd == "session" then
        local fishTime = session.totalTime
        if session.fishStart then
            fishTime = fishTime + (GetTime() - session.fishStart)
        end
        local timeStr
        if fishTime < 60 then
            timeStr = string.format("%ds", fishTime)
        elseif fishTime < 3600 then
            timeStr = string.format("%dm %ds", math.floor(fishTime / 60), fishTime % 60)
        else
            timeStr = string.format("%dh %dm", math.floor(fishTime / 3600),
                math.floor((fishTime % 3600) / 60))
        end
        local sessionUnique = 0
        for _ in pairs(session.unique) do sessionUnique = sessionUnique + 1 end

        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cFF4CBFF0Nemo|r: Session - %d caught, %d unique, %s fishing",
            session.catches, sessionUnique, timeStr))

    else
        if frame:IsShown() then
            frame:Hide()
        else
            RefreshDisplay()
            frame:Show()
        end
    end
end