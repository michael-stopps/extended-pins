local addonName, addon = ...
local ExtendedPins = CreateFrame("Frame")

ExtendedPins.pins = {}
ExtendedPins.isInternalCall = false
ExtendedPins.manualTarget = nil
local ARRIVAL_THRESHOLD_SQ = 0.00001

-- ==========================================
-- 0. DATABASE INITIALIZATION
-- ==========================================
ExtendedPins:RegisterEvent("ADDON_LOADED")
ExtendedPins:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        ExtendedPinsDB = ExtendedPinsDB or {}
        ExtendedPins.pins = ExtendedPinsDB
        
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
    
    self.texture:SetAtlas("Waypoint-MapPin-Untracked", true) 
    self.texture:SetVertexColor(0, 1, 0, 1) 
end

function ExtendedPinsPinMixin:ApplyFrameLevel()
    self:SetFrameStrata("HIGH")
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
    
    local title = self.pinData.name or "Map Pin Sharing"
    GameTooltip:SetText(title,1,1,1)
    
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
            for i, pin in ipairs(ExtendedPins.pins) do
                if pin == self.pinData then
                    table.remove(ExtendedPins.pins, i)
                    
                    if ExtendedPins.manualTarget == self.pinData then
                        ExtendedPins.manualTarget = nil
                    end
                    
                    break
                end
            end
            
            if ExtendedPins.dataProvider then
                ExtendedPins.dataProvider:RefreshAllData(true)
            end
            
            ExtendedPins:UpdateRouting()
        else
            ExtendedPins.manualTarget = self.pinData
            ExtendedPins:UpdateRouting()
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
    
    local x, y
    if pos.GetXY then
        x, y = pos:GetXY()
    else
        x, y = pos.x, pos.y
    end

    if not x or not y then return end
    
    local newPin = {mapID = mapID, x = x, y = y}
    table.insert(ExtendedPins.pins, newPin)
    ExtendedPins.manualTarget = newPin 
    
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
    if ExtendedPins.isInternalCall then return end
    
    if ExtendedPins.lastTrackedPin then
        for i, pin in ipairs(ExtendedPins.pins) do
            if pin == ExtendedPins.lastTrackedPin then
                table.remove(ExtendedPins.pins, i)
                break
            end
        end
        ExtendedPins.lastTrackedPin = nil
        
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

    local fullString = "/way " .. msg
    
    for oneCommand in fullString:gmatch("/way%s+([^/]+)") do
        
        local mapID = defaultMapID
        local mapMatch = oneCommand:match("#(%d+)")
        if mapMatch then
            mapID = tonumber(mapMatch)
            oneCommand = oneCommand:gsub("#%d+", "")
        end

        local xStr, yStr, nameStr = oneCommand:match("(%d+%.?%d*)%s+(%d+%.?%d*)%s*(.*)")
        
        if xStr and yStr and mapID and mapID ~= 0 then
            local x, y = tonumber(xStr) / 100, tonumber(yStr) / 100
            local title = nil
            
            if nameStr and nameStr ~= "" then
                local trimmed = strtrim(nameStr)
                if trimmed ~= "" then title = trimmed end
            end

            local newPin = {mapID = mapID, x = x, y = y, name = title}
            table.insert(ExtendedPins.pins, newPin)
            ExtendedPins.manualTarget = newPin
            pinsAdded = pinsAdded + 1
        end
    end

    if pinsAdded > 0 then
        ExtendedPins:UpdateRouting()
        if ExtendedPins.dataProvider and WorldMapFrame:IsShown() then
            ExtendedPins.dataProvider:RefreshAllData(true)
        end
        local pinsText = (pinsAdded == 1) and "pin" or "pins"
        print(string.format("|cffffd100Added %d %s.|r", pinsAdded, pinsText))
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

        if distSq < ARRIVAL_THRESHOLD_SQ then
            table.remove(self.pins, targetIdx)
            if self.manualTarget == targetPin then self.manualTarget = nil end
            
            if #self.pins == 0 then
                print("|cffffd100Final destination reached.|r")
            else
                print("|cffffd100Waypoint reached. Routing to next nearest.|r")
            end
            
            if self.dataProvider then self.dataProvider:RefreshAllData(true) end
            self:UpdateRouting() 
            return
        end

        local wasTracking = ExtendedPins.lastTrackedPin
        ExtendedPins.lastTrackedPin = targetPin

        if wasTracking ~= targetPin then
            if ExtendedPins.dataProvider then
                ExtendedPins.dataProvider:RefreshAllData(true)
            end

            self.isInternalCall = true
            local pt = UiMapPoint.CreateFromCoordinates(targetPin.mapID, targetPin.x, targetPin.y)
            C_Map.SetUserWaypoint(pt)
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            self.isInternalCall = false
        end
    else
        ExtendedPins.lastTrackedPin = nil
        self.isInternalCall = true
        C_Map.ClearUserWaypoint()
        self.isInternalCall = false
    end
end

-- ==========================================
-- 6. VISIBILITY FIXES
-- ==========================================

hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
    if ExtendedPins.dataProvider then
        ExtendedPins.dataProvider:RefreshAllData(true)
    end
end)

WorldMapFrame:HookScript("OnShow", function()
    if ExtendedPins.dataProvider then
        ExtendedPins.dataProvider:RefreshAllData(true)
    end
end)
