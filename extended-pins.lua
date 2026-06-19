local addonName, addon = ...
local ExtendedPins = CreateFrame("Frame")

ExtendedPins.pins = {}
ExtendedPins.isInternalCall = false
ExtendedPins.manualTarget = nil
local ARRIVAL_THRESHOLD_SQ = 0.00001 -- Approx 10-15 yards squared

-- ==========================================
-- 0. DATABASE INITIALIZATION
-- ==========================================
ExtendedPins:RegisterEvent("ADDON_LOADED")
ExtendedPins:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        -- Initialize the SavedVariable if it's the user's first time
        ExtendedPinsDB = ExtendedPinsDB or {}
        -- Point our local pins table to the SavedVariable
        ExtendedPins.pins = ExtendedPinsDB
        
        -- Initial refresh once the data is safely loaded
        C_Timer.After(1, function()
            if ExtendedPins.dataProvider then
                ExtendedPins.dataProvider:RefreshAllData(true)
            end
            ExtendedPins:UpdateRouting()
        end)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ==========================================
-- 1. NATIVE MAP PIN VISUALS
-- ==========================================
ExtendedPinsPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ExtendedPinsPinMixin:OnLoad()
    self:SetSize(32, 32)
    self:SetScalingLimits(1, 1, 1)

    self.texture = self:CreateTexture(nil, "OVERLAY")
    self.texture:SetPoint("CENTER") 
    
    -- The 'true' flag is the magic bullet: it forces the Atlas to use its native dimensions
    -- rather than stretching/collapsing to the frame's bounds.
    self.texture:SetAtlas("Waypoint-MapPin-Untracked", true) 
    self.texture:SetVertexColor(0, 1, 0, 1) -- Tints the grayscale pin a crisp green
end

-- FIX: Override Blizzard's frame leveling to prevent the pin from sinking under the map
function ExtendedPinsPinMixin:ApplyFrameLevel()
    -- self:SetFrameStrata("DIALOG") -- Works, but map pins sit above default UI map pin
    self:SetFrameStrata("HIGH")
    -- self:SetFrameLevel(5000) -- Goes along with the DIALOG frame strata
    self:SetFrameLevel(2000)
end

function ExtendedPinsPinMixin:OnAcquired(pinData)
    self.pinData = pinData
    self:SetPosition(pinData.x, pinData.y)
    
    self:SetScript("OnEnter", self.OnMouseEnter)
    self:SetScript("OnLeave", self.OnMouseLeave)
    self:SetScript("OnMouseDown", self.OnMouseDown)
    
    self:SetMouseClickEnabled(true)
    self:SetMouseMotionEnabled(true)
    self:Show() 
end

function ExtendedPinsPinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    
    -- Check if this pin has a custom name, otherwise use the default
    -- local title = self.pinData.name or "ExtendedPins Pin"
    -- local title = self.pinData.name or string.format("%.2f, %.2f", self.pinData.x * 100, self.pinData.y * 100)
    local title = self.pinData.name or "Map Pin Sharing"
    GameTooltip:SetText(title,1,1,1)
    
    -- GameTooltip:AddLine(string.format("%.2f, %.2f", self.pinData.x * 100, self.pinData.y * 100), 1, 0.82, 0)
    GameTooltip:AddLine("Track this location to enable sharing.", 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("<Click to track pin>", 0.1, 1, 0)
    GameTooltip:AddLine("<Ctrl click to remove pin>", 0.1, 1, 0)
    GameTooltip:Show()
end

function ExtendedPinsPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function ExtendedPinsPinMixin:OnMouseDown(button)
    if button == "LeftButton" then
        if IsControlKeyDown() then
            -- DELETE LOGIC
            for i, pin in ipairs(ExtendedPins.pins) do
                if pin == self.pinData then
                    table.remove(ExtendedPins.pins, i)
                    
                    -- Clean up if this was our manual target
                    if ExtendedPins.manualTarget == self.pinData then
                        ExtendedPins.manualTarget = nil
                    end
                    
                    -- print("|cFF00FF00ExtendedPins:|r Pin removed.")
                    break
                end
            end
            
            -- Refresh the map visuals immediately
            if ExtendedPins.dataProvider then
                ExtendedPins.dataProvider:RefreshAllData(true)
            end
            
            -- Update routing (will clear the native pin if that was the last one)
            ExtendedPins:UpdateRouting()
        else
            -- TRACKING LOGIC (Existing)
            ExtendedPins.manualTarget = self.pinData
            ExtendedPins:UpdateRouting()
            -- print("|cFF00FF00ExtendedPins:|r Manually tracking selected pin.")
        end
    end
end

-- ==========================================
-- 2. NATIVE DATA PROVIDER
-- ==========================================
ExtendedPinsDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)
 
function ExtendedPinsDataProviderMixin:GetPinTemplate()
    return "ExtendedPinsPinTemplate"
end

function ExtendedPinsDataProviderMixin:RefreshAllData(hasValidMap)
    self:GetMap():RemoveAllPinsByTemplate(self:GetPinTemplate())
    if not hasValidMap then return end
    
    local mapID = self:GetMap():GetMapID()
    for _, pin in ipairs(ExtendedPins.pins) do

        --[[
        if pin.mapID == mapID then
            self:GetMap():AcquirePin(self:GetPinTemplate(), pin)
        end
        ]]
        if pin.mapID == mapID and pin ~= ExtendedPins.lastTrackedPin then
            self:GetMap():AcquirePin(self:GetPinTemplate(), pin)
        end

    end
end

local function InjectDataProvider()
    if not WorldMapFrame.pinPools["ExtendedPinsPinTemplate"] then
        WorldMapFrame.pinPools["ExtendedPinsPinTemplate"] = CreateObjectPool(
            function(pool)
                local frame = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
                Mixin(frame, ExtendedPinsPinMixin)
                frame:OnLoad()
                return frame
            end,
            function(pool, frame)
                frame:Hide()
                frame:ClearAllPoints()
                frame:SetScript("OnEnter", nil)
                frame:SetScript("OnLeave", nil)
                frame:SetScript("OnMouseDown", nil)
                frame:SetMouseClickEnabled(false)
                frame:SetMouseMotionEnabled(false)
            end
        )
    end

    ExtendedPins.dataProvider = CreateFromMixins(ExtendedPinsDataProviderMixin)
    WorldMapFrame:AddDataProvider(ExtendedPins.dataProvider)
end

EventRegistry:RegisterFrameEventAndCallback("VARIABLES_LOADED", InjectDataProvider)

-- ==========================================
-- 3. INTERCEPT DEFAULT BEHAVIOR (FIXED)
-- ==========================================
hooksecurefunc(C_Map, "SetUserWaypoint", function(uiMapPoint)
    if ExtendedPins.isInternalCall then return end
    
    local mapID = uiMapPoint.uiMapID
    local pos = uiMapPoint.position
    
    -- Robust coordinate extraction: 
    -- Check for the GetXY method first, fall back to direct x,y access for chat links
    local x, y
    if pos.GetXY then
        x, y = pos:GetXY()
    else
        x, y = pos.x, pos.y
    end

    -- Safety check to ensure we actually have coordinates before proceeding
    if not x or not y then return end
    
    table.insert(ExtendedPins.pins, {mapID = mapID, x = x, y = y})
    -- print(string.format("|cFF00FF00ExtendedPins:|r Added pin at %.2f, %.2f", x * 100, y * 100))
    
    C_Timer.After(0, function()
        ExtendedPins:UpdateRouting()
        if ExtendedPins.dataProvider and WorldMapFrame:IsShown() then
            ExtendedPins.dataProvider:RefreshAllData(true)
        end
    end)
end)

-- ==========================================
-- 3.5 SYNC DELETION
-- ==========================================
hooksecurefunc(C_Map, "ClearUserWaypoint", function()
    -- If we cleared it internally (auto-switching), ignore this
    if ExtendedPins.isInternalCall then return end
    
    -- If the user manually cleared the Blizzard pin, find it in our list and kill it
    if ExtendedPins.lastTrackedPin then
        for i, pin in ipairs(ExtendedPins.pins) do
            if pin == ExtendedPins.lastTrackedPin then
                table.remove(ExtendedPins.pins, i)
                -- print("|cFF00FF00ExtendedPins:|r Pin removed via native UI.")
                break
            end
        end
        ExtendedPins.lastTrackedPin = nil
        
        -- Immediately update to find the next nearest target
        ExtendedPins:UpdateRouting()
        if ExtendedPins.dataProvider then
            ExtendedPins.dataProvider:RefreshAllData(true)
        end
    end
end)

-- ==========================================
-- 4. SLASH COMMANDS (BULK & CONTEXT AWARE)
-- ==========================================
SLASH_EXTENDEDPINSWAY1 = "/way"
SlashCmdList["EXTENDEDPINSWAY"] = function(msg)
    if msg:lower():trim() == "clear" then
        table.wipe(ExtendedPins.pins)
        ExtendedPinsDB = ExtendedPins.pins
        ExtendedPins.manualTarget = nil
        ExtendedPins.isInternalCall = true
        C_Map.ClearUserWaypoint()
        ExtendedPins.isInternalCall = false
        if ExtendedPins.dataProvider then ExtendedPins.dataProvider:RefreshAllData(true) end
        print("|cffffd100All pins cleared.|r")
        return
    end

    local pinsAdded = 0
    local defaultMapID = (WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")

    -- 1. Split the string by "/way". 
    -- We add a leading "/way " just in case the first one was stripped by the slash command handler
    -- but others remain in the string.
    local fullString = "/way " .. msg
    
    -- This pattern finds every instance of "/way" and captures everything until the next "/way"
    for oneCommand in fullString:gmatch("/way%s+([^/]+)") do
        
        -- 2. Extract explicit Map ID if present (e.g., #2405)
        local mapID = defaultMapID
        local mapMatch = oneCommand:match("#(%d+)")
        if mapMatch then
            mapID = tonumber(mapMatch)
            -- Clean the map ID out of the command string so it doesn't break coordinate parsing
            oneCommand = oneCommand:gsub("#%d+", "")
        end

        -- 3. Parse Coords and Name
        -- Pattern: (numbers) (space) (numbers) (optional name)
        local xStr, yStr, nameStr = oneCommand:match("(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)")
        
        if xStr and yStr and mapID and mapID ~= 0 then
            local x, y = tonumber(xStr) / 100, tonumber(yStr) / 100
            local title = nil
            
            if nameStr and nameStr ~= "" then
                local trimmed = strtrim(nameStr)
                if trimmed ~= "" then title = trimmed end
            end

            table.insert(ExtendedPins.pins, {mapID = mapID, x = x, y = y, name = title})
            pinsAdded = pinsAdded + 1
        end
    end

    -- 4. Finalize and Update
    if pinsAdded > 0 then
        ExtendedPins:UpdateRouting()
        if ExtendedPins.dataProvider and WorldMapFrame:IsShown() then
            ExtendedPins.dataProvider:RefreshAllData(true)
        end
        print(string.format("|cffffd100Added %d pins.|r", pinsAdded))
    else
        print("|cffffd100Usage: /way [#mapID] <x> <y> [name] (Supports multi-paste)|r")
    end
end

-- ==========================================
-- 5. ROUTING ENGINE
-- ==========================================
ExtendedPins:SetScript("OnUpdate", function(self, elapsed)
    self.ticker = (self.ticker or 0) + elapsed
    if self.ticker >= 0.5 then
        self.ticker = 0
        self:UpdateRouting()
    end
end)

function ExtendedPins:UpdateRouting()
    if #self.pins == 0 then 
        self.isInternalCall = true
        C_Map.ClearUserWaypoint()
        self.isInternalCall = false
        return 
    end
    
    local playerMap = C_Map.GetBestMapForUnit("player")
    if not playerMap then return end

    local playerPos = C_Map.GetPlayerMapPosition(playerMap, "player")
    if not playerPos then return end
    local px, py = playerPos:GetXY()

    local targetPin = nil
    local targetIdx = nil

    if self.manualTarget then
        for i, pin in ipairs(self.pins) do
            if pin == self.manualTarget then
                targetPin = pin
                targetIdx = i
                break
            end
        end
        if not targetPin then self.manualTarget = nil end
    end

    if not targetPin then
        local closestDist = math.huge
        for i, pin in ipairs(self.pins) do
            if pin.mapID == playerMap then
                local dx = pin.x - px
                local dy = pin.y - py
                local distSq = (dx * dx) + (dy * dy)
                
                if distSq < closestDist then
                    closestDist = distSq
                    targetPin = pin
                    targetIdx = i
                end
            end
        end
    end

    if targetPin then
        local dx = targetPin.x - px
        local dy = targetPin.y - py
        local distSq = (dx * dx) + (dy * dy)

        -- 1. PROXIMITY CHECK: Did we arrive?
        if distSq < ARRIVAL_THRESHOLD_SQ then
            table.remove(self.pins, targetIdx)
            if self.manualTarget == targetPin then self.manualTarget = nil end
            
            if #self.pins == 0 then
                print("|cffffd100Final destination reached.|r")
            else
                print("|cffffd100Waypoint reached. Routing to next nearest.|r")
            end
            
            if self.dataProvider then self.dataProvider:RefreshAllData(true) end
            self:UpdateRouting() -- Recalculate for the next pin
            return
        end

        -- 2. VISUAL SYNC: Hide the green pin because it's now the active Blizzard pin
        local wasTracking = ExtendedPins.lastTrackedPin
        ExtendedPins.lastTrackedPin = targetPin

        if wasTracking ~= targetPin and ExtendedPins.dataProvider then
            ExtendedPins.dataProvider:RefreshAllData(true)
        end

        -- 3. NATIVE UPDATE: Set the actual Blizzard Waypoint
        self.isInternalCall = true
        local pt = UiMapPoint.CreateFromCoordinates(targetPin.mapID, targetPin.x, targetPin.y)
        C_Map.SetUserWaypoint(pt)
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        self.isInternalCall = false
    else
        -- No pins left or none in this zone
        ExtendedPins.lastTrackedPin = nil
        self.isInternalCall = true
        C_Map.ClearUserWaypoint()
        self.isInternalCall = false
    end


end

-- ==========================================
-- 6. VISIBILITY FIXES
-- ==========================================

-- Refresh pins whenever you flip to a new zone or zoom the map
hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
    if ExtendedPins.dataProvider then
        ExtendedPins.dataProvider:RefreshAllData(true)
    end
end)

-- Refresh pins the moment the map is opened
WorldMapFrame:HookScript("OnShow", function()
    if ExtendedPins.dataProvider then
        ExtendedPins.dataProvider:RefreshAllData(true)
    end
end)