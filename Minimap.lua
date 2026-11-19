-- Minimap.lua : le bouton de la minicarte, avec le logo de la fenêtre (le parchemin, en haut à gauche). Clic : ouvrir /
-- fermer ; clic droit : réglages ; glisser : le déplacer autour de la minicarte (sa place est gardée pour le compte,
-- ForeverCraftAtlasDB.minimapAngle). Caché par la case « Bouton de la minicarte » des réglages.
local _, ns = ...

ns.LOGO = "Interface\\Icons\\INV_Scroll_04"
ns.DEFAULTS.minimap = true

local button

local function Angle()
    local a = ForeverCraftAtlasDB and tonumber(ForeverCraftAtlasDB.minimapAngle)
    return a or 225
end

local function Place()
    local a = math.rad(Angle())
    local r = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function Create()
    local b = CreateFrame("Button", "ForeverCraftAtlasMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ns.LOGO)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- (le logo rond, comme le portrait de la fenêtre)
    if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, which)
        if which == "RightButton" then ns.OpenSettings() else ns.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
            ForeverCraftAtlasDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ForeverCraftAtlas")
        GameTooltip:AddLine("Clic : ouvrir / fermer", 1, 1, 1)
        GameTooltip:AddLine("Clic droit : réglages", 1, 1, 1)
        GameTooltip:AddLine("Glisser : déplacer le bouton", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function ns.UpdateMinimapButton()
    if not Minimap then return end
    if not ns.Get("minimap") then
        if button then button:Hide() end
        return
    end
    button = button or Create()
    Place()
    button:Show()
end

ns.OnChange(function(key) if key == nil or key == "minimap" then ns.UpdateMinimapButton() end end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ns.UpdateMinimapButton()
end)
