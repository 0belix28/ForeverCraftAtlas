-- Prices : les prix de l'hôtel des ventes pour ForeverCraftAtlas, sans aucune dépendance.
--
-- Deux sources, toutes deux en jeu :
-- 1. Les relevés de ForeverCraftAtlas lui-même (« Relevés en jeu », plus bas) : tout l'hôtel des ventes (le bouton
--    « Scanner l'HDV », ou l'analyse lancée par ForeverExchange ou un autre addon, suivie au passage), et ce que tu y
--    parcours. Pour les composants, chaque offre : ce que coûte l'achat de plusieurs.
-- 2. ForeverExchange (facultatif, l'addon de prix de WoW Forever) : ses données sont lues telles quelles dans sa table
--    de sauvegarde (ForeverExchangeDB, rien n'y est écrit) : prix minimum, valeur marché, moyennes 7 et 30 jours,
--    quantité en vente, évolution sur 7 jours. Elles servent quand un objet n'a pas de relevé à nous, et pour les prix
--    « Achat sans relevé ». Sans ForeverExchange, seulement nos relevés et les marchands.
--
-- Pas de ventes par jour ni de taux de vente : aucun addon de WoW Forever ne les connaît (T.SoldPerDay et T.SaleRate
-- rendent nil). La table va dans l'espace privé de l'addon (ns.Prices), aucune variable globale.
local addonName, ns = ...
local T = {}
ns.Prices = T

-- ForeverExchange ------------------------------------------------------------------------------------------------------
-- Sa table : ForeverExchangeDB.houses["<royaume> - <faction>"].items[n°] = { min, mkt, qty, auc, t (date du scan),
-- lmin, lqty, lt (dernière recherche à l'HV), a7, a30, ch7, ... } ; house.lastScan : la date de son dernier scan.
local function HouseKey()
    return (GetRealmName and GetRealmName() or "?") .. " - " .. (UnitFactionGroup and UnitFactionGroup("player") or "Neutral")
end

local function House()
    local db = _G.ForeverExchangeDB
    if type(db) ~= "table" or type(db.houses) ~= "table" then return nil end
    local h = db.houses[HouseKey()]
    if type(h) ~= "table" or type(h.items) ~= "table" then return nil end
    return h
end
T.House = House

local function FXItem(itemID)
    itemID = tonumber(itemID)
    local h = itemID and House()
    local it = h and h.items[itemID]
    return type(it) == "table" and it or nil, h
end

local function Num(v) return type(v) == "number" and v > 0 and v or nil end

-- Le prix minimum actuel chez ForeverExchange (comme sa propre infobulle) : le plus récent du dernier scan et de la
-- dernière recherche à l'HV. Rend (prix, date, en vente au dernier scan, quantité) ou nil.
local function FXCurrent(it, h)
    if not it then return nil end
    if Num(it.lmin) and it.lt and (not it.t or it.lt > it.t) then return it.lmin, it.lt, true, it.lqty end
    if not Num(it.min) then return nil end
    return it.min, it.t, (it.t and h and h.lastScan and it.t == h.lastScan) or false, it.qty
end

-- ForeverExchange est-il là, avec des données pour ce royaume ?
function T.Ready() return House() ~= nil end
function T.HasExchange() return T.Ready() end
T.HasAuctionator = T.HasExchange -- (ancien nom)

-- Les prix proposés pour « Achat sans relevé », dans l'ordre du menu : value, text (le menu), label (dans une
-- phrase), mid (ligne d'état), short (ligne de liste).
T.SOURCES = {
    { value = "FXAvg7", text = "Moyenne sur 7 jours (ForeverExchange)", label = "moyenne sur 7 jours de ForeverExchange",
        mid = "moyenne 7 j", short = "moy. 7 j" },
    { value = "FXAvg30", text = "Moyenne sur 30 jours (ForeverExchange)", label = "moyenne sur 30 jours de ForeverExchange",
        mid = "moyenne 30 j", short = "moy. 30 j" },
    { value = "FXMarket", text = "Valeur marché (ForeverExchange)", label = "valeur marché de ForeverExchange",
        mid = "valeur marché", short = "marché" },
    { value = "FXMin", text = "Prix minimum (ForeverExchange)", label = "prix minimum de ForeverExchange",
        mid = "prix minimum", short = "min" },
}
T.DEFAULT = "FXAvg7"
-- (sans valeur pour la source choisie : les autres, dans cet ordre)
T.FALLBACK = { "FXAvg7", "FXMarket", "FXMin", "FXAvg30" }

local BY_KEY = {}
for _, s in ipairs(T.SOURCES) do BY_KEY[s.value] = s end
-- (pas des choix du menu : le prix le plus bas relevé en jeu par ForeverCraftAtlas, et celui de ForeverExchange)
T.LIVE = "live"
BY_KEY[T.LIVE] = { value = T.LIVE, label = "prix le plus bas au dernier relevé de l'hôtel des ventes",
    mid = "relevé de l'hôtel des ventes", short = "HV" }
T.EXCHANGE = "exchange"
T.AUCTIONATOR = T.EXCHANGE -- (ancien nom)
BY_KEY[T.EXCHANGE] = { value = T.EXCHANGE, label = "prix minimum chez ForeverExchange", mid = "ForeverExchange",
    short = "FX" }

function T.Source(key, default)
    if BY_KEY[key] and key ~= T.LIVE and key ~= T.EXCHANGE then return key end
    return BY_KEY[default] and default or T.DEFAULT
end
function T.Label(key) return BY_KEY[key] and BY_KEY[key].label or tostring(key or "") end
function T.Title(key) return (T.Label(key):gsub("^%l", string.upper)) end
function T.Short(key) return BY_KEY[key] and BY_KEY[key].short or tostring(key or "") end
function T.Mid(key) return BY_KEY[key] and (BY_KEY[key].mid or BY_KEY[key].label) or tostring(key or "") end

function T.Choices()
    local out = {}
    for _, s in ipairs(T.SOURCES) do out[#out + 1] = { value = s.value, text = s.text } end
    return out
end

-- La valeur d'une source pour un objet, ou nil.
local function Value(key, itemID)
    local it, h = FXItem(itemID)
    if not it then return nil end
    if key == "FXAvg7" then return Num(it.a7) end
    if key == "FXAvg30" then return Num(it.a30) end
    if key == "FXMarket" then return Num(it.mkt) end
    if key == "FXMin" then return (FXCurrent(it, h)) end
    return nil
end
T.Value = Value

-- Pas de ventes connues sur WoW Forever.
function T.SoldPerDay() return nil end
function T.SaleRate() return nil end
-- Le nombre d'annonces au dernier scan de ForeverExchange, ou nil.
function T.Auctions(itemID)
    local it = FXItem(itemID)
    return it and Num(it.auc) or nil
end
-- (les prix des marchands viennent des tables du jeu : Data.lua buy)
function T.VendorBuy() return nil end

-- Un prix relevé aberrant (une annonce seule à un prix fou) : au-delà de T.ODD fois le plus haut des prix habituels de
-- l'objet chez ForeverExchange (moyennes 7 et 30 jours), il est écarté.
T.ODD = 5
function T.Reference(itemID)
    local it = FXItem(itemID)
    if not it then return nil end
    local best
    for _, v in ipairs({ Num(it.a30) or false, Num(it.a7) or false }) do
        if v and (not best or v > best) then best = v end
    end
    return best
end

-- Le prix d'un objet selon la source choisie ; sans elle, celles de T.FALLBACK. Rend (prix, source prise) ou nil. Le
-- prix minimum : celui du dernier relevé en jeu d'abord (source prise : T.LIVE ; sauf noLive).
function T.Price(itemID, source, noLive)
    source = T.Source(source)
    if source == "FXMin" and not noLive then
        local live = T.Live(itemID)
        if live then return live.price, T.LIVE end
    end
    local v = Value(source, itemID)
    if v then return v, source end
    for _, key in ipairs(T.FALLBACK) do
        if key ~= source then
            v = Value(key, itemID)
            if v then return v, key end
        end
    end
    return nil
end

-- Nombres : « 23 153 », « 6 », « 1,5 », « 0,34 », « < 0,01 ».
local function Decimals(n)
    if n >= 9.5 then
        local s = tostring(math.floor(n + 0.5))
        return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
    end
    if n >= 0.995 then return (("%.1f"):format(n):gsub("%.0$", ""):gsub("%.", ",")) end
    if n >= 0.01 then return (("%.2f"):format(n):gsub("0$", ""):gsub("%.", ",")) end
    return "< 0,01"
end
T.Decimals = Decimals

function T.PerDay(n, short)
    if not n then return short and "ventes inconnues" or "ventes inconnues" end
    local text = Decimals(n)
    local shown = tonumber((text:gsub("[^%d,]", ""):gsub(",", "."))) or 0
    return text .. " " .. (shown < 2 and "vente" or "ventes") .. (short and "/jour" or " par jour")
end

function T.Percent(r) return Decimals((r or 0) * 100) .. " %" end

-- « à 06:13 » aujourd'hui, « le 09/11 à 06:13 » un autre jour.
function T.At(t)
    local fmt = date or (os and os.date)
    if not (t and fmt) then return "" end
    if fmt("%Y%j", t) == fmt("%Y%j", time()) then return "à " .. fmt("%H:%M", t) end
    return "le " .. fmt("%d/%m à %H:%M", t)
end

-- L'évolution sur 7 jours chez ForeverExchange : « +12 % sur 7 j », ou nil.
local function Trend(itemID)
    local it = FXItem(itemID)
    local ch = it and type(it.ch7) == "number" and it.ch7 or nil
    if not ch then return nil end
    local p = math.floor(ch * 100 + (ch >= 0 and 0.5 or -0.5))
    if p == 0 then return "stable sur 7 j" end
    return (p > 0 and "+" or "") .. p .. " % sur 7 j"
end

-- Ce que ForeverExchange sait de plus (moyennes, tendance), pour le détail d'un prix.
local function FXExtra(itemID, money)
    local it = FXItem(itemID)
    if not it then return nil end
    local parts = {}
    if money and Num(it.a7) then parts[#parts + 1] = "moyenne 7 j " .. money(it.a7) end
    if money and Num(it.a30) then parts[#parts + 1] = "30 j " .. money(it.a30) end
    local trend = Trend(itemID)
    if trend then parts[#parts + 1] = trend end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Ce sur quoi repose un prix (how de ns.AuctionPrice), sans son nom : « 207 en vente, relevé il y a 3 min · moyenne
-- 7 j 2 pa 74 · +12 % sur 7 j » ; ForeverExchange : « 207 en vente, analysé il y a 2 h par ForeverExchange · ... ».
function T.Detail(how, money)
    if not how then return "" end
    local parts = {}
    if how.source == T.EXCHANGE then
        parts[1] = T.ExchangeText(how.item)
        if how.gone then parts[2] = "pas en vente au dernier relevé" end
    elseif how.source == T.LIVE then
        parts[1] = T.LiveTail(T.Live(how.item) or how.live)
    else
        if how.liveOdd then
            parts[1] = "prix relevé aberrant" .. (money and (" (" .. money(how.liveOdd) .. ")") or "")
        elseif how.gone then
            parts[1] = "pas en vente au dernier relevé"
        end
    end
    local extra = how.item and FXExtra(how.item, money)
    if extra then parts[#parts + 1] = extra end
    return table.concat(parts, " · ")
end

-- Court, pour une ligne de liste : « 207 en vente (+12 % sur 7 j) », « pas en vente », « prix ForeverExchange ».
function T.ShortDetail(how)
    if not how then return "" end
    local qty
    local live = how.item and T.Live(how.item)
    if live and (live.qty or 0) > 0 then qty = live.qty
    else
        local it, h = FXItem(how.item)
        local _, _, _, q = FXCurrent(it, h)
        qty = Num(q)
    end
    local text = qty and (Decimals(qty) .. " en vente") or (how.gone and "pas en vente" or "")
    local trend = how.item and Trend(how.item)
    if trend then text = text ~= "" and (text .. " (" .. trend .. ")") or trend end
    return text
end

-- Avec son nom : « prix le plus bas au dernier relevé de l'hôtel des ventes, 207 en vente, relevé il y a 3 min ».
function T.Basis(how, money)
    if not how or not how.source then return nil end
    local detail = T.Detail(how, money)
    return T.Label(how.source) .. (detail ~= "" and (", " .. detail) or "")
end

-- Pourquoi un objet n'a pas de prix d'enchère (il compte alors au marchand).
function T.Why(how, money)
    if how and how.liveOdd then
        return "prix relevé aberrant" .. (money and (" (" .. money(how.liveOdd) .. ")") or "")
    end
    if how and how.gone then return "pas en vente au dernier relevé de l'hôtel des ventes" end
    return T.HasExchange() and "jamais vu à l'hôtel des ventes (ni par ForeverExchange, ni à un relevé)"
        or "jamais vu à l'hôtel des ventes (aucun relevé ; ForeverExchange absent)"
end

-- Quand datent les prix de ForeverExchange : « ForeverExchange : analyse à 06:13 » ; sans lui, il le dit.
function T.DataText()
    local h = House()
    if not h then return "ForeverExchange absent" end
    if not h.lastScan then return "ForeverExchange : aucune analyse" end
    return "ForeverExchange : analyse " .. T.At(h.lastScan)
end

-- Le détail, en lignes d'infobulle : { libellé, valeur }.
function T.DataLines()
    local lines = {}
    local h = House()
    if h then
        local n = 0
        for _ in pairs(h.items) do n = n + 1 end
        lines[#lines + 1] = { "ForeverExchange", h.lastScan and ("analyse " .. T.At(h.lastScan)) or "aucune analyse" }
        lines[#lines + 1] = { "Objets connus", Decimals(n) }
    else
        lines[#lines + 1] = { "ForeverExchange", "absent (facultatif)" }
    end
    local scan = T.ScanLine and T.ScanLine()
    if scan then lines[#lines + 1] = scan end
    return lines
end

-- Ce que fait le bouton « ForeverExchange » de la fenêtre.
T.EXCHANGE_HELP = "Ouvre la fenêtre de ForeverExchange (historique et graphiques des prix). Ses prix servent quand un "
    .. "objet n'a pas encore été relevé par ForeverCraftAtlas, et pour « Achat sans relevé ». Une analyse lancée par "
    .. "ForeverExchange à l'hôtel des ventes est aussi lue par ForeverCraftAtlas : une seule suffit pour les deux."
T.REFRESH_HELP_MANUAL = T.EXCHANGE_HELP

-- Ce que fait « Scanner l'HDV ».
T.SCAN_HELP = "Relève toutes les annonces de l'hôtel des ventes (il doit être ouvert) : le prix le plus bas de chaque "
    .. "objet, et chaque offre des composants. Le jeu n'en donne qu'un par quart d'heure : plus tôt, c'est une "
    .. "recherche de tous les objets, page après page (le prix le plus bas de chacun, pas chaque offre). "
    .. "ForeverExchange lit la même analyse s'il est installé."

-- Recharger l'interface, et rouvrir la fenêtre au chargement suivant (gardé pour les anciennes données).
function T.Reload(reopen)
    if type(reopen) == "table" then reopen.reopen = true end
    if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
end

function T.Reopen(saved, open)
    if type(saved) ~= "table" or not saved.reopen then return false end
    saved.reopen = nil
    C_Timer.After(0.5, open)
    return true
end

-- (les achats de plusieurs, T.Fill, gardés jusqu'à T.Clear ou au prochain relevé ; redéfini plus bas)
function T.Clear() end

-- Relevés en jeu ------------------------------------------------------------------------------------------------------
-- Les prix de ton royaume en ce moment, vus à l'hôtel des ventes (celui du jeu ou celui d'un addon : les mêmes réponses du
-- jeu, C_AuctionHouse) :
-- - tout l'hôtel des ventes, à son ouverture : chaque annonce (plus bas, « Le relevé de tout l'hôtel des ventes ») ;
-- - une catégorie ou une recherche (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED et _ADDED) : pour chaque objet, son prix le
--   plus bas à l'unité et la quantité en vente. Sur Forever, un objet qui s'empile est une marchandise (prix à
--   l'unité ; c'est ce que le jeu y suppose) et une annonce d'un objet qui ne s'empile pas est un objet : tout ce
--   qu'une catégorie montre est relevé ; seul un objet que le jeu dit « pas une marchandise » et qui s'empilerait
--   serait vendu en piles entières (prix d'une pile) : laissé ;
-- - un objet ouvert : une marchandise (COMMODITY_SEARCH_RESULTS_UPDATED et _ADDED : le prix à l'unité de chaque
--   annonce) ou un objet (ITEM_SEARCH_RESULTS_UPDATED et _ADDED : le prix et la quantité de chaque annonce, d'où
--   l'unité).
-- Pour chaque objet : son prix le plus bas, la quantité en vente et, pour ceux que l'addon demande (T.LiveAttach : les
-- composants de CraftAtlas), toutes ses offres, du moins cher au plus cher (chaque prix à l'unité et combien il y en a
-- à ce prix) : ce que coûterait l'achat de plusieurs tout de suite (T.Fill). Une catégorie ne dit que le prix le plus
-- bas et la quantité : les offres d'avant restent si elles s'y accordent encore (même prix, même quantité), sinon
-- elles sont oubliées jusqu'au prochain relevé.
-- Gardés dans les variables de l'addon (T.LiveAttach, une table à lui), oubliés après T.LIVE_KEEP : jusque-là, le
-- dernier relevé fait le prix, quel que soit son âge (dit à côté : « relevé il y a 2 h »). T.OnLive(fn) : appelée un
-- instant après de nouveaux relevés.
T.LIVE_KEEP = 14 * 86400
T.BOOK_LEVELS = 200 -- (prix différents gardés par objet, les moins chers)

-- store[n° d'objet] = { prix le plus bas à l'unité (0 : rien en vente), quantité en vente, quand, offres { prix,
-- quantité, prix, quantité... } ou nil, quand les offres ont été relevées, true s'il en manque (pas toutes chargées) } ;
-- store.scan : le relevé de tout l'hôtel des ventes (at : le dernier fini, how, items, auctions ; asked : la dernière
-- demande ; failed : la dernière restée sans réponse).
local store, wanted, liveListeners, liveSoon, fills = nil, nil, {}, false, {}

-- t : la table de l'addon pour ses relevés ; books : quels objets gardent toutes leurs offres (true : tous ; une
-- fonction(n° d'objet) ; nil : aucun, seulement le prix le plus bas et la quantité).
function T.LiveAttach(t, books)
    store, wanted, fills = t, books, {}
    local now = time()
    for id, e in pairs(store) do
        if type(id) == "number" then
            if type(e) ~= "table" or type(e[3]) ~= "number" or now - e[3] > T.LIVE_KEEP then
                store[id] = nil
            elseif e[4] ~= nil and (type(e[4]) ~= "table" or type(e[5]) ~= "number" or now - e[5] > T.LIVE_KEEP) then
                e[4], e[5], e[6] = nil, nil, nil
            end
        end
    end
    if type(store.scan) ~= "table" then store.scan = {} end
end

-- (les achats de plusieurs sont gardés jusqu'à T.Clear, et refaits à chaque nouveau relevé)
local clearPrices = T.Clear
function T.Clear() clearPrices() fills = {} end

local function Wants(itemID)
    if wanted == true then return true end
    if type(wanted) ~= "function" then return false end
    local ok, yes = pcall(wanted, itemID)
    return ok and yes and true or false
end

function T.OnLive(fn) liveListeners[#liveListeners + 1] = fn end

local function LiveChanged()
    fills = {}
    if liveSoon then return end
    liveSoon = true
    C_Timer.After(0.5, function()
        liveSoon = false
        for _, fn in ipairs(liveListeners) do pcall(fn) end
    end)
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- Des offres triées : { [prix à l'unité] = quantité } -> { prix, quantité, ... } du moins cher, au plus T.BOOK_LEVELS
-- prix ; rend aussi true quand il y en avait plus (les plus chères laissées).
local function Levels(map)
    local prices = {}
    for p in pairs(map) do prices[#prices + 1] = p end
    table.sort(prices)
    local out = {}
    for i = 1, math.min(#prices, T.BOOK_LEVELS) do
        out[#out + 1] = prices[i]
        out[#out + 1] = map[prices[i]]
    end
    return out, #prices > T.BOOK_LEVELS
end

-- Les offres gardées disent-elles encore vrai, d'après un relevé qui n'a que le prix le plus bas et la quantité ?
local function Agrees(book, price, qty)
    if #book == 0 then return price <= 0 end
    local total = 0
    for i = 2, #book, 2 do total = total + book[i] end
    return book[1] == price and total == qty
end

local function Record(itemID, unit, qty, book, partial)
    local now, old = time(), store[itemID]
    local e = { unit > 0 and math.floor(unit + 0.5) or 0, math.max(0, math.floor(qty or 0)), now }
    if book and Wants(itemID) then
        e[4], e[5], e[6] = book, now, partial or nil
    elseif type(old) == "table" and type(old[4]) == "table" and not old[6] and Agrees(old[4], e[1], e[2]) then
        e[4], e[5] = old[4], now -- (même prix le plus bas, même quantité : les mêmes offres, encore vraies)
    end
    store[itemID] = e
end

-- Un relevé : le prix le plus bas à l'unité (cuivre) d'un objet et la quantité en vente, maintenant ; book : toutes
-- ses offres ({ [prix à l'unité] = quantité }), partial : s'il en manque (pas toutes chargées).
function T.LiveRecord(itemID, unit, qty, book, partial)
    if not store or Secret(itemID) or Secret(unit) or Secret(qty) then return end
    itemID, unit, qty = tonumber(itemID), tonumber(unit), tonumber(qty)
    if not itemID or not unit or unit <= 0 then return end
    local levels, cut
    if type(book) == "table" then levels, cut = Levels(book) end
    Record(itemID, unit, qty, levels, partial or cut)
    LiveChanged()
end

-- Le dernier relevé d'un objet en vente : { price = le prix le plus bas à l'unité, qty = la quantité en vente, age =
-- depuis combien de secondes } ; nil sans relevé (ou plus vieux que T.LIVE_KEEP), ou s'il n'y était pas en vente.
function T.Live(itemID)
    local e = store and store[tonumber(itemID) or false]
    if type(e) ~= "table" or (e[1] or 0) <= 0 then return nil end
    local age = time() - e[3]
    if age > T.LIVE_KEEP then return nil end
    return { price = e[1], qty = e[2], age = math.max(0, age) }
end

-- Combien d'objets ont un relevé (en vente).
function T.LiveCount()
    local n, now = 0, time()
    for id, e in pairs(store or {}) do
        if type(id) == "number" and type(e) == "table" and (e[1] or 0) > 0 and now - e[3] <= T.LIVE_KEEP then n = n + 1 end
    end
    return n
end

-- Toutes les offres d'un objet, au dernier relevé : { levels = { prix, quantité, ... } du moins cher, qty = combien en
-- tout, age, partial = s'il en manque, none = rien en vente } ; nil quand on ne les connaît pas (l'addon ne les garde
-- pas pour lui, pas de relevé, ou seulement son prix le plus bas). Un objet absent du dernier relevé de tout l'hôtel
-- des ventes (jamais vu, ou vu sans rien en vente) n'y est pas en vente.
function T.Book(itemID)
    itemID = tonumber(itemID)
    if not (store and itemID) then return nil end
    local now, e = time(), store[itemID]
    if type(e) == "table" and type(e[4]) == "table" and type(e[5]) == "number" and now - e[5] <= T.LIVE_KEEP then
        local qty = 0
        for i = 2, #e[4], 2 do qty = qty + e[4][i] end
        return { levels = e[4], qty = qty, age = math.max(0, now - e[5]), partial = e[6] and true or false,
            none = #e[4] == 0 }
    end
    local s = store.scan
    if type(s) == "table" and s.at and now - s.at <= T.LIVE_KEEP and Wants(itemID)
        and (type(e) ~= "table" or ((e[1] or 0) <= 0 and now - e[3] <= T.LIVE_KEEP)) then
        return { levels = {}, qty = 0, age = math.max(0, now - s.at), partial = false, none = true }
    end
    return nil
end

-- Acheter n unités d'un objet tout de suite, aux offres les moins chères (seulement celles sous cap quand il est
-- donné : au-delà, le marchand est moins cher) : { got = unités trouvées, cost = ce qu'elles coûtent, low et top = le
-- prix à l'unité de la moins chère et de la plus chère prises, qty = combien en vente en tout, age, partial, none } ;
-- nil quand on ne connaît pas ses offres.
function T.Fill(itemID, n, cap)
    n = math.max(0, math.floor(tonumber(n) or 0))
    local key = tostring(itemID) .. ":" .. n .. ":" .. tostring(cap)
    local hit = fills[key]
    if hit ~= nil then return hit or nil end
    local book = T.Book(itemID)
    if not book then fills[key] = false return nil end
    local got, cost, low, top, levels = 0, 0, nil, nil, book.levels
    for i = 1, #levels - 1, 2 do
        if got >= n then break end
        local p, q = levels[i], levels[i + 1]
        if cap and p >= cap then break end
        local take = math.min(q, n - got)
        got, cost, top = got + take, cost + take * p, p
        low = low or p
    end
    local out = { got = got, cost = cost, low = low, top = top, qty = book.qty, age = book.age, partial = book.partial,
        none = book.none }
    fills[key] = out
    return out
end

-- « à l'instant », « il y a 3 min », « il y a 2 h 05 », « il y a 1 j 5 h », « il y a 4 j ».
function T.AgeText(age)
    if age < 60 then return "à l'instant" end
    local m = math.floor(age / 60 + 0.5)
    if m < 60 then return ("il y a %d min"):format(m) end
    local h, mm = math.floor(m / 60), m % 60
    if h < 24 then return mm > 0 and ("il y a %d h %02d"):format(h, mm) or ("il y a %d h"):format(h) end
    local d, hh = math.floor(h / 24), h % 24
    return (d < 3 and hh > 0) and ("il y a %d j %d h"):format(d, hh) or ("il y a %d j"):format(d)
end

-- La fin d'un relevé : « 207 en vente, relevé il y a 3 min ».
function T.LiveTail(live)
    if not live then return "" end
    local qty = (live.qty or 0) > 0 and (Decimals(live.qty) .. " en vente, ") or ""
    return qty .. "relevé " .. T.AgeText(live.age)
end

-- Un relevé en une phrase : « 1 pa 29, 207 en vente, relevé il y a 3 min » (sans le prix : « le moins cher sur ton
-- royaume, 207 en vente, relevé il y a 3 min »).
function T.LiveText(live, money, withoutPrice)
    if not live then return "" end
    local head = withoutPrice and "le moins cher sur ton royaume" or (money and money(live.price) or "")
    return head .. ", " .. T.LiveTail(live)
end

-- ForeverExchange, en prix ----------------------------------------------------------------------------------------------
-- Le prix minimum d'un objet chez ForeverExchange : { price, age = depuis combien de secondes (nil : inconnu), qty,
-- listed = en vente à son dernier scan } ; nil s'il ne l'a jamais vu (ou sans ForeverExchange).
function T.Exchange(itemID)
    local it, h = FXItem(itemID)
    local price, at, listed, qty = FXCurrent(it, h)
    if not price or Secret(price) then return nil end
    return { price = price, age = at and math.max(0, time() - at) or nil, qty = Num(qty), listed = listed }
end
T.Auctionator = T.Exchange -- (ancien nom)

-- « 207 en vente, analysé il y a 2 h par ForeverExchange ».
function T.ExchangeText(itemID)
    local e = T.Exchange(itemID)
    if not e then return "" end
    local text = e.age and ("analysé " .. T.AgeText(e.age) .. " par ForeverExchange") or "vu par ForeverExchange"
    if e.qty and e.listed ~= false then text = Decimals(e.qty) .. " en vente, " .. text end
    return text
end
T.AuctionatorText = T.ExchangeText

-- Le prix le plus bas d'un objet : d'abord notre relevé (T.Live), sinon ForeverExchange. Rend (prix, how) ou (nil, how).
function T.Lowest(itemID)
    local how = { item = itemID, lowest = true }
    local live = T.Live(itemID)
    if live then
        how.source, how.wanted, how.live = T.LIVE, T.LIVE, live
        return live.price, how
    end
    local e = T.Exchange(itemID)
    if e then
        how.source, how.wanted, how.exchange, how.gone = T.EXCHANGE, T.EXCHANGE, e, T.Gone(itemID) or nil
        return e.price, how
    end
    how.none, how.gone = true, T.Gone(itemID) or nil
    return nil, how
end

-- Les fenêtres qui suivent les relevés (T.OnLive) suivent aussi les analyses de ForeverExchange : sa date du dernier
-- scan est regardée toutes les quelques secondes (il n'a pas d'API d'événements ; une simple lecture de table).
local following = false
function T.FollowExchange()
    if following or not C_Timer or not C_Timer.NewTicker then return end
    following = true
    local last
    C_Timer.NewTicker(3, function()
        local h = House()
        local at = h and h.lastScan or false
        if last ~= nil and at ~= last then LiveChanged() end
        last = at
    end)
end
T.FollowAuctionator = T.FollowExchange -- (ancien nom)

-- Ce que coûte un objet acheté à l'hôtel des ventes : le prix le plus bas de son dernier relevé (useLive), sinon la
-- source choisie et ses remplaçantes. Rend (prix, source prise : T.LIVE pour le relevé) ou nil.
function T.Buy(itemID, source, useLive)
    local live = useLive and T.Live(itemID)
    if live then return live.price, T.LIVE end
    return T.Price(itemID, source)
end

-- Le prix le plus bas d'un résultat de parcours est-il celui d'une unité ? Oui, sauf pour un objet que le jeu dit
-- « pas une marchandise » et qui s'empile (vendu en piles entières). La fiche d'un objet que le jeu n'a pas encore
-- chargée (la plupart, dans une catégorie) ne l'empêche pas : sur Forever, objet empilé = marchandise.
local function UnitPriced(key)
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
    if not (ok and type(info) == "table") or info.isCommodity ~= false then return true end
    local stack
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local ok2, n = pcall(C_Item.GetItemMaxStackSizeByID, key.itemID)
        stack = ok2 and n or nil
    end
    if stack == nil and C_Item and C_Item.GetItemInfo then stack = select(8, C_Item.GetItemInfo(key.itemID)) end
    return type(stack) ~= "number" or stack <= 1
end

-- Le relevé de tout l'hôtel des ventes : son état (plus bas) ; run.browse : une recherche de tous les objets en cours
-- (la nôtre, ou celle d'un autre addon : l'analyse de ForeverExchange), et les objets qu'elle a montrés.
local run = { token = 0 }

local function Browse(results)
    local best, qty = {}, {}
    local seen = run.browse and run.browse.seen or nil
    for _, r in ipairs(type(results) == "table" and results or {}) do
        local key = r.itemKey
        local id = key and key.itemID
        if seen and id and (r.totalQuantity or 0) > 0 and not seen[id] then
            seen[id] = true
            run.browse.n = (run.browse.n or 0) + 1 -- (combien d'objets vus : la barre du relevé)
        end
        if id and (key.battlePetSpeciesID or 0) == 0 and (r.totalQuantity or 0) > 0 and type(r.minPrice) == "number"
            and r.minPrice > 0 and UnitPriced(key) then
            if not best[id] or r.minPrice < best[id] then best[id] = r.minPrice end
            qty[id] = (qty[id] or 0) + r.totalQuantity
        end
    end
    for id, price in pairs(best) do T.LiveRecord(id, price, qty[id]) end
end

local function Commodity(itemID)
    local AH = C_AuctionHouse
    local best, qty, map = nil, 0, {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and type(r.unitPrice) == "number" and r.unitPrice > 0 then
            if not best or r.unitPrice < best then best = r.unitPrice end
            local q = tonumber(r.quantity) or 0
            qty = qty + q
            if q > 0 then map[r.unitPrice] = (map[r.unitPrice] or 0) + q end
        end
    end
    -- (une longue liste arrive par morceaux : tant qu'elle n'est pas toute là, il manque les offres les plus chères)
    local full = AH.HasFullCommoditySearchResults and AH.HasFullCommoditySearchResults(itemID)
    if best then
        T.LiveRecord(itemID, best, qty, map, full == false)
    elseif full == true and store and not Secret(itemID) and tonumber(itemID) then
        Record(tonumber(itemID), 0, 0, {}) -- (toute la liste, et rien dedans : rien en vente)
        LiveChanged()
    end
end

local function Items(key)
    local AH = C_AuctionHouse
    if type(key) ~= "table" or not key.itemID or (key.battlePetSpeciesID or 0) ~= 0 then return end
    local best, qty, map = nil, 0, {}
    for i = 1, AH.GetNumItemSearchResults(key) or 0 do
        local r = AH.GetItemSearchResultInfo(key, i)
        -- (le prix d'achat d'une annonce entière, pour sa quantité ; une annonce sans achat immédiat ne compte pas)
        if r and type(r.buyoutAmount) == "number" and r.buyoutAmount > 0 and (r.quantity or 0) > 0 then
            local unit = r.buyoutAmount / r.quantity
            if not best or unit < best then best = unit end
            qty = qty + r.quantity
            local p = math.floor(unit + 0.5)
            map[p] = (map[p] or 0) + r.quantity
        end
    end
    local full = AH.HasFullItemSearchResults and AH.HasFullItemSearchResults(key)
    if best then T.LiveRecord(key.itemID, best, qty, map, full == false) end
end

-- Le relevé de tout l'hôtel des ventes ---------------------------------------------------------------------------------
-- Un instant après l'ouverture de l'hôtel des ventes (T.SCAN_DELAY), toutes ses annonces : le jeu les envoie d'un coup
-- (C_AuctionHouse.ReplicateItems, fait pour cela : de chaque annonce, l'objet, la quantité, le prix d'achat immédiat),
-- au plus une fois par quart d'heure (T.SCAN_EVERY ; avant, rien à redemander). Sa réponse est lue par paquets
-- (T.SCAN_BATCH annonces par image : pas d'à-coup), puis rangée d'un coup : pour chaque objet, son prix le plus bas,
-- sa quantité et, pour ceux que l'addon garde, chacune de ses offres ; ce qui n'y est pas n'est plus en vente (son
-- ancien relevé est effacé). Fermer l'hôtel des ventes avant la fin l'abandonne.
-- Sans réponse du jeu (T.SCAN_WAIT secondes), ou quand le dernier relevé fini a plus d'un quart d'heure alors qu'il est
-- trop tôt pour en redemander un : une recherche de tous les objets (une recherche vide, page après page :
-- SendBrowseQuery puis RequestMoreBrowseResults, au rythme que le jeu permet), qui donne de chacun le prix le plus bas
-- et la quantité, pas chaque offre. La liste de l'hôtel des ventes l'affiche pendant ce temps ; ta propre recherche
-- l'arrête, et sans réponse au relevé, elle ne part que si personne n'a rien cherché depuis l'ouverture.
-- La même recherche faite par un autre addon (l'analyse de ForeverExchange ou d'Auctionator : la même recherche vide)
-- est suivie de même jusqu'au bout : c'est aussi un relevé de tout l'hôtel des ventes (run.browse, à part du relevé
-- demandé, qui peut être en cours en même temps ; nous n'en demandons alors pas les pages).
-- ForeverExchange fait de même : le premier qui demande le relevé le fait, l'autre le voit (hooksecurefunc sur les
-- fonctions du jeu) et lit la même réponse pour ses propres prix.
-- T.autoScan : faux, le relevé ne se lance qu'à la main (« Scanner l'HDV », T.ScanNow) ; ceux lancés par un autre
-- addon (ForeverExchange à l'ouverture de l'HV, Auctionator) sont suivis.
T.autoScan = false
T.SCAN_EVERY = 15 * 60
T.SCAN_DELAY = 1.5
T.SCAN_WAIT = 45
T.SCAN_BATCH = 2500
T.SCAN_STALL = 60 -- (recherche de tous les objets : plus rien depuis tant de secondes, elle n'est plus suivie)
local PET_CAGE = 82800 -- (une mascotte en cage : un seul objet pour toutes, laissé)

-- run.state : nil, "asked" (relevé demandé, réponse attendue) ou "reading" (sa lecture) ; token change à chaque état (une
-- minuterie d'avant se tait). run.browse : la recherche de tous les objets suivie, { seen = les objets qu'elle a
-- montrés, since = son début, pages, mine = la nôtre (nous en demandons les pages), waiting = page suivante attendue }.
local ahOpen, openedAt, lastOther = false, 0, nil -- (lastOther : GetTime() de la dernière recherche d'un autre)
local StartBrowse

local function Scan() return store and store.scan or {} end

local function SetState(state)
    run.state, run.token = state, run.token + 1
    LiveChanged() -- (les fenêtres montrent où en est le relevé)
    return run.token
end

local function StopBrowse()
    if run.browse then run.browse = nil LiveChanged() end
end

-- Ce qui n'est pas dans un relevé de tout l'hôtel des ventes, et n'a pas été revu depuis son début, n'est plus en vente.
local function MarkGone(seen, since)
    local now = time()
    for id, e in pairs(store) do
        if type(id) == "number" and not seen[id] and type(e) == "table" and e[3] < since then
            local book = Wants(id) and {} or nil
            store[id] = { 0, 0, now, book, book and now or nil }
        end
    end
end

local function Finish(how, seen, since, auctions)
    MarkGone(seen, since)
    local s, n = Scan(), 0
    for _ in pairs(seen) do n = n + 1 end
    s.at, s.how, s.items, s.auctions, s.failed = time(), how, n, auctions, nil
end

local function NoAnswer()
    Scan().failed = time()
    SetState(nil)
    -- (personne n'a rien cherché depuis l'ouverture : la recherche de tous les objets, à la place)
    if ahOpen and not run.browse and not (lastOther and lastOther > openedAt + 1) then StartBrowse() end
end

local function ReadReplicate(token)
    local AH = C_AuctionHouse
    local ok, total = pcall(AH.GetNumReplicateItems)
    total = ok and tonumber(total) or 0
    if total <= 0 then NoAnswer() return end
    run.total, run.done = total, 0
    local since = Scan().asked or time()
    local best, qty, books, wants, auctions, i = {}, {}, {}, {}, 0, 0
    local function Step()
        if run.token ~= token then return end -- (abandonné : l'hôtel des ventes s'est fermé)
        local last = math.min(total - 1, i + T.SCAN_BATCH - 1)
        for k = i, last do
            local got, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(AH.GetReplicateItemInfo, k)
            -- (une valeur secrète ne se compare pas : vérifiée d'abord)
            if got and not (Secret(itemID) or Secret(count) or Secret(buyout)) and type(itemID) == "number"
                and itemID > 0 and itemID ~= PET_CAGE and type(count) == "number" and count > 0
                and type(buyout) == "number" and buyout > 0 then
                local unit = buyout / count
                auctions = auctions + 1
                if not best[itemID] or unit < best[itemID] then best[itemID] = unit end
                qty[itemID] = (qty[itemID] or 0) + count
                local w = wants[itemID]
                if w == nil then w = Wants(itemID) wants[itemID] = w end
                if w then
                    local map = books[itemID]
                    if not map then map = {} books[itemID] = map end
                    local p = math.floor(unit + 0.5)
                    map[p] = (map[p] or 0) + count
                end
            end
        end
        i = last + 1
        run.done = i
        if i < total then C_Timer.After(0, Step) return end
        for id, unit in pairs(best) do
            local levels, cut
            if books[id] then levels, cut = Levels(books[id]) end
            Record(id, unit, qty[id], levels, cut)
        end
        Finish("replicate", best, since, auctions)
        SetState(nil)
    end
    Step()
end

-- Le relevé demandé (par nous, l'autre addon ou un autre) : sa réponse est attendue.
local function OnReplicateAsked()
    if not store then return end
    Scan().asked = time()
    if run.state == "reading" then return end
    local token = SetState("asked")
    C_Timer.After(T.SCAN_WAIT, function() if run.token == token then NoAnswer() end end)
end

-- La réponse (une seule lecture par demande ; une réponse tardive, après la recherche de tous les objets partie à sa
-- place, est lue quand même : elle a chaque offre).
local function OnReplicateList()
    local asked = Scan().asked
    if not ahOpen or run.state == "reading" or not asked or time() - asked > 300 or run.answered == asked then return end
    run.answered = asked
    if run.browse then run.browse.mine = false end -- (la réponse a tout : plus besoin de demander des pages)
    local token = SetState("reading")
    run.total, run.done = 0, 0
    -- (un instant avant de lire : la liste finit d'arriver)
    C_Timer.After(0.5, function() if run.token == token then ReadReplicate(token) end end)
end

-- Une recherche de tous les objets : vide, sans filtre (celle-ci, ou la même par un autre addon).
local function IsFull(query)
    if type(query) ~= "table" or query.searchString ~= "" or Secret(query.searchString) then return false end
    for _, k in ipairs({ "filters", "itemClassFilters" }) do
        if type(query[k]) == "table" and #query[k] > 0 then return false end
    end
    return (query.minLevel or 0) == 0 and (query.maxLevel or 0) == 0
end

local function Stalled()
    local b = run.browse
    local pages = b and b.pages
    if not b then return end
    C_Timer.After(T.SCAN_STALL, function() if run.browse == b and b.pages == pages then StopBrowse() end end)
end

local function MorePages()
    local b, AH = run.browse, C_AuctionHouse
    if not (b and b.mine and ahOpen) then return end
    if AH.IsThrottledMessageSystemReady then
        local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
        if ok and not ready then b.waiting = true return end -- (le jeu dira quand : THROTTLED_SYSTEM_READY)
    end
    b.waiting = false
    pcall(AH.RequestMoreBrowseResults)
end

local function AfterBrowse()
    local b = run.browse
    if not b then return end
    b.pages = b.pages + 1
    local ok, full = pcall(C_AuctionHouse.HasFullBrowseResults)
    if ok and full then
        run.browse = nil
        Finish("browse", b.seen, b.since)
        LiveChanged()
        return
    end
    Stalled()
    MorePages()
end

local function OnBrowseQuery(query)
    if not store then return end
    if not run.sending then lastOther = GetTime() end
    if IsFull(query) then
        run.browse = { seen = {}, n = 0, since = time(), pages = 0, mine = run.sending and true or false, waiting = false }
        LiveChanged()
        Stalled()
    else
        StopBrowse() -- (une autre recherche : celle de tous les objets ne va pas au bout)
    end
end

-- (les favoris : le jeu les cherche de lui-même à l'ouverture, ce n'est pas toi qui cherches)
local function OtherQuery()
    if GetTime() - openedAt > 1 then lastOther = GetTime() end
    StopBrowse()
end

function StartBrowse()
    local AH = C_AuctionHouse
    if run.browse or not (ahOpen and store and AH and AH.SendBrowseQuery) then return end
    run.sending = true
    pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    run.sending = false
end

local function StartScan()
    local AH = C_AuctionHouse
    if not (ahOpen and store and AH) or run.state or run.browse then return end
    local s, now = Scan(), time()
    if AH.ReplicateItems and now - (s.asked or 0) >= T.SCAN_EVERY then
        pcall(AH.ReplicateItems) -- (l'accroche ci-dessous suit la demande, comme celle de l'autre addon)
        if not run.state then OnReplicateAsked() end
    elseif now - (s.at or 0) >= T.SCAN_EVERY and not (lastOther and lastOther > openedAt + 1) then
        StartBrowse()
    end
end

-- Le relevé demandé de la main (bouton « Scanner l'HDV ») : tout l'hôtel des ventes, chaque offre (ReplicateItems) ;
-- moins d'un quart d'heure après le dernier demandé (le jeu n'en donne pas plus), la recherche de tous les objets à la
-- place (le prix le plus bas de chacun). Rend false et pourquoi quand il ne peut pas partir (T.CanScan).
function T.CanScan()
    if not (ahOpen and store and C_AuctionHouse) then return false, "Ouvre l'hôtel des ventes pour le relever." end
    if run.state or run.browse then return false, "Relevé de tout l'hôtel des ventes en cours." end
    return true
end

function T.ScanNow()
    local ok, why = T.CanScan()
    if not ok then return false, why end
    local AH = C_AuctionHouse
    if AH.ReplicateItems and time() - (Scan().asked or 0) >= T.SCAN_EVERY then
        pcall(AH.ReplicateItems)
        if not run.state then OnReplicateAsked() end
    else
        StartBrowse()
    end
    return true
end

-- Le prochain relevé de chaque offre (ReplicateItems) possible : dans combien de secondes (0 : tout de suite).
function T.ScanWait()
    return math.max(0, (Scan().asked or 0) + T.SCAN_EVERY - time())
end

function T.AHOpen() return ahOpen end

local hookedAH
local function Hook()
    local AH = C_AuctionHouse
    if not hooksecurefunc or type(AH) ~= "table" or hookedAH == AH then return end
    hookedAH = AH
    if type(AH.ReplicateItems) == "function" then hooksecurefunc(AH, "ReplicateItems", OnReplicateAsked) end
    if type(AH.SendBrowseQuery) == "function" then hooksecurefunc(AH, "SendBrowseQuery", OnBrowseQuery) end
    for _, name in ipairs({ "SearchForFavorites", "SearchForItemKeys" }) do
        if type(AH[name]) == "function" then hooksecurefunc(AH, name, OtherQuery) end
    end
end
Hook()

-- Où en est le relevé de tout l'hôtel des ventes, en quelques mots (« hôtel des ventes relevé à 10:42 » ; short :
-- « HV relevé à 10:42 ») ; nil sans relevé (ou plus vieux que T.LIVE_KEEP).
function T.ScanText(short)
    if run.state or run.browse then
        return short and "relevé de l'HV en cours" or "relevé de tout l'hôtel des ventes en cours"
    end
    local s = Scan()
    if s.at and time() - s.at <= T.LIVE_KEEP then
        return (short and "HV relevé " or "hôtel des ventes relevé ") .. T.At(s.at)
    end
    return nil
end

-- Où en est le relevé en cours, pour la barre (T.ScanBar) : { fraction = de 0 à 1 (nil : sans total connu), text =
-- l'étape, done = fini à l'instant } ; nil sans relevé en cours ni fini il y a moins de T.SCAN_SHOW_DONE secondes.
T.SCAN_SHOW_DONE = 5
function T.ScanProgress()
    local s = Scan()
    if run.state == "asked" then
        return { text = ("Relevé demandé au jeu : réponse attendue (%d s)"):format(math.max(0, time() - (s.asked or time()))) }
    elseif run.state == "reading" then
        local total, done = run.total or 0, run.done or 0
        if total <= 0 then return { text = "Réponse reçue : lecture des annonces..." } end
        return { fraction = done / total, text = ("Lecture des annonces : %s / %s (%d %%)"):format(Decimals(done),
            Decimals(total), math.floor(100 * done / total)) }
    elseif run.browse then
        local b = run.browse
        return { text = ("Recherche de tous les objets : page %d · %s objet%s vu%s"):format(b.pages + 1,
            Decimals(b.n or 0), (b.n or 0) > 1 and "s" or "", (b.n or 0) > 1 and "s" or "") }
    end
    local now = time()
    if s.at and now - s.at <= T.SCAN_SHOW_DONE then
        local parts = {}
        if s.auctions then parts[#parts + 1] = Decimals(s.auctions) .. " annonce" .. (s.auctions > 1 and "s" or "") end
        if s.items then parts[#parts + 1] = Decimals(s.items) .. " objet" .. (s.items > 1 and "s" or "") end
        return { fraction = 1, done = true, text = "Relevé terminé" .. (#parts > 0 and (" : " .. table.concat(parts, ", ")) or "") }
    end
    if s.failed and now - s.failed <= T.SCAN_SHOW_DONE and not (s.at and s.at > s.failed) then
        return { fraction = 1, done = true, failed = true, text = "Pas de réponse du jeu au relevé" }
    end
    return nil
end

-- La barre du relevé de l'hôtel des ventes (en bas de la fenêtre de ForeverCraftAtlas) : l'étape en cours écrite
-- dessus ; sans total connu (réponse attendue, recherche page par page), elle avance en boucle. Elle se montre seule
-- pendant un relevé (et quelques secondes après), regardée dix fois par seconde tant que parent est affiché ;
-- onToggle(shown) quand elle apparaît ou disparaît (pour cacher ce qu'elle recouvre).
function T.ScanBar(parent, onToggle)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(16)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.6)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar:Hide()
    function bar:Update()
        local p = T.ScanProgress()
        if not p then
            if self:IsShown() then
                self:Hide()
                if onToggle then onToggle(false) end
            end
            return
        end
        self:SetValue(p.fraction or ((GetTime() % 2) / 2))
        if p.failed then self:SetStatusBarColor(0.8, 0.25, 0.2)
        elseif p.done then self:SetStatusBarColor(0.25, 0.75, 0.3)
        else self:SetStatusBarColor(0.2, 0.5, 1) end
        self.text:SetText(p.text)
        if not self:IsShown() then
            self:Show()
            if onToggle then onToggle(true) end
        end
    end
    local watch, since = CreateFrame("Frame", nil, parent), 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < 0.1 then return end
        since = 0
        bar:Update()
    end)
    return bar
end

-- Absent du dernier relevé de tout l'hôtel des ventes (ou vu sans rien en vente depuis) : il n'y est pas en vente.
function T.Gone(itemID)
    itemID = tonumber(itemID)
    if not (store and itemID) then return false end
    local e, s = store[itemID], store.scan
    if type(e) == "table" and time() - (e[3] or 0) <= T.LIVE_KEEP then return (e[1] or 0) <= 0 end
    return type(s) == "table" and s.at ~= nil and time() - s.at <= T.LIVE_KEEP
end

-- La même chose en ligne d'infobulle : { libellé, détail } (« Hôtel des ventes relevé », « à 10:42 · 52 300 annonces,
-- 4 120 objets ») ; nil s'il n'y en a jamais eu.
function T.ScanLine()
    local s = Scan()
    if run.state or run.browse then return { "Hôtel des ventes", "relevé de toutes ses annonces en cours" } end
    if not s.at then
        if s.failed then return { "Hôtel des ventes", "pas de réponse au relevé " .. T.At(s.failed) } end
        return nil
    end
    local parts = {}
    local function Count(n, word) return Decimals(n) .. " " .. word .. (n > 1 and "s" or "") end
    if s.auctions then parts[#parts + 1] = Count(s.auctions, "annonce") end
    if s.items then parts[#parts + 1] = Count(s.items, "objet") end
    return { "Hôtel des ventes relevé", T.At(s.at) .. (#parts > 0 and (" · " .. table.concat(parts, ", ")) or "") }
end

local liveEvents = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
    pcall(liveEvents.RegisterEvent, liveEvents, e) -- (un événement inconnu du client ne bloque pas les autres)
end
liveEvents:SetScript("OnEvent", function(_, event, a)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen, openedAt = true, GetTime()
        Hook()
        if T.autoScan then C_Timer.After(T.SCAN_DELAY, StartScan) end
        LiveChanged() -- (les fenêtres : le bouton du relevé)
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        LiveChanged()
        if run.state then SetState(nil) end -- (un relevé pas fini est abandonné)
        StopBrowse()
        return
    end
    if not (store and C_AuctionHouse) then return end
    pcall(function()
        if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
            Browse(C_AuctionHouse.GetBrowseResults())
            AfterBrowse()
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            Browse(a)
            AfterBrowse()
        elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
            Commodity(a)
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
            Items(a)
        elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
            OnReplicateList()
        elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" and run.browse and run.browse.waiting then
            MorePages()
        end
    end)
end)
