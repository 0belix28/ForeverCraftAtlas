-- Window.lua : la fenêtre de ForeverCraftAtlas, dans le cadre des fenêtres du jeu (ButtonFrameTemplate).
-- En haut : afficher toutes les recettes, les apprises ou les non apprises ; le
-- tri ; seulement les métiers du personnage ; une recherche. À gauche, le type d'objet créé (équipement par
-- emplacement, armes par genre, consommables par recharge commune...) et les métiers ; à droite, leurs recettes :
-- « <coût> (<+/- bénéfice>) » et, dessous, le bénéfice par seconde de fabrication, les points de compétence au niveau
-- du personnage, et pour une recette non apprise comment l'apprendre (l'icône du parchemin montre son infobulle et où
-- le trouver) ; en dessous, les icônes des composants et combien il en faut (au survol : leur infobulle et leur prix).
-- Les prix (relevés en jeu, sinon ForeverExchange) se montrent avec ce sur quoi ils reposent : combien l'objet créé a
-- d'offres et son évolution sur 7 jours, combien de composants sont en vente sur ton royaume. « Fabrications » :
-- les prix de plusieurs (les composants aux offres les moins chères de l'hôtel des ventes, une à une ; « ~ » devant
-- un coût estimé), et les nombres de composants sous chaque recette pour toutes. Une recette dont le jeu n'a pas les
-- objets n'est pas montrée (ns.RecipeReady) : elle arrive avec eux, ou jamais si le serveur ne les a pas ; ni celle
-- dont un composant ne s'achète pas (ns.RecipeBuyable : pas en vente au dernier relevé de l'hôtel des ventes, et aucun
-- marchand ne le vend).
-- Sur chaque recette, l'étoile la met en favori (la case « Favoris », à gauche, ne montre qu'elles) et « + Wishlist »
-- l'ajoute à la wishlist (Wishlist.lua). Onglets du bas : « Recettes », « XP Road » (Route.lua) et « Wishlist » (ce
-- qu'il faut acheter, le coût et le bénéfice, puis les achats confirmés, Purchase.lua).
local _, ns = ...
local UI = ns.SettingsKit
local PX = ns.Prices

local W, H = 980, 660
local INSET_TOP, INSET_BOTTOM = 98, 28
local PROF_W, PROF_ROW_H, ROW_H = 190, 24, 74
local TYPE_H = 126          -- type d'objet, seuil de bénéfice, niveau simulé, « Favoris », au-dessus des métiers
local REAGENTS = 8          -- icônes de composants par ligne
local REAGENT_SIZE = 20
local LIST_H = H - INSET_TOP - INSET_BOTTOM - 12
local GREY = { 0.62, 0.62, 0.62 }

local P = CreateFrame("Frame", "ForeverCraftAtlasFrame", UIParent, "ButtonFrameTemplate")
P:SetSize(W, H)
P:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
-- Rangée parmi les fenêtres du jeu (personnage, sacs, hôtel des ventes, métiers : strate MEDIUM, premier plan) : un
-- clic sur une autre fenêtre la fait passer devant ; un clic sur celle-ci ou son ouverture la remet devant (OnShow).
P:SetFrameStrata("MEDIUM")
P:SetToplevel(true)
-- Elle peut sortir de l'écran, comme avec BlizzMove, sauf une bande de 40 points qui reste toujours visible (pour la
-- rattraper) : le jeu la garde dans l'écran (SetClampedToScreen), mais réduite à cette bande (SetClampRectInsets).
local VISIBLE = 40
local function Offscreen(frame)
    if not frame.SetClampRectInsets then return end
    local w, h = math.max(0, frame:GetWidth() - VISIBLE), math.max(0, frame:GetHeight() - VISIBLE)
    frame:SetClampRectInsets(w, -w, -h, h)
end
P:SetClampedToScreen(true)
Offscreen(P)
P:HookScript("OnSizeChanged", Offscreen)
P:SetMovable(true)
P:EnableMouse(true)
P:RegisterForDrag("LeftButton")
P:SetScript("OnDragStart", function(self) self:StartMoving() end)
P:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if point then ns.Set("point", { point, relPoint, x, y }) end
end)
P:Hide()
if P.SetTitle then P:SetTitle("ForeverCraftAtlas : recettes") end
if P.SetPortraitToAsset then P:SetPortraitToAsset("Interface\\Icons\\INV_Scroll_04") end
if UISpecialFrames then table.insert(UISpecialFrames, "ForeverCraftAtlasFrame") end -- (Échap la ferme)
ns.window = P

local function Font(parent, template, color)
    local fs = parent:CreateFontString(nil, "ARTWORK", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function Tip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Les filtres du haut -------------------------------------------------------------------------------------------------
local function Dropdown(label, key, width, choices, x, y, anchor, tip)
    local text = Font(P, "GameFontNormal")
    if anchor then text:SetPoint("LEFT", anchor, "RIGHT", 22, 0) else text:SetPoint("TOPLEFT", P, "TOPLEFT", x, y - 4) end
    text:SetText(label)
    local menu = CreateFrame("DropdownButton", nil, P, "WowStyle1DropdownTemplate")
    menu:SetPoint("LEFT", text, "RIGHT", 10, 0)
    menu:SetWidth(width)
    menu:SetupMenu(function(_, root)
        for _, c in ipairs(choices) do
            root:CreateRadio(c.text, function() return ns.Get(key) == c.value end, function() ns.Set(key, c.value) end, c.value)
        end
    end)
    menu.key = key
    Tip(menu, label, tip)
    return menu, text
end

local ROW1, ROW2 = -30, -62
local show, showText = Dropdown("Afficher", "show", 150, {
    { value = "all", text = "Toutes les recettes" }, { value = "learned", text = "Les apprises" },
    { value = "unlearned", text = "Les non apprises" } }, 66, ROW1, nil,
    "Toutes les recettes des métiers, seulement celles que le personnage connaît, ou seulement les autres.")
-- (« Bénéfice » : en % du coût, à l'hôtel des ventes ou au marchand selon la case ; Recipes.lua)
local sort, sortText = Dropdown("Trier par", "sort", 170, {
    { value = "profit", text = "Bénéfice" },
    { value = "xp", text = "Le mieux pour l'xp" }, { value = "cost", text = "Coût" },
    { value = "skillup", text = "Points de compétence" }, { value = "level", text = "Niveau requis" },
    { value = "name", text = "Nom" } }, nil, nil, show, "L'ordre des recettes. « Bénéfice » : ce qui rapporte le plus "
        .. "par rapport à l'investissement d'abord, le bénéfice en % du coût des composants (2 po de bénéfice pour 1 po "
        .. "de composants, +200 %, passent devant 5 po pour 20 po, +25 %) ; à l'hôtel des ventes (prix toujours relevé "
        .. "en jeu, moins la commission), ou au marchand avec la case « Revente au marchand » ; puis les pertes, la plus "
        .. "petite en % d'abord ; sans bénéfice connu, à la fin. « Ventes/jour minimum » écarte ce qui se vend trop peu. "
        .. "« Le mieux pour l'xp » : la chance de "
        .. "gagner un point d'abord (les recettes sûres, 100 %, en tête) ; à chance égale, la plus rapide à fabriquer (le "
        .. "temps compte plus que le bénéfice) ; à temps égal, celle qui rapporte le plus (à perte : la plus petite perte). "
        .. "Sans revente connue, le coût compte comme une perte ; un composant sans prix, après. À la fin, celles qui ne "
        .. "donnent rien (grises, niveau trop bas) ou d'un métier que tu n'as pas.")
P.show, P.sort = show, sort

local mine = UI.NewCheck(P)
mine:SetPoint("LEFT", sort, "RIGHT", 18, 0)
local mineText = Font(P, "GameFontHighlight")
mineText:SetPoint("LEFT", mine, "RIGHT", 2, 0)
mineText:SetText("Seulement mes métiers")
mine:SetScript("OnClick", function(self)
    ns.Set("mine", self:GetChecked() and true or false)
end)
Tip(mine, "Seulement mes métiers", "Cachée : tous les métiers (d'après les tables du jeu). Cochée : ceux du personnage.")
P.mine = mine

local vendorResale = UI.NewCheck(P)
vendorResale:SetPoint("LEFT", mineText, "RIGHT", 18, 0)
local vendorText = Font(P, "GameFontHighlight")
vendorText:SetPoint("LEFT", vendorResale, "RIGHT", 2, 0)
vendorText:SetText("Revente au marchand")
vendorResale:SetScript("OnClick", function(self)
    ns.Set("vendorResale", self:GetChecked() and true or false)
end)
Tip(vendorResale, "Revente au marchand", "Cochée : le bénéfice compte la vente de l'objet créé à un marchand (PNJ), à "
    .. "son prix de vente du jeu, sans commission. Décochée : sa vente à l'hôtel des ventes (son offre la moins chère "
    .. "relevée en jeu, moins 5 %), ou au marchand quand aucun prix n'a été relevé. Cochée, les filtres « Ventes/jour "
    .. "minimum » et « % de vente minimum » sont désactivés. Un objet que le marchand n'achète pas (sans prix de vente, comme les "
    .. "parchemins où se gravent les enchantements) compte une revente de 0 : tout son coût en perte.")
P.vendorResale = vendorResale

local searchText = Font(P, "GameFontNormal")
searchText:SetPoint("TOPLEFT", P, "TOPLEFT", 66, ROW2 - 4)
searchText:SetText("Chercher")
local search = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
search:SetSize(180, 20) -- (la place pour « Niveau requis au plus » et « Fabrications »)
search:SetPoint("LEFT", searchText, "RIGHT", 14, 0)
search:SetAutoFocus(false)
search:SetMaxLetters(40)
search:SetScript("OnTextChanged", function(self, userInput) if userInput then ns.Set("search", strtrim(self:GetText() or "")) end end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEscapePressed", function(self) self:SetText("") ns.Set("search", "") self:ClearFocus() end)
Tip(search, "Chercher", "Une partie du nom de la recette. Échap : effacer.")
P.search = search

-- Niveau de métier requis au plus : cache les recettes qui demandent plus (vide ou 0 : pas de limite).
local levelText = Font(P, "GameFontNormal")
levelText:SetPoint("LEFT", search, "RIGHT", 24, 0)
levelText:SetText("Niveau requis au plus")
local level = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
level:SetSize(44, 20)
level:SetPoint("LEFT", levelText, "RIGHT", 12, 0)
level:SetAutoFocus(false)
level:SetMaxLetters(4)
if level.SetNumeric then level:SetNumeric(true) end
level:SetScript("OnTextChanged", function(self, userInput)
    if userInput then ns.Set("maxLevel", math.max(0, tonumber(self:GetText() or "") or 0)) end
end)
level:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
level:SetScript("OnEscapePressed", function(self) self:SetText("") ns.Set("maxLevel", 0) self:ClearFocus() end)
Tip(level, "Niveau requis au plus", "Cache les recettes qui demandent un niveau de métier plus haut (le niveau pour "
    .. "l'apprendre). Vide ou 0 : pas de limite. Échap : effacer.")
P.maxLevel = level

-- Combien de fois fabriquer chaque recette : coût, revente et bénéfice pour toutes (1 à 9999).
local craftsText = Font(P, "GameFontNormal")
craftsText:SetPoint("LEFT", level, "RIGHT", 24, 0)
craftsText:SetText("Fabrications")
local crafts = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
crafts:SetSize(44, 20)
crafts:SetPoint("LEFT", craftsText, "RIGHT", 12, 0)
crafts:SetAutoFocus(false)
crafts:SetMaxLetters(4)
if crafts.SetNumeric then crafts:SetNumeric(true) end
crafts:SetScript("OnTextChanged", function(self, userInput)
    local v = userInput and tonumber(self:GetText() or "")
    if v and v >= 1 then ns.Set("crafts", math.floor(v)) end
end)
crafts:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
crafts:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(ns.Crafts())) end)
crafts:SetScript("OnEscapePressed", function(self) ns.Set("crafts", 1) self:ClearFocus() end)
Tip(crafts, "Fabrications", "Combien de fois fabriquer chaque recette. Le coût est celui de tous ses composants, achetés "
    .. "tout de suite aux offres les moins chères de l'hôtel des ventes, une à une (relevées par « Scanner l'HDV ») : avec "
    .. "« Fabrications » à 10 et 4 composants par recette, les 40 moins chers en vente ; ce qui n'y est pas se compte "
    .. "chez le marchand, ou au prix de ForeverExchange (« il en manque »). La revente, le bénéfice et le temps de "
    .. "fabrication sont ceux des 10 ; le bénéfice par seconde reste le même. « ~ » : coût estimé (des offres pas "
    .. "encore connues). "
    .. "Échap : 1.")
P.crafts = crafts

local header = Font(P, "GameFontHighlight")
header:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, ROW2 - 4)
header:SetJustifyH("RIGHT")
-- (la place à droite de « Fabrications » : un en-tête long, avec un type d'objet et un niveau simulé, est tronqué
-- plutôt que de passer sur la case)
header:SetWidth(280)
header:SetWordWrap(false)
P.header = header

-- L'encart : les métiers à gauche, les recettes à droite ----------------------------------------------------------------
local inset = P.Inset or P
if P.Inset then
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", P, "TOPLEFT", 4, -INSET_TOP)
    inset:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", -6, INSET_BOTTOM)
end

local function ScrollBar(parent, onScroll)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(8)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(slider)
    if UI.HasAtlas("!minimal-scrollbar-track-middle") then track:SetAtlas("!minimal-scrollbar-track-middle")
    else track:SetColorTexture(1, 1, 1, 0.08) end
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 40)
    if UI.HasAtlas("minimal-scrollbar-small-thumb-middle") then thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    else thumb:SetColorTexture(1, 0.82, 0, 0.5) end
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.setting then return end
        onScroll(math.floor(value + 0.5))
    end)
    return slider
end

-- Une liste à lignes réutilisées.
local function NewList(parent, width, height, rowHeight, build, fill)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, height)
    list.rows, list.data, list.offset = {}, {}, 0
    list.visible = math.max(1, math.floor(height / rowHeight))
    local bar = ScrollBar(parent, function(v) list.offset = v list:Render() end)
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, -18)
    bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 4, 18)
    bar:SetHeight(height - 36)
    list.bar = bar
    local function Arrow(direction, point, relative, y, step)
        local button = CreateFrame("Button", nil, bar, "UIPanelScroll" .. direction .. "ButtonTemplate")
        button:SetSize(16, 16)
        button:SetPoint(point, bar, relative, 0, y)
        button:SetScript("OnClick", function()
            local max = math.max(0, #list.data - list.visible)
            list.offset = math.max(0, math.min(max, list.offset + step))
            list:Render()
        end)
        return button
    end
    bar.up = Arrow("Up", "BOTTOM", "TOP", 1, -1)
    bar.down = Arrow("Down", "TOP", "BOTTOM", -1, 1)
    for i = 1, list.visible do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints(row)
        row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        row.selected:SetBlendMode("ADD")
        row.selected:SetVertexColor(1, 0.82, 0, 0.35)
        row.selected:Hide()
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) list:Scroll(delta) end)
        build(row, list)
        list.rows[i] = row
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) list:Scroll(delta) end)
    -- (list.paged : une liste par pages, sans défilement ni barre ; chaque page tient dans ses lignes)
    function list:Scroll(delta)
        if self.paged then return end
        local max = math.max(0, #self.data - self.visible)
        local v = math.max(0, math.min(max, self.offset - delta * 3))
        if v ~= self.offset then self.offset = v self:Render() end
    end
    function list:SetData(data, keepOffset)
        self.data = data or {}
        if not keepOffset then self.offset = 0 end
        self.offset = math.max(0, math.min(self.offset, math.max(0, #self.data - self.visible)))
        self:Render()
    end
    -- (moins de lignes que la place n'en permet, pour en laisser dessous, aux boutons des pages : au plus celles créées)
    function list:SetRows(n)
        n = math.max(1, math.min(n or #self.rows, #self.rows))
        if n == self.visible then return end
        self.visible = n
        self:SetHeight(n * rowHeight)
        bar:SetHeight(n * rowHeight - 36)
        self:SetData(self.data, true)
    end
    function list:Render()
        for i, row in ipairs(self.rows) do
            local entry = i <= self.visible and self.data[self.offset + i] or nil
            row.entry = entry
            if entry then fill(row, entry, self.offset + i) row:Show() else row:Hide() end
        end
        local max = math.max(0, #self.data - self.visible)
        bar.setting = true
        bar:SetMinMaxValues(0, max)
        bar:SetValue(self.offset)
        bar.setting = false
        bar.up:SetEnabled(self.offset > 0)
        bar.down:SetEnabled(self.offset < max)
        bar:SetShown(max > 0 and not self.paged)
    end
    return list
end

-- Type d'objet créé : un menu à sous-menus (Équipement > Torse, Taille... ; Armes > Épée... ; Consommables > les
-- recharges communes, puis les autres par sous-genre ; Enchantements > ce qu'ils enchantent ; le reste par genre du
-- jeu), chaque entrée avec son nombre de recettes (les autres filtres appliqués : ns.List, list.kinds).
local function Counted(name, n) return ("%s |cff9d9d9d(%d)|r"):format(name, n or 0) end
local function TypeIs(value) return function() return (ns.Get("itemType") or "") == value end end
local function TypeSet(value) return function() ns.Set("itemType", value) end end
local typeMenu = CreateFrame("DropdownButton", nil, inset, "WowStyle1DropdownTemplate")
typeMenu:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
typeMenu:SetWidth(PROF_W - 12)
typeMenu:SetupMenu(function(_, root)
    local counts = P.recipes and P.recipes.kinds or {}
    local total = 0
    for _, c in pairs(counts) do total = total + c.count end
    root:CreateRadio(Counted("Tous les objets", total), TypeIs(""), TypeSet(""), "")
    for _, c in ipairs(ns.KindMenu(counts)) do
        local kind = c.kind
        local entry = root:CreateRadio(Counted(c.name, c.count), function()
            local f = ns.Get("itemType") or ""
            return f == kind or f:sub(1, #kind + 1) == kind .. "/"
        end, TypeSet(kind), kind)
        -- (un sous-menu dès qu'il y a de quoi choisir : « Tous : Équipement », puis chaque sous-type)
        if entry and entry.CreateRadio and (#c.subs > 1 or (c.subs[1] and c.subs[1].name ~= c.name)) then
            entry:CreateRadio(Counted("Tous : " .. c.name, c.count), TypeIs(kind), TypeSet(kind), kind)
            for _, sub in ipairs(c.subs) do
                local e = entry:CreateRadio(Counted(sub.name, sub.count), TypeIs(sub.key), TypeSet(sub.key), sub.key)
                if e and e.SetTooltip and sub.key:find("/cd%d+$") then
                    e:SetTooltip(function(tooltip)
                        tooltip:SetText(sub.name, 1, 0.82, 0)
                        tooltip:AddLine("Recharge commune : en utiliser un rend les autres indisponibles le temps de "
                            .. "la recharge (d'après les tables du jeu).", 1, 1, 1, true)
                    end)
                end
            end
        end
    end
end)
Tip(typeMenu, "Type d'objet", "Seulement les recettes qui créent ce type d'objet : l'équipement par emplacement "
    .. "(torse, taille...), les armes par genre, les consommables par recharge commune (ceux qui la partagent : les "
    .. "potions, les explosifs et grenades, les élixirs et flacons...), puis les autres par genre ; les enchantements "
    .. "par ce qu'ils enchantent. Entre parenthèses : combien de recettes, avec les autres filtres.")
P.itemType = typeMenu

-- « Bénéfice plus de » X pièces d'or : seulement les recettes dont le bénéfice est plus grand (X peut être négatif :
-- -0,5, une perte de moins de 50 pa ; vide : pas de limite ; un bénéfice inconnu est caché dès qu'il y a une limite).
local minText = Font(inset, "GameFontNormal")
minText:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -42)
minText:SetText("Bénéfice plus de")
local minProfit = CreateFrame("EditBox", nil, inset, "InputBoxTemplate")
minProfit:SetSize(46, 20)
minProfit:SetPoint("LEFT", minText, "RIGHT", 8, 0)
minProfit:SetAutoFocus(false)
minProfit:SetMaxLetters(9)
local minUnit = Font(inset, "GameFontHighlight")
minUnit:SetPoint("LEFT", minProfit, "RIGHT", 4, 0)
minUnit:SetText("po")
minProfit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = strtrim(self:GetText() or "")
    if text == "" then ns.Set("minProfit", nil) return end
    local copper = ns.ParseGold(text)
    if copper then ns.Set("minProfit", copper) end -- (« - » ou « 1, » en cours de frappe : rien encore)
end)
minProfit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
minProfit:SetScript("OnEditFocusLost", function(self) self:SetText(ns.GoldText(ns.Get("minProfit"))) end)
minProfit:SetScript("OnEscapePressed", function(self) self:SetText("") ns.Set("minProfit", nil) self:ClearFocus() end)
Tip(minProfit, "Bénéfice plus de", "Seulement les recettes dont le bénéfice est plus grand que ce nombre de pièces "
    .. "d'or (aux prix et à la revente choisis : hôtel des ventes, ou marchand avec « Revente au marchand » ; pour "
    .. "une seule fabrication, indépendamment du nombre saisi dans « Fabrications »). Négatif : jusqu'à cette perte "
    .. "(-0,5 : les pertes de moins de 50 pa par fabrication). 0 : celles "
    .. "qui rapportent. Celles dont le bénéfice est inconnu (un composant ou la revente sans prix) sont cachées. "
    .. "Vide : pas de limite. Échap : effacer.")
P.minProfit = minProfit

-- Niveau simulé du métier choisi : les points de compétence (couleur, chance, tri « Le mieux pour l'xp ») comptés à ce
-- niveau plutôt qu'au vrai (ns.SkillLevel) ; un par métier, grisé sur « Tous les métiers ».
local simText = Font(inset, "GameFontNormalSmall")
simText:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -72)
simText:SetText("Niveau simulé")
local simSkill = CreateFrame("EditBox", nil, inset, "InputBoxTemplate")
simSkill:SetSize(46, 20)
simSkill:SetPoint("LEFT", simText, "RIGHT", 8, 0)
simSkill:SetAutoFocus(false)
simSkill:SetMaxLetters(3)
if simSkill.SetNumeric then simSkill:SetNumeric(true) end
local function SimText()
    local v = ns.SimSkill(ns.Get("profession"))
    return v and tostring(v) or ""
end
simSkill:SetScript("OnTextChanged", function(self, userInput)
    local profession = ns.Get("profession")
    if not userInput or profession == 0 then return end
    ns.SetSimSkill(profession, tonumber(strtrim(self:GetText() or "")))
end)
simSkill:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
simSkill:SetScript("OnEditFocusLost", function(self) self:SetText(SimText()) end)
simSkill:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    ns.SetSimSkill(ns.Get("profession"), nil)
    self:ClearFocus()
end)
Tip(simSkill, "Niveau simulé", "Compte les points de compétence comme si le métier choisi était à ce niveau : la "
    .. "couleur des recettes, leur chance de faire gagner un point et le tri « Le mieux pour l'xp » (pour préparer "
    .. "la montée du métier ; aussi pour un métier que le personnage n'a pas). Un niveau par métier, gardé pour ce "
    .. "personnage ; la liste des métiers le montre en bleu, le vrai entre parenthèses (« 225 (185) »). Seulement avec les seuils de couleur des tables "
    .. "du jeu : une recette qui n'en a pas ne donne alors pas de points. Choisis d'abord un métier à gauche. Vide ou "
    .. "Échap : ton vrai niveau.")
P.simSkill = simSkill

-- « Favoris » : seulement les recettes en favori (l'étoile à gauche de leur nom), avec les autres filtres.
local favorites = UI.NewCheck(inset)
favorites:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -98)
local favoritesText = Font(inset, "GameFontHighlight")
favoritesText:SetPoint("LEFT", favorites, "RIGHT", 2, 0)
favoritesText:SetText("Favoris")
favorites:SetScript("OnClick", function(self)
    ns.Set("favoritesOnly", self:GetChecked() and true or false)
end)
Tip(favorites, "Favoris", "Cochée : seulement les recettes en favori (l'étoile à gauche de leur nom), avec les autres "
    .. "filtres : « Tous les métiers » pour celles de tous les métiers. Les favoris valent pour tout le compte.")
P.favorites = favorites

-- Métiers
local profBox = CreateFrame("Frame", nil, inset)
profBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6 - TYPE_H)
profBox:SetSize(PROF_W, LIST_H - TYPE_H)
local profList = NewList(profBox, PROF_W - 14, LIST_H - TYPE_H, PROF_ROW_H, function(row)
    row.text = Font(row, "GameFontNormal")
    row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetWordWrap(false)
end, function(row, entry)
    row.skillLine = entry.skillLine
    row.text:SetText(entry.text)
    row.selected:SetShown(ns.Get("profession") == entry.skillLine)
    if ns.Get("profession") == entry.skillLine then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(1, 0.82, 0) end
end)
profList:SetPoint("TOPLEFT", profBox, "TOPLEFT", 0, 0)
for _, row in ipairs(profList.rows) do
    row:SetScript("OnClick", function(self)
        ns.Set("profession", self.skillLine)
    end)
end
P.professions = profList
local sep = inset:CreateTexture(nil, "ARTWORK")
sep:SetColorTexture(1, 1, 1, 0.08)
sep:SetWidth(1)
sep:SetPoint("TOPLEFT", profBox, "TOPRIGHT", 4, TYPE_H)
sep:SetPoint("BOTTOMLEFT", profBox, "BOTTOMRIGHT", 4, 0)

-- Objets : nom et couleur de qualité (le jeu charge ceux qu'il n'a pas encore vus : on redessine alors).
local pendingItems = {}
local function ItemName(id)
    local name, link, quality
    if C_Item and C_Item.GetItemInfo then name, link, quality = C_Item.GetItemInfo(id) end
    if not name then
        pendingItems[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return ("Objet %d"):format(id), nil, nil
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return name, link, color and color.hex or nil
end

local function ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or nil
end

local function RecipeIcon(r)
    if r.out then local icon = ItemIcon(r.out) if icon then return icon end end
    if r.icon then return r.icon end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, r.id)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Colored(r)
    local color = r.up and ns.DIFFICULTY[r.up.kind]
    return color and ("|c" .. color .. r.name .. "|r") or r.name
end

-- « <coût> (<+/- bénéfice>) » ; « ~ » devant un coût estimé : un composant compté sans ses offres, ou qui manque à
-- l'hôtel des ventes.
local function Approx(r) return (r.estimate or r.short) and "~" or "" end

local function PriceText(r)
    local cost = r.cost and (Approx(r) .. ns.Money(r.cost)) or (#r.reagents == 0 and "—" or "?")
    if r.value == nil then return cost end
    return cost .. " (" .. ns.Signed(r.profit) .. ")"
end
ns.PriceText = PriceText

-- Infobulle d'un parchemin : celle du jeu, puis où le trouver (CMaNGOS et QuestieDB).
local shownScroll = {}
local function ScrollTooltip(owner, itemID)
    shownScroll.owner, shownScroll.item = owner, itemID
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID) else GameTooltip:SetText(ItemName(itemID)) end
    local data = ns.DATA.recipeItems and ns.DATA.recipeItems[itemID]
    GameTooltip:AddLine(" ")
    if data and #data > 1 then
        GameTooltip:AddLine("Pour l'obtenir :", 1, 0.82, 0)
        for i = 2, math.min(#data, 11) do GameTooltip:AddLine(ns.SourceLine(data[i]), 1, 1, 1, true) end
        if #data > 11 then GameTooltip:AddLine(("... et %d autres"):format(#data - 11), 0.6, 0.6, 0.6) end
    else
        GameTooltip:AddLine("Où le trouver : inconnu (pas dans la base de CMaNGOS ni dans QuestieDB).", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end
ns.ScrollTooltip = ScrollTooltip

-- D'où vient le prix d'achat d'un composant à l'hôtel des ventes : « le moins cher sur ton royaume, 207 en
-- vente, relevé il y a 3 min » (vu en le parcourant), ou « moyenne sur 7 jours de ForeverExchange · 306 annonces ».
local function BuyText(itemID, source)
    if source == PX.LIVE then return PX.LiveText(PX.Live(itemID), nil, true) end
    local auctions = PX.Auctions(itemID)
    local text = PX.Label(source)
    if source ~= ns.BuySource() then text = text .. " (pas de " .. PX.Label(ns.BuySource()) .. ")" end
    if auctions then
        return ("%s · %s annonce%s à sa dernière analyse"):format(text, PX.Decimals(auctions), auctions > 1 and "s" or "")
    end
    return text
end

-- Comment se paient les unités d'un composant (le détail de ns.ReagentCost), en lignes d'infobulle : « 40 aux offres
-- les moins chères de l'hôtel des ventes (22 pc à 25 pc l'unité) », « 12 chez le marchand, à 30 pc », « il en manque
-- 8 à l'hôtel des ventes (32 en vente) : comptés à 30 pc (valeur du marché de ton royaume) », « offres relevées il y
-- a 3 min » ; sans ses offres : « ~ toutes au même prix... ».
local function CostLines(d)
    local lines = {}
    if not d then return lines end
    local N = PX.Decimals
    if d.ah ~= nil then
        if d.ah > 0 then
            local range = d.low == d.top and ns.Money(d.low) or (ns.Money(d.low) .. " à " .. ns.Money(d.top))
            lines[#lines + 1] = ("%s aux offres les moins chères de l'hôtel des ventes (%s l'unité)"):format(N(d.ah), range)
        end
        if d.vendor then
            lines[#lines + 1] = ("%s chez le marchand, à %s%s"):format(N(d.vendor), ns.Money(d.vendorPrice),
                d.none and " (aucun en vente)" or (d.ah > 0 and " (moins cher que les offres suivantes)"
                    or (d.vendor < d.n and "" or " (moins cher que les offres)")))
        end
        if d.short then
            lines[#lines + 1] = ("|cffff8040il en manque %s à l'hôtel des ventes (%s)|r : comptés à %s (%s)"):format(
                N(d.short), d.none and "aucun en vente" or (N(d.qty or 0) .. " en vente"), ns.Money(d.shortPrice),
                PX.Label(d.shortSource))
        end
        if d.partial then lines[#lines + 1] = "il manque ses offres les plus chères (pas toutes chargées)" end
        lines[#lines + 1] = "offres relevées " .. PX.AgeText(d.age or 0)
    elseif d.estimate then
        lines[#lines + 1] = "~ toutes au même prix : ses offres ne sont pas connues (elles sont relevées par "
            .. "« Scanner l'HDV »)"
    end
    return lines
end

-- Infobulle d'un composant : celle du jeu, puis combien il en faut, son prix et ce qu'il coûte pour la recette (pour
-- toutes ses fabrications).
local function ReagentTooltip(owner, itemID, qty)
    local count = ns.Crafts()
    local n = qty * count
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID) else GameTooltip:SetText(ItemName(itemID)) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Il en faut", count > 1 and ("%d x %d = %s"):format(qty, count, PX.Decimals(n))
        or tostring(qty), 1, 0.82, 0, 1, 1, 1)
    local have = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true)
    if type(have) == "number" then GameTooltip:AddDoubleLine("Tu en as", tostring(have), 1, 0.82, 0, 1, 1, 1) end
    local unit, kind, source, dearer = ns.UnitCost(itemID)
    local total, d = ns.ReagentCost(itemID, n)
    if unit then
        GameTooltip:AddDoubleLine(kind == "vendor" and "Prix chez le marchand" or "Prix à l'hôtel des ventes", ns.Money(unit),
            1, 0.82, 0, 1, 1, 1)
        if kind == "ah" then GameTooltip:AddLine("   " .. BuyText(itemID, source), 0.8, 0.8, 0.8, true) end
        if kind == "ah" and source ~= PX.LIVE then -- (pas encore relevé : un prix de ForeverExchange)
            GameTooltip:AddLine("   pas encore relevé : « Scanner l'HDV », l'hôtel des ventes ouvert",
                0.6, 0.6, 0.6, true)
        end
        if kind == "ah" and dearer and ns.Get("vendorFirst") then
            GameTooltip:AddLine("   moins cher que chez le marchand (" .. ns.Money(dearer) .. ")", 0.8, 0.8, 0.8, true)
        end
    elseif not (d and d.none) then
        GameTooltip:AddLine("Pas de prix : ni un relevé, ni ForeverExchange, ni un marchand n'en connaissent.", 1, 0.4, 0.4, true)
    end
    if total and (n > 1 or (d and d.ah ~= nil)) then
        GameTooltip:AddDoubleLine(count > 1 and ("Pour %d fabrications"):format(count) or "Pour la recette",
            ((d.estimate or d.short) and "~" or "") .. ns.Money(total), 1, 0.82, 0, 1, 1, 1)
        for _, line in ipairs(CostLines(d)) do GameTooltip:AddLine("   " .. line, 0.8, 0.8, 0.8, true) end
    elseif d and d.ah ~= nil then -- (pas assez en vente, et pas de prix pour le reste)
        GameTooltip:AddLine(("Aucun prix pour les %s qui manquent à l'hôtel des ventes (%s)."):format(
            PX.Decimals(n - d.ah), d.none and "aucun en vente" or (PX.Decimals(d.qty or 0) .. " en vente")),
            1, 0.4, 0.4, true)
    end
    GameTooltip:Show()
end

-- Où se paie un composant de la recette, en un mot, dans son infobulle.
local function Where(d)
    if not d then return "" end
    if d.ah ~= nil then
        if d.short then return " (il en manque " .. PX.Decimals(d.short) .. ")" end
        if d.vendor and d.ah == 0 then return " (marchand)" end
        return d.vendor and " (relevé + marchand)" or " (relevé)"
    end
    if d.kind == "vendor" then return " (marchand)" end
    return d.source == PX.LIVE and " (relevé)" or " (FX)"
end

-- Infobulle d'une recette : l'objet créé, puis composants, prix, points et apprentissage.
local function RecipeTooltip(owner, r)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if r.out and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.out)
    elseif GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(r.id)
    else GameTooltip:SetText(r.name) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s · %s%s"):format(ns.ProfessionName(r.skillLine), r.learned and "apprise" or "non apprise",
        r.learnedAt and r.learnedAt < 9999 and (" · niveau " .. r.learnedAt) or ""), 1, 0.82, 0)
    local count = r.crafts or 1
    local time = ns.CraftTime(r.id)
    if time and count > 1 then -- (le temps de toutes, comme le coût et la revente ; puis celui d'une)
        GameTooltip:AddDoubleLine(("Temps des %d fabrications"):format(count), ns.TimeText(time * count), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Temps d'une fabrication", ns.TimeText(time), 1, 0.82, 0, 1, 1, 1)
    elseif time then
        GameTooltip:AddDoubleLine("Temps de fabrication", ns.TimeText(time), 1, 0.82, 0, 1, 1, 1)
    end
    if #r.reagents > 0 then
        GameTooltip:AddLine(count > 1 and ("Composants, pour %d fabrications :"):format(count) or "Composants :", 1, 0.82, 0)
        for i, reagent in ipairs(r.reagents) do
            local name, _, hex = ItemName(reagent[1])
            local d = r.reagentCosts and r.reagentCosts[i] or nil
            GameTooltip:AddDoubleLine(("%s%s|r x%s"):format(hex or "|cffffffff", name, PX.Decimals(reagent[2] * count)),
                d and d.cost and (((d.estimate or d.short) and "~" or "") .. ns.Money(d.cost) .. Where(d))
                    or "prix inconnu", 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddDoubleLine(count > 1 and ("Coût des %d"):format(count) or "Coût",
        r.cost and (Approx(r) .. ns.Money(r.cost)) or (#r.missing > 0 and "incomplet (prix manquants)" or "—"),
        1, 0.82, 0, 1, 1, 1)
    if count > 1 and r.cost then
        GameTooltip:AddDoubleLine("Coût d'une fabrication", Approx(r) .. ns.Money(r.cost / count), 1, 0.82, 0, 1, 1, 1)
    end
    if r.out then
        local vendor = r.valueKind == "vendor" or (not r.value and ns.VendorResale())
        local cut = ns.Get("ahCut") and not vendor
        local label, unknown
        if r.engraved then -- (un parchemin par fabrication)
            label = (count > 1 and ("Revente des %d parchemins"):format(count) or "Revente du parchemin")
                .. (vendor and " au marchand" or "") .. (cut and " (-5 %)" or "")
            unknown = "aucune vente connue"
        else
            label = ("Revente%s (%sx%s%s)"):format(vendor and " au marchand" or "", count > 1 and (count .. " fois ") or "",
                r.qmin == r.qmax and r.qmin or (r.qmin .. "-" .. r.qmax), cut and ", -5 %" or "")
            unknown = "prix inconnu"
        end
        GameTooltip:AddDoubleLine(label, r.value and ns.Money(r.value) or unknown, 1, 0.82, 0, 1, 1, 1)
        if r.unsellable then -- (revendu au marchand, qui ne l'achète pas : 0)
            GameTooltip:AddLine("   invendable au marchand (pas de prix de vente) : revente comptée à 0", 0.8, 0.8, 0.8, true)
        elseif r.valueKind == "ah" and r.how then -- (sur quoi repose la revente : le relevé, ou ForeverExchange)
            GameTooltip:AddLine("   " .. PX.Basis(r.how, ns.Money), 0.8, 0.8, 0.8, true)
        elseif r.how and (r.how.slow or r.how.none) then -- (pourquoi pas l'hôtel des ventes)
            GameTooltip:AddLine("   à l'hôtel des ventes : " .. PX.Why(r.how, ns.Money), 0.8, 0.8, 0.8, true)
        end
        local live = not ns.VendorResale() and PX.Live(r.out)
        if live and not (r.how and r.how.source == PX.LIVE) then -- (relevé, mais pas pris : se vend trop peu...)
            GameTooltip:AddLine("   au dernier relevé : " .. PX.LiveText(live, ns.Money), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddDoubleLine(count > 1 and ("Bénéfice des %d"):format(count) or "Bénéfice",
            (r.profit and Approx(r) or "") .. ns.Signed(r.profit), 1, 0.82, 0, 1, 1, 1)
        if r.profitPct then
            GameTooltip:AddDoubleLine("Bénéfice en % du coût", ns.SignedPercent(r.profitPct), 1, 0.82, 0, 1, 1, 1)
        end
        if r.perSecond then
            GameTooltip:AddDoubleLine("Bénéfice par seconde", ns.SignedRate(r.perSecond), 1, 0.82, 0, 1, 1, 1)
        end
        if not ns.VendorResale() then
            -- (ForeverExchange : le prix minimum qu'il a vu, quand l'objet est revendu au prix de notre relevé)
            local e = PX.Exchange(r.out)
            if e and not (r.how and r.how.source == PX.EXCHANGE) then
                GameTooltip:AddDoubleLine("ForeverExchange", ns.Money(e.price), 1, 0.82, 0, 1, 1, 1)
                GameTooltip:AddLine("   " .. PX.ExchangeText(r.out), 0.8, 0.8, 0.8, true)
            end
            if not r.ahPrice and PX.Gone(r.out) then
                GameTooltip:AddLine("   Pas en vente au dernier relevé de l'hôtel des ventes.", 0.8, 0.8, 0.8, true)
            end
        end
        if r.engraved then
            GameTooltip:AddLine("Gravé sur un parchemin, l'enchantement se vend à l'hôtel des ventes : sa revente est le "
                .. "prix de ce parchemin.", 0.6, 0.6, 0.6, true)
        end
    end
    if r.short then
        GameTooltip:AddLine(("Pas assez de certains composants en vente pour %s : ce qui manque compte au prix de "
            .. "ForeverExchange (survole le composant)."):format(count > 1 and (count .. " fabrications") or "la recette"),
            1, 0.5, 0.25, true)
    elseif r.estimate and r.cost then
        GameTooltip:AddLine("~ : coût estimé, les offres de certains composants ne sont pas connues (toutes sont relevées "
            .. "par « Scanner l'HDV »).", 0.6, 0.6, 0.6, true)
    end
    local up = ns.SkillUpText(r.up)
    if up then
        local level = r.simulated and ns.SimSkill(r.skillLine)
        GameTooltip:AddDoubleLine(level and ("Points de compétence (au niveau simulé %d)"):format(level)
            or "Points de compétence", up, 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(ns.SkillThresholdText(r), 0.8, 0.8, 0.8, true)
    if not r.learned then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Pour l'apprendre :", 1, 0.82, 0)
        GameTooltip:AddLine((ns.HowToLearn(r)), 1, 1, 1, true)
        if r.sourceText and r.sourceText ~= "" then GameTooltip:AddLine(r.sourceText, 0.85, 0.85, 0.85, true) end
    end
    GameTooltip:Show()
end

-- Recettes
local LIST_X = PROF_W + 18
local LIST_W = W - LIST_X - 40
-- (l'onglet « Wishlist » : toute la largeur, sans la colonne des métiers)
local FULL_X = 8
local FULL_W = W - FULL_X - 40

local function Plural(n, word) return ("%d %s%s"):format(n, word, n > 1 and "s" or "") end

-- L'étoile des favoris, à gauche du nom : celle des favoris de l'hôtel des ventes du jeu (son atlas), sinon son icône.
local function SetStar(tex, on)
    local atlas = on and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off"
    if UI.HasAtlas(atlas) then
        tex:SetAtlas(atlas)
        tex:SetDesaturated(false)
        tex:SetAlpha(1)
    else
        tex:SetTexture("Interface\\COMMON\\FavoritesIcon")
        tex:SetDesaturated(not on)
        tex:SetAlpha(on and 1 or 0.45)
    end
end

local function StarTip(self)
    local r = self:GetParent().entry
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(ns.IsFavorite(r.id) and "Retirer des favoris" or "Ajouter aux favoris", 1, 0.82, 0)
    GameTooltip:AddLine("La case « Favoris », à gauche, ne montre que les recettes en favori.", 1, 1, 1, true)
    GameTooltip:Show()
end

local function WishTip(self)
    local r = self:GetParent().entry
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Ajouter à la wishlist", 1, 0.82, 0)
    if ns.WishlistBuying() then
        GameTooltip:AddLine("Des achats de la wishlist sont en cours : arrête-les (onglet « Wishlist ») pour la modifier.",
            1, 0.3, 0.3, true)
    else
        local n, inList = ns.Crafts(), ns.WishlistCrafts(r.id)
        GameTooltip:AddLine(("Ajoute %s de %s à la wishlist (le nombre de « Fabrications »)."):format(
            Plural(n, "fabrication"), r.name), 1, 1, 1, true)
        if inList > 0 then
            GameTooltip:AddLine(("Déjà dans la wishlist : %s."):format(Plural(inList, "fabrication")), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("L'onglet « Wishlist » dit ce qu'il faut acheter, le coût et le bénéfice, puis achète tout à "
            .. "l'hôtel des ventes et chez les marchands.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- Une ligne de recette (onglet « Recettes ») : l'icône de l'objet créé, l'étoile des favoris, le nom,
-- ses lignes d'information, « <coût> (<+/- bénéfice>) » à droite, les composants dessous, et en bas à droite
-- « + Wishlist ».
local function BuildRecipeRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(16, 15)
    row.star:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -4)
    row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
    row.star.tex:SetAllPoints(row.star)
    row.star:SetScript("OnClick", function()
        local r = row.entry
        if r then ns.ToggleFavorite(r.id) end
        if GameTooltip:GetOwner() == row.star then StarTip(row.star) end
    end)
    row.star:SetScript("OnEnter", StarTip)
    row.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.star:EnableMouseWheel(true)
    row.star:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
    row.name = Font(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 60, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -230, 0)
    row.name:SetWordWrap(false)
    row.line = Font(row, "GameFontHighlightSmall", GREY)
    row.line:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.line:SetPoint("RIGHT", row, "RIGHT", -230, 0)
    row.line:SetWordWrap(false)
    row.thresholds = Font(row, "GameFontDisableSmall")
    row.thresholds:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 0, -3)
    row.thresholds:SetPoint("RIGHT", row, "RIGHT", -230, 0)
    row.thresholds:SetWordWrap(false)
    row.price = Font(row, "GameFontHighlight")
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.price:SetJustifyH("RIGHT")
    row.sub = Font(row, "GameFontDisableSmall")
    row.sub:SetPoint("TOPRIGHT", row.price, "BOTTOMRIGHT", 0, -3)
    row.sub:SetJustifyH("RIGHT")
    -- (3e ligne, à droite : combien l'objet se vend par jour et son taux de vente, quand il se revend aux enchères)
    row.sales = Font(row, "GameFontDisableSmall")
    row.sales:SetPoint("TOPRIGHT", row.sub, "BOTTOMRIGHT", 0, -3)
    row.sales:SetJustifyH("RIGHT")
    local scroll = CreateFrame("Button", nil, row)
    scroll:SetSize(22, 22)
    scroll:SetPoint("RIGHT", row, "RIGHT", -200, 0)
    scroll.tex = scroll:CreateTexture(nil, "ARTWORK")
    scroll.tex:SetAllPoints(scroll)
    scroll:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    scroll:SetScript("OnEnter", function(self) if self.itemID then ScrollTooltip(self, self.itemID) end end)
    scroll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scroll:SetScript("OnClick", function(self)
        if self.itemID and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            local _, link = ItemName(self.itemID)
            HandleModifiedItemClick(link or ("item:" .. self.itemID))
        end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
    row.scroll = scroll
    -- (3e ligne : les composants, une icône et le nombre qu'il en faut ; survol : leur infobulle)
    row.reagents = {}
    for i = 1, REAGENTS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(REAGENT_SIZE, REAGENT_SIZE)
        b:SetPoint("TOPLEFT", row.thresholds, "BOTTOMLEFT", (i - 1) * (REAGENT_SIZE + 10), -4)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints(b)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
        b.count:SetJustifyH("RIGHT")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self) if self.itemID then ReagentTooltip(self, self.itemID, self.qty) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.itemID and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                local _, link = ItemName(self.itemID)
                HandleModifiedItemClick(link or ("item:" .. self.itemID))
            end
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
        b:Hide()
        row.reagents[i] = b
    end
    -- (en bas à droite : l'ajouter à la wishlist, avec le nombre de « Fabrications »)
    row.wish = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.wish:SetSize(100, 18)
    row.wish:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
    row.wish:SetMotionScriptsWhileDisabled(true)
    row.wish:SetScript("OnClick", function()
        local r = row.entry
        if r then ns.WishlistAdd(r.id, ns.Crafts()) end
        if GameTooltip:GetOwner() == row.wish then WishTip(row.wish) end
    end)
    row.wish:SetScript("OnEnter", WishTip)
    row.wish:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.wish:EnableMouseWheel(true)
    row.wish:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
end

local function FillRecipeRow(row, r)
    row.icon:SetTexture(RecipeIcon(r))
    row.icon:SetDesaturated(not r.learned)
    SetStar(row.star.tex, ns.IsFavorite(r.id))
    row.name:SetText(Colored(r))
    local parts = {}
    if ns.Get("profession") == 0 then parts[#parts + 1] = ns.ProfessionName(r.skillLine) end
    if r.learnedAt and r.learnedAt < 9999 then parts[#parts + 1] = "niveau " .. r.learnedAt end
    local up = ns.SkillUpText(r.up)
    if up then parts[#parts + 1] = up end
    local time = ns.CraftsTime(r) -- (pour toutes les fabrications)
    if time then parts[#parts + 1] = ns.TimeText(time) end
    if not r.learned then parts[#parts + 1] = "|cffd0a060" .. (ns.HowToLearn(r)) .. "|r" end
    row.line:SetText(table.concat(parts, " · "))
    row.thresholds:SetText(ns.SkillThresholdText(r))
    row.price:SetText(PriceText(r))
    local sub
    -- (le bénéfice en % du coût en tête de la ligne : c'est lui que classe le tri « Bénéfice »)
    local pct = r.profitPct and (ns.SignedPercent(r.profitPct) .. " · ") or ""
    if r.perSecond then
        sub = ns.SignedRate(r.perSecond) .. " par seconde"
    else
        sub = r.value and "coût (bénéfice)"
            or (r.out and (r.engraved and "coût (parchemin sans prix)" or "coût (revente inconnue)") or "coût")
    end
    row.sub:SetText(sub and (pct .. sub))
    -- (revente à l'hôtel des ventes : combien il y en a en vente, et son évolution sur 7 jours chez ForeverExchange :
    -- « 207 en vente (+12 % sur 7 j) » ; revente au marchand d'un objet qu'il n'achète pas : pourquoi tout le coût est
    -- en perte)
    row.sales:SetText((r.valueKind == "ah" and r.how and PX.ShortDetail(r.how, true))
        or (r.unsellable and "invendable au marchand") or "")
    for i, b in ipairs(row.reagents) do
        local reagent = r.reagents[i]
        if reagent then
            b.itemID, b.qty = reagent[1], reagent[2]
            b.tex:SetTexture(ItemIcon(reagent[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local d = r.reagentCosts and r.reagentCosts[i] or nil
            local priced = (d and d.cost ~= nil) or ns.UnitCost(reagent[1]) ~= nil
            b.tex:SetVertexColor(1, priced and 1 or 0.45, priced and 1 or 0.45)
            -- (le nombre pour toutes les fabrications ; orangé : il en manque à l'hôtel des ventes)
            b.count:SetText(tostring(reagent[2] * (r.crafts or 1)))
            if d and d.short then b.count:SetTextColor(1, 0.5, 0.25) else b.count:SetTextColor(1, 1, 1) end
            b:Show()
        else
            b.itemID = nil
            b:Hide()
        end
    end
    local scrollID = not r.learned and r.scrolls[1] or nil
    row.scroll.itemID = scrollID
    if scrollID then
        row.scroll.tex:SetTexture(ItemIcon(scrollID) or "Interface\\Icons\\INV_Scroll_03")
        row.scroll:Show()
    else
        row.scroll:Hide()
    end
    local inList = ns.WishlistCrafts(r.id)
    row.wish:SetText(inList > 0 and ("Wishlist (%d)"):format(inList) or "+ Wishlist")
    row.wish:SetEnabled(not ns.WishlistBuying())
end

local function HookRecipeRow(row)
    row:SetScript("OnEnter", function(self) if self.entry then RecipeTooltip(self, self.entry) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local r = self.entry
        if r and r.out and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            local _, link = ItemName(r.out)
            HandleModifiedItemClick(link or ("item:" .. r.out))
        end
    end)
end

local listBox = CreateFrame("Frame", nil, inset)
listBox:SetPoint("TOPLEFT", inset, "TOPLEFT", LIST_X, -6)
listBox:SetSize(LIST_W, LIST_H)
local list = NewList(listBox, LIST_W, LIST_H, ROW_H, BuildRecipeRow, FillRecipeRow)
list:SetPoint("TOPLEFT", listBox, "TOPLEFT", 0, 0)
for _, row in ipairs(list.rows) do HookRecipeRow(row) end
P.list = list

-- Les pages de la liste, tout en bas de la fenêtre, à gauche : « < Page 2 / 5 > » (la ligne du bas se range à leur
-- droite ; seulement sur l'onglet Recettes, avec plusieurs pages). Une page = les lignes que montre la liste : pas de
-- défilement, seulement les pages. La page revient à la première quand un filtre, le tri, la recherche ou le métier
-- changent (ns.OnChange).
local PAGE = #list.rows
list.paged = true
local recipePage = 1
local PAGER_W = 170
local pager = CreateFrame("Frame", nil, P)
pager:SetSize(PAGER_W, 22)
pager:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", 8, 4)
pager:Hide()
local pagePrev = CreateFrame("Button", nil, pager, "UIPanelButtonTemplate")
pagePrev:SetSize(28, 22)
pagePrev:SetText("<")
pagePrev:SetPoint("LEFT", pager, "LEFT", 0, 0)
local pageNext = CreateFrame("Button", nil, pager, "UIPanelButtonTemplate")
pageNext:SetSize(28, 22)
pageNext:SetText(">")
pageNext:SetPoint("RIGHT", pager, "RIGHT", 0, 0)
local pageText = Font(pager, "GameFontHighlightSmall")
pageText:SetPoint("LEFT", pagePrev, "RIGHT", 4, 0)
pageText:SetPoint("RIGHT", pageNext, "LEFT", -4, 0)
pageText:SetJustifyH("CENTER")
P.pagePrev, P.pageNext, P.pageText, P.pager = pagePrev, pageNext, pageText, pager
-- (les pages montrées ou non ; sans elles, la ligne du bas reprend le bord)
local function ShowPager(shown)
    pager:SetShown(shown)
    pager:SetWidth(shown and PAGER_W or 1)
end

local empty = Font(listBox, "GameFontHighlight", GREY)
empty:SetPoint("TOPLEFT", listBox, "TOPLEFT", 30, -60)
empty:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -30, -60)
empty:SetJustifyH("CENTER")
empty:Hide()
P.empty = empty

-- XP Road : la route de montée du métier choisi (Route.lua) -------------------------------------------------------------
-- En haut, « Route » : la plus rapide ou la moins chère, et « Rétablir » les recettes écartées ; dessous, le résumé. À
-- droite des métiers, les étapes (de quel niveau à quel niveau, quelle recette, combien de fabrications, comment
-- l'apprendre, ses composants ; un clic sur une étape : une autre route, sans sa recette), et la liste de ce qu'il faut
-- acheter.
local routeMode, routeModeText = Dropdown("Route", "routeMode", 170, {
    { value = "fast", text = "La plus rapide" }, { value = "cheap", text = "La moins chère" } }, 66, ROW1, nil,
    "La plus rapide : le moins de temps de fabrication jusqu'à 300 (à temps égal, la moins chère). La moins chère : "
        .. "le plus petit coût (composants achetés, plus l'apprentissage des recettes, moins la revente au marchand de "
        .. "tout ce qui est fabriqué ; à coût égal, la plus rapide). Les composants s'achètent aux offres relevées de "
        .. "l'hôtel des ventes, les moins chères d'abord, ou chez un marchand ; une recette dont un composant ou le "
        .. "parchemin ne s'achète pas n'est pas utilisée.")
P.routeMode = routeMode

local restore = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
restore:SetSize(170, 22)
restore:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, ROW1 + 2)
restore:SetScript("OnClick", function() ns.RestoreRoute(ns.Get("profession")) end)
Tip(restore, "Rétablir les recettes écartées", "Les recettes écartées de la route de ce métier (par un clic sur une "
    .. "étape) peuvent de nouveau y être utilisées.")
P.restore = restore

local routeSummary = Font(P, "GameFontHighlight")
routeSummary:SetPoint("TOPLEFT", P, "TOPLEFT", 66, ROW2 - 4)
routeSummary:SetPoint("RIGHT", P, "RIGHT", -16, 0)
routeSummary:SetWordWrap(false)
P.routeSummary = routeSummary

local routeNote = Font(inset, "GameFontHighlightSmall", GREY)
routeNote:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -40)
routeNote:SetWidth(PROF_W - 16)
routeNote:SetText("Départ : le niveau simulé, sinon le tien ; arrivée : 300. Clic sur une étape : une autre route, "
    .. "sans sa recette.")
P.routeNote = routeNote

local SHOP_W, SHOP_ROW_H, ROUTE_ROW_H = 236, 24, 74
local ROUTE_W = LIST_W - SHOP_W - 24
local routeBox = CreateFrame("Frame", nil, inset)
routeBox:SetPoint("TOPLEFT", inset, "TOPLEFT", LIST_X, -6)
routeBox:SetSize(LIST_W, LIST_H)
routeBox:Hide()
P.routeBox = routeBox

-- (les pièces de la route : « 2 po 5 pa » ; un coût net négatif est un bénéfice)
local function NetText(net)
    if net <= -0.5 then return "bénéfice " .. ns.Signed(-net) end
    return "coût " .. ns.Money(net)
end

-- « 40 aux offres les moins chères de l'HV (22 pc à 25 pc l'unité) », « 20 chez le marchand, à 30 pc ».
local function RouteBuyLines(d)
    local lines = {}
    if (d.ah or 0) > 0 then
        local range = d.low and d.top and d.low ~= d.top and (ns.Money(d.low) .. " à " .. ns.Money(d.top))
            or (d.low and ns.Money(d.low)) or "?"
        lines[#lines + 1] = (d.estimate and "~ %s au prix le plus bas relevé à l'HV (%s l'unité ; ses offres une à une "
            .. "ne sont pas connues)" or "%s aux offres les moins chères de l'HV (%s l'unité)"):format(
            PX.Decimals(d.ah), range)
    end
    if (d.vendor or 0) > 0 then
        lines[#lines + 1] = ("%s chez le marchand, à %s"):format(PX.Decimals(d.vendor), ns.Money(d.vendorPrice))
    end
    return lines
end

local function StepColor(step)
    local up = ns.SkillUp(step.r, step.from, true)
    local color = up and ns.DIFFICULTY[up.kind]
    return color and ("|c" .. color .. step.r.name .. "|r") or step.r.name
end

local function ChanceText(step)
    local a, b = ns.Percent(step.chanceFrom), ns.Percent(step.chanceTo)
    return a == b and ("chance " .. a) or ("chance " .. a .. " à " .. b)
end

local function StepTooltip(owner, step)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(StepColor(step))
    local points = step.to - step.from
    GameTooltip:AddLine(("Niveaux %d à %d : %d point%s"):format(step.from, step.to, points, points > 1 and "s" or ""),
        1, 1, 1)
    GameTooltip:AddDoubleLine("Fabrications", ("%d (%s en moyenne)"):format(step.crafts,
        (("%.1f"):format(step.expected):gsub("%.", ","))), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Chance d'un point", ChanceText(step):gsub("^chance ", ""), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Temps", ("%s%s (%s chacune)"):format(step.castKnown and "" or "~", ns.TimeText(step.time),
        ns.TimeText(step.c.cast)), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Apprendre", step.learn and ns.LearnText(step.learn) or "apprise plus tôt dans la route",
        1, 0.82, 0, 1, 1, 1)
    if #step.reagents > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Composants", 1, 0.82, 0)
        for _, d in ipairs(step.reagents) do
            GameTooltip:AddDoubleLine(("%s x %s"):format(PX.Decimals(d.n), (ItemName(d.id))), ns.Money(d.cost), 1, 1, 1, 1, 1, 1)
            for _, line in ipairs(RouteBuyLines(d)) do GameTooltip:AddLine("   " .. line, 0.7, 0.7, 0.7, true) end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Achat des composants", ns.Money(step.buy), 1, 0.82, 0, 1, 1, 1)
    if step.learnCost > 0 then GameTooltip:AddDoubleLine("Apprentissage", ns.Money(step.learnCost), 1, 0.82, 0, 1, 1, 1) end
    GameTooltip:AddDoubleLine("Revente au marchand", step.unsellable and "invendable (0)" or ns.Money(step.resale),
        1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Étape", NetText(step.net), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Clic : une autre route, sans cette recette (« Rétablir », en haut, la rend). Maj + clic : lien.",
        0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function RouteReagentTooltip(owner, d)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) else GameTooltip:SetText((ItemName(d.id))) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(("%s pour cette étape"):format(PX.Decimals(d.n)), ns.Money(d.cost), 1, 0.82, 0, 1, 1, 1)
    for _, line in ipairs(RouteBuyLines(d)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end

local routeList = NewList(routeBox, ROUTE_W, LIST_H, ROUTE_ROW_H, function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = Font(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.name:SetWordWrap(false)
    row.line = Font(row, "GameFontHighlightSmall", GREY)
    row.line:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.line:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.line:SetWordWrap(false)
    row.learn = Font(row, "GameFontHighlightSmall")
    row.learn:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 0, -3)
    row.learn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.learn:SetWordWrap(false)
    row.price = Font(row, "GameFontHighlight")
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.price:SetJustifyH("RIGHT")
    row.reagents = {}
    for i = 1, REAGENTS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(REAGENT_SIZE, REAGENT_SIZE)
        b:SetPoint("TOPLEFT", row.learn, "BOTTOMLEFT", (i - 1) * (REAGENT_SIZE + 18), -4)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints(b)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, -2)
        b.count:SetJustifyH("LEFT")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self) if self.detail then RouteReagentTooltip(self, self.detail) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.detail and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                local _, link = ItemName(self.detail.id)
                HandleModifiedItemClick(link or ("item:" .. self.detail.id))
            end
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
        b:Hide()
        row.reagents[i] = b
    end
end, function(row, e)
    for _, b in ipairs(row.reagents) do b.detail = nil b:Hide() end
    row.price:SetText("")
    row.learn:SetText("")
    row.icon:SetDesaturated(false)
    if e.kind == "step" then
        row.icon:SetTexture(RecipeIcon(e.r))
        row.name:SetText(("|cffffffff%d à %d|r   %s"):format(e.from, e.to, StepColor(e)))
        row.line:SetText(("%d fabrication%s · %s%s · %s"):format(e.crafts, e.crafts > 1 and "s" or "",
            e.castKnown and "" or "~", ns.TimeText(e.time), ChanceText(e)))
        row.learn:SetText(e.learn and ("|cffd0a060" .. ns.LearnText(e.learn) .. "|r")
            or "|cff9d9d9dapprise plus tôt dans la route|r")
        row.price:SetText(ns.Money(e.buy + e.learnCost) .. " (" .. ns.Signed(-e.net) .. ")")
        for i, b in ipairs(row.reagents) do
            local d = e.reagents[i]
            if d then
                b.detail = d
                b.tex:SetTexture(ItemIcon(d.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.count:SetText(PX.Decimals(d.n))
                b:Show()
            end
        end
    elseif e.kind == "rank" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        row.name:SetText(("|cffffd100%d|r   Rang %s"):format(e.level, e.name))
        row.line:SetText(("Apprendre le rang %s pour dépasser %d (son prix n'est pas compté)."):format(e.name, e.level))
    elseif e.kind == "start" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        row.name:SetText("Apprendre le métier")
        row.line:SetText("Le personnage n'a pas ce métier : l'apprendre d'abord chez un formateur.")
    else -- (gap : plus de recette pour monter)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(true)
        row.name:SetText(("|cffff4040%d|r   Plus de recette pour monter"):format(e.level))
        local info, parts = e.info or {}, {}
        if (info.unlearnable or 0) > 0 then parts[#parts + 1] = ("%d ne s'apprennent pas"):format(info.unlearnable) end
        if (info.unbuyable or 0) > 0 then parts[#parts + 1] = ("%d ont un composant qui ne s'achète pas"):format(info.unbuyable) end
        if (info.recharge or 0) > 0 then parts[#parts + 1] = ("%d ont un temps de recharge"):format(info.recharge) end
        if (info.excluded or 0) > 0 then parts[#parts + 1] = ("%d écartées"):format(info.excluded) end
        row.line:SetText("Aucune recette utilisable ne donne de point à ce niveau"
            .. (#parts > 0 and (" (dans ce métier : " .. table.concat(parts, ", ") .. ")") or "") .. ".")
        row.learn:SetText("|cff9d9d9dUne recette ne s'apprend pas quand ni le formateur, ni un marchand, ni l'HV "
            .. "(au dernier relevé) ne la donnent.|r")
    end
end)
routeList:SetPoint("TOPLEFT", routeBox, "TOPLEFT", 0, 0)
for _, row in ipairs(routeList.rows) do
    row:SetScript("OnEnter", function(self)
        if self.entry and self.entry.kind == "step" then StepTooltip(self, self.entry) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not (e and e.kind == "step") then return end
        if IsModifiedClick and IsModifiedClick() then
            if e.r.out and HandleModifiedItemClick then
                local _, link = ItemName(e.r.out)
                HandleModifiedItemClick(link or ("item:" .. e.r.out))
            end
            return
        end
        GameTooltip:Hide()
        ns.ExcludeFromRoute(e.r.skillLine, e.r.id)
    end)
end
P.routeList = routeList

local routeEmpty = Font(routeBox, "GameFontHighlight", GREY)
routeEmpty:SetPoint("TOPLEFT", routeBox, "TOPLEFT", 30, -60)
routeEmpty:SetWidth(ROUTE_W - 60)
routeEmpty:SetJustifyH("CENTER")
routeEmpty:Hide()
P.routeEmpty = routeEmpty

-- Ce qu'il faut acheter
local shopSep = routeBox:CreateTexture(nil, "ARTWORK")
shopSep:SetColorTexture(1, 1, 1, 0.08)
shopSep:SetWidth(1)
shopSep:SetPoint("TOPLEFT", routeBox, "TOPLEFT", ROUTE_W + 14, 0)
shopSep:SetPoint("BOTTOMLEFT", routeBox, "BOTTOMLEFT", ROUTE_W + 14, 0)
local shopTitle = Font(routeBox, "GameFontNormal")
shopTitle:SetPoint("TOPLEFT", routeBox, "TOPLEFT", ROUTE_W + 22, -4)
shopTitle:SetWidth(SHOP_W - 14)
shopTitle:SetWordWrap(false)
P.shopTitle = shopTitle
local shopList = NewList(routeBox, SHOP_W - 14, LIST_H - 24, SHOP_ROW_H, function(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.price = Font(row, "GameFontHighlightSmall")
    row.price:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.price:SetJustifyH("RIGHT")
    row.name = Font(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
end, function(row, e)
    row.icon:SetTexture(ItemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local name, _, hex = ItemName(e.id)
    row.name:SetText(("%s%s x %s%s"):format(e.estimate and "~" or "", PX.Decimals(e.n), hex or "", name)
        .. (hex and "|r" or ""))
    row.price:SetText(ns.Money(e.cost))
end)
shopList:SetPoint("TOPLEFT", routeBox, "TOPLEFT", ROUTE_W + 20, -24)
for _, row in ipairs(shopList.rows) do
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.id) else GameTooltip:SetText((ItemName(e.id))) end
        GameTooltip:AddLine(" ")
        if e.learn then
            GameTooltip:AddLine(("Pour apprendre « %s » : %s"):format(e.r.name, ns.LearnText(e.learn)), 1, 1, 1, true)
        else
            GameTooltip:AddDoubleLine(("%s pour la route"):format(PX.Decimals(e.n)), ns.Money(e.cost), 1, 0.82, 0, 1, 1, 1)
            for _, line in ipairs(RouteBuyLines(e)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.entry and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            local _, link = ItemName(self.entry.id)
            HandleModifiedItemClick(link or ("item:" .. self.entry.id))
        end
    end)
end
P.shopList = shopList

-- Wishlist : les recettes à fabriquer tout de suite (Wishlist.lua), achetées par Purchase.lua -------------------------
-- En haut, son bilan (coût, revente, bénéfice), « Vider » et « Confirmer les achats » (« Arrêter les achats » pendant
-- les achats) ; dessous, ce qu'il faut acheter et où, ou où en sont les achats. Dans l'encart, toute la largeur, une
-- ligne par recette : ses composants (combien en acheter ; au survol, d'où ils viennent et leur prix), son coût et son
-- bénéfice, ce qu'elle dépense, et en bas à droite son nombre de fabrications et « Retirer ».
local wishSummary = Font(P, "GameFontHighlight")
wishSummary:SetPoint("TOPLEFT", P, "TOPLEFT", 66, ROW1 - 4)
wishSummary:SetPoint("RIGHT", P, "RIGHT", -290, 0)
wishSummary:SetWordWrap(false)
P.wishSummary = wishSummary

local wishConfirm = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
wishConfirm:SetSize(170, 22)
wishConfirm:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, ROW1 + 2)
wishConfirm:SetMotionScriptsWhileDisabled(true)
wishConfirm:SetScript("OnClick", function()
    if ns.WishlistBuying() then
        ns.WishlistStop()
        ns.Say("achats de la wishlist arrêtés : le reste n'est pas acheté.")
        return
    end
    local ok, why = ns.WishlistConfirm()
    if not ok then
        ns.Say("pas d'achats : " .. (why or "rien à acheter."))
    elseif why then
        ns.Say(why)
    else
        ns.Say("achats confirmés : ouvre l'hôtel des ventes ou la fenêtre d'un marchand, ils commencent d'eux-mêmes.")
    end
end)
wishConfirm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if ns.WishlistBuying() then
        GameTooltip:SetText("Arrêter les achats", 1, 0.82, 0)
        GameTooltip:AddLine("Le reste n'est pas acheté. Ce qui l'a été reste aux recettes de la wishlist : une nouvelle "
            .. "confirmation ne le rachète pas.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Confirmer les achats", 1, 0.82, 0)
        GameTooltip:AddLine("Fige ce qu'il faut acheter, où et à quel prix (celui de l'aperçu). Ensuite, dès que tu "
            .. "ouvres l'hôtel des ventes, une fenêtre propose chaque achat : le jeu demande un clic par achat. Chez un "
            .. "marchand, tout s'achète sans clic dès que sa fenêtre est ouverte. Un prix plus haut que prévu demande ta "
            .. "confirmation (prix avant et après, nouveau bénéfice) : continuer, ou passer à la recette suivante. Ce qui "
            .. "est pris dans tes sacs est réservé aux recettes de la wishlist.", 1, 1, 1, true)
        if not self:IsEnabled() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rien à acheter : la wishlist est vide, ou tous ses composants sont déjà là.", 1, 0.3, 0.3, true)
        end
    end
    GameTooltip:Show()
end)
wishConfirm:SetScript("OnLeave", function() GameTooltip:Hide() end)
P.wishConfirm = wishConfirm

local wishClear = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
wishClear:SetSize(90, 22)
wishClear:SetPoint("RIGHT", wishConfirm, "LEFT", -6, 0)
wishClear:SetText("Vider")
wishClear:SetMotionScriptsWhileDisabled(true)
wishClear:SetScript("OnClick", function() ns.WishlistClear() end)
Tip(wishClear, "Vider la wishlist", "Retire toutes ses recettes (pas pendant des achats). Une recette fabriquée se retire "
    .. "de la wishlist : ses composants ne lui sont plus réservés.")
P.wishClear = wishClear

local wishStatus = Font(P, "GameFontHighlightSmall", GREY)
wishStatus:SetPoint("TOPLEFT", P, "TOPLEFT", 66, ROW2 - 4)
wishStatus:SetPoint("RIGHT", P, "RIGHT", -196, 0)
wishStatus:SetWordWrap(false)
P.wishStatus = wishStatus

-- (pendant les achats, l'hôtel des ventes ouvert et sa fenêtre des achats fermée : la rouvrir)
local wishPanel = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
wishPanel:SetSize(170, 22)
wishPanel:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, ROW2 + 2)
wishPanel:SetText("Fenêtre des achats")
wishPanel:SetScript("OnClick", function() if ns.ShowBuyFrame then ns.ShowBuyFrame() end end)
Tip(wishPanel, "Fenêtre des achats", "Rouvre la fenêtre des achats de la wishlist, à l'hôtel des ventes.")
wishPanel:Hide()
P.wishPanel = wishPanel

local wishBox = CreateFrame("Frame", nil, inset)
wishBox:SetPoint("TOPLEFT", inset, "TOPLEFT", FULL_X, -6)
wishBox:SetSize(FULL_W, LIST_H)
wishBox:Hide()
P.wishBox = wishBox

-- (où s'achètent les composants d'une recette, en un mot : « HV : 2 composants · marchand : 1 · sacs : 1 »)
local function WhereText(p)
    local ah, vendor, bags = 0, 0, 0
    for _, d in ipairs(p.reagents) do
        if d.ahUnits > 0 then ah = ah + 1 end
        if d.vendor > 0 then vendor = vendor + 1 end
        if d.bags > 0 then bags = bags + 1 end
    end
    local parts = {}
    if ah > 0 then parts[#parts + 1] = "HV : " .. Plural(ah, "composant") end
    if vendor > 0 then parts[#parts + 1] = "marchand : " .. vendor end
    if bags > 0 then parts[#parts + 1] = "sacs : " .. bags end
    return table.concat(parts, " · ")
end

-- Infobulle d'un composant de la wishlist : combien il en faut, ce qui est déjà là, puis où il s'achète et à quel prix
-- (pendant les achats : où ils en sont).
local function WishReagentTooltip(owner, p, d)
    local N = PX.Decimals
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) else GameTooltip:SetText((ItemName(d.id))) end
    GameTooltip:AddLine(" ")
    local per = d.need / math.max(1, p.crafts)
    GameTooltip:AddDoubleLine("Il en faut", p.crafts > 1 and ("%s x %d = %s"):format(N(per), p.crafts, N(d.need))
        or N(d.need), 1, 0.82, 0, 1, 1, 1)
    if d.have > 0 then GameTooltip:AddDoubleLine("Déjà à cette recette", N(d.have), 1, 0.82, 0, 1, 1, 1) end
    if d.bags > 0 then GameTooltip:AddDoubleLine("Pris dans tes sacs", N(d.bags), 1, 0.82, 0, 1, 1, 1) end
    if p.buys then
        for _, b in ipairs(p.buys) do
            if b.item == d.id then
                GameTooltip:AddDoubleLine(b.where == "ah" and "À l'hôtel des ventes" or "Chez un marchand",
                    ("%s sur %s achetés%s"):format(N(b.got), N(b.n), b.skipped and " (recette passée)" or ""),
                    1, 0.82, 0, 1, 1, 1)
                if b.got > 0 then
                    GameTooltip:AddLine(("   %s dépensés%s"):format(ns.Money(b.spent), b.planned
                        and (" (prévu " .. ns.Money(b.planned * math.min(b.got, b.n) / b.n) .. ")") or ""), 0.8, 0.8, 0.8, true)
                end
                if b.missing > 0 then
                    GameTooltip:AddLine(("   %s introuvables à l'hôtel des ventes"):format(N(b.missing)), 1, 0.5, 0.25, true)
                end
            end
        end
    else
        if d.buy == 0 then GameTooltip:AddLine("Rien à acheter : tout est déjà là.", 0.25, 1, 0.25, true) end
        if d.ah > 0 then
            local range = (d.low and d.top and d.low ~= d.top) and (ns.Money(d.low) .. " à " .. ns.Money(d.top))
                or (d.low and ns.Money(d.low)) or "?"
            GameTooltip:AddDoubleLine(N(d.ah) .. " à l'hôtel des ventes", d.ahCost and ((d.estimate and "~" or "")
                .. ns.Money(d.ahCost)) or "prix inconnu", 1, 0.82, 0, 1, 1, 1)
            if not d.ahCost then
                GameTooltip:AddLine("   aucun prix connu : il sera cherché à l'achat", 0.8, 0.8, 0.8, true)
            elseif d.estimate then
                GameTooltip:AddLine(("   ~ au prix le plus bas connu (%s l'unité) : ses offres ne sont pas relevées "
                    .. "(« Scanner l'HDV »)"):format(range), 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine(("   aux offres les moins chères (%s l'unité), relevées %s"):format(range,
                    PX.AgeText(d.age or 0)), 0.8, 0.8, 0.8, true)
            end
        end
        if d.short > 0 then
            GameTooltip:AddDoubleLine(("|cffff8040%s de plus à l'hôtel des ventes|r"):format(N(d.short)),
                d.shortCost and ("~" .. ns.Money(d.shortCost)) or "prix inconnu", 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine("   pas assez en vente au dernier relevé, et aucun marchand ne le vend : il sera cherché à "
                .. "l'achat" .. (d.shortPrice and (" (compté à " .. ns.Money(d.shortPrice) .. ", "
                .. PX.Label(d.shortSource) .. ")") or ""), 0.8, 0.8, 0.8, true)
        end
        if d.vendor > 0 then
            GameTooltip:AddDoubleLine(N(d.vendor) .. " chez un marchand", ("%s (%s l'unité)"):format(
                ns.Money(d.vendorCost), ns.Money(d.vendorPrice)), 1, 0.82, 0, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

-- Infobulle d'une recette de la wishlist : l'objet créé, puis ses montants.
local function WishTooltip(owner, p)
    local r = p.r
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if r and r.out and GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.out)
    elseif r and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(r.id)
    else GameTooltip:SetText(r and r.name or ("Recette %d"):format(p.entry.id)) end
    GameTooltip:AddLine(" ")
    if not r then
        GameTooltip:AddLine("Cette recette n'est plus dans les données de ForeverCraftAtlas : retire-la.", 1, 0.4, 0.4, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(("%s · %s"):format(ns.ProfessionName(r.skillLine), Plural(p.crafts, "fabrication")), 1, 0.82, 0)
    if p.time then GameTooltip:AddDoubleLine("Temps de fabrication", ns.TimeText(p.time), 1, 0.82, 0, 1, 1, 1) end
    local function Line(label, value) GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1) end
    if p.rec then
        local cost, profit = ns.PlanRecipeNow(p.rec)
        Line("Coût prévu", p.rec.cost and ns.Money(p.rec.cost) or "inconnu")
        Line("Coût d'après les achats faits", cost and ns.Money(cost) or "inconnu")
        Line("Revente", p.rec.value and ns.Money(p.rec.value) or "inconnue")
        Line("Bénéfice attendu", profit and ns.Signed(profit) or "inconnu")
        if p.rec.skipped then
            GameTooltip:AddLine("Recette passée : le reste de ses composants n'est pas acheté.", 1, 0.5, 0.25, true)
        end
    else
        Line("Achats", p.complete and "rien à acheter" or (p.spend and ((p.estimate and "~" or "") .. ns.Money(p.spend))
            or "prix inconnus"))
        Line("Coût (achats et ce qui est déjà là)", p.cost and ((p.estimate and "~" or "") .. ns.Money(p.cost)) or "inconnu")
        Line(p.valueKind == "vendor" and "Revente au marchand" or "Revente", p.value and ns.Money(p.value)
            or (r.out and "inconnue" or "rien de créé"))
        Line("Bénéfice", p.profit and ns.Signed(p.profit) or "inconnu")
        GameTooltip:AddLine("Ce qui est déjà là compte au prix le plus bas du moment.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine("Ses composants : survole leurs icônes. Maj + clic : lien de l'objet.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function BuildWishRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = Font(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5)
    row.name:SetPoint("RIGHT", row, "RIGHT", -360, 0)
    row.name:SetWordWrap(false)
    row.line = Font(row, "GameFontHighlightSmall", GREY)
    row.line:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.line:SetPoint("RIGHT", row, "RIGHT", -360, 0)
    row.line:SetWordWrap(false)
    row.price = Font(row, "GameFontHighlight")
    row.price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.price:SetJustifyH("RIGHT")
    row.sub = Font(row, "GameFontDisableSmall")
    row.sub:SetPoint("TOPRIGHT", row.price, "BOTTOMRIGHT", 0, -3)
    row.sub:SetJustifyH("RIGHT")
    row.state = Font(row, "GameFontHighlightSmall")
    row.state:SetPoint("TOPRIGHT", row.sub, "BOTTOMRIGHT", 0, -3)
    row.state:SetJustifyH("RIGHT")
    row.reagents = {}
    for i = 1, REAGENTS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(REAGENT_SIZE, REAGENT_SIZE)
        b:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", (i - 1) * (REAGENT_SIZE + 22), -8)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints(b)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, -2)
        b.count:SetJustifyH("LEFT")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self) if self.detail and row.entry then WishReagentTooltip(self, row.entry, self.detail) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.detail and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
                local _, link = ItemName(self.detail.id)
                HandleModifiedItemClick(link or ("item:" .. self.detail.id))
            end
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) row:GetScript("OnMouseWheel")(row, delta) end)
        b:Hide()
        row.reagents[i] = b
    end
    -- (en bas à droite : son nombre de fabrications, et la retirer)
    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(80, 18)
    row.remove:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
    row.remove:SetText("Retirer")
    row.remove:SetMotionScriptsWhileDisabled(true)
    row.remove:SetScript("OnClick", function()
        local p = row.entry
        if p then ns.WishlistRemove(p.key) end
    end)
    Tip(row.remove, "Retirer de la wishlist", "Une fois la recette fabriquée (ou plus voulue) : ses composants ne lui sont "
        .. "plus réservés. Pas pendant des achats.")
    row.crafts = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.crafts:SetSize(44, 18)
    row.crafts:SetPoint("RIGHT", row.remove, "LEFT", -12, 0)
    row.crafts:SetAutoFocus(false)
    row.crafts:SetMaxLetters(4)
    if row.crafts.SetNumeric then row.crafts:SetNumeric(true) end
    row.crafts:SetScript("OnTextChanged", function(self, userInput)
        local p = row.entry
        local v = userInput and p and tonumber(self:GetText() or "")
        if v and v >= 1 then ns.WishlistSetCrafts(p.key, v) end
    end)
    row.crafts:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.crafts:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.crafts:SetScript("OnEditFocusLost", function(self)
        local p = row.entry
        if p then self:SetText(tostring(p.entry.crafts)) end
    end)
    Tip(row.crafts, "Fabrications", "Combien de fois fabriquer cette recette (1 à 9999) : ce qu'il faut acheter, le coût "
        .. "et le bénéfice suivent. Pas pendant des achats.")
    row.craftsText = Font(row, "GameFontHighlightSmall")
    row.craftsText:SetPoint("RIGHT", row.crafts, "LEFT", -8, 0)
    row.craftsText:SetText("Fabrications")
end

local WHITE, GREEN, ORANGE = { 1, 1, 1 }, { 0.25, 1, 0.25 }, { 1, 0.5, 0.25 }

local function FillWishRow(row, p)
    local r = p.r
    local buying = ns.WishlistBuying()
    row.icon:SetTexture(r and RecipeIcon(r) or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetDesaturated(not r)
    row.name:SetText(r and r.name or ("Recette %d (plus dans les données)"):format(p.entry.id))
    local parts = {}
    if r then parts[#parts + 1] = ns.ProfessionName(r.skillLine) end
    parts[#parts + 1] = Plural(p.crafts, "fabrication")
    if p.time then parts[#parts + 1] = ns.TimeText(p.time) end
    if r and not r.learned then parts[#parts + 1] = "|cffd0a060non apprise|r" end
    row.line:SetText(table.concat(parts, " · "))
    for i, b in ipairs(row.reagents) do
        local d = p.reagents[i]
        b.detail = d
        if d then
            b.tex:SetTexture(ItemIcon(d.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local n, color
            if p.buys then -- (pendant les achats : ce qu'il en reste à acheter ; vert : tout est là ; orangé : introuvables)
                local left, missing = 0, 0
                for _, x in ipairs(p.buys) do
                    if x.item == d.id then left, missing = left + ns.BuyRemaining(x), missing + x.missing end
                end
                n = left > 0 and left or (missing > 0 and missing or d.need)
                color = left > 0 and WHITE or (missing > 0 and ORANGE or GREEN)
            else -- (combien en acheter ; vert : rien, tout est là ; orangé : pas assez en vente au dernier relevé)
                n = d.buy > 0 and d.buy or d.need
                color = d.buy == 0 and GREEN or (d.short > 0 and ORANGE or WHITE)
            end
            b.count:SetText(PX.Decimals(n))
            b.count:SetTextColor(color[1], color[2], color[3])
            b:Show()
        else
            b:Hide()
        end
    end
    if p.rec then
        local cost, profit = ns.PlanRecipeNow(p.rec)
        row.price:SetText((cost and ns.Money(cost) or "?") .. (p.rec.value and (" (" .. ns.Signed(profit) .. ")") or ""))
        local spent, left = 0, 0
        for _, b in ipairs(p.buys) do
            spent = spent + b.spent
            if ns.BuyRemaining(b) > 0 then left = left + 1 end
        end
        row.sub:SetText("dépensé " .. ns.Money(spent))
        row.state:SetText(p.rec.skipped and "|cffff8040passée : le reste n'est pas acheté|r"
            or (left > 0 and ("|cffffd100%s à faire|r"):format(Plural(left, "achat")) or "|cff40ff40composants achetés|r"))
    else
        local approx = p.estimate and "~" or ""
        local price = p.cost and (approx .. ns.Money(p.cost)) or (r and #r.reagents == 0 and "—" or "?")
        row.price:SetText(price .. (p.value and (" (" .. ns.Signed(p.profit) .. ")") or ""))
        row.sub:SetText(p.complete and "rien à acheter"
            or ("à acheter : " .. (p.spend and (approx .. ns.Money(p.spend)) or "prix inconnus")))
        row.state:SetText(p.complete and "|cff40ff40prête : tous ses composants sont là|r" or WhereText(p))
    end
    if not row.crafts:HasFocus() then row.crafts:SetText(tostring(p.entry.crafts)) end
    row.crafts:SetEnabled(not buying)
    row.crafts:SetAlpha(buying and 0.5 or 1)
    row.remove:SetEnabled(not buying)
end

local wishList = NewList(wishBox, FULL_W, LIST_H, ROW_H, BuildWishRow, FillWishRow)
wishList:SetPoint("TOPLEFT", wishBox, "TOPLEFT", 0, 0)
for _, row in ipairs(wishList.rows) do
    row:SetScript("OnEnter", function(self) if self.entry then WishTooltip(self, self.entry) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local r = self.entry and self.entry.r
        if r and r.out and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            local _, link = ItemName(r.out)
            HandleModifiedItemClick(link or ("item:" .. r.out))
        end
    end)
end
P.wishList = wishList

local wishEmpty = Font(wishBox, "GameFontHighlight", GREY)
wishEmpty:SetPoint("TOPLEFT", wishBox, "TOPLEFT", 30, -60)
wishEmpty:SetPoint("TOPRIGHT", wishBox, "TOPRIGHT", -30, -60)
wishEmpty:SetJustifyH("CENTER")
wishEmpty:SetText("La wishlist est vide : « + Wishlist », sur une recette de l'onglet « Recettes », l'ajoute "
    .. " avec le nombre de « Fabrications ». Ici, elle dit ce qu'il faut acheter, le coût et le bénéfice, puis "
    .. "achète tout à l'hôtel des ventes et chez les marchands.")
wishEmpty:Hide()
P.wishEmpty = wishEmpty

-- L'onglet « Wishlist » : l'aperçu de la liste (Wishlist.lua) et, pendant les achats, où ils en sont.
local function RefreshWishlist()
    local preview = ns.WishlistPreview()
    local buying = ns.WishlistBuying()
    for _, p in ipairs(preview.entries) do
        p.rec = buying and ns.PlanRecipe(p.key) or nil
        p.buys = p.rec and ns.PlanBuys(p.key) or nil
    end
    P.wishPreview = preview
    wishList:SetData(preview.entries, P.keepOffset)
    P.keepOffset = false
    wishEmpty:SetShown(#preview.entries == 0)
    local t = preview.totals
    if buying then
        local spent, planned = 0, 0
        for _, b in ipairs(ns.WishlistPlan().buys) do
            spent = spent + b.spent
            planned = planned + (b.planned and b.planned * math.min(b.got, b.n) / b.n or b.spent)
        end
        wishSummary:SetText(("Achats en cours : %s dépensés (prévu %s)"):format(ns.Money(spent), ns.Money(planned)))
        wishStatus:SetText(("Restent %s à l'hôtel des ventes et %s chez un marchand : ouvre leur fenêtre, ils "
            .. "commencent d'eux-mêmes."):format(Plural(ns.BuysLeft("ah"), "achat"), Plural(ns.BuysLeft("vendor"), "achat")))
        wishConfirm:SetText("Arrêter les achats")
        wishConfirm:Enable()
        wishClear:Disable()
    else
        local approx = t.estimate and "~" or ""
        wishSummary:SetText(#preview.entries == 0 and "Wishlist vide"
            or ("%s · coût %s · revente %s · bénéfice %s"):format(Plural(t.recipes, "recette"),
                t.cost and (approx .. ns.Money(t.cost)) or "?", t.value and ns.Money(t.value) or "?", ns.Signed(t.profit)))
        local parts = {}
        if t.ahCount > 0 then
            parts[#parts + 1] = ("%s à l'hôtel des ventes (%s)"):format(t.ahSpend and (approx .. ns.Money(t.ahSpend)) or "?",
                Plural(t.ahCount, "achat"))
        end
        if t.vendorCount > 0 then
            parts[#parts + 1] = ("%s chez un marchand (%s)"):format(ns.Money(t.vendorSpend), Plural(t.vendorCount, "achat"))
        end
        local status = #parts > 0 and ("À acheter : " .. table.concat(parts, ", "))
            or (#preview.entries > 0 and "Rien à acheter : tous les composants sont là." or "")
        if t.bagCount > 0 then status = status .. " · déjà dans tes sacs : " .. Plural(t.bagCount, "composant") end
        local last = ns.WishlistLast()
        if last then
            status = status .. (" · derniers achats : %s dépensés (prévu %s)"):format(ns.Money(last.spent), ns.Money(last.planned))
        end
        wishStatus:SetText(status)
        wishConfirm:SetText("Confirmer les achats")
        wishConfirm:SetEnabled(t.todo > 0)
        wishClear:SetEnabled(#preview.entries > 0)
    end
    wishPanel:SetShown(ns.CanShowBuyFrame and ns.CanShowBuyFrame() or false)
end

-- Onglets, en bas de la fenêtre, comme ceux du jeu : « Recettes », « XP Road » et « Wishlist » (réglage « tab »).
local TAB_KEYS = { "recipes", "route", "wishlist" }
local TAB_INDEX = { recipes = 1, route = 2, wishlist = 3 }
local TAB_TITLES = { recipes = "ForeverCraftAtlas : recettes", route = "ForeverCraftAtlas : XP Road", wishlist = "ForeverCraftAtlas : wishlist" }
local tabs = {}
for i, label in ipairs({ "Recettes", "XP Road", "Wishlist" }) do
    local tab = CreateFrame("Button", "ForeverCraftAtlasFrameTab" .. i, P, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(label)
    if i == 1 then tab:SetPoint("TOPLEFT", P, "BOTTOMLEFT", 11, 2) else tab:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", 3, 0) end
    tab:SetScript("OnClick", function(self)
        ns.Set("tab", TAB_KEYS[self:GetID()])
    end)
    tabs[i] = tab
end
if not P.Tabs then P.Tabs = tabs end -- (le modèle les range déjà dans P.Tabs)
if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(P, #tabs) end
P.tabs = tabs

-- (ce qui se voit dans chaque onglet : les métiers à gauche pour les recettes et la route ; la wishlist prend toute la
-- largeur)
local SHOWN = {
    recipes = { show, showText, sort, sortText, vendorResale, vendorText, searchText, search, levelText, level,
        craftsText, crafts, header, typeMenu, minText, minProfit, minUnit,
        favorites, favoritesText, listBox },
    route = { routeMode, routeModeText, routeSummary, routeNote, routeBox },
    wishlist = { wishSummary, wishConfirm, wishClear, wishStatus, wishBox },
}
for _, f in ipairs({ mine, mineText, profBox, sep, simText, simSkill }) do
    table.insert(SHOWN.recipes, f)
    table.insert(SHOWN.route, f)
end
local TAB_WIDGETS = {}
for _, set in pairs(SHOWN) do
    for _, f in ipairs(set) do TAB_WIDGETS[f] = true end
end
local function ShowTab(tab)
    local visible = {}
    for _, f in ipairs(SHOWN[tab]) do visible[f] = true end
    for f in pairs(TAB_WIDGETS) do f:SetShown(visible[f] or false) end
end

-- Bas de la fenêtre
local settings = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
settings:SetSize(110, 22)
settings:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", -6, 4)
settings:SetText("Réglages")
settings:SetScript("OnClick", function() ns.OpenSettings() end)
-- « ForeverExchange » : ouvre sa fenêtre (ses prix sont lus en direct, rien à recharger) ; grisé sans lui.
local refresh = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
refresh:SetSize(120, 22)
refresh:SetPoint("RIGHT", settings, "LEFT", -4, 0)
refresh:SetText("ForeverExchange")
refresh:SetMotionScriptsWhileDisabled(true)
refresh:SetScript("OnClick", function()
    if type(_G.ForeverExchange_Toggle) == "function" then _G.ForeverExchange_Toggle() end
end)
refresh:HookScript("OnShow", function(self) self:SetEnabled(type(_G.ForeverExchange_Toggle) == "function") end)
refresh:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("ForeverExchange", 1, 0.82, 0)
    if type(_G.ForeverExchange_Toggle) ~= "function" then
        GameTooltip:AddLine("ForeverExchange n'est pas chargé (facultatif) : ForeverCraftAtlas se sert alors de ses "
            .. "propres relevés et des marchands.", 1, 0.5, 0.25, true)
    end
    GameTooltip:AddLine(PX.EXCHANGE_HELP, 1, 1, 1, true)
    local lines = PX.DataLines()
    if #lines > 0 then GameTooltip:AddLine(" ") end
    for _, l in ipairs(lines) do GameTooltip:AddDoubleLine(l[1], l[2], 1, 0.82, 0, 1, 1, 1) end
    GameTooltip:Show()
end)
refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
P.refresh = refresh
-- « Scanner l'HDV » : le relevé de tout l'hôtel des ventes, seulement de ce bouton (plus rien à son ouverture :
-- PX.autoScan, Core.lua) ; grisé quand il est fermé ou qu'un relevé est en cours.
local scanAH = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
scanAH:SetSize(120, 22)
scanAH:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
scanAH:SetText("Scanner l'HDV")
scanAH:SetMotionScriptsWhileDisabled(true) -- (l'infobulle dit pourquoi il est grisé)
local function ScanTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Scanner l'hôtel des ventes", 1, 0.82, 0)
    GameTooltip:AddLine(PX.SCAN_HELP, 1, 1, 1, true)
    local ok, why = PX.CanScan()
    if not ok then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(why, 1, 0.3, 0.3, true)
    elseif PX.ScanWait() > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Chaque offre de nouveau dans %d min : d'ici là, la recherche de tous les objets."):format(
            math.ceil(PX.ScanWait() / 60)), 0.8, 0.8, 0.8, true)
    end
    local line = PX.ScanLine()
    if line then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end
scanAH:SetScript("OnClick", function(self)
    PX.ScanNow()
    self:SetEnabled((PX.CanScan()))
    if GameTooltip:GetOwner() == self then ScanTip(self) end
end)
scanAH:SetScript("OnEnter", ScanTip)
scanAH:SetScript("OnLeave", function() GameTooltip:Hide() end)
P.scan = scanAH
local dated = Font(P, "GameFontHighlightSmall", GREY)
dated:SetPoint("RIGHT", scanAH, "LEFT", -8, 0)
dated:SetJustifyH("RIGHT")
P.dated = dated
local status = Font(P, "GameFontHighlightSmall", GREY)
status:SetPoint("BOTTOMLEFT", pager, "BOTTOMRIGHT", 10, 5) -- (à droite des pages ; sans pages, au bord)
status:SetPoint("RIGHT", dated, "LEFT", -12, 0)
status:SetWordWrap(false)
P.status = status
-- La barre du relevé de l'hôtel des ventes, à la place de cette ligne pendant qu'il se fait (Prices.ScanBar).
local scanBar = PX.ScanBar(P, function(shown) status:SetShown(not shown) end)
scanBar:SetPoint("BOTTOMLEFT", pager, "BOTTOMRIGHT", 10, 3)
scanBar:SetPoint("RIGHT", dated, "LEFT", -12, 0)
P.scanBar = scanBar

-- Affichage -----------------------------------------------------------------------------------------------------------
local function ProfessionEntries()
    local my = ns.MyProfessions()
    local entries = { { skillLine = 0, text = "Tous les métiers" } }
    for _, skillLine in ipairs(ns.AllProfessions()) do
        if not ns.Get("mine") or my[skillLine] then
            local m, sim = my[skillLine], ns.SimSkill(skillLine)
            -- (niveau simulé : en bleu, le vrai en gris entre parenthèses, « 225 (185) »)
            local level = m and ("  |cffffffff" .. m.skill .. "|r") or ""
            if sim then
                level = "  |cff66bbff" .. sim .. "|r" .. (m and (" |cff9d9d9d(" .. m.skill .. ")|r") or "")
            end
            entries[#entries + 1] = { skillLine = skillLine, text = ns.ProfessionName(skillLine) .. level }
        end
    end
    return entries
end

-- (recipes : la liste vide, avec combien de recettes y manquent faute d'objet prêt ou de composant qui s'achète,
-- ns.List)
local function EmptyText(recipes)
    if #ns.AllRecipes() == 0 then
        return "Aucune recette encore : ouvre la fenêtre d'un de tes métiers (ForeverCraftAtlas lit ses recettes)."
            .. " Les données de tous les métiers (Data.lua) manquent : réinstalle l'addon."
    end
    if ns.Get("favoritesOnly") and ns.FavoriteCount() == 0 then
        return "Aucun favori : l'étoile à gauche du nom d'une recette la met en favori. Décoche « Favoris » pour voir "
            .. "toutes les recettes."
    end
    local waiting, unknown = recipes and recipes.waiting or 0, recipes and recipes.unknown or 0
    local unbuyable = recipes and recipes.unbuyable or 0
    if waiting > 0 then
        return ("Chargement : le jeu demande au serveur les objets de %d recette%s."):format(waiting, waiting > 1 and "s" or "")
    end
    if unbuyable > 0 then
        local text = unbuyable > 1 and ("Aucune recette à montrer : %d correspondent, mais un de leurs composants ne "
            .. "s'achète pas : il n'était pas en vente au dernier relevé de l'hôtel des ventes, et aucun marchand ne le "
            .. "vend (elles reviennent quand il y est en vente)."):format(unbuyable)
            or ("Aucune recette à montrer : une correspond, mais un de ses composants ne s'achète pas : il n'était pas "
                .. "en vente au dernier relevé de l'hôtel des ventes, et aucun marchand ne le vend (elle revient quand il "
                .. "y est en vente).")
        if unknown > 0 then
            text = text .. (" Le serveur de Forever n'a pas les objets de %d autre%s."):format(unknown, unknown > 1 and "s" or "")
        end
        return text
    end
    if unknown > 1 then
        return ("Aucune recette à montrer : %d correspondent, mais le serveur de Forever n'a pas leurs objets (leur "
            .. "infobulle resterait sur « Récupération des informations de l'objet »)."):format(unknown)
    elseif unknown == 1 then
        return "Aucune recette à montrer : une correspond, mais le serveur de Forever n'a pas son objet (son infobulle "
            .. "resterait sur « Récupération des informations de l'objet »)."
    end
    if ns.Get("minProfit") then
        return ("Aucune recette ne correspond (filtres, recherche, métier choisi, type d'objet, bénéfice plus de %s)."):format(
            ns.Money(ns.Get("minProfit")) .. (ns.Get("minProfit") < 0 and " de perte" or ""))
    end
    return "Aucune recette ne correspond (filtres, recherche, métier choisi, type d'objet)."
end

local function StatusText()
    local parts = {}
    -- (le dernier relevé de tout l'hôtel des ventes ; sinon combien d'objets ont un prix relevé ; puis ForeverExchange)
    local live = PX.LiveCount()
    local scan = PX.ScanText(true) or (live > 0 and ("%d prix relevés à l'HV"):format(live))
        or "pas encore de relevé de l'HV"
    if not ns.HasExchange() then
        parts[1] = "Prix : " .. scan .. " (ForeverExchange absent : sinon les marchands)"
    else
        parts[1] = "Prix : " .. scan .. " (sans relevé : ForeverExchange, " .. PX.Short(ns.BuySource()) .. ")"
    end
    if ns.VendorResale() then parts[#parts + 1] = "Revente : au marchand" end
    -- (les données de tous les métiers : dans les réglages, la place est pour la date des prix)
    local scanned = 0
    for _ in pairs(ns.Scans()) do scanned = scanned + 1 end
    parts[#parts + 1] = ("%d métier%s lu%s"):format(scanned, scanned > 1 and "s" or "", scanned > 1 and "s" or "")
    return table.concat(parts, " · ")
end

-- L'onglet « XP Road » : la route du métier choisi (Route.lua).
local function RefreshRoute(profession)
    local excluded = profession ~= 0 and ns.RouteExcludedCount(profession) or 0
    restore:SetShown(excluded > 0)
    restore:SetText(("Rétablir %d recette%s"):format(excluded, excluded > 1 and "s" or ""))
    if routeMode.GenerateMenu then routeMode:GenerateMenu() end
    if profession == 0 then
        P.route = nil
        routeList:SetData({})
        shopList:SetData({})
        shopTitle:SetText("")
        routeEmpty:SetText("Choisis un métier à gauche : sa route de ton niveau (ou du niveau simulé) jusqu'à 300.")
        routeEmpty:Show()
        routeSummary:SetText("XP Road : la meilleure façon de monter un métier, aux prix relevés")
        return
    end
    local route = ns.Route(profession, ns.Get("routeMode"))
    P.route = route
    routeList:SetData(route.rows, P.keepOffset)
    shopList:SetData(route.shopping, P.keepOffset)
    P.keepOffset = false
    local t, name = route.totals, ns.ProfessionName(profession)
    local waiting = route.info and route.info.waiting or 0
    if route.done then
        routeEmpty:SetText(("%s est déjà à %d : plus rien à monter."):format(name, route.target))
    elseif #route.steps == 0 and waiting > 0 then
        routeEmpty:SetText(("Chargement : le jeu demande au serveur les objets de %d recette%s."):format(waiting,
            waiting > 1 and "s" or ""))
    else
        routeEmpty:SetText("")
    end
    routeEmpty:SetShown(routeEmpty:GetText() ~= "")
    local spent = t.buy + t.learn
    shopTitle:SetText("À acheter · " .. ns.Money(spent))
    if route.done or #route.steps == 0 then
        routeSummary:SetText(("%s : de %d à %d"):format(name, route.from, route.target))
        return
    end
    local approx = route.estimate and "~" or ""
    routeSummary:SetText(("%s : de %d à %d%s · %d fabrications · %s%s · %s (achats %s, revente %s)"):format(name,
        route.from, route.reached, route.reached < route.target and " |cffff4040(arrêt)|r" or "", t.crafts, approx,
        ns.TimeText(t.time), NetText(t.net), ns.Money(spent), ns.Money(t.resale)))
end

function ns.Refresh()
    if not P:IsShown() then return end
    local profession = ns.Get("profession")
    local entries = ProfessionEntries()
    local found = false
    for _, e in ipairs(entries) do if e.skillLine == profession then found = true end end
    if not found then ns.Set("profession", 0) return end
    profList:SetData(entries, true)
    local tab = TAB_INDEX[ns.Get("tab")] and ns.Get("tab") or "recipes"
    local onRoute = tab == "route"
    ShowTab(tab)
    ShowPager(false) -- (montrées plus bas, sur l'onglet Recettes)
    -- (sur la route, le niveau simulé est son départ : en haut de la colonne, seul)
    simText:ClearAllPoints()
    simText:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, onRoute and -14 or -72)
    if PanelTemplates_SetTab then PanelTemplates_SetTab(P, TAB_INDEX[tab]) end
    if P.SetTitle then P:SetTitle(TAB_TITLES[tab]) end
    status:SetText(StatusText())
    dated:SetText(PX.DataText())
    scanAH:SetEnabled((PX.CanScan()))
    mine:SetChecked(ns.Get("mine"))
    local oneProfession = profession ~= 0
    if not oneProfession then simSkill:ClearFocus() end
    simSkill:SetEnabled(oneProfession)
    simSkill:SetAlpha(oneProfession and 1 or 0.5)
    simText:SetAlpha(oneProfession and 1 or 0.5)
    if not simSkill:HasFocus() then simSkill:SetText(SimText()) end
    if tab ~= "wishlist" then wishPanel:Hide() end
    if onRoute then
        RefreshRoute(profession)
        return
    end
    restore:Hide()
    if tab == "wishlist" then
        RefreshWishlist()
        return
    end
    if not crafts:HasFocus() then crafts:SetText(tostring(ns.Crafts())) end
    vendorResale:SetChecked(ns.VendorResale())
    favorites:SetChecked(ns.Get("favoritesOnly"))
    if sort.GenerateMenu then sort:GenerateMenu() end
    -- (lazy : avec le tri par nom ou par niveau requis, seule la page affichée est chiffrée, ns.List)
    local recipes = ns.List({ lazy = true })
    P.recipes = recipes
    local pages = math.max(1, math.ceil(#recipes / PAGE))
    recipePage = math.max(1, math.min(recipePage, pages))
    local shown = {}
    for i = (recipePage - 1) * PAGE + 1, math.min(#recipes, recipePage * PAGE) do
        local r = recipes[i]
        if recipes.lazy then ns.Decorate(r, r.kind) end
        shown[#shown + 1] = r
    end
    P.page, P.pages, P.shown = recipePage, pages, shown
    list:SetData(shown, P.keepOffset)
    P.keepOffset = false
    pageText:SetText(("Page %d / %d"):format(recipePage, pages))
    ShowPager(pages > 1)
    pagePrev:SetEnabled(recipePage > 1)
    pageNext:SetEnabled(recipePage < pages)
    empty:SetShown(#recipes == 0)
    empty:SetText(#recipes == 0 and EmptyText(recipes) or "")
    local my = profession ~= 0 and ns.MyProfessions()[profession]
    local sim = profession ~= 0 and ns.SimSkill(profession)
    local itemType = ns.Get("itemType") or ""
    header:SetText(("%s%s%s%s · %d %s%s"):format(profession == 0 and "Tous les métiers" or ns.ProfessionName(profession),
        my and (" " .. my.skill .. " / " .. my.max) or "", sim and (" · |cff66bbffsimulé " .. sim .. "|r") or "",
        itemType ~= "" and (" · " .. ns.KindLabel(itemType, recipes.kinds)) or "",
        #recipes, ns.Get("favoritesOnly") and "favori" or "recette", #recipes > 1 and "s" or ""))
    if not search:HasFocus() then search:SetText(ns.Get("search") or "") end
    if not level:HasFocus() then
        local v = tonumber(ns.Get("maxLevel")) or 0
        level:SetText(v > 0 and tostring(v) or "")
    end
    if not minProfit:HasFocus() then minProfit:SetText(ns.GoldText(ns.Get("minProfit"))) end
    if show.GenerateMenu then show:GenerateMenu() end
    if typeMenu.GenerateMenu then typeMenu:GenerateMenu() end
    -- (le texte du bouton : le type choisi, sans son nombre)
    if typeMenu.OverrideText then typeMenu:OverrideText(ns.KindLabel(ns.Get("itemType"), recipes.kinds)) end
end

local token = 0
local function RefreshSoon()
    token = token + 1
    local mine = token
    C_Timer.After(0.15, function() if mine == token then ns.Refresh() end end)
end

-- Noms arrivés du jeu : les lignes et l'infobulle d'un parchemin sont redessinées (sans refaire les prix).
local redraw = false
local function Redraw()
    if redraw or not P:IsShown() then return end
    redraw = true
    C_Timer.After(0.3, function()
        redraw = false
        if not P:IsShown() then return end
        list:Render()
        wishList:Render()
        routeList:Render()
        shopList:Render()
        local owner = shownScroll.owner
        if owner and GameTooltip:IsShown() and GameTooltip:GetOwner() == owner then ScrollTooltip(owner, shownScroll.item) end
    end)
end

-- Des prix vus à l'hôtel des ventes pendant que la fenêtre est ouverte : elle suit.
ns.Prices.OnLive(function()
    if not P:IsShown() then return end
    P.keepOffset = true
    ns.Refresh()
end)

-- « < » et « > » : la page d'avant ou d'après, depuis son haut.
for _, b in ipairs({ pagePrev, pageNext }) do
    b:SetScript("OnClick", function(self)
        recipePage = recipePage + (self == pageNext and 1 or -1)
        ns.Refresh()
    end)
end

-- (ce qui ne change ni les recettes montrées ni leur ordre choisi : la page reste ; tout le reste revient à la première)
local KEEP_PAGE = { point = true, names = true, items = true, scan = true, skills = true, trainer = true, route = true,
    favorites = true, wishlist = true, wishlistCrafts = true, tab = true, routeMode = true }

ns.OnChange(function(key)
    if key == "point" then return end
    if not KEEP_PAGE[key] then recipePage = 1 end
    if key == "names" then Redraw() return end
    if key == "items" then -- (des objets arrivés du serveur : leurs recettes rejoignent la liste)
        if not P:IsShown() then return end
        P.keepOffset = true
    end
    if key == "search" or key == "maxLevel" or key == "crafts" or key == "minProfit"
        or key == "simSkill" or key == "wishlistCrafts" then
        RefreshSoon() return
    end
    if key == "favorites" or key == "wishlist" then
        -- (l'étoile et « + Wishlist » des lignes ; avec la case « Favoris », une recette retirée des favoris s'en va)
        if ns.Get("tab") ~= "wishlist" and not (key == "favorites" and ns.Get("favoritesOnly")) then
            if P:IsShown() then list:Render() end
            return
        end
        P.keepOffset = true
    end
    if key == "scan" or key == "skills" or key == "trainer" or key == "route" then P.keepOffset = true end
    ns.Refresh()
end)

P:HookScript("OnShow", function(self)
    local point = ns.Get("point")
    if type(point) == "table" and point[1] then
        self:ClearAllPoints()
        self:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    end
    self:Raise() -- (ouverte devant les autres fenêtres, comme le jeu le fait pour les siennes)
    PX.Clear() -- (les achats de plusieurs recomptés à chaque ouverture)
    ns.Refresh()
end)
P:HookScript("OnHide", function()
    search:ClearFocus()
end)

-- Après un rechargement demandé par l'addon : la fenêtre se rouvre.
local reopen = CreateFrame("Frame")
reopen:RegisterEvent("PLAYER_ENTERING_WORLD")
reopen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    PX.Reopen(ForeverCraftAtlasDB, ns.Open)
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:SetScript("OnEvent", function(_, _, id)
    if id and pendingItems[id] then
        pendingItems[id] = nil
        if P:IsShown() and not loader.pending then
            loader.pending = true
            C_Timer.After(0.2, function()
                loader.pending = false
                if P:IsShown() then
                    list:Render()
                    wishList:Render()
                    routeList:Render()
                    shopList:Render()
                end
            end)
        end
    end
end)
