-- Wishlist.lua : les favoris et la wishlist.
--
-- Favoris : l'étoile à gauche du nom d'une recette la met en favori ; la case « Favoris » de l'onglet « Recettes » ne
-- montre qu'elles (ns.List, avec les autres filtres). Pour tout le compte : ForeverCraftAtlasDB.favorites[recette] = true.
--
-- Wishlist : les recettes à fabriquer tout de suite, chacune avec son nombre de fabrications (« + Wishlist » d'une
-- recette l'ajoute avec le nombre de « Fabrications »). Son aperçu dit, pour chacune, ce qu'il faut acheter et où, ce
-- que cela coûte, ce que rapporte la revente et le bénéfice ; « Confirmer les achats » fige ce plan, et Purchase.lua
-- l'achète dès que la fenêtre de l'hôtel des ventes ou d'un marchand est ouverte.
--
-- Ce qu'il faut à une recette : quantité x fabrications de chaque composant. Ce qu'elle a déjà compte d'abord (pris
-- dans les sacs à une confirmation, ou acheté pour elle : entry.have) ; puis ce qui est dans les sacs (sans la banque)
-- et n'est pas déjà à une autre recette de la liste ; le reste s'achète, recette par recette, dans l'ordre de la liste :
-- aux offres les moins chères de l'hôtel des ventes (au dernier relevé ; seulement celles sous le prix du marchand
-- quand il en vend et que « Prix des marchands » est coché), puis chez le marchand ; sans marchand, ce qui manque aux
-- offres relevées se cherchera aussi à l'hôtel des ventes (compté au prix de ForeverExchange, estimé). Deux recettes qui partagent
-- un composant : la seconde prend les offres suivantes. Sans ses offres (pas encore relevées), un composant se compte
-- à son prix le plus bas (ns.UnitCost), estimé.
-- Coût d'une recette : ses achats, plus ce qu'elle a déjà ou prend dans les sacs, au prix le plus bas du moment ; sa
-- revente, comme dans la liste des recettes (ns.Price, pour ses fabrications) ; le bénéfice, la différence.
--
-- Gardée par personnage (ses sacs, son or) : ForeverCraftAtlasDB.wishlist[personnage] = { version, entries = { { key, id =
-- recette, crafts, have = { [composant] = unités } } }, nextKey, plan, last }. plan : les achats confirmés, { at,
-- recipes = { { key, id, crafts, name, value, own, cost, profit, skipped } }, buys = { { key, item, where = "ah" ou
-- "vendor", n, planned (coût prévu des n ; nil : inconnu), unit (marchand : prix prévu à l'unité), estimate, got,
-- spent, missing (introuvables à l'hôtel des ventes), skipped, acceptedUnit } } } ; last : le bilan du dernier.
local _, ns = ...
local PX = ns.Prices

local MAX_CRAFTS = 9999
local VERSION = 1

-- Messages dans la discussion : « ForeverCraftAtlas : ... ».
function ns.Say(text)
    print("|cffffd100ForeverCraftAtlas|r : " .. text)
end

-- Un objet par son nom, de la couleur de sa qualité (« Objet 123 » tant que le jeu n'a pas sa fiche), et son lien.
function ns.ItemLabel(id)
    local name, _, quality
    if C_Item and C_Item.GetItemInfo then name, _, quality = C_Item.GetItemInfo(id) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return ("Objet %d"):format(id)
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and color.hex and (color.hex .. name .. "|r") or name
end

function ns.ItemLink(id)
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(id))
    return link or ns.ItemLabel(id)
end

-- « 35 x Cuir épais »
function ns.Units(id, n, link)
    return ("%s x %s"):format(PX.Decimals(n), link and ns.ItemLink(id) or ns.ItemLabel(id))
end

-- Combien d'un objet dans les sacs du personnage (sans la banque).
function ns.InBags(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id)
        if ok and type(n) == "number" and not (issecretvalue and issecretvalue(n)) then return n end
    end
    return 0
end

-- Favoris -------------------------------------------------------------------------------------------------------------
function ns.Favorites()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    if type(ForeverCraftAtlasDB.favorites) ~= "table" then ForeverCraftAtlasDB.favorites = {} end
    return ForeverCraftAtlasDB.favorites
end

function ns.IsFavorite(id)
    local favorites = ForeverCraftAtlasDB and ForeverCraftAtlasDB.favorites
    return type(favorites) == "table" and id ~= nil and favorites[id] == true
end

function ns.ToggleFavorite(id)
    if not id then return end
    local favorites = ns.Favorites()
    favorites[id] = (not favorites[id]) or nil
    ns.Changed("favorites")
end

function ns.FavoriteCount()
    local n = 0
    for _ in pairs(ns.Favorites()) do n = n + 1 end
    return n
end

-- La wishlist ---------------------------------------------------------------------------------------------------------
local checked = {} -- (la wishlist d'un personnage vérifiée une fois par session : ce qu'une ancienne version a écrit)

local function Clamp(n)
    return math.max(1, math.min(MAX_CRAFTS, math.floor(tonumber(n) or 1)))
end

local function Store()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    if type(ForeverCraftAtlasDB.wishlist) ~= "table" then ForeverCraftAtlasDB.wishlist = {} end
    local char = ns.CharKey()
    local w = ForeverCraftAtlasDB.wishlist[char]
    if type(w) ~= "table" then
        w = {}
        ForeverCraftAtlasDB.wishlist[char] = w
    end
    if not checked[char] then
        checked[char] = true
        w.version = VERSION
        if type(w.entries) ~= "table" then w.entries = {} end
        w.nextKey = math.max(1, math.floor(tonumber(w.nextKey) or 1))
        local seen = {}
        for i = #w.entries, 1, -1 do
            local e = w.entries[i]
            if type(e) ~= "table" or type(e.id) ~= "number" then
                table.remove(w.entries, i)
            else
                e.crafts = Clamp(e.crafts)
                if type(e.have) ~= "table" then e.have = {} end
                if type(e.key) ~= "number" or seen[e.key] then e.key = nil end
                if e.key then seen[e.key] = true end
            end
        end
        for _, e in ipairs(w.entries) do
            if not e.key then e.key = w.nextKey end
            w.nextKey = math.max(w.nextKey, e.key + 1)
        end
        if w.plan ~= nil and (type(w.plan) ~= "table" or type(w.plan.buys) ~= "table"
            or type(w.plan.recipes) ~= "table") then
            w.plan = nil
        end
    end
    return w
end

function ns.WishlistEntries() return Store().entries end
function ns.WishlistPlan() return Store().plan end
function ns.WishlistLast() return Store().last end

-- Des achats confirmés, pas encore finis : la wishlist ne se modifie pas tant qu'ils ne sont pas finis ou arrêtés.
function ns.WishlistBuying() return Store().plan ~= nil end

local function EntryByKey(w, key)
    for i, e in ipairs(w.entries) do
        if e.key == key then return e, i end
    end
end

-- Combien de fois la wishlist fabrique cette recette (0 : elle n'y est pas).
function ns.WishlistCrafts(id)
    local n = 0
    for _, e in ipairs(Store().entries) do
        if e.id == id then n = n + e.crafts end
    end
    return n
end

-- Ajouter une recette (déjà là : ses fabrications s'ajoutent) ; false pendant des achats.
function ns.WishlistAdd(id, crafts)
    local w = Store()
    if w.plan or type(id) ~= "number" then return false end
    crafts = Clamp(crafts)
    for _, e in ipairs(w.entries) do
        if e.id == id then
            e.crafts = Clamp(e.crafts + crafts)
            ns.Changed("wishlist")
            return true
        end
    end
    w.entries[#w.entries + 1] = { key = w.nextKey, id = id, crafts = crafts, have = {} }
    w.nextKey = w.nextKey + 1
    ns.Changed("wishlist")
    return true
end

function ns.WishlistSetCrafts(key, crafts)
    local w = Store()
    local e = not w.plan and EntryByKey(w, key)
    if not e then return false end
    crafts = Clamp(crafts)
    if e.crafts == crafts then return true end
    e.crafts = crafts
    ns.Changed("wishlistCrafts")
    return true
end

function ns.WishlistRemove(key)
    local w = Store()
    if w.plan then return false end
    local _, i = EntryByKey(w, key)
    if not i then return false end
    table.remove(w.entries, i)
    ns.Changed("wishlist")
    return true
end

function ns.WishlistClear()
    local w = Store()
    if w.plan or #w.entries == 0 then return false end
    w.entries = {}
    w.last = nil
    ns.Changed("wishlist")
    return true
end

-- L'aperçu ------------------------------------------------------------------------------------------------------------
-- Les unités start + 1 à start + n des offres (levels : { prix à l'unité, quantité, ... } du moins cher), seulement
-- celles moins chères que cap : (coût, unités prises, prix à l'unité de la moins chère et de la plus chère prises).
local function Walk(levels, start, n, cap)
    local cost, got, skip, low, top = 0, 0, start, nil, nil
    for i = 1, #levels - 1, 2 do
        if got >= n then break end
        local p, q = levels[i], levels[i + 1]
        if cap and p >= cap then break end
        if skip >= q then
            skip = skip - q
        else
            local take = math.min(q - skip, n - got)
            skip = 0
            cost, got, low, top = cost + take * p, got + take, low or p, p
        end
    end
    return cost, got, low, top
end

-- Un composant d'une recette : { id, need, have (déjà à elle), bags (pris dans les sacs), buy (à acheter), ah (aux
-- offres relevées), ahCost, low, top, age, short (il en manque aux offres, sans marchand), shortPrice, shortSource,
-- shortCost, vendor (chez le marchand), vendorPrice, estimate (prix sans les offres), ahUnits et ahPlanned (ce que
-- l'hôtel des ventes doit fournir, et son coût prévu ; nil : inconnu), vendorCost, spend (les achats ; nil : inconnu),
-- unit (le prix le plus bas du moment), own (ce qu'elle a et prend dans les sacs, à ce prix), cost (spend + own) }.
local function Reagent(id, need, have, state)
    local d = { id = id, need = need, have = have }
    local rest = need - have
    d.bags = math.min(rest, state.Free(id))
    state.free[id] = state.Free(id) - d.bags
    local buy = rest - d.bags
    d.buy = buy
    d.ah, d.ahCost, d.short, d.shortCost, d.vendor = 0, 0, 0, 0, 0
    d.unit = (ns.UnitCost(id))
    local owned = have + d.bags
    d.own = owned == 0 and 0 or (d.unit and owned * d.unit or nil)
    if buy > 0 then
        local vendor = ns.VendorPrice(id)
        local cap = (vendor and ns.Get("vendorFirst")) and vendor or nil
        local book = PX.Book(id)
        if book then
            local start = state.used[id] or 0
            local cost, got, low, top = Walk(book.levels, start, buy, cap)
            state.used[id] = start + got
            d.ah, d.ahCost, d.low, d.top, d.age, d.partial = got, cost, low, top, book.age, book.partial
            local rest2 = buy - got
            if rest2 > 0 then
                if vendor then
                    d.vendor, d.vendorPrice = rest2, vendor
                else
                    local price, source = PX.Price(id, ns.BuySource())
                    d.short, d.shortPrice, d.shortSource = rest2, price, source
                    d.shortCost = price and price * rest2 or nil
                end
            end
        else
            local unit, kind = ns.UnitCost(id)
            if kind == "vendor" then
                d.vendor, d.vendorPrice = buy, unit
            elseif unit then
                d.ah, d.ahCost, d.low, d.top, d.estimate = buy, unit * buy, unit, unit, true
            else
                d.ah, d.ahCost = buy, nil -- (aucun prix connu : il se cherchera quand même à l'hôtel des ventes)
            end
        end
    end
    d.ahUnits = d.ah + d.short
    if d.ahCost and d.shortCost then d.ahPlanned = d.ahCost + d.shortCost end
    d.vendorCost = d.vendor > 0 and d.vendor * d.vendorPrice or 0
    d.spend = d.ahPlanned and (d.ahPlanned + d.vendorCost) or nil
    d.cost = (d.spend and d.own) and (d.spend + d.own) or nil
    return d
end

-- (toutes les recettes, par n° ; celles dont le jeu n'a pas encore un objet sont demandées au serveur)
local function RecipeMap()
    local map = {}
    for _, r in ipairs(ns.AllRecipes()) do map[r.id] = r end
    return map
end

-- Une recette de la wishlist : { key, entry, r (la recette ; nil : plus dans les données), crafts, reagents (ci-dessus),
-- complete (tous ses composants sont déjà là), spend, cost, value, valueKind, unsellable, profit, estimate, time }.
local function EntryPreview(e, r, state)
    local p = { key = e.key, entry = e, r = r, crafts = e.crafts, reagents = {} }
    if not r then return p end
    ns.RecipeReady(r) -- (un parchemin gravé que le serveur n'a pas : pas de revente)
    local spend, cost, own, complete = 0, 0, 0, true
    for i, reagent in ipairs(r.reagents) do
        local id = reagent[1]
        local need = reagent[2] * e.crafts
        local d = Reagent(id, need, math.min(e.have[id] or 0, need), state)
        p.reagents[i] = d
        if d.have < need then complete = false end
        spend = (spend and d.spend) and spend + d.spend or nil
        cost = (cost and d.cost) and cost + d.cost or nil
        own = (own and d.own) and own + d.own or nil
        p.estimate = p.estimate or d.estimate or d.short > 0 or nil
    end
    p.complete = complete
    p.spend, p.own = spend, own
    p.cost = #r.reagents > 0 and cost or nil
    ns.Price(r, e.crafts) -- (la revente pour ces fabrications ; son coût à lui ne sert pas ici)
    p.value, p.valueKind, p.unsellable, p.how = r.value, r.valueKind, r.unsellable, r.how
    p.profit = (p.cost and p.value) and (p.value - p.cost) or nil
    local t = ns.CraftTime(r.id)
    p.time = t and t * e.crafts or nil
    return p
end

-- L'aperçu de toute la wishlist : { entries = { (EntryPreview) }, byKey, totals = { recipes, spend, ahSpend,
-- vendorSpend, cost, value, profit, ahCount, vendorCount, bagCount, unknown, estimate, todo (recettes à acheter) } }.
function ns.WishlistPreview()
    local w = Store()
    local map = RecipeMap()
    -- (ce que les recettes de la liste ont déjà est à elles : pas pris par une autre)
    local reserved = {}
    for _, e in ipairs(w.entries) do
        local r = map[e.id]
        for _, reagent in ipairs(r and r.reagents or {}) do
            local id = reagent[1]
            reserved[id] = (reserved[id] or 0) + math.min(e.have[id] or 0, reagent[2] * e.crafts)
        end
    end
    local state = { used = {}, free = {} }
    function state.Free(id)
        if state.free[id] == nil then state.free[id] = math.max(0, ns.InBags(id) - (reserved[id] or 0)) end
        return state.free[id]
    end
    local out = { entries = {}, byKey = {} }
    local t = { recipes = #w.entries, spend = 0, ahSpend = 0, vendorSpend = 0, cost = 0, value = 0, profit = 0,
        ahCount = 0, vendorCount = 0, bagCount = 0, unknown = false, estimate = false, todo = 0 }
    for _, e in ipairs(w.entries) do
        local p = EntryPreview(e, map[e.id], state)
        out.entries[#out.entries + 1] = p
        out.byKey[e.key] = p
        if not p.r then
            t.unknown = true
        else
            if not p.complete then t.todo = t.todo + 1 end
            for _, d in ipairs(p.reagents) do
                if d.ahUnits > 0 then
                    t.ahCount = t.ahCount + 1
                    t.ahSpend = (t.ahSpend and d.ahPlanned) and t.ahSpend + d.ahPlanned or nil
                end
                if d.vendor > 0 then
                    t.vendorCount = t.vendorCount + 1
                    t.vendorSpend = t.vendorSpend + d.vendorCost
                end
                if d.bags > 0 then t.bagCount = t.bagCount + 1 end
            end
            t.spend = (t.spend and p.spend) and t.spend + p.spend or nil
            t.cost = (t.cost and (p.cost or #p.r.reagents == 0)) and t.cost + (p.cost or 0) or nil
            t.value = (t.value and p.value) and t.value + p.value or (p.r.out and nil or t.value)
            t.estimate = t.estimate or p.estimate or false
        end
    end
    t.profit = (t.cost and t.value) and (t.value - t.cost) or nil
    out.totals = t
    return out
end

-- Les achats confirmés ------------------------------------------------------------------------------------------------
-- Confirmer : le plan de l'aperçu est figé (ce qui est pris dans les sacs va aux recettes : entry.have) ; rend true, ou
-- false et pourquoi ; true et un message quand les sacs avaient tout.
function ns.WishlistConfirm()
    local w = Store()
    if w.plan then return false, "des achats sont déjà en cours." end
    if #w.entries == 0 then return false, "la wishlist est vide." end
    local preview = ns.WishlistPreview()
    local plan = { at = time(), recipes = {}, buys = {} }
    for _, p in ipairs(preview.entries) do
        if p.r and not p.complete then
            local e = p.entry
            plan.recipes[#plan.recipes + 1] = { key = e.key, id = e.id, crafts = e.crafts, name = p.r.name,
                value = p.value, own = p.own, cost = p.cost, profit = p.profit }
            for _, d in ipairs(p.reagents) do
                if d.bags > 0 then e.have[d.id] = (e.have[d.id] or 0) + d.bags end
                if d.ahUnits > 0 then
                    plan.buys[#plan.buys + 1] = { key = e.key, item = d.id, where = "ah", n = d.ahUnits,
                        planned = d.ahPlanned, estimate = (d.estimate or d.short > 0) or nil, got = 0, spent = 0,
                        missing = 0 }
                end
                if d.vendor > 0 then
                    plan.buys[#plan.buys + 1] = { key = e.key, item = d.id, where = "vendor", n = d.vendor,
                        unit = d.vendorPrice, planned = d.vendor * d.vendorPrice, got = 0, spent = 0, missing = 0 }
                end
            end
        end
    end
    if #plan.buys == 0 then
        ns.Changed("wishlist")
        return true, "rien à acheter : tes sacs ont déjà tous les composants."
    end
    w.plan, w.last = plan, nil
    ns.Changed("wishlist")
    return true
end

-- Arrêter : le reste n'est pas acheté (ce qui l'a été reste aux recettes : la prochaine confirmation ne le rachète pas).
function ns.WishlistStop()
    local w = Store()
    if not w.plan then return false end
    w.plan = nil
    ns.Changed("wishlist")
    return true
end

-- Ce qu'il reste à acheter d'un achat du plan.
function ns.BuyRemaining(b)
    if b.skipped then return 0 end
    return math.max(0, b.n - b.got - b.missing)
end

-- La recette d'un achat du plan, et sa place (« recette 2 sur 3 »).
function ns.PlanRecipe(key)
    local plan = Store().plan
    for i, rec in ipairs(plan and plan.recipes or {}) do
        if rec.key == key then return rec, i, #plan.recipes end
    end
end

-- Le prochain achat à faire à l'hôtel des ventes ("ah") ou chez un marchand ("vendor"), dans l'ordre de la liste.
function ns.NextBuy(where)
    local plan = Store().plan
    for _, b in ipairs(plan and plan.buys or {}) do
        if b.where == where and ns.BuyRemaining(b) > 0 then return b end
    end
end

-- Combien d'achats restent à faire là ("ah" ou "vendor").
function ns.BuysLeft(where)
    local plan, n = Store().plan, 0
    for _, b in ipairs(plan and plan.buys or {}) do
        if b.where == where and ns.BuyRemaining(b) > 0 then n = n + 1 end
    end
    return n
end

-- Les achats du plan pour une recette de la liste.
function ns.PlanBuys(key)
    local plan, out = Store().plan, {}
    for _, b in ipairs(plan and plan.buys or {}) do
        if b.key == key then out[#out + 1] = b end
    end
    return out
end

-- Le bénéfice attendu de la recette d'un achat : sa revente, moins ce qu'elle a déjà (au prix de la confirmation), ce
-- que ses achats ont coûté et le prévu de ceux qui restent ; avec n et cost, n unités de cet achat-ci à ce coût (un
-- nouveau prix). nil : inconnu (une revente ou un prix sans valeur).
function ns.WishlistProfit(b, n, cost)
    local plan = Store().plan
    local rec = plan and ns.PlanRecipe(b.key)
    if not (rec and rec.value and rec.own) then return nil end
    local total = rec.own
    for _, x in ipairs(plan.buys) do
        if x.key == b.key then
            total = total + x.spent
            local left = ns.BuyRemaining(x)
            if x == b and n then
                total = total + cost
                left = math.max(0, left - n)
            end
            if left > 0 then
                if not x.planned then return nil end
                total = total + x.planned * left / x.n
            end
        end
    end
    return rec.value - total
end

-- Le coût et le bénéfice attendus d'une recette du plan, d'après ses achats faits (ns.WishlistProfit).
function ns.PlanRecipeNow(rec)
    local buys = ns.PlanBuys(rec.key)
    if #buys == 0 then return rec.cost, rec.profit end
    local profit = ns.WishlistProfit(buys[1])
    return (profit and rec.value) and (rec.value - profit) or nil, profit
end

-- (tout est acheté, introuvable ou passé : le bilan, gardé et dit dans la discussion)
local function CheckDone(w)
    local plan = w.plan
    if not plan then return end
    for _, b in ipairs(plan.buys) do
        if ns.BuyRemaining(b) > 0 then return end
    end
    local spent, planned, missing, skipped = 0, 0, {}, {}
    for _, b in ipairs(plan.buys) do
        spent = spent + b.spent
        planned = planned + (b.planned and b.planned * math.min(b.got, b.n) / b.n or b.spent)
        if b.missing > 0 then missing[#missing + 1] = { item = b.item, n = b.missing } end
    end
    for _, rec in ipairs(plan.recipes) do
        if rec.skipped then skipped[#skipped + 1] = rec.name end
    end
    w.last = { at = time(), spent = spent, planned = planned, missing = missing, skipped = skipped }
    w.plan = nil
    local text = ("achats de la wishlist terminés : %s dépensés (prévu %s)."):format(ns.Money(spent), ns.Money(planned))
    if #missing > 0 then
        local parts = {}
        for _, m in ipairs(missing) do parts[#parts + 1] = ns.Units(m.item, m.n, true) end
        text = text .. " Introuvables à l'hôtel des ventes : " .. table.concat(parts, ", ") .. "."
    end
    if #skipped > 0 then text = text .. " Recettes passées : " .. table.concat(skipped, ", ") .. "." end
    ns.Say(text)
end

-- Des unités achetées pour un achat du plan (n, pour spent) : elles vont à sa recette.
function ns.WishlistBought(b, n, spent)
    local w = Store()
    if not w.plan or not n or n <= 0 then return end
    b.got = b.got + n
    b.spent = b.spent + (spent or 0)
    local e = EntryByKey(w, b.key)
    if e then e.have[b.item] = (e.have[b.item] or 0) + n end
    CheckDone(w)
    ns.Changed("wishlist")
end

-- Des unités introuvables (rien en vente à l'hôtel des ventes) : l'achat ne les cherche plus.
function ns.WishlistMissing(b, n)
    local w = Store()
    if not w.plan or not n or n <= 0 then return end
    b.missing = b.missing + n
    CheckDone(w)
    ns.Changed("wishlist")
end

-- « Recette suivante » : le reste de cette recette n'est pas acheté (ses autres composants non plus).
function ns.WishlistSkip(key)
    local w = Store()
    local rec = w.plan and ns.PlanRecipe(key)
    if not rec then return end
    rec.skipped = true
    for _, b in ipairs(w.plan.buys) do
        if b.key == key then b.skipped = true end
    end
    ns.Say(("recette passée : %s x %d (le reste de ses composants n'est pas acheté)."):format(rec.name, rec.crafts))
    CheckDone(w)
    ns.Changed("wishlist")
end
