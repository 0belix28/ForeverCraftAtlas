-- Purchase.lua : l'achat de la wishlist confirmée (Wishlist.lua). Le jeu ne permet ces achats que la fenêtre de
-- l'hôtel des ventes ou d'un marchand ouverte, et seul le joueur l'ouvre (en parlant au PNJ) : s'en approcher ne suffit
-- pas, un addon ne peut ni l'ouvrir ni acheter sans elle.
--
-- Hôtel des ventes : un instant après son ouverture, la fenêtre « ForeverCraftAtlas : achats de la wishlist » s'ouvre sous la
-- sienne (elle se déplace ; sa place est gardée). Pour chaque composant, recette par recette dans l'ordre de la liste :
-- une recherche de ses offres (C_AuctionHouse.SendSearchQuery, au rythme que le serveur permet), puis le bouton
-- « Acheter ». Le jeu réserve l'achat à un clic du joueur (StartCommoditiesPurchase et PlaceBid ont HasRestrictions dans
-- l'API de Forever) : un clic par composant, par annonce pour un objet qui ne s'empile pas. Le devis du serveur
-- (COMMODITY_PRICE_UPDATED) est confirmé aussitôt, sans autre clic (ConfirmCommoditiesPurchase n'est pas restreint),
-- s'il ne dépasse pas le prix accepté.
-- Marchand : ce que la wishlist lui achète l'est dès l'ouverture de sa fenêtre, sans clic (BuyMerchantItem, comme le
-- fait la fenêtre du marchand), un composant après l'autre ; seul compte ce qui arrive dans les sacs (sacs pleins, or
-- insuffisant : le reste attend la prochaine visite).
-- Plus cher que prévu (à l'hôtel des ventes : ses offres, ou le devis ; chez le marchand : son prix) : une fenêtre de
-- confirmation dit le prix prévu et le nouveau, et le bénéfice de la recette avant et après ; « Continuer l'achat » paie
-- le nouveau prix, « Recette suivante » laisse le reste de cette recette (ses autres composants aussi) et passe à la
-- suivante ; la fermer n'achète rien (à l'hôtel des ventes, « Chercher de nouveau » reprend). Moins cher : l'achat suit.
local addonName, ns = ...
local PX = ns.Prices

local OPEN_DELAY = 1.5   -- (après l'ouverture de l'hôtel des ventes : sa fenêtre fait d'abord ses propres recherches)
local SEARCH_WAIT = 10   -- (une recherche sans réponse est refaite une fois)
local ANSWER_WAIT = 20   -- (un devis ou un achat sans réponse)
local MORE_PAGES = 10    -- (pages d'offres demandées au plus, pour un composant dont il faut beaucoup)
local BAG_WAIT = 3       -- (chez le marchand : le temps qu'un achat arrive dans les sacs)
local GREY = { 0.62, 0.62, 0.62 }
local ICON = "Interface\\Icons\\INV_Scroll_04"

local Update, Advance, Search, Evaluate, Start, Ask, ContinueAH, SkipAH, CancelAH, RunMerchant

-- (une valeur du jeu qui ne se compare pas, secrète : comme absente)
local function Num(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return tonumber(v)
end

local function Font(parent, template, color)
    local fs = parent:CreateFontString(nil, "ARTWORK", template)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Plural(n, word) return ("%d %s%s"):format(n, word, n > 1 and "s" or "") end

-- (le bouton d'un objet : son infobulle du jeu au survol, son lien au Maj + clic)
local function ItemButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints(b)
    b:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetText(ns.ItemLabel(self.itemID)) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.itemID and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            HandleModifiedItemClick(ns.ItemLink(self.itemID))
        end
    end)
    return b
end

local function Tip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- La confirmation d'un prix plus haut que prévu ----------------------------------------------------------------------
-- Au format des boîtes de dialogue du jeu (bord DialogBorderTemplate), en haut de l'écran comme elles.
local C = CreateFrame("Frame", "ForeverCraftAtlasPriceFrame", UIParent)
C:SetSize(470, 216)
C:SetPoint("TOP", UIParent, "TOP", 0, -135)
C:SetFrameStrata("DIALOG")
C:SetToplevel(true)
C:SetClampedToScreen(true)
C:EnableMouse(true)
C:SetMovable(true)
C:RegisterForDrag("LeftButton")
C:SetScript("OnDragStart", function(self) self:StartMoving() end)
C:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
C:Hide()
ns.priceFrame = C
if UISpecialFrames then table.insert(UISpecialFrames, "ForeverCraftAtlasPriceFrame") end -- (Échap la ferme : rien acheté)
do
    local ok, border = pcall(CreateFrame, "Frame", nil, C, "DialogBorderTemplate")
    if ok and border then
        border:SetAllPoints(C)
    else
        local bg = C:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(C)
        bg:SetColorTexture(0, 0, 0, 0.9)
    end
end
local closePrice = CreateFrame("Button", nil, C, "UIPanelCloseButton")
closePrice:SetPoint("TOPRIGHT", C, "TOPRIGHT", -3, -3)
closePrice:SetScript("OnClick", function() C:Hide() end)
C.title = Font(C, "GameFontNormalLarge")
C.title:SetPoint("TOP", C, "TOP", 0, -18)
C.title:SetJustifyH("CENTER")
C.title:SetText("Le prix a changé")
C.icon = ItemButton(C, 32)
C.icon:SetPoint("TOPLEFT", C, "TOPLEFT", 24, -46)
C.item = Font(C, "GameFontHighlight")
C.item:SetPoint("TOPLEFT", C.icon, "TOPRIGHT", 10, -1)
C.item:SetPoint("RIGHT", C, "RIGHT", -24, 0)
C.item:SetWordWrap(false)
C.recipe = Font(C, "GameFontHighlightSmall", GREY)
C.recipe:SetPoint("TOPLEFT", C.item, "BOTTOMLEFT", 0, -4)
C.recipe:SetPoint("RIGHT", C, "RIGHT", -24, 0)
C.recipe:SetWordWrap(false)
C.before = Font(C, "GameFontHighlight")
C.before:SetPoint("TOPLEFT", C, "TOPLEFT", 24, -94)
C.after = Font(C, "GameFontHighlight")
C.after:SetPoint("TOPLEFT", C.before, "BOTTOMLEFT", 0, -6)
C.profit = Font(C, "GameFontNormal")
C.profit:SetPoint("TOPLEFT", C.after, "BOTTOMLEFT", 0, -10)
C.profit:SetPoint("RIGHT", C, "RIGHT", -24, 0)
C.continue = CreateFrame("Button", nil, C, "UIPanelButtonTemplate")
C.continue:SetSize(170, 24)
C.continue:SetPoint("BOTTOMLEFT", C, "BOTTOMLEFT", 24, 18)
C.continue:SetText("Continuer l'achat")
Tip(C.continue, "Continuer l'achat", "Achète au nouveau prix, puis les achats de la recette continuent.")
C.skip = CreateFrame("Button", nil, C, "UIPanelButtonTemplate")
C.skip:SetSize(170, 24)
C.skip:SetPoint("BOTTOMRIGHT", C, "BOTTOMRIGHT", -24, 18)
C.skip:SetText("Recette suivante")
Tip(C.skip, "Recette suivante", "N'achète pas ce composant, ni le reste de cette recette : les achats passent à la "
    .. "recette suivante de la wishlist.")

-- (fermée sans choix, par la croix ou Échap : rien n'est acheté)
C:SetScript("OnHide", function(self)
    local info = self.info
    self.info = nil
    if info and info.onCancel then info.onCancel() end
end)

local function Decide(which)
    local info = C.info
    C.info = nil
    C:Hide()
    if info and info[which] then info[which]() end -- (dans le clic du joueur : un achat à l'hôtel des ventes le peut)
end
C.continue:SetScript("OnClick", function() Decide("onContinue") end)
C.skip:SetScript("OnClick", function() Decide("onSkip") end)

-- (une question en cours se ferme sans réponse : plus d'achats, fenêtre du marchand ou de l'hôtel des ventes fermée)
local function Dismiss(where)
    if C.info and (not where or C.info.where == where) then
        C.info = nil
        C:Hide()
    end
end

-- info : { where = "ah" ou "vendor", buy (un achat du plan), n (unités), before (leur coût prévu ; nil : inconnu),
-- after (leur nouveau coût), onContinue, onSkip, onCancel }.
function ns.AskPrice(info)
    C.info = nil -- (une question d'avant, sans suite : remplacée)
    local b, n = info.buy, math.max(1, info.n)
    C.icon.itemID = b.item
    C.icon.tex:SetTexture(ItemIcon(b.item))
    C.item:SetText(ns.Units(b.item, n) .. (info.where == "ah" and " à l'hôtel des ventes" or " chez le marchand"))
    local rec, i, total = ns.PlanRecipe(b.key)
    C.recipe:SetText(rec and ("pour %s x %d (recette %d sur %d)"):format(rec.name, rec.crafts, i, total) or "")
    C.before:SetText(info.before and ("Prévu : %s (%s l'unité)"):format(ns.Money(info.before), ns.Money(info.before / n))
        or "Prévu : prix inconnu à la confirmation")
    local more = info.before and info.after - info.before
    C.after:SetText(("Maintenant : %s (%s l'unité)%s"):format(ns.Money(info.after), ns.Money(info.after / n),
        (more and more >= 0.5) and (" |cffff4040+" .. ns.Money(more) .. "|r") or ""))
    local was, now = ns.WishlistProfit(b), ns.WishlistProfit(b, info.n, info.after)
    C.profit:SetText(("Bénéfice de la recette : %s prévu, %s à ce prix"):format(was and ns.Signed(was) or "inconnu",
        now and ns.Signed(now) or "inconnu"))
    C.info = info
    C:Show()
    C:Raise()
end

-- La fenêtre des achats à l'hôtel des ventes -------------------------------------------------------------------------
local B = CreateFrame("Frame", "ForeverCraftAtlasBuyFrame", UIParent, "ButtonFrameTemplate")
B:SetSize(430, 196)
B:SetFrameStrata("HIGH")
B:SetToplevel(true)
B:SetClampedToScreen(true)
B:SetMovable(true)
B:EnableMouse(true)
B:RegisterForDrag("LeftButton")
B:SetScript("OnDragStart", function(self) self:StartMoving() end)
B:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if point then
        ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
        ForeverCraftAtlasDB.buyPoint = { point, relPoint, x, y }
    end
end)
B:Hide()
if B.SetTitle then B:SetTitle("ForeverCraftAtlas : achats de la wishlist") end
if B.SetPortraitToAsset then B:SetPortraitToAsset(ICON) end
ns.buyFrame = B
local inset = B.Inset or B
B.recipe = Font(B, "GameFontNormal")
B.recipe:SetPoint("TOPLEFT", B, "TOPLEFT", 66, -34)
B.recipe:SetPoint("RIGHT", B, "RIGHT", -12, 0)
B.recipe:SetWordWrap(false)
B.icon = ItemButton(inset, 36)
B.icon:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
B.item = Font(inset, "GameFontHighlight")
B.item:SetPoint("TOPLEFT", B.icon, "TOPRIGHT", 10, -2)
B.item:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
B.item:SetWordWrap(false)
B.price = Font(inset, "GameFontHighlightSmall")
B.price:SetPoint("TOPLEFT", B.item, "BOTTOMLEFT", 0, -5)
B.price:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
B.price:SetWordWrap(false)
B.note = Font(inset, "GameFontHighlightSmall", GREY)
B.note:SetPoint("TOPLEFT", B.icon, "BOTTOMLEFT", 0, -8)
B.note:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
B.buy = CreateFrame("Button", nil, B, "UIPanelButtonTemplate")
B.buy:SetSize(210, 22)
B.buy:SetPoint("BOTTOMRIGHT", B, "BOTTOMRIGHT", -6, 4)
B.buy:SetMotionScriptsWhileDisabled(true)
B.left = Font(B, "GameFontHighlightSmall", GREY)
B.left:SetPoint("BOTTOMLEFT", B, "BOTTOMLEFT", 12, 9)
B.left:SetPoint("RIGHT", B.buy, "LEFT", -8, 0)
B.left:SetWordWrap(false)

-- (sous la fenêtre de l'hôtel des ventes, ou là où le joueur l'a mise)
local function Place()
    B:ClearAllPoints()
    local p = ForeverCraftAtlasDB and ForeverCraftAtlasDB.buyPoint
    if type(p) == "table" and p[1] then
        B:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif AuctionHouseFrame then
        B:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 0, -2)
    else
        B:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
end

-- L'achat en cours à l'hôtel des ventes ------------------------------------------------------------------------------
-- cur = { buy (du plan), item, commodity (d'après la réponse de la recherche), phase, levels ({ prix à l'unité,
-- quantité } du moins cher) ou auctions ({ id, price, q, unit }), picks (les annonces à acheter), q (unités du prochain
-- achat), cost (leur coût), planned (leur coût prévu), acceptedUnit (un prix à l'unité accepté, plus haut que prévu),
-- limit (le devis accepté sans question), quote, after, from, total, bid, deadline, tries, pages, note }. Phases :
-- "search" (la recherche attend sa réponse), "ready" (le bouton « Acheter »), "price" (la confirmation d'un prix plus
-- haut ; from : "search" ou "quote"), "quote" (devis demandé), "confirm" (achat confirmé, réponse attendue), "bid" (une
-- annonce achetée, réponse attendue), "wait" (« Chercher de nouveau » : pas de réponse, refus, prix refusé), "done".
local cur
local ahOpen, openedAt, ticker, pending = false, 0, nil, nil

-- (une demande au serveur quand il en accepte : sinon quand il le dit, AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
local function Ready()
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return not (ok and ready == false)
end

local function WhenReady(fn)
    if not Ready() then
        pending = fn
        return
    end
    pending = nil
    fn()
end

-- (marchandise ou objet, pour le tri de la recherche ; sa réponse le dit)
local function GuessCommodity(itemID)
    local AH = C_AuctionHouse
    local ok, info = pcall(function() return AH.GetItemKeyInfo(AH.MakeItemKey(itemID)) end)
    if ok and type(info) == "table" and info.isCommodity ~= nil then return info.isCommodity and true or false end
    local stack = C_Item and C_Item.GetItemMaxStackSizeByID and Num(C_Item.GetItemMaxStackSizeByID(itemID))
    return (stack or 2) > 1
end

local function CancelQuote()
    if cur and (cur.phase == "quote" or (cur.phase == "price" and cur.from == "quote")) then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
end

function Search(note)
    if not (cur and ahOpen) then return end
    cur.phase, cur.levels, cur.auctions, cur.picks, cur.pages = "search", nil, nil, nil, 0
    cur.note = note
    cur.deadline = GetTime() + SEARCH_WAIT
    WhenReady(function()
        if not (cur and cur.phase == "search" and ahOpen) then return end
        local AH, order = C_AuctionHouse, (Enum and Enum.AuctionHouseSortOrder) or {}
        cur.deadline = GetTime() + SEARCH_WAIT
        local sorts = GuessCommodity(cur.item) and { { sortOrder = order.Price or 0, reverseSort = false } }
            or { { sortOrder = order.Buyout or 4, reverseSort = false } }
        local item = cur.item
        local ok = pcall(function() AH.SendSearchQuery(AH.MakeItemKey(item), sorts, false) end)
        if not ok then cur.phase, cur.note = "wait", "La recherche n'est pas partie : « Chercher de nouveau »." end
        Update()
    end)
    Update()
end

-- Les offres d'une marchandise (sans les siennes, qui ne s'achètent pas), du moins cher : (offres, quantité, toutes là).
local function ReadCommodities(itemID)
    local AH = C_AuctionHouse
    local levels, total = {}, 0
    for i = 1, Num(AH.GetNumCommoditySearchResults(itemID)) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        local price = r and Num(r.unitPrice)
        local q = r and ((Num(r.quantity) or 0) - (Num(r.numOwnerItems) or 0)) or 0
        if price and price > 0 and q > 0 then
            levels[#levels + 1] = { price, q }
            total = total + q
        end
    end
    table.sort(levels, function(a, b) return a[1] < b[1] end)
    local ok, full = pcall(AH.HasFullCommoditySearchResults, itemID)
    return levels, total, not ok or full ~= false
end

-- Les annonces d'un objet avec achat immédiat (sans les siennes), la moins chère à l'unité d'abord.
local function ReadItems(key)
    local AH = C_AuctionHouse
    local auctions, total = {}, 0
    for i = 1, Num(AH.GetNumItemSearchResults(key)) or 0 do
        local r = AH.GetItemSearchResultInfo(key, i)
        local price, q, id = r and Num(r.buyoutAmount), r and Num(r.quantity), r and Num(r.auctionID)
        if price and price > 0 and q and q > 0 and id and not r.containsOwnerItem then
            auctions[#auctions + 1] = { id = id, price = price, q = q, unit = price / q }
            total = total + q
        end
    end
    table.sort(auctions, function(a, b)
        if a.unit ~= b.unit then return a.unit < b.unit end
        return a.id < b.id
    end)
    local ok, full = pcall(AH.HasFullItemSearchResults, key)
    return auctions, total, not ok or full ~= false
end

-- D'après la recherche : ce que le prochain achat prend (q unités, au plus ce qu'il reste à acheter ; une annonce
-- d'objet entière) et son coût ; plus cher que prévu (ou prévu inconnu), la confirmation ; rien en vente : introuvable.
function Evaluate()
    local b = cur.buy
    local want = ns.BuyRemaining(b)
    local q, cost = 0, 0
    if cur.commodity then
        for _, l in ipairs(cur.levels or {}) do
            if q >= want then break end
            local take = math.min(l[2], want - q)
            q, cost = q + take, cost + take * l[1]
        end
    else
        cur.picks = {}
        for _, a in ipairs(cur.auctions or {}) do
            if q >= want then break end
            cur.picks[#cur.picks + 1] = a
            q, cost = q + a.q, cost + a.price
        end
    end
    cur.tries = 0
    if q <= 0 then
        ns.Say(("%s : rien en vente à l'hôtel des ventes, compté comme introuvable."):format(ns.Units(b.item, want, true)))
        cur.phase = "done"
        ns.WishlistMissing(b, want)
        Advance()
        return
    end
    -- (le prévu de ce qui reste, d'après le total : ce que ces unités et celles déjà achetées devaient coûter, moins ce
    -- qui est déjà payé ; une annonce un peu plus chère après une moins chère ne demande rien)
    cur.q, cur.cost = q, cost
    cur.planned = b.planned and (b.planned * math.min(b.n, b.got + q) / b.n - b.spent) or nil
    cur.limit = math.max(cur.planned or -1, cur.acceptedUnit and cur.acceptedUnit * q or -1)
    if cur.limit < 0 or cost > cur.limit + 0.5 then
        Ask("search", cost)
    else
        cur.phase = "ready"
        Update()
    end
end

function Ask(from, after)
    cur.phase, cur.from, cur.after = "price", from, after
    Update()
    ns.AskPrice({ where = "ah", buy = cur.buy, n = cur.q, before = cur.planned, after = after,
        onContinue = ContinueAH, onSkip = SkipAH, onCancel = CancelAH })
end

-- (dans un clic du joueur : le jeu l'exige pour StartCommoditiesPurchase et PlaceBid)
local function Purchase()
    local AH = C_AuctionHouse
    if not Ready() then
        cur.note = "Le serveur est occupé : clique de nouveau dans un instant."
        Update()
        return
    end
    local money = Num(GetMoney and GetMoney()) or 0
    if cur.commodity then
        if money < cur.cost then
            cur.note = ("Pas assez d'or : il faut %s."):format(ns.Money(cur.cost))
            Update()
            return
        end
        cur.phase, cur.deadline, cur.quote, cur.note = "quote", GetTime() + ANSWER_WAIT, nil, nil
        local ok = pcall(AH.StartCommoditiesPurchase, cur.item, cur.q)
        if not ok and cur and cur.phase == "quote" then
            cur.phase, cur.note = "ready", "Le jeu a refusé l'achat : clique de nouveau sur « Acheter »."
        end
    else
        local a = cur.picks and cur.picks[1]
        if not a then
            Search()
            return
        end
        if money < a.price then
            cur.note = ("Pas assez d'or : il faut %s."):format(ns.Money(a.price))
            Update()
            return
        end
        cur.phase, cur.deadline, cur.bid, cur.note = "bid", GetTime() + ANSWER_WAIT, a, nil
        local ok = pcall(AH.PlaceBid, a.id, a.price)
        if not ok and cur and cur.phase == "bid" then
            cur.phase, cur.bid, cur.note = "ready", nil, "Le jeu a refusé l'achat : clique de nouveau sur « Acheter »."
        end
    end
    Update()
end

local function Confirm(total)
    cur.phase, cur.total, cur.deadline = "confirm", total, GetTime() + ANSWER_WAIT
    local ok = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, cur.item, cur.q)
    if not ok and cur and cur.phase == "confirm" then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        cur.phase, cur.note = "wait", "L'achat n'a pas pu être confirmé : « Chercher de nouveau »."
    end
    Update()
end

local function Bought(n, spent)
    local b = cur.buy
    cur.phase = "done"
    ns.Say(("acheté %s à l'hôtel des ventes pour %s%s."):format(ns.Units(b.item, n, true), ns.Money(spent),
        b.planned and (" (prévu " .. ns.Money(b.planned * n / b.n) .. ")") or ""))
    ns.WishlistBought(b, n, spent)
end

-- (une marchandise achetée : n unités, au prix du devis ; la suite)
local function CommodityDone(n)
    n = math.max(0, math.min(n or cur.q, cur.q))
    Bought(n, (cur.total or cur.cost) * n / cur.q)
    Advance()
end

function ContinueAH() -- (dans le clic de « Continuer l'achat »)
    if not (cur and cur.phase == "price") then return end
    cur.acceptedUnit = cur.after / cur.q
    cur.limit = math.max(cur.planned or -1, cur.after)
    if cur.from == "quote" then -- (le devis vaut encore : confirmé ; expiré, un nouveau dans ce clic)
        local ok, left = pcall(C_AuctionHouse.GetQuoteDurationRemaining)
        if ok and (Num(left) or 0) > 0 then
            Confirm(cur.after)
            return
        end
    end
    cur.phase = "ready"
    Purchase()
end

function SkipAH()
    if not cur then return end
    CancelQuote()
    local key = cur.buy.key
    cur.phase = "done"
    ns.WishlistSkip(key)
    Advance()
end

function CancelAH() -- (la confirmation fermée : rien n'est acheté)
    if not (cur and cur.phase == "price") then return end
    CancelQuote()
    cur.phase, cur.note = "wait", "Nouveau prix refusé : rien acheté. « Chercher de nouveau » pour reprendre."
    Update()
end

-- Le prochain achat (le même tant qu'il en reste : une nouvelle recherche), ou plus rien ici.
function Advance()
    if not ahOpen then
        cur = nil
        return
    end
    local b = ns.WishlistBuying() and ns.NextBuy("ah") or nil
    if not b then
        cur = nil
        Update()
        return
    end
    if not (cur and cur.buy == b) then cur = { buy = b, item = b.item, tries = 0 } end
    Search()
end

function Start()
    if not (ahOpen and ns.WishlistBuying() and ns.NextBuy("ah")) then return end
    if not B:IsShown() then
        Place()
        B:Show()
    end
    if cur then Update() else Advance() end
end

-- La fenêtre des achats rouverte (onglet « Wishlist ») ; peut-elle l'être (l'hôtel des ventes ouvert, des achats à y
-- faire, la fenêtre fermée) ?
ns.ShowBuyFrame = function() Start() end
function ns.CanShowBuyFrame()
    return ahOpen and ns.WishlistBuying() and ns.NextBuy("ah") ~= nil and not B:IsShown()
end

function Update()
    if not B:IsShown() then return end
    local plan = ns.WishlistPlan()
    local ahLeft, vendorLeft = ns.BuysLeft("ah"), ns.BuysLeft("vendor")
    B.left:SetText(plan and ("Restent : %s ici, %s chez un marchand"):format(Plural(ahLeft, "achat"),
        Plural(vendorLeft, "achat")) or "")
    if not cur then
        B.icon.itemID = nil
        B.icon.tex:SetTexture(ICON)
        B.recipe:SetText("")
        if plan then
            B.item:SetText("Plus rien à acheter à l'hôtel des ventes.")
            B.price:SetText(vendorLeft > 0 and ("Le reste s'achète chez un marchand (%s) : ouvre sa fenêtre."):format(
                Plural(vendorLeft, "achat")) or "")
        else
            local last = ns.WishlistLast()
            B.item:SetText("Achats de la wishlist terminés.")
            B.price:SetText(last and ("%s dépensés (prévu %s)."):format(ns.Money(last.spent), ns.Money(last.planned)) or "")
        end
        B.note:SetText("")
        B.buy:SetText("Fermer")
        B.buy:Enable()
        return
    end
    local b = cur.buy
    local rec, i, total = ns.PlanRecipe(b.key)
    B.recipe:SetText(rec and ("%s x %d · recette %d sur %d"):format(rec.name, rec.crafts, i, total) or "")
    B.icon.itemID = b.item
    B.icon.tex:SetTexture(ItemIcon(b.item))
    local want = ns.BuyRemaining(b)
    B.item:SetText(ns.Units(b.item, want))
    local phase, price = cur.phase, ""
    if phase == "search" then
        price = "Recherche de ses offres..."
    elseif phase == "quote" then
        price = "Devis demandé au serveur..."
    elseif phase == "confirm" or phase == "bid" then
        price = "Achat en cours..."
    elseif cur.cost then
        price = ("Prévu : %s · maintenant : %s"):format(cur.planned and ns.Money(cur.planned) or "inconnu", ns.Money(cur.cost))
        if cur.q < want then price = price .. (" (seulement %s en vente)"):format(PX.Decimals(cur.q)) end
    end
    B.price:SetText(price)
    B.note:SetText(cur.note or (phase == "ready" and "Le jeu demande un clic par achat." or ""))
    if phase == "ready" then
        if cur.commodity then
            B.buy:SetText(("Acheter %s (%s)"):format(PX.Decimals(cur.q), ns.Money(cur.cost)))
        else
            local a = cur.picks and cur.picks[1]
            B.buy:SetText(a and ("Acheter %s (%s)"):format(PX.Decimals(a.q), ns.Money(a.price)) or "Acheter")
        end
        B.buy:Enable()
    elseif phase == "wait" then
        B.buy:SetText("Chercher de nouveau")
        B.buy:Enable()
    elseif phase == "price" then
        B.buy:SetText("Voir le nouveau prix")
        B.buy:Enable()
    else
        B.buy:SetText("Patiente...")
        B.buy:Disable()
    end
end

B.buy:SetScript("OnClick", function()
    if not cur then
        B:Hide()
    elseif cur.phase == "ready" then
        Purchase()
    elseif cur.phase == "wait" then
        cur.tries = 0
        Search()
    elseif cur.phase == "price" then
        Ask(cur.from, cur.after)
    end
end)
B.buy:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Acheter", 1, 0.82, 0)
    GameTooltip:AddLine("Le jeu réserve les achats à l'hôtel des ventes à un clic du joueur : un clic par composant (par "
        .. "annonce pour un objet qui ne s'empile pas). Le devis du serveur est confirmé sans autre clic tant qu'il ne "
        .. "dépasse pas le prix prévu ; plus cher, une fenêtre demande quoi faire.", 1, 1, 1, true)
    GameTooltip:Show()
end)
B.buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
B:HookScript("OnShow", function() Update() end)

local function Tick()
    if not (cur and cur.deadline) or GetTime() < cur.deadline then return end
    cur.deadline = nil
    if cur.phase == "search" then
        cur.tries = (cur.tries or 0) + 1
        if cur.tries < 2 then
            Search()
        else
            cur.phase, cur.note = "wait", "Pas de réponse à la recherche : « Chercher de nouveau »."
            Update()
        end
    elseif cur.phase == "quote" then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        cur.phase, cur.note = "ready", "Pas de devis du serveur : rien acheté, clique de nouveau sur « Acheter »."
        Update()
    elseif cur.phase == "confirm" or cur.phase == "bid" then
        cur.phase, cur.bid = "wait", nil
        cur.note = "Pas de réponse du serveur : l'achat a peut-être eu lieu (regarde ta boîte aux lettres). « Chercher "
            .. "de nouveau » pour continuer."
        Update()
    end
end

local AH_EVENTS = {}
function AH_EVENTS.AUCTION_HOUSE_SHOW()
    ahOpen, openedAt = true, GetTime()
    if not ticker then ticker = C_Timer.NewTicker(0.5, Tick) end
    C_Timer.After(OPEN_DELAY, function() if ahOpen then Start() end end)
end
function AH_EVENTS.AUCTION_HOUSE_CLOSED()
    ahOpen = false
    CancelQuote()
    cur, pending = nil, nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    Dismiss("ah")
    B:Hide()
end
local function OnCommodities(itemID)
    if not (cur and cur.phase == "search" and Num(itemID) == cur.item) then return end
    cur.commodity = true
    local levels, total, full = ReadCommodities(cur.item)
    if total < ns.BuyRemaining(cur.buy) and not full and cur.pages < MORE_PAGES then
        cur.pages, cur.deadline = cur.pages + 1, GetTime() + SEARCH_WAIT
        local item = cur.item
        WhenReady(function()
            if cur and cur.phase == "search" then pcall(C_AuctionHouse.RequestMoreCommoditySearchResults, item) end
        end)
        return
    end
    cur.levels = levels
    Evaluate()
end
AH_EVENTS.COMMODITY_SEARCH_RESULTS_UPDATED = OnCommodities
AH_EVENTS.COMMODITY_SEARCH_RESULTS_ADDED = OnCommodities
local function OnItems(key)
    if not (cur and cur.phase == "search" and type(key) == "table" and Num(key.itemID) == cur.item) then return end
    cur.commodity = false
    local auctions, total, full = ReadItems(key)
    if total < ns.BuyRemaining(cur.buy) and not full and cur.pages < MORE_PAGES then
        cur.pages, cur.deadline = cur.pages + 1, GetTime() + SEARCH_WAIT
        WhenReady(function()
            if cur and cur.phase == "search" then pcall(C_AuctionHouse.RequestMoreItemSearchResults, key) end
        end)
        return
    end
    cur.auctions = auctions
    Evaluate()
end
AH_EVENTS.ITEM_SEARCH_RESULTS_UPDATED = OnItems
AH_EVENTS.ITEM_SEARCH_RESULTS_ADDED = OnItems
function AH_EVENTS.COMMODITY_PRICE_UPDATED(_, total)
    if not (cur and cur.phase == "quote") then return end
    total = Num(total)
    if not total then return end
    if total <= (cur.limit or -1) + 0.5 then
        Confirm(total)
    else
        cur.quote = total
        Ask("quote", total)
    end
end
function AH_EVENTS.COMMODITY_PRICE_UNAVAILABLE()
    if not (cur and (cur.phase == "quote" or (cur.phase == "price" and cur.from == "quote"))) then return end
    Dismiss("ah")
    Search("Ce prix n'est plus disponible : nouvelle recherche.")
end
function AH_EVENTS.COMMODITY_PURCHASED(itemID, quantity)
    if cur and cur.phase == "confirm" and Num(itemID) == cur.item then CommodityDone(Num(quantity)) end
end
function AH_EVENTS.COMMODITY_PURCHASE_SUCCEEDED()
    if cur and cur.phase == "confirm" then CommodityDone(cur.q) end
end
function AH_EVENTS.COMMODITY_PURCHASE_FAILED()
    if cur and (cur.phase == "confirm" or cur.phase == "quote") then Search("L'achat a échoué : nouvelle recherche.") end
end
function AH_EVENTS.AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)
    if not (cur and cur.phase == "bid" and cur.bid and Num(auctionID) == cur.bid.id) then return end
    local bid = cur.bid
    cur.bid = nil
    for i, a in ipairs(cur.auctions or {}) do
        if a == bid then
            table.remove(cur.auctions, i)
            break
        end
    end
    local was = cur
    Bought(bid.q, bid.price)
    if cur ~= was then return end -- (plus d'achats : finis, ou arrêtés)
    if ns.BuyRemaining(cur.buy) > 0 and #(cur.auctions or {}) > 0 then Evaluate() else Advance() end
end
function AH_EVENTS.AUCTION_HOUSE_SHOW_ERROR()
    if cur and (cur.phase == "bid" or cur.phase == "quote" or cur.phase == "confirm") then
        Search("L'achat n'a pas abouti (annonce déjà partie ?) : nouvelle recherche.")
    end
end
function AH_EVENTS.AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED()
    if not cur then return end
    if cur.phase == "quote" or cur.phase == "bid" then
        cur.phase, cur.bid = "ready", nil
        cur.note = "Le serveur n'a pas pris l'achat (trop de demandes) : clique de nouveau sur « Acheter »."
        Update()
    elseif cur.phase == "search" then
        Search(cur.note)
    end
end
function AH_EVENTS.AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
    local fn = pending
    pending = nil
    if fn then fn() end
end
local merchantRefused -- (le jeu a refusé l'achat sans clic chez le marchand : dit une fois)
local function Blocked(name, func)
    if name ~= addonName then return end
    if func == "BuyMerchantItem" or func == "BuyMerchantItem()" then
        if not merchantRefused then
            merchantRefused = true
            ns.Say("le jeu refuse l'achat automatique chez le marchand (BuyMerchantItem) : rien n'y est acheté. "
                .. "Achète ces composants à la main ; dis-le pour que ForeverCraftAtlas demande un clic à la place.")
        end
        return
    end
    if not cur then return end
    if cur.phase == "quote" or cur.phase == "bid" then
        cur.phase, cur.bid = "ready", nil
        cur.note = "Le jeu a bloqué l'achat : clique de nouveau sur « Acheter »."
        Update()
    end
end
AH_EVENTS.ADDON_ACTION_BLOCKED = Blocked
AH_EVENTS.ADDON_ACTION_FORBIDDEN = Blocked

-- Chez le marchand ---------------------------------------------------------------------------------------------------
-- waiting : l'achat qui attend ses objets dans les sacs { buy, item, before, count, unit, timer } ; tried : les achats
-- déjà tentés à cette visite (sacs pleins, stock épuisé, prix refusé : pas de nouvel essai avant la prochaine).
local merchantOpen, tried, waiting = false, {}, nil

-- Ce que vend le marchand ouvert, contre de l'or seulement : { [objet] = { index, price, stack, unit, available } }.
local function MerchantOffers()
    local offers = {}
    if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo and GetMerchantNumItems and GetMerchantItemID) then
        return offers
    end
    for i = 1, Num(GetMerchantNumItems()) or 0 do
        local id = Num(GetMerchantItemID(i))
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if id and ok and type(info) == "table" then
            local price, stack = Num(info.price) or 0, math.max(1, Num(info.stackCount) or 1)
            if price > 0 and not info.hasExtendedCost and info.isPurchasable ~= false then
                local unit = price / stack
                if not offers[id] or unit < offers[id].unit then
                    offers[id] = { index = i, price = price, stack = stack, unit = unit, available = Num(info.numAvailable) }
                end
            end
        end
    end
    return offers
end

-- (ce qui est arrivé dans les sacs compte ; le reste attend la prochaine visite)
local function Arrived()
    local w = waiting
    if not w then return end
    waiting = nil
    if w.timer then w.timer:Cancel() end
    local got = math.max(0, math.min(w.count, ns.InBags(w.item) - w.before))
    if got > 0 then
        ns.Say(("acheté %s chez le marchand pour %s."):format(ns.Units(w.item, got, true), ns.Money(got * w.unit)))
        ns.WishlistBought(w.buy, got, got * w.unit)
    end
    if got < w.count then
        ns.Say(("chez le marchand, %s pas reçus (sacs pleins ? stock épuisé ?) : ils restent à acheter."):format(
            ns.Units(w.item, w.count - got, true)))
    end
    RunMerchant()
end

local function MerchantBuy(b, m, want)
    tried[b] = true
    local stacks = math.ceil(want / m.stack)
    if m.available and m.available >= 0 then stacks = math.min(stacks, m.available) end
    if stacks <= 0 then return RunMerchant() end
    local count, cost = stacks * m.stack, stacks * m.price
    if (Num(GetMoney and GetMoney()) or 0) < cost then
        ns.Say(("pas assez d'or pour %s chez le marchand (%s)."):format(ns.Units(b.item, count, true), ns.Money(cost)))
        return RunMerchant()
    end
    local max = math.max(m.stack, Num(GetMerchantItemMaxStack and GetMerchantItemMaxStack(m.index)) or m.stack)
    waiting = { buy = b, item = b.item, before = ns.InBags(b.item), count = count, unit = m.unit }
    local left = count
    while left > 0 do
        local take = math.min(left, max)
        take = math.max(m.stack, take - take % m.stack)
        pcall(BuyMerchantItem, m.index, take)
        left = left - take
    end
    waiting.timer = C_Timer.NewTimer(BAG_WAIT, Arrived)
end

-- Les achats de la wishlist chez ce marchand, un à la fois, dans l'ordre de la liste ; plus cher que prévu (et pas déjà
-- accepté à ce prix) : la confirmation d'abord.
function RunMerchant()
    if not merchantOpen or waiting or C.info or not ns.WishlistBuying() then return end
    local offers = MerchantOffers()
    for _, b in ipairs(ns.WishlistPlan().buys) do
        local want = (b.where == "vendor" and not tried[b]) and ns.BuyRemaining(b) or 0
        local m = want > 0 and offers[b.item]
        if m then
            if m.unit > math.max(b.unit or 0, b.acceptedUnit or 0) + 1e-6 then
                ns.AskPrice({ where = "vendor", buy = b, n = want, before = b.unit and b.unit * want, after = m.unit * want,
                    onContinue = function()
                        b.acceptedUnit = m.unit
                        RunMerchant()
                    end,
                    onSkip = function()
                        ns.WishlistSkip(b.key)
                        RunMerchant()
                    end,
                    onCancel = function()
                        tried[b] = true
                        RunMerchant()
                    end })
                return
            end
            return MerchantBuy(b, m, want)
        end
    end
end

local MERCHANT_EVENTS = {}
function MERCHANT_EVENTS.MERCHANT_SHOW()
    merchantOpen, tried = true, {}
    C_Timer.After(0.3, RunMerchant) -- (la liste du marchand finit d'arriver)
end
function MERCHANT_EVENTS.MERCHANT_UPDATE()
    if merchantOpen then RunMerchant() end
end
function MERCHANT_EVENTS.MERCHANT_CLOSED()
    merchantOpen = false
    Dismiss("vendor")
end
function MERCHANT_EVENTS.BAG_UPDATE_DELAYED()
    if waiting and ns.InBags(waiting.item) - waiting.before >= waiting.count then Arrived() end
end

local events = CreateFrame("Frame")
for name in pairs(AH_EVENTS) do pcall(events.RegisterEvent, events, name) end
for name in pairs(MERCHANT_EVENTS) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function(_, event, ...)
    local fn = AH_EVENTS[event] or MERCHANT_EVENTS[event]
    if fn then fn(...) end
end)

-- Des achats confirmés, arrêtés ou finis : l'hôtel des ventes ou le marchand déjà ouverts suivent.
ns.OnChange(function(key)
    if key ~= "wishlist" then return end
    if not ns.WishlistBuying() then
        CancelQuote()
        cur = nil
        Dismiss()
        Update()
        return
    end
    if ahOpen and not cur and GetTime() - openedAt >= OPEN_DELAY then Start() end
    if merchantOpen and not waiting then C_Timer.After(0, RunMerchant) end
    Update()
end)
