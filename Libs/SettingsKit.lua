-- SettingsKit : les pages de réglages des addons du dépôt (RouteXP, les patchs), au rythme de la liste de réglages du jeu
-- (Blizzard_Settings_Shared de WoW Forever) : titre en GameFontHighlightHuge à 7, -22 du coin, trait du jeu à 50,
-- bouton « Par défaut » de 96 x 22 en haut à droite ; sections en GameFontHighlightLarge blanc dans une bande de 45 ;
-- lignes de 26 de haut espacées de 9, nom du réglage en or (GameFontNormal) à 37 du bord de la ligne, contrôle 80 à
-- gauche du milieu (case du jeu 30 x 29, curseur à pas de 250, menu de 220, bouton rouge de 22 de haut). En plus de la
-- liste du jeu : la description de chaque réglage est toujours affichée sous son nom, la page commence par ce que fait
-- l'addon et ce qu'il ne fait pas, et les choix visuels (polices, textures, icônes) se voient avant d'être choisis.
--
-- Fichier commun (shared/SettingsKit.lua), copié dans chaque addon (Libs\SettingsKit.lua). Range sa table dans
-- l'espace privé de l'addon (ns.SettingsKit) ; aucune variable globale, hormis la fenêtre de confirmation partagée
-- (StaticPopupDialogs.FOREVERCRAFTATLAS_CONFIRM). Une page peut aussi se ranger sous celle d'un autre addon (spec.parent : le
-- patch d'un addon, sous la page de cet addon).

local _, ns = ...
local UI = {}
ns.SettingsKit = UI

-- Mesures --------------------------------------------------------------------------------------
local LEFT, TOP, BOTTOM = 25, 16, 20      -- les lignes partent à 25 du bord du cadre, 16 sous l'en-tête
local HEADER_HEIGHT = 50                  -- titre à 7, -22 ; trait à -50
local TITLE_X, TITLE_Y = 7, 22
local SECTION_HEIGHT, SECTION_X, SECTION_Y = 45, 7, 16
local ROW_HEIGHT, ROW_GAP = 26, 9
local LABEL_X, LABEL_END = 37, 85         -- nom à 37 du bord de la ligne, jusqu'à 85 avant le milieu
local INDENT_STEP = 15                    -- une option qui en précise une autre : 15 plus loin, en petit
local CONTROL_X = -80                     -- contrôle 80 à gauche du milieu
local CHECK_W, CHECK_H = 30, 29
local SLIDER_W, DROPDOWN_W = 250, 220
local BUTTON_W, BUTTON_H, BUTTON_PAD = 200, 22, 24
local DEFAULTS_W = 96
local PAGE_MIN_WIDTH = 420
local RIGHT_MARGIN = 10
local BAR_SPACE = 12                      -- la barre de défilement et son écart
local DESC_GAP = 1                        -- entre la ligne d'un réglage et sa description
local BOX_RIGHT = 14
local DIMMED = 0.5

local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local SOFT = { 0.78, 0.78, 0.78 }         -- texte de présentation (comme l'en-tête de Spoken)
local DESC = { 0.82, 0.82, 0.82 }         -- descriptions des réglages

UI.metrics = {
    LEFT = LEFT, TOP = TOP, HEADER_HEIGHT = HEADER_HEIGHT, ROW_HEIGHT = ROW_HEIGHT, ROW_GAP = ROW_GAP,
    LABEL_X = LABEL_X, CONTROL_X = CONTROL_X, SECTION_HEIGHT = SECTION_HEIGHT, BUTTON_H = BUTTON_H,
    TITLE_X = TITLE_X, TITLE_Y = TITLE_Y,
}
UI.colors = { GOLD = GOLD, WHITE = WHITE, SOFT = SOFT, DESC = DESC }

-- Outils --------------------------------------------------------------------------------------
local function HasAtlas(name)
    return (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) ~= nil
end
UI.HasAtlas = HasAtlas

local function Atlas(frame, layer, atlas, useSize)
    if not HasAtlas(atlas) then return nil end
    local texture = frame:CreateTexture(nil, layer)
    texture:SetAtlas(atlas, useSize)
    return texture
end

local function Flat(frame, layer, r, g, b, a)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Font(parent, template, color)
    local fs = parent:CreateFontString(nil, "ARTWORK", template)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end
UI.Font = Font

local function Put(region, parent, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

local function Height(fs, least)
    local h = fs:GetStringHeight() or 0
    if h < (least or 0) then h = least end
    return math.ceil(h)
end

local function Tip(frame, title, body, reason)
    if not (title or body or reason) or not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(title or body or reason, 1, 0.82, 0, 1, true)
    if title and body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    if reason then GameTooltip:AddLine(reason, 1, 0.5, 0.25, true) end
    GameTooltip:Show()
end
UI.Tip = Tip

-- Une ligne surlignée au survol, comme celles du jeu (HoverBackgroundTemplate : blanc à 10 %, de 10 avant la ligne
-- à 5 avant sa fin).
local function Band(parent)
    local hit = CreateFrame("Button", nil, parent)
    local band = Flat(hit, "BACKGROUND", 1, 1, 1, 0.1)
    band:SetPoint("TOPLEFT", hit, "TOPLEFT", -10, 2)
    band:SetPoint("BOTTOMRIGHT", hit, "BOTTOMRIGHT", -5, -2)
    band:Hide()
    hit.band = band
    hit:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    return hit
end

local function Above(frame, parent)
    frame:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)
end

-- Fenêtres de confirmation -------------------------------------------------------------------
-- Une seule fenêtre partagée : le texte et l'action voyagent avec elle (data).
if StaticPopupDialogs and not StaticPopupDialogs.FOREVERCRAFTATLAS_CONFIRM then
    StaticPopupDialogs.FOREVERCRAFTATLAS_CONFIRM = {
        text = "%s",
        button1 = YES or "Oui",
        button2 = NO or "Non",
        OnAccept = function(_, data) if data and data.accept then data.accept() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function UI.Confirm(question, accept, acceptLabel, cancelLabel)
    local dialog = StaticPopupDialogs and StaticPopupDialogs.FOREVERCRAFTATLAS_CONFIRM
    if not (dialog and StaticPopup_Show) then
        accept()
        return
    end
    dialog.button1 = acceptLabel or YES or "Oui"
    dialog.button2 = cancelLabel or NO or "Non"
    StaticPopup_Show("FOREVERCRAFTATLAS_CONFIRM", question, nil, { accept = accept })
end

-- Ouvre une page dans les options du jeu (hors combat : le jeu refuse en combat).
function UI.Open(page)
    if InCombatLockdown and InCombatLockdown() then
        print("|cffe6b85c" .. (page.spec.name or "") .. "|r : impossible d'ouvrir les réglages en combat.")
        return
    end
    if not page.category and page.Register then page:Register(true) end
    if page.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(page.category.GetID and page.category:GetID() or page.category.ID)
    end
end

-- La page de premier niveau de la liste Options > AddOns qui porte ce nom (celle d'un autre addon).
function UI.FindCategory(name)
    local list = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
    for _, group in ipairs(list and list.groups or {}) do
        for _, category in ipairs(group.categories or {}) do
            if category.GetName and category:GetName() == name and not (category.GetParentCategory and category:GetParentCategory()) then
                return category
            end
        end
    end
end

-- Fenêtres à part (le sélecteur de choix visuels) -------------------------------------------------------
local TAB_COLORS = { normal = { 0.62, 0.62, 0.62 }, hover = { 1, 1, 1 }, active = GOLD }
local TAB_PAD, TAB_GAP, TAB_TOP = 10, 4, -28

-- Le cadre d'une fenêtre à part : celui des fenêtres du jeu (ButtonFrameTemplate, avec ses bordures et son fond de
-- WoW Forever), sans portrait ni barre de boutons, sinon un cadre simple et sa croix. Déplaçable à la souris, fermé
-- par Échap.
local function SetShellTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    else
        if not frame.shellTitle then
            frame.shellTitle = frame.TitleText or Font(frame, "GameFontNormal")
            if not frame.TitleText then frame.shellTitle:SetPoint("TOP", frame, "TOP", 0, -6) end
        end
        frame.shellTitle:SetText(text)
    end
end

local function NewShell(name, title, width, height)
    local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate")
    if not ok or not frame then
        frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.CloseButton = close
    end
    frame:Hide()
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, frame) end
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, frame) end
    SetShellTitle(frame, title)
    if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
    return frame
end
UI.NewShell = NewShell

-- Page --------------------------------------------------------------------------------------
local Page = {}
Page.__index = Page
UI.PageMixin = Page

-- spec : name (catégorie dans Options > AddOns), title, about (ce que fait l'addon), limits (texte
-- ou liste : ce qu'il ne fait pas), defaults (fonction du bouton « Par défaut »), canvas (un cadre
-- existant à remplir, celui d'une catégorie déjà inscrite), register (false : ne pas inscrire ; "later" :
-- page:Register() l'inscrira), beforeRegister(catégorie) (appelé juste avant l'inscription dans la liste),
-- parent (le nom de la page d'un autre addon : celle-ci se range dessous, dès qu'elle existe ; sinon, après
-- quelques secondes de jeu, au premier niveau sous le nom « <parent> - <name> »).
function UI.NewPage(spec)
    local page = setmetatable({ spec = spec, items = {} }, Page)
    local canvas = spec.canvas or CreateFrame("Frame")
    if not spec.canvas then canvas:Hide() end
    page.canvas = canvas
    canvas.OnCommit = canvas.OnCommit or function() end
    canvas.OnRefresh = function() page:Refresh() end
    canvas.OnDefault = function()
        if spec.defaults then
            spec.defaults()
            page:Refresh()
        end
    end

    -- (header = false : une page d'une fenêtre à onglets, sans titre ni trait : la fenêtre a les siens)
    local header = spec.header ~= false
    if header then
        local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        title:SetJustifyH("LEFT")
        Put(title, canvas, TITLE_X, -TITLE_Y)
        title:SetText(spec.title or spec.name)
        page.title = title

        local rule = Atlas(canvas, "ARTWORK", "Options_HorizontalDivider", true)
        if rule then
            rule:SetPoint("TOP", canvas, "TOP", 0, -HEADER_HEIGHT)
        else
            rule = Flat(canvas, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], 0.3)
            rule:SetHeight(1)
            rule:SetPoint("TOPLEFT", canvas, "TOPLEFT", TITLE_X, -HEADER_HEIGHT)
            rule:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -TITLE_X, -HEADER_HEIGHT)
        end
        page.rule = rule
    end

    if spec.defaults and header then
        local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
        button:SetSize(DEFAULTS_W, BUTTON_H)
        button:SetText(SETTINGS_DEFAULTS or "Par défaut")
        button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -36, -16)
        button:SetScript("OnClick", function()
            UI.Confirm(spec.defaultsQuestion or ("Remettre tous les réglages de " .. (spec.name or "") ..
                " à leur valeur par défaut ?"), function()
                spec.defaults()
                page:Refresh()
            end)
        end)
        page.defaultsButton = button
    end

    local scroll = CreateFrame("ScrollFrame", nil, canvas)
    scroll:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, header and -(HEADER_HEIGHT + 2) or 0)
    scroll:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(PAGE_MIN_WIDTH, 1)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) page:ScrollTo((scroll:GetVerticalScroll() or 0) - delta * 32) end)
    scroll:SetScript("OnSizeChanged", function() page:Reflow() end)
    page.scroll, page.body = scroll, body
    page:BuildBar()

    canvas:HookScript("OnShow", function() page:Refresh() end)

    if spec.about or spec.limits then page:Intro(spec.about, spec.limits) end

    if spec.parent and spec.register ~= false and not spec.canvas then
        -- (la page de l'autre addon s'inscrit à son chargement, à la connexion ou plus tard : on l'attend)
        if not page:Register() then UI.WaitForParent(page) end
    elseif spec.register ~= false and not spec.canvas and Settings and Settings.RegisterCanvasLayoutCategory then
        page.category = Settings.RegisterCanvasLayoutCategory(canvas, spec.name)
        if spec.register ~= "later" then page:Register() end
    end
    return page
end

-- Une page à ranger sous celle d'un autre addon, qui n'existe pas encore : inscrite dès que cet addon inscrit la sienne
-- (Settings.RegisterAddOnCategory, accroché une fois), ou essayée à la connexion ; au premier niveau si elle n'est
-- toujours pas là 30 secondes après la connexion (l'autre addon n'a pas de page).
local waiting = {}
function UI.WaitForParent(page)
    waiting[#waiting + 1] = page
    if not UI.waitHooked and Settings and Settings.RegisterAddOnCategory then
        UI.waitHooked = true
        hooksecurefunc(Settings, "RegisterAddOnCategory", function(category)
            local name = type(category) == "table" and category.GetName and category:GetName()
            local top = not (category and category.GetParentCategory and category:GetParentCategory())
            for i = #waiting, 1, -1 do
                local p = waiting[i]
                if p.registered or (top and name == p.spec.parent and p:Register(false, category)) then
                    table.remove(waiting, i)
                end
            end
        end)
    end
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_LOGIN")
    waiter:SetScript("OnEvent", function()
        for _, delay in ipairs({ 0, 1, 3, 10 }) do C_Timer.After(delay, function() page:Register() end) end
        C_Timer.After(30, function() page:Register(true) end)
    end)
end

-- Inscrit la page dans la liste Options > AddOns (tout de suite, ou plus tard avec register = "later" : par
-- exemple après la page d'un autre addon qu'elle remplace). Sous la page d'un autre addon (spec.parent) : dès
-- qu'elle existe (parent : sa catégorie, si on l'a déjà) ; « force » : au premier niveau si elle n'existe toujours pas.
function Page:Register(force, parent)
    if self.registered then return true end
    if self.spec.parent and not self.category then
        if not (Settings and Settings.RegisterCanvasLayoutCategory) then return false end
        parent = parent or UI.FindCategory(self.spec.parent)
        if parent and Settings.RegisterCanvasLayoutSubcategory then
            self.category = Settings.RegisterCanvasLayoutSubcategory(parent, self.canvas, self.spec.name)
            self.registered = true
            return true
        end
        if not force then return false end
        self.category = Settings.RegisterCanvasLayoutCategory(self.canvas, self.spec.parent .. " - " .. self.spec.name)
    end
    if not self.category then return false end
    self.registered = true
    -- Avant l'inscription dans la liste (qui la redessine) : par exemple pour y masquer une autre page.
    if self.spec.beforeRegister then self.spec.beforeRegister(self.category) end
    Settings.RegisterAddOnCategory(self.category)
    return true
end

-- La barre de défilement fine du jeu (MinimalScrollBar) quand le client a ses images, sinon une
-- barre unie.
function Page:BuildBar()
    local bar = CreateFrame("Frame", nil, self.canvas)
    bar:SetWidth(8)
    bar:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", -2, 6)
    bar:Hide()
    local track = Atlas(bar, "BACKGROUND", "!minimal-scrollbar-track-middle", false)
    if track then
        track:SetAllPoints(bar)
    else
        Flat(bar, "BACKGROUND", 1, 1, 1, 0.06):SetAllPoints(bar)
    end
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(8)
    thumb:SetHeight(20)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    local face = Atlas(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-middle", false)
    if not face then face = Flat(thumb, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], 0.45) end
    face:SetAllPoints(thumb)
    face:SetAlpha(0.8)
    thumb:SetScript("OnEnter", function() face:SetAlpha(1) end)
    thumb:SetScript("OnLeave", function() if not self.dragging then face:SetAlpha(0.8) end end)
    local page = self
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / ((bar:GetEffectiveScale()) or 1)
    end
    local function Release()
        page.dragging = false
        bar:SetScript("OnUpdate", nil)
        face:SetAlpha(0.8)
    end
    thumb:SetScript("OnMouseDown", function()
        page.grab = (thumb:GetTop() or 0) - CursorY()
        page.dragging = true
        bar:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then Release() return end
            local travel = (bar:GetHeight() or 0) - (thumb:GetHeight() or 0)
            if travel <= 0 then return end
            local offset = (bar:GetTop() or 0) - (CursorY() + page.grab)
            page:ScrollTo(math.max(0, math.min(travel, offset)) / travel * (page.range or 0))
        end)
    end)
    thumb:SetScript("OnMouseUp", Release)
    thumb:SetScript("OnHide", Release)
    self.bar, self.thumb = bar, thumb
end

function Page:ScrollTo(value)
    value = math.max(0, math.min(value or 0, self.range or 0))
    self.scroll:SetVerticalScroll(value)
    self:UpdateBar()
end

function Page:UpdateBar()
    local view = self.scroll:GetHeight() or 0
    local range = math.max(0, math.floor((self.contentHeight or 0) - view))
    self.range = range
    if range <= 0 or view <= 0 then
        self.bar:Hide()
        if (self.scroll:GetVerticalScroll() or 0) ~= 0 then self.scroll:SetVerticalScroll(0) end
        return
    end
    self.bar:Show()
    local barHeight = self.bar:GetHeight() or view
    local thumbHeight = math.max(20, math.floor(barHeight * view / (view + range)))
    self.thumb:SetHeight(thumbHeight)
    local at = math.min(1, (self.scroll:GetVerticalScroll() or 0) / range)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.bar, "TOP", 0, -math.floor((barHeight - thumbHeight) * at))
end

-- Largeur des lignes : celle de la zone visible moins ses marges, jamais sous 420.
function Page:Width()
    local available = (self.scroll:GetWidth() or 0) - BAR_SPACE
    local width = available - LEFT - RIGHT_MARGIN
    if width < PAGE_MIN_WIDTH then width = PAGE_MIN_WIDTH end
    return math.floor(width)
end

function Page:Middle() return LEFT + math.floor(self:Width() / 2) end
function Page:Column() return self:Middle() + CONTROL_X end

function Page:Add(item)
    item.regions = item.regions or {}
    table.insert(self.items, item)
    self.dirty = true
    return item
end

-- Place tout, de haut en bas, en refermant ce qui est caché.
function Page:Reflow()
    if self.flowing then return end
    self.flowing = true
    local width = self:Width()
    self.body:SetWidth(LEFT + width + RIGHT_MARGIN)
    local y, first = -TOP, true
    for _, item in ipairs(self.items) do
        local shown = not item.visible or item.visible() and true or false
        item.shown = shown
        for _, region in ipairs(item.regions) do region:SetShown(shown) end
        if shown then
            if not first and item.kind ~= "section" then y = y - (item.gap or ROW_GAP) end
            local height = item.place(y, width) or 0
            item.top, item.height = y, height
            y = y - height
            first = false
        end
    end
    self.contentHeight = -y + BOTTOM
    self.body:SetHeight(self.contentHeight)
    self:UpdateBar()
    self.dirty = false
    self.flowing = false
end

-- Relit chaque réglage, regrise ce qui ne s'applique pas, puis replace tout.
function Page:Refresh()
    for _, item in ipairs(self.items) do
        if item.sync then item.sync() end
        if item.enabled then
            local on, reason = item.enabled()
            on = on and true or false
            item.isEnabled, item.reason = on, (not on) and reason or nil
            if item.setEnabled then item.setEnabled(on) end
            for _, region in ipairs(item.fade or {}) do region:SetAlpha(on and 1 or DIMMED) end
        end
    end
    self:Reflow()
end

-- Présentation : ce que fait l'addon (texte gris clair, comme l'en-tête de Spoken), puis ses
-- limites sous un petit titre or.
function Page:Intro(about, limits)
    local body = self.body
    local aboutText = about and Font(body, "GameFontHighlight", SOFT)
    if aboutText then aboutText:SetText(about) end
    local head, lines = nil, {}
    if limits then
        head = Font(body, "GameFontNormal", GOLD)
        head:SetText(self.spec.limitsTitle or "Limites")
        if type(limits) == "string" then limits = { limits } end
        for _, text in ipairs(limits) do
            local fs = Font(body, "GameFontHighlightSmall", DESC)
            fs:SetText("•  " .. text)
            table.insert(lines, fs)
        end
    end
    local regions = { aboutText, head }
    for _, fs in ipairs(lines) do table.insert(regions, fs) end
    local kept = {}
    for _, region in ipairs(regions) do if region then table.insert(kept, region) end end
    self.intro = { about = aboutText, head = head, lines = lines }
    return self:Add({ kind = "intro", regions = kept, place = function(top, width)
        local x, w = LEFT + SECTION_X, width - SECTION_X * 2
        local y = top
        if aboutText then
            aboutText:SetWidth(w)
            Put(aboutText, body, x, y)
            y = y - Height(aboutText, 12) - 10
        end
        if head then
            Put(head, body, x, y)
            y = y - Height(head, 12) - 4
            for _, fs in ipairs(lines) do
                fs:SetWidth(w - 10)
                Put(fs, body, x + 4, y)
                y = y - Height(fs, 10) - 3
            end
            y = y - 2
        end
        return top - y
    end })
end

-- Un paragraphe libre, aligné sur les titres de section.
function Page:Text(text, template, color)
    local fs = Font(self.body, template or "GameFontHighlightSmall", color or DESC)
    fs:SetText(text)
    local body = self.body
    local item = self:Add({ kind = "text", regions = { fs }, fs = fs, place = function(top, width)
        fs:SetWidth(width - SECTION_X * 2)
        Put(fs, body, LEFT + SECTION_X, top)
        return Height(fs, 10)
    end })
    item.SetText = function(_, value) fs:SetText(value) end
    return item
end

-- Une section : son titre blanc dans une bande de 45, et une phrase facultative qui dit ce qu'elle
-- règle.
function Page:Section(text, desc)
    local body = self.body
    local fs = Font(body, "GameFontHighlightLarge", WHITE)
    fs:SetText(text)
    local d = desc and Font(body, "GameFontHighlightSmall", DESC)
    if d then d:SetText(desc) end
    return self:Add({ kind = "section", regions = { fs, d }, title = fs, desc = d, place = function(top, width)
        Put(fs, body, LEFT + SECTION_X, top - SECTION_Y)
        if not d then return SECTION_HEIGHT end
        local below = top - SECTION_Y - Height(fs, 16) - 5
        d:SetWidth(width - SECTION_X * 2)
        Put(d, body, LEFT + SECTION_X, below)
        return (top - below) + Height(d, 10) + 12
    end })
end

-- Ce que partagent toutes les lignes à contrôle : la bande de survol, le nom en or, la description
-- toujours affichée dessous, le contrôle dans la colonne commune.
local function NewRow(page, spec)
    local body = page.body
    local hit = Band(body)
    local label = Font(body, spec.indent and "GameFontNormalSmall" or "GameFontNormal", GOLD)
    label:SetText(spec.label or "")
    if label.SetWordWrap then label:SetWordWrap(true) end
    local desc = spec.desc and Font(body, "GameFontHighlightSmall", DESC)
    if desc then desc:SetText(spec.desc) end
    local item = { kind = "row", spec = spec, hit = hit, label = label, desc = desc,
        visible = spec.visible, enabled = spec.enabled, regions = { hit, label, desc },
        fade = { label, desc } }
    hit:SetScript("OnEnter", function()
        hit.band:Show()
        if item.reason then Tip(hit, spec.label, nil, item.reason) end
    end)
    hit:SetScript("OnLeave", function()
        hit.band:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return item
end

-- Place une ligne : `control` (sa hauteur `controlHeight`) dans la colonne, à `offset` du milieu.
local function PlaceRow(page, item, control, top, width, offset, controlHeight)
    local body = page.body
    local x = LEFT + (item.spec.indent and INDENT_STEP or 0)
    local labelX = x + LABEL_X
    local middle = page:Middle()
    local labelWidth = math.max(60, middle - LABEL_END - labelX)
    item.label:SetWidth(labelWidth)
    local labelHeight = Height(item.label, 12)
    local line = math.max(ROW_HEIGHT, labelHeight + 8, controlHeight or 0)
    -- Centré dans la ligne (sans lui fixer de hauteur, qui couperait un nom sur deux lignes).
    Put(item.label, body, labelX, top - math.floor((line - labelHeight) / 2))
    if control then
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", body, "TOPLEFT", middle + (offset or CONTROL_X),
            top - math.floor((line - (controlHeight or 0)) / 2))
    end
    local height = line
    if item.desc then
        item.desc:SetWidth(LEFT + width - BOX_RIGHT - labelX)
        Put(item.desc, body, labelX, top - line - DESC_GAP)
        height = line + DESC_GAP + Height(item.desc, 10)
    end
    item.hit:SetSize(width, height)
    Put(item.hit, body, LEFT, top)
    item.line = line
    return height
end

-- Case à cocher du jeu (SettingsCheckboxTemplate, 30 x 29) ou la classique là où le client n'a pas
-- les images.
local function NewCheck(parent)
    if HasAtlas("checkbox-minimal") then
        local box = CreateFrame("CheckButton", nil, parent)
        box:SetSize(CHECK_W, CHECK_H)
        box:SetNormalTexture(Atlas(box, "ARTWORK", "checkbox-minimal", true))
        box:SetPushedTexture(Atlas(box, "ARTWORK", "checkbox-minimal", true))
        box:SetCheckedTexture(Atlas(box, "OVERLAY", "checkmark-minimal", true))
        local greyed = Atlas(box, "OVERLAY", "checkmark-minimal-disabled", true)
        if greyed then box:SetDisabledCheckedTexture(greyed) end
        return box
    end
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    return box
end
UI.NewCheck = NewCheck

-- spec : label, desc, get(), set(value), indent, enabled() -> bool, raison ; visible()
function Page:Checkbox(spec)
    local item = NewRow(self, spec)
    local box = NewCheck(self.body)
    Above(box, self.body)
    item.control = box
    table.insert(item.regions, box)
    box:SetScript("OnClick", function(b)
        local on = b:GetChecked() and true or false
        spec.set(on)
        if spec.changed then spec.changed(on) end
        self:Refresh()
    end)
    item.hit:SetScript("OnClick", function() if box:IsEnabled() then box:Click() end end)
    item.sync = function() box:SetChecked(spec.get() and true or false) end
    item.setEnabled = function(on) box:SetEnabled(on) end
    item.place = function(top, width) return PlaceRow(self, item, box, top, width, CONTROL_X, box:GetHeight()) end
    item.sync()
    return self:Add(item)
end

-- spec : label, desc, min, max, step, get(), set(value), format(value) -> texte
function Page:Slider(spec)
    local item = NewRow(self, spec)
    local body = self.body
    local format = spec.format or function(v) return tostring(math.floor(v + 0.5)) end
    local step = spec.step or 1
    -- (arrondi à la précision du pas : 0,05 x 24 donnerait 1,2000000000000002)
    local decimals = math.max(0, math.ceil(-math.log10(step) - 1e-9))
    local function Take(value)
        value = tonumber(("%." .. decimals .. "f"):format(math.floor(value / step + 0.5) * step))
        if value < spec.min then value = spec.min elseif value > spec.max then value = spec.max end
        if math.abs(value - (spec.get() or 0)) >= step / 2 then
            spec.set(value)
            if spec.changed then spec.changed(value) end
        end
        return value
    end
    local frame
    local ok, made = pcall(CreateFrame, "Frame", nil, body, "MinimalSliderWithSteppersTemplate")
    if ok and made and made.Init and MinimalSliderWithSteppersMixin and made.RegisterCallback then
        frame = made
        frame:SetWidth(SLIDER_W)
        local formatters = {}
        local labels = MinimalSliderWithSteppersMixin.Label
        if labels and labels.Right then formatters[labels.Right] = function(v) return format(v) end end
        frame:Init(spec.get(), spec.min, spec.max, math.floor((spec.max - spec.min) / step + 0.5), formatters)
        frame:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v) Take(v) end, frame)
        item.sync = function() frame:SetValue(spec.get()) end
        item.setEnabled = function(on) frame:SetEnabled(on) end
        item.slider = frame.Slider
    else
        frame = CreateFrame("Frame", nil, body)
        frame:SetSize(SLIDER_W, 20)
        local slider = CreateFrame("Slider", nil, frame, "UISliderTemplate")
        slider:SetSize(SLIDER_W - 50, 16)
        slider:SetOrientation("HORIZONTAL")
        slider:SetPoint("LEFT", frame, "LEFT", 0, 0)
        slider:SetMinMaxValues(spec.min, spec.max)
        slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local value = Font(frame, "GameFontHighlight")
        value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
        slider:SetScript("OnValueChanged", function(_, v) value:SetText(format(Take(v))) end)
        item.sync = function()
            slider:SetValue(spec.get())
            value:SetText(format(spec.get()))
        end
        item.setEnabled = function(on)
            if slider.SetEnabled then slider:SetEnabled(on) elseif on then slider:Enable() else slider:Disable() end
        end
        item.slider, item.value = slider, value
    end
    Above(frame, body)
    item.control = frame
    table.insert(item.regions, frame)
    item.place = function(top, width) return PlaceRow(self, item, frame, top, width, CONTROL_X, 20) end
    item.Take = Take
    item.sync()
    return self:Add(item)
end

local function Choices(spec)
    if type(spec.choices) == "function" then return spec.choices() end
    return spec.choices
end

local dropdowns = 0
-- spec : label, desc, choices ({ { value =, text = }, ... } ou une fonction qui les rend), get(), set(v)
function Page:Dropdown(spec)
    local item = NewRow(self, spec)
    local body = self.body
    local function TextOf(value)
        for _, choice in ipairs(Choices(spec) or {}) do
            if choice.value == value then return choice.text end
        end
        return tostring(value or "")
    end
    local function Choose(value)
        spec.set(value)
        if spec.changed then spec.changed(value) end
        self:Refresh()
    end
    item.Choose, item.TextOf = Choose, TextOf
    local control
    local ok, made = pcall(CreateFrame, "DropdownButton", nil, body, "WowStyle1DropdownTemplate")
    if ok and made and made.SetupMenu then
        control = made
        control:SetWidth(DROPDOWN_W)
        control:SetupMenu(function(_, root)
            for _, choice in ipairs(Choices(spec) or {}) do
                root:CreateRadio(choice.text, function() return spec.get() == choice.value end,
                    function() Choose(choice.value) end, choice.value)
            end
        end)
        item.sync = function() if control.GenerateMenu then control:GenerateMenu() end end
        item.setEnabled = function(on) control:SetEnabled(on) end
        item.offset = CONTROL_X
    else
        dropdowns = dropdowns + 1
        control = CreateFrame("Frame", "RouteXPSettingsDropdown" .. dropdowns, body, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(control, function(_, level)
            for _, choice in ipairs(Choices(spec) or {}) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = choice.text
                info.checked = spec.get() == choice.value
                info.func = function()
                    Choose(choice.value)
                    if CloseDropDownMenus then CloseDropDownMenus() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(control, DROPDOWN_W - 40) end
        item.sync = function() UIDropDownMenu_SetText(control, TextOf(spec.get())) end
        item.setEnabled = function(on)
            if on then UIDropDownMenu_EnableDropDown(control) else UIDropDownMenu_DisableDropDown(control) end
        end
        item.offset = CONTROL_X - 16
    end
    Above(control, body)
    item.control = control
    table.insert(item.regions, control)
    item.place = function(top, width) return PlaceRow(self, item, control, top, width, item.offset, 26) end
    item.sync()
    return self:Add(item)
end

-- Un bouton rouge du jeu, élargi à son texte (jamais sous 200), dans la colonne des contrôles.
-- spec : label (nom de la ligne, facultatif), text (texte du bouton), desc, onClick, width
function Page:Button(spec)
    local item = NewRow(self, spec)
    local button = CreateFrame("Button", nil, self.body, "UIPanelButtonTemplate")
    button:SetHeight(BUTTON_H)
    button:SetText(spec.text or spec.label)
    button:SetWidth(math.max(spec.width or BUTTON_W, (button:GetTextWidth() or 0) + BUTTON_PAD))
    button:SetScript("OnClick", function() spec.onClick(); self:Refresh() end)
    Above(button, self.body)
    item.control = button
    table.insert(item.regions, button)
    item.setEnabled = function(on) button:SetEnabled(on) end
    item.sync = spec.sync
    item.place = function(top, width) return PlaceRow(self, item, button, top, width, CONTROL_X, BUTTON_H) end
    return self:Add(item)
end

-- Le sélecteur de couleur du jeu (ColorPickerFrame), avec l'opacité si demandée : apply(couleur) à chaque
-- changement, et la couleur de départ si le joueur annule. Clients récents : SetupColorPickerAndShow ; anciens :
-- les champs func / opacityFunc / cancelFunc.
function UI.OpenColorPicker(color, opacity, apply)
    local picker = ColorPickerFrame
    if not picker then return end
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    local function Read()
        local nr, ng, nb = picker:GetColorRGB()
        local na = a
        if opacity then
            if picker.GetColorAlpha then na = picker:GetColorAlpha()
            elseif OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
        end
        return { nr, ng, nb, na }
    end
    local function Changed() apply(Read()) end
    local function Cancel() apply({ r, g, b, a }) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a, hasOpacity = opacity and true or false,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancel })
    else
        picker.func, picker.opacityFunc, picker.cancelFunc = Changed, Changed, Cancel
        picker.hasOpacity, picker.opacity = opacity and true or false, 1 - a
        picker:SetColorRGB(r, g, b)
        picker:Hide()
        picker:Show()
    end
end

-- Une couleur : une pastille dans la colonne des contrôles, et sa valeur en clair à côté ; cliquer (la pastille
-- ou la ligne) ouvre le sélecteur de couleur du jeu.
-- spec : label, desc, get() -> { r, g, b, a }, set({ r, g, b, a }), opacity (false : sans opacité)
function Page:Color(spec)
    local item = NewRow(self, spec)
    local body = self.body
    local swatch = CreateFrame("Button", nil, body)
    swatch:SetSize(38, 18)
    Flat(swatch, "BORDER", 0, 0, 0, 1):SetAllPoints(swatch)
    local back = Flat(swatch, "ARTWORK", 0.45, 0.45, 0.45, 1) -- (sous la couleur : son opacité se voit)
    back:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    local fill = swatch:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    local value = Font(body, "GameFontHighlightSmall", DESC)
    Above(swatch, body)
    item.control, item.fill, item.value = swatch, fill, value
    table.insert(item.regions, swatch)
    table.insert(item.regions, value)
    table.insert(item.fade, value)
    item.sync = function()
        local c = spec.get() or { 1, 1, 1, 1 }
        fill:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        local text = ("#%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
        if spec.opacity ~= false then text = text .. ("  %d %%"):format(math.floor((c[4] or 1) * 100 + 0.5)) end
        value:SetText(text)
    end
    local function Pick()
        UI.OpenColorPicker(spec.get() or { 1, 1, 1, 1 }, spec.opacity ~= false, function(c)
            spec.set(c)
            if spec.changed then spec.changed(c) end
            item.sync()
        end)
    end
    item.Pick = Pick
    swatch:SetScript("OnClick", Pick)
    item.hit:SetScript("OnClick", function() if swatch:IsEnabled() then Pick() end end)
    item.setEnabled = function(on) swatch:SetEnabled(on) end
    item.place = function(top, width)
        local height = PlaceRow(self, item, swatch, top, width, CONTROL_X, 18)
        value:ClearAllPoints()
        value:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        return height
    end
    item.sync()
    return self:Add(item)
end

-- Un cadre libre sur la page (hauteur fixe ou mesurée), aligné sur les titres de section.
function Page:Custom(frame, height, place)
    local body = self.body
    frame:SetParent(body)
    return self:Add({ kind = "custom", regions = { frame }, frame = frame, place = function(top, width)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", body, "TOPLEFT", LEFT + SECTION_X, top)
        if place then return place(frame, width - SECTION_X - BOX_RIGHT) end
        frame:SetWidth(width - SECTION_X - BOX_RIGHT)
        return type(height) == "function" and height() or height or frame:GetHeight()
    end })
end

-- Un écart vertical.
function Page:Space(height)
    return self:Add({ kind = "space", place = function() return height or 8 end })
end

-- Choix visuels -----------------------------------------------------------------------------------
-- Rien ne se choisit sur un nom seul : le sélecteur montre chaque choix tel qu'il apparaîtra, en grille d'icônes ou
-- en vignettes (un fond, une bordure, une barre, un texte dans sa police), avec des onglets par source, une recherche,
-- et en bas le choix survolé (sinon l'actuel), en grand, avec son nom. Un clic choisit et s'applique tout de suite ;
-- la fenêtre reste ouverte pour en essayer d'autres (Fermer, ou Échap).

-- Une icône se note par une chaîne, gardée telle quelle dans les réglages : « tex:<fichier ou numéro de fichier> »,
-- suivie de « :gauche:droite:haut:bas » pour n'en prendre qu'une partie, ou « atlas:<nom> ».
function UI.IconLook(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" then return nil end
    local atlas = value:match("^atlas:(.+)$")
    if atlas then return { atlas = atlas } end
    local body = value:match("^tex:(.+)$")
    if not body then return nil end
    local file, l, r, t, b = body:match("^(.-):([%d.]+):([%d.]+):([%d.]+):([%d.]+)$")
    file = file or body
    return { texture = tonumber(file) or file, coords = l and { tonumber(l), tonumber(r), tonumber(t), tonumber(b) } or nil }
end

function UI.IconValue(look)
    if type(look) ~= "table" then return nil end
    if look.atlas then return "atlas:" .. look.atlas end
    if not look.texture then return nil end
    local value = "tex:" .. tostring(look.texture)
    local c = look.coords
    if c then value = value .. (":%s:%s:%s:%s"):format(c[1], c[2], c[3], c[4]) end
    return value
end

-- Pose une icône (valeur « tex: »/« atlas: », ou apparence décodée) sur une texture ; false si elle n'existe pas ici.
function UI.SetIcon(texture, value)
    local look = UI.IconLook(value)
    if not look then return false end
    if look.atlas then
        if not HasAtlas(look.atlas) then return false end
        texture:SetAtlas(look.atlas)
        return true
    end
    if not look.texture then return false end
    -- (SetTexture rend false quand le fichier n'existe pas)
    if texture:SetTexture(look.texture) == false then return false end
    local c = look.coords
    if c then texture:SetTexCoord(c[1], c[2], c[3], c[4]) else texture:SetTexCoord(0, 1, 0, 1) end
    return true
end

-- L'icône dans un texte (|T...|t ou |A...|a).
function UI.IconMarkup(value, size)
    local look = UI.IconLook(value)
    size = size or 16
    if not look then return "" end
    if look.atlas then return ("|A:%s:%d:%d|a"):format(look.atlas, size, size) end
    local c = look.coords
    if c then
        return ("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t"):format(tostring(look.texture), size, size, math.floor(c[1] * 64),
            math.floor(c[2] * 64), math.floor(c[3] * 64), math.floor(c[4] * 64))
    end
    return ("|T%s:%d:%d|t"):format(tostring(look.texture), size, size)
end

-- Toutes les icônes de sorts et d'objets du jeu (celles de la fenêtre des macros), relevées une seule fois.
local allIcons
function UI.AllIcons()
    if allIcons then return allIcons end
    local raw, seen = {}, {}
    for _, fill in ipairs({ GetLooseMacroIcons, GetLooseMacroItemIcons, GetMacroIcons, GetMacroItemIcons }) do
        if type(fill) == "function" then pcall(fill, raw) end
    end
    allIcons = {}
    for _, icon in ipairs(raw) do
        local id = tonumber(icon)
        local texture = id or ("Interface\\Icons\\" .. tostring(icon))
        local key = tostring(texture):lower()
        if not seen[key] then
            seen[key] = true
            allIcons[#allIcons + 1] = { value = "tex:" .. tostring(texture), name = (not id) and tostring(icon) or nil }
        end
    end
    return allIcons
end

-- Les onglets du sélecteur d'icônes : extra (des choix propres à l'addon, en tête : « par défaut »...), puis toutes les
-- icônes du jeu. IconCatalog.lua (chargé après) la remplace : icônes des addons de carte et du jeu par thème.
function UI.IconSources(extra, extraText)
    local sources = {}
    if extra then sources[#sources + 1] = { key = "addon", text = extraText or "Proposées", entries = extra } end
    sources[#sources + 1] = { key = "all", text = "Toutes les icônes (sorts, objets)", entries = UI.AllIcons, huge = true }
    return sources
end

local PICK_W, PICK_H = 584, 572
local PICK_SIDE, PICK_TOP, PICK_BOTTOM, PICK_BAR = 18, 96, 86, 16
-- Beaucoup d'onglets : leur liste à gauche, comme celle des catégories des réglages du jeu (Blizzard_CategoryList :
-- en-têtes de 30 à image Options_CategoryHeader_<n> et nom à 20 ; lignes de 175 x 20, nom à 36, en or, blanc sur
-- Options_List_Active quand c'est l'onglet ouvert, Options_List_Hover au survol).
local SIDE_W, SIDE_GAP, SIDE_ROW, SIDE_HEAD, SIDE_SPACE = 175, 12, 20, 30, 8
local CELL_EDGE = { 0.32, 0.32, 0.32, 1 }
local LAYOUTS = {
    icons = { w = 36, h = 36, gap = 4, preview = { 44, 44 }, row = { 30, 30 } },
    samples = { w = 164, h = 58, gap = 9, preview = { 164, 40 }, row = { 124, 26 } },
}

local function EntriesOf(source)
    local entries = source and source.entries
    if type(entries) == "function" then entries = entries() end
    return entries or {}
end

-- L'entrée d'une valeur dans les sources, et sa source (sans parcourir la liste de toutes les icônes : trop longue).
local function FindEntry(sources, value)
    if value == nil then return nil end
    for _, source in ipairs(sources or {}) do
        if not source.huge then
            for _, entry in ipairs(EntriesOf(source)) do
                if entry.value == value then return entry, source end
            end
        end
    end
end

local function NameOf(sources, value)
    local entry = FindEntry(sources, value)
    if entry and entry.name then return entry.name end
    local look = UI.IconLook(value)
    if look and look.atlas then return look.atlas end
    if look and type(look.texture) == "number" then return "Icône n° " .. look.texture end
    if look and look.texture then return (tostring(look.texture):match("([^\\/]+)$")) or tostring(look.texture) end
    return tostring(value or "")
end
UI.ChoiceName = NameOf

-- Une case : un fond sombre et un cadre fin (or : le choix actuel), l'icône, ou la vignette d'un choix.
local function NewCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    local back = Flat(cell, "BACKGROUND", 0, 0, 0, 0.5)
    back:SetAllPoints(cell)
    cell.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = Flat(cell, "BORDER", CELL_EDGE[1], CELL_EDGE[2], CELL_EDGE[3], 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(1)
            edge:SetPoint(side .. "LEFT", cell, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", cell, side .. "RIGHT", 0, 0)
        else
            edge:SetWidth(1)
            edge:SetPoint("TOP" .. side, cell, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, cell, "BOTTOM" .. side, 0, 0)
        end
        table.insert(cell.edges, edge)
    end
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    local ok, sample = pcall(CreateFrame, "Frame", nil, cell, "BackdropTemplate")
    cell.sample = ok and sample or CreateFrame("Frame", nil, cell)
    cell.bar = CreateFrame("StatusBar", nil, cell)
    cell.bar:SetMinMaxValues(0, 1)
    cell.bar:SetValue(0.65)
    cell.text = Font(cell, "GameFontHighlight")
    cell.text:SetJustifyH("CENTER")
    cell.text:SetJustifyV("MIDDLE")
    cell.label = Font(cell, "GameFontHighlightSmall", DESC)
    cell.label:SetJustifyH("CENTER")
    if cell.label.SetWordWrap then cell.label:SetWordWrap(false) end
    Flat(cell, "HIGHLIGHT", 1, 1, 1, 0.14):SetAllPoints(cell)
    return cell
end

local function Edge(cell, color)
    for _, edge in ipairs(cell.edges) do edge:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
end

-- Dessine une entrée dans une case. « icons » : son icône (entry.look : l'aperçu d'un choix spécial comme « par
-- défaut ») ; « samples » : la vignette que dessine render(case, entrée), en montrant case.sample (un cadre à fond et
-- bordure), case.bar (une barre) ou case.text (un texte), avec son nom dessous si named.
local function Draw(cell, entry, layout, render, named)
    cell.entry = entry
    cell.icon:Hide()
    cell.sample:Hide()
    cell.bar:Hide()
    cell.text:Hide()
    cell.label:Hide()
    if layout == "samples" then
        local below = named and 16 or 0
        for _, part in ipairs({ cell.sample, cell.bar, cell.text }) do
            part:ClearAllPoints()
            part:SetPoint("TOPLEFT", cell, "TOPLEFT", 3, -3)
            part:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3 + below)
        end
        if named then
            cell.label:ClearAllPoints()
            cell.label:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 3, 3)
            cell.label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
            cell.label:SetText(entry.name or tostring(entry.value or ""))
            cell.label:Show()
        end
        if render then
            local ok, err = pcall(render, cell, entry)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    else
        cell.icon:ClearAllPoints()
        cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 3, -3)
        cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
        if not UI.SetIcon(cell.icon, entry.look or entry.value) then cell.icon:SetTexture(nil) end
        cell.icon:Show()
    end
end
UI.DrawChoice = Draw

local Picker = {}
Picker.__index = Picker
UI.PickerMixin = Picker
local picker

local function NewPicker()
    local p = setmetatable({ cells = {}, tabs = {}, offset = 0, list = {}, entries = {}, visibleCells = 0 }, Picker)
    local frame = NewShell("RouteXPPicker", "", PICK_W, PICK_H)
    frame:SetFrameStrata("DIALOG")
    p.frame = frame
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(22)
    p.row = row
    local ok, search = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not (ok and search) then search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate") end
    search:SetSize(240, 20)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() p:Filter() end)
    p.search = search
    p.count = Font(frame, "GameFontHighlightSmall", DESC)
    p.count:SetJustifyH("RIGHT")
    p.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PICK_SIDE - 4, -66)
    local grid = CreateFrame("Frame", nil, frame)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta) p:ScrollTo(p.offset - delta) end)
    p.grid = grid
    p.empty = Font(grid, "GameFontHighlight", DESC)
    p.empty:SetJustifyH("CENTER")
    p.empty:SetPoint("CENTER", grid, "CENTER", 0, 0)
    p.empty:SetText("Aucun résultat.")
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", frame, "TOPLEFT", PICK_SIDE - 6, -60)
    side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PICK_SIDE - 6, PICK_BOTTOM - 8)
    side:SetWidth(SIDE_W)
    side:Hide()
    p.side, p.sideItems, p.sideHeads = side, {}, {}
    p:BuildBar()
    local preview = NewCell(frame)
    preview:EnableMouse(false)
    p.preview = preview
    p.previewName = Font(frame, "GameFontNormal", GOLD)
    p.previewNote = Font(frame, "GameFontHighlightSmall", DESC)
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(DEFAULTS_W, BUTTON_H)
    close:SetText(CLOSE or "Fermer")
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PICK_SIDE, 18)
    close:SetScript("OnClick", function() frame:Hide() end)
    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(DEFAULTS_W, BUTTON_H)
    reset:SetText(SETTINGS_DEFAULTS or "Par défaut")
    reset:SetPoint("RIGHT", close, "LEFT", -8, 0)
    reset:SetScript("OnClick", function()
        if p.spec and p.spec.default ~= nil then p:Choose({ value = p.spec.default }) end
    end)
    p.close, p.reset = close, reset
    return p
end

-- La barre de défilement fine, à droite de la grille (comme celle des pages).
function Picker:BuildBar()
    local bar = CreateFrame("Frame", nil, self.frame)
    bar:SetWidth(8)
    bar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PICK_SIDE + 4, -PICK_TOP)
    bar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -PICK_SIDE + 4, PICK_BOTTOM)
    bar:Hide()
    local track = Atlas(bar, "BACKGROUND", "!minimal-scrollbar-track-middle", false)
    if track then track:SetAllPoints(bar) else Flat(bar, "BACKGROUND", 1, 1, 1, 0.06):SetAllPoints(bar) end
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(8)
    thumb:SetHeight(20)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    local face = Atlas(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-middle", false)
    if not face then face = Flat(thumb, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], 0.45) end
    face:SetAllPoints(thumb)
    face:SetAlpha(0.8)
    local p = self
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / ((bar:GetEffectiveScale()) or 1)
    end
    local function Release()
        p.dragging = false
        bar:SetScript("OnUpdate", nil)
        face:SetAlpha(0.8)
    end
    thumb:SetScript("OnEnter", function() face:SetAlpha(1) end)
    thumb:SetScript("OnLeave", function() if not p.dragging then face:SetAlpha(0.8) end end)
    thumb:SetScript("OnMouseDown", function()
        p.grab = (thumb:GetTop() or 0) - CursorY()
        p.dragging = true
        bar:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then Release() return end
            local travel = (bar:GetHeight() or 0) - (thumb:GetHeight() or 0)
            if travel <= 0 then return end
            local at = ((bar:GetTop() or 0) - (CursorY() + p.grab)) / travel
            p:ScrollTo(math.floor(math.max(0, math.min(1, at)) * (p.maxOffset or 0) + 0.5))
        end)
    end)
    thumb:SetScript("OnMouseUp", Release)
    thumb:SetScript("OnHide", Release)
    self.bar, self.thumb = bar, thumb
end

function Picker:UpdateBar()
    local maxOffset = self.maxOffset or 0
    if maxOffset <= 0 then self.bar:Hide() return end
    self.bar:Show()
    local height = self.bar:GetHeight() or 1
    local thumbHeight = math.max(20, math.floor(height * self.rows / (maxOffset + self.rows)))
    self.thumb:SetHeight(thumbHeight)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.bar, "TOP", 0, -math.floor((height - thumbHeight) * self.offset / maxOffset))
end

-- Les cases de la grille (autant que la place en laisse) et l'aperçu du bas, pour une disposition.
function Picker:Layout(layout)
    local L = LAYOUTS[layout] or LAYOUTS.icons
    local side = self.sideMode and (SIDE_W + SIDE_GAP) or 0
    local width = PICK_W + side
    local left = PICK_SIDE + side
    local frame = self.frame
    frame:SetWidth(width)
    self.side:SetShown(self.sideMode and true or false)
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 8, -62)
    self.grid:ClearAllPoints()
    self.grid:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -PICK_TOP)
    self.grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PICK_SIDE - PICK_BAR, PICK_BOTTOM)
    -- (l'encart sombre du cadre du jeu, autour de la grille et de sa barre de défilement)
    if frame.Inset then
        frame.Inset:ClearAllPoints()
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", left - 8, -PICK_TOP + 8)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PICK_SIDE + 8, PICK_BOTTOM - 8)
    end
    local gridW = width - left - PICK_SIDE - PICK_BAR
    local gridH = PICK_H - PICK_TOP - PICK_BOTTOM
    self.cols = math.max(1, math.floor((gridW + L.gap) / (L.w + L.gap)))
    self.rows = math.max(1, math.floor((gridH + L.gap) / (L.h + L.gap)))
    local x0 = math.floor((gridW - (self.cols * (L.w + L.gap) - L.gap)) / 2)
    local n = self.cols * self.rows
    for i = 1, math.max(n, #self.cells) do
        local cell = self.cells[i]
        if i <= n then
            if not cell then
                cell = NewCell(self.grid)
                cell:SetScript("OnClick", function(c) if c.entry then self:Choose(c.entry) end end)
                cell:SetScript("OnEnter", function(c)
                    self.hover = c.entry
                    self:ShowPreview()
                    if c.entry then Tip(c, c.entry.name or NameOf(self.spec and self.spec.sources, c.entry.value), "Clic : choisir.") end
                end)
                cell:SetScript("OnLeave", function()
                    self.hover = nil
                    self:ShowPreview()
                    if GameTooltip then GameTooltip:Hide() end
                end)
                cell:EnableMouseWheel(true)
                cell:SetScript("OnMouseWheel", function(_, delta) self:ScrollTo(self.offset - delta) end)
                self.cells[i] = cell
            end
            cell:SetSize(L.w, L.h)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", self.grid, "TOPLEFT", x0 + ((i - 1) % self.cols) * (L.w + L.gap),
                -math.floor((i - 1) / self.cols) * (L.h + L.gap))
        elseif cell then
            cell.entry = nil
            cell:Hide()
        end
    end
    self.visibleCells = n
    self.preview:SetSize(L.preview[1], L.preview[2])
    self.preview:ClearAllPoints()
    self.preview:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", PICK_SIDE + 4, 20)
    self.previewName:ClearAllPoints()
    self.previewName:SetPoint("TOPLEFT", self.preview, "TOPRIGHT", 12, -2)
    self.previewName:SetPoint("RIGHT", self.reset, "LEFT", -12, 0)
    self.previewNote:ClearAllPoints()
    self.previewNote:SetPoint("TOPLEFT", self.previewName, "BOTTOMLEFT", 0, -4)
    self.previewNote:SetPoint("RIGHT", self.reset, "LEFT", -12, 0)
end

function Picker:PaintTab(tab, hover)
    local color = tab.key == self.sourceKey and TAB_COLORS.active or (hover and TAB_COLORS.hover or TAB_COLORS.normal)
    tab.text:SetTextColor(color[1], color[2], color[3])
end

-- Les onglets des sources, en texte, centrés sous le titre (cachés s'il n'y a qu'une source).
function Picker:MakeTabs(sources)
    for i, source in ipairs(sources) do
        local tab = self.tabs[i]
        if not tab then
            tab = CreateFrame("Button", nil, self.row)
            tab:SetHeight(22)
            tab.text = Font(tab, "GameFontNormal")
            tab.text:SetJustifyH("CENTER")
            tab.text:SetJustifyV("MIDDLE")
            tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
            tab:SetScript("OnEnter", function(t) self:PaintTab(t, true) end)
            tab:SetScript("OnLeave", function(t) self:PaintTab(t, false) end)
            tab:SetScript("OnClick", function(t)
                self:Select(t.key)
            end)
            self.tabs[i] = tab
        end
        tab.key = source.key
        tab.text:SetText(source.text)
        tab:SetWidth(math.ceil((tab.text:GetStringWidth() or 0) + TAB_PAD * 2))
        tab:Show()
    end
    for i = #sources + 1, #self.tabs do self.tabs[i]:Hide() end
    local total = 0
    for i = 1, #sources do total = total + self.tabs[i]:GetWidth() + (i > 1 and TAB_GAP or 0) end
    self.row:SetWidth(math.max(1, total))
    self.row:ClearAllPoints()
    self.row:SetPoint("TOP", self.frame, "TOP", 0, TAB_TOP)
    local x = 0
    for i = 1, #sources do
        self.tabs[i]:ClearAllPoints()
        self.tabs[i]:SetPoint("LEFT", self.row, "LEFT", x, 0)
        x = x + self.tabs[i]:GetWidth() + TAB_GAP
    end
    self.row:SetShown(#sources > 1)
end

-- Une ligne de la liste de gauche, et sa couleur : celle de l'onglet ouvert (sauf pendant une recherche, qui
-- parcourt tous les onglets), survolée, ou au repos.
function Picker:PaintSide(item)
    local open = item.key == self.sourceKey and not self.searching
    item.text:SetFontObject(open and "GameFontHighlight" or "GameFontNormal")
    local atlas = open and "Options_List_Active" or (item.over and "Options_List_Hover")
    if atlas and HasAtlas(atlas) then
        item.back:SetAtlas(atlas, true)
        item.back:Show()
    elseif atlas then
        item.back:SetColorTexture(1, 1, 1, open and 0.12 or 0.06)
        item.back:SetAllPoints(item)
        item.back:Show()
    else
        item.back:Hide()
    end
end

function Picker:SideItem(i)
    local item = self.sideItems[i]
    if item then return item end
    item = CreateFrame("Button", nil, self.side)
    item:SetSize(SIDE_W, SIDE_ROW)
    item.back = item:CreateTexture(nil, "BACKGROUND")
    item.back:SetPoint("CENTER", item, "CENTER", 0, 0)
    item.text = item:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    item.text:SetJustifyH("LEFT")
    item.text:SetPoint("TOPLEFT", item, "TOPLEFT", 36, 1)
    item.text:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 1)
    item:SetScript("OnEnter", function(b) b.over = true self:PaintSide(b) end)
    item:SetScript("OnLeave", function(b) b.over = false self:PaintSide(b) end)
    item:SetScript("OnClick", function(b)
        if self.search:GetText() ~= "" then self.search:SetText("") end
        self:Select(b.key)
    end)
    self.sideItems[i] = item
    return item
end

function Picker:SideHead(i)
    local head = self.sideHeads[i]
    if head then return head end
    head = CreateFrame("Frame", nil, self.side)
    head:SetSize(SIDE_W, SIDE_HEAD)
    head.back = head:CreateTexture(nil, "ARTWORK")
    head.back:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    head.text = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    head.text:SetJustifyH("LEFT")
    head.text:SetPoint("LEFT", head, "LEFT", 20, -1)
    self.sideHeads[i] = head
    return head
end

-- La liste des onglets à gauche : ceux sans groupe en tête, puis chaque groupe sous son en-tête ; un onglet facultatif
-- sans rien à montrer (l'addon n'est pas installé) n'y est pas.
function Picker:MakeSide(sources)
    for _, item in ipairs(self.sideItems) do item:Hide() end
    for _, head in ipairs(self.sideHeads) do head:Hide() end
    local y, items, heads, group = 0, 0, 0, nil
    for _, source in ipairs(sources) do
        if not source.optional or #EntriesOf(source) > 0 then
            if source.group and source.group ~= group then
                group = source.group
                heads = heads + 1
                if y > 0 then y = y + SIDE_SPACE end
                local head = self:SideHead(heads)
                local atlas = "Options_CategoryHeader_" .. math.min(heads, 2)
                if HasAtlas(atlas) then head.back:SetAtlas(atlas, true) head.back:Show() else head.back:Hide() end
                head.text:SetText(source.groupText or group)
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", self.side, "TOPLEFT", 0, -y)
                head:Show()
                y = y + SIDE_HEAD
            end
            items = items + 1
            local item = self:SideItem(items)
            item.key = source.key
            item.text:SetText(source.text)
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", self.side, "TOPLEFT", 0, -y)
            item:Show()
            y = y + SIDE_ROW
        end
    end
end

function Picker:PaintTabs()
    for _, tab in ipairs(self.tabs) do if tab:IsShown() then self:PaintTab(tab, false) end end
    for _, item in ipairs(self.sideItems) do if item:IsShown() then self:PaintSide(item) end end
end

function Picker:Select(key)
    local sources = self.spec and self.spec.sources or {}
    local source = sources[1]
    for _, s in ipairs(sources) do if s.key == key then source = s end end
    if not source then return end
    self.sourceKey = source.key
    self.entries = EntriesOf(source)
    self.offset = 0
    self:Filter(true)
end

-- Ce que montre la grille : la source choisie, réduite à ce qui contient le texte cherché (nom ou fichier). reveal :
-- défile jusqu'au choix actuel.
function Picker:Filter(reveal)
    if not self.spec then return end
    local text = strtrim(self.search:GetText() or ""):lower()
    local list = self.entries or {}
    -- (onglets en liste : la recherche les parcourt tous, sauf celui de toutes les icônes du jeu, sans noms, s'il
    -- n'est pas ouvert)
    self.searching = text ~= "" and self.sideMode or false
    if self.searching then
        local pool, seen = {}, {}
        for _, source in ipairs(self.spec.sources or {}) do
            if not source.huge or source.key == self.sourceKey then
                for _, entry in ipairs(EntriesOf(source)) do
                    if entry.value == nil or not seen[entry.value] then
                        if entry.value ~= nil then seen[entry.value] = true end
                        pool[#pool + 1] = entry
                    end
                end
            end
        end
        list = pool
    end
    self:PaintTabs()
    if text ~= "" then
        local found = {}
        for _, entry in ipairs(list) do
            local hay = entry.search
            if not hay then
                hay = ((entry.name or "") .. " " .. tostring(entry.value or "")):lower()
                entry.search = hay
            end
            if hay:find(text, 1, true) then found[#found + 1] = entry end
        end
        list = found
    end
    self.list = list
    self.count:SetText(#list .. " choix" .. (self.searching and " (tous les onglets)" or ""))
    local offset = 0
    if reveal then
        for i, entry in ipairs(list) do
            if entry.value == self.current then
                offset = math.floor((i - 1) / self.cols) - math.floor(self.rows / 2)
                break
            end
        end
    end
    self:ScrollTo(offset)
end

function Picker:ScrollTo(offset)
    self.maxOffset = math.max(0, math.ceil(#self.list / self.cols) - self.rows)
    self.offset = math.max(0, math.min(self.maxOffset, math.floor(offset or 0)))
    self:Update()
end

function Picker:Update()
    local spec = self.spec
    if not spec then return end
    for i = 1, self.visibleCells do
        local cell = self.cells[i]
        local entry = self.list[self.offset * self.cols + i]
        if entry then
            Draw(cell, entry, spec.layout or "icons", spec.render, true)
            Edge(cell, entry.value == self.current and GOLD or CELL_EDGE)
            cell:Show()
        else
            cell.entry = nil
            cell:Hide()
        end
    end
    self.empty:SetShown(#self.list == 0)
    self:UpdateBar()
    self:ShowPreview()
end

-- En bas : le choix survolé, sinon l'actuel, en grand, avec son nom.
function Picker:ShowPreview()
    local spec = self.spec
    if not spec then return end
    local entry, current = self.hover, false
    if not entry then
        current = true
        entry = FindEntry(spec.sources, self.current) or { value = self.current }
    end
    if entry.value == nil and not entry.look then
        self.preview:Hide()
        self.previewName:SetText("")
    else
        Draw(self.preview, entry, spec.layout or "icons", spec.render, false)
        Edge(self.preview, current and GOLD or CELL_EDGE)
        self.preview:Show()
        self.previewName:SetText(entry.name or NameOf(spec.sources, entry.value))
    end
    self.previewNote:SetText(current and "Choix actuel." or "Clic : choisir (le changement se voit tout de suite).")
end

function Picker:Choose(entry)
    if not (self.spec and entry) then return end
    self.current = entry.value
    if self.spec.set then self.spec.set(entry.value) end
    self:Update()
end

-- La case de la grille qui montre une valeur (après avoir choisi son onglet et défilé jusqu'à elle).
function Picker:CellFor(value)
    for i, entry in ipairs(self.list) do
        if entry.value == value then
            self:ScrollTo(math.floor((i - 1) / self.cols))
            return self.cells[i - self.offset * self.cols]
        end
    end
end

function Picker:Open(spec)
    self.spec = spec
    self.hover = nil
    self.current = spec.get and spec.get()
    self.entries, self.list = {}, {}
    SetShellTitle(self.frame, spec.title or "")
    local sources = spec.sources or {}
    local grouped = #sources > 4
    for _, source in ipairs(sources) do if source.group then grouped = true end end
    self.sideMode = grouped
    self:Layout(spec.layout or "icons")
    if grouped then
        self:MakeTabs({})
        self:MakeSide(sources)
    else
        self:MakeSide({})
        self:MakeTabs(sources)
    end
    self.reset:SetShown(spec.default ~= nil)
    self.search:SetText("")
    -- l'onglet où se trouve le choix actuel (une icône de la liste complète : son onglet), sinon le premier
    local _, where = FindEntry(spec.sources, self.current)
    if not where then
        local look = UI.IconLook(self.current)
        for _, source in ipairs(spec.sources or {}) do if source.huge and look and look.texture then where = source end end
    end
    self.frame:Show()
    if self.frame.Raise then self.frame:Raise() end
    self:Select((where or (spec.sources or {})[1] or {}).key)
end

-- Ouvre le sélecteur. spec : title, layout (« icons » ou « samples »), sources = { { key, text, entries (liste ou
-- fonction) de { value, name, look }, huge }, ... }, get(), set(valeur), default (valeur du bouton « Par défaut »),
-- render(case, entrée) (vignettes).
function UI.Pick(spec)
    picker = picker or NewPicker()
    picker:Open(spec)
    return picker
end
function UI.Picker() return picker end

-- Un choix visuel dans une ligne : l'aperçu du choix actuel dans la colonne des contrôles (un clic ouvre le
-- sélecteur), et son nom à côté.
-- spec : label, desc, get(), set(valeur), layout (« icons » ou « samples »), sources (onglets) ou entries (une seule
-- liste), render(case, entrée) (vignettes), default, title (titre du sélecteur), indent, enabled, visible, changed
function Page:Visual(spec)
    local item = NewRow(self, spec)
    local body = self.body
    local layout = spec.layout or "icons"
    local sources = spec.sources or { { key = "list", text = spec.label or "", entries = spec.entries } }
    local L = LAYOUTS[layout] or LAYOUTS.icons
    local cell = NewCell(body)
    cell:SetSize(L.row[1], L.row[2])
    Above(cell, body)
    local value = Font(body, "GameFontHighlightSmall", DESC)
    if value.SetWordWrap then value:SetWordWrap(false) end
    item.control, item.value, item.sources = cell, value, sources
    table.insert(item.regions, cell)
    table.insert(item.regions, value)
    table.insert(item.fade, value)
    item.sync = function()
        local v = spec.get()
        Draw(cell, FindEntry(sources, v) or { value = v }, layout, spec.render, false)
        value:SetText(NameOf(sources, v))
    end
    local function Open()
        return UI.Pick({ title = spec.title or spec.label, layout = layout, sources = sources, render = spec.render,
            default = spec.default, get = spec.get, set = function(v)
                spec.set(v)
                if spec.changed then spec.changed(v) end
                self:Refresh()
            end })
    end
    item.Open = Open
    cell:SetScript("OnClick", Open)
    cell:SetScript("OnEnter", function() Tip(cell, spec.label, "Clic : voir tous les choix et en choisir un.") end)
    cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    item.hit:SetScript("OnClick", function() if cell:IsEnabled() then Open() end end)
    item.setEnabled = function(on)
        cell:SetEnabled(on)
        cell:SetAlpha(on and 1 or DIMMED)
    end
    item.place = function(top, width)
        local height = PlaceRow(self, item, cell, top, width, CONTROL_X, L.row[2])
        value:ClearAllPoints()
        value:SetPoint("LEFT", cell, "RIGHT", 10, 0)
        value:SetWidth(math.max(60, LEFT + width - BOX_RIGHT - (self:Middle() + CONTROL_X + L.row[1] + 10)))
        return height
    end
    item.sync()
    return self:Add(item)
end

-- Une icône (Page:Visual en grille d'icônes). spec.extra : des choix propres à l'addon, en tête (onglet extraText) ;
-- spec.tags : les thèmes de ce qui se règle (« rare treasure »...), pour l'onglet « Suggestions » (IconCatalog.lua).
function Page:Icon(spec)
    spec.layout = "icons"
    spec.sources = spec.sources or UI.IconSources(spec.extra, spec.extraText, spec.tags)
    return self:Visual(spec)
end

return UI
