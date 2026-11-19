-- Route.lua : « XP Road », la route de montée d'un métier, du niveau du personnage (ou de son niveau simulé) jusqu'à
-- 300 : quelles recettes fabriquer, combien de fois, de quel niveau à quel niveau, et tout ce qu'il faut acheter, aux
-- prix relevés. Deux routes : la plus rapide (le moins de temps de fabrication) ou la moins chère (le plus petit coût :
-- composants achetés, plus l'apprentissage des recettes, moins la revente au marchand de ce qui est fabriqué).
--
-- Ce que la route s'autorise (demandé par le propriétaire, 2026-11-15) :
-- - une recette apprise, apprise avec le métier, enseignée par un formateur (son prix compte), ou dont le parchemin
--   est vendu par un marchand (Data.lua recipeItems, ligne V) ou était en vente au dernier relevé de l'hôtel des ventes
--   (son prix compte) ; sinon (parchemin de butin, de quête...) elle n'est pas utilisée ;
-- - des composants toujours achetés : chez un marchand (sans limite) ou aux offres relevées de l'hôtel des ventes, les
--   moins chères d'abord, une à une (celles sous le prix du marchand quand il en vend). Un composant qu'aucun
--   marchand ne vend et qui n'est pas en vente au dernier relevé : la recette n'est pas utilisée. Quand la route a
--   acheté toutes les offres d'un composant sans marchand, la suite est recalculée sans lui ;
-- - tout ce qui est fabriqué est revendu au marchand (son prix de vente du jeu ; sans prix : 0), rien n'est gardé ;
-- - une recette écartée par un clic dans la route (ns.ExcludeFromRoute) n'est plus utilisée pour ce métier ;
-- - une recette à temps de recharge (Data.lua recharge : l'étoffe lunaire, 95 h ; les transmutations, 1 à 47 h ; le
--   feu de camp, 5 min) n'est pas utilisée : on ne peut pas l'enchaîner.
--
-- Points de compétence : ceux de ns.SkillUp (seuils de couleur des tables du jeu ; une recette sans seuils n'est pas
-- utilisée) ; au niveau s, une fabrication fait monter d'un point avec la chance c : il en faut 1 / c en moyenne. Le
-- nombre de fabrications d'une étape est cette moyenne, arrondie au-dessus.
--
-- Calcul : pour chaque niveau, de 299 au départ, le meilleur reste de route (programmation dynamique) ; une recette
-- utilisée de s à t coûte son apprentissage une fois, puis à chaque niveau (1 / c) x (composants - revente) et
-- (1 / c) x temps de fabrication. La plus rapide compare le temps, puis le coût ; la moins chère, le coût, puis le
-- temps. Le prix d'un composant est d'abord celui de sa première offre, puis le prix moyen de la quantité que la route
-- en achète (deux passes) ; la route est ensuite « achetée » étape par étape, offre par offre.
local _, ns = ...
local PX = ns.Prices

local TARGET = 300
ns.ROUTE_TARGET = TARGET
-- (les rangs : au-delà de 75, 150 et 225, il faut apprendre le rang suivant ; leur prix n'est pas dans les données)
local RANKS = { { 75, "Compagnon" }, { 150, "Expert" }, { 225, "Artisan" } }
local DEFAULT_CAST = 3 -- (temps de fabrication inconnu du jeu : compté 3 s, dit estimé)
local INF = math.huge

-- Recettes écartées de la route, par métier, pour tout le compte : ForeverCraftAtlasDB.routeExcluded[métier][recette] = true.
function ns.RouteExcluded(skillLine)
    local db = ForeverCraftAtlasDB and ForeverCraftAtlasDB.routeExcluded
    return db and db[skillLine] or {}
end

function ns.RouteExcludedCount(skillLine)
    local n = 0
    for _ in pairs(ns.RouteExcluded(skillLine)) do n = n + 1 end
    return n
end

function ns.ExcludeFromRoute(skillLine, recipeID)
    if not skillLine or skillLine == 0 or not recipeID then return end
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.routeExcluded = ForeverCraftAtlasDB.routeExcluded or {}
    ForeverCraftAtlasDB.routeExcluded[skillLine] = ForeverCraftAtlasDB.routeExcluded[skillLine] or {}
    ForeverCraftAtlasDB.routeExcluded[skillLine][recipeID] = true
    ns.Changed("route")
end

-- (toutes les recettes écartées de ce métier reviennent)
function ns.RestoreRoute(skillLine)
    if ForeverCraftAtlasDB and ForeverCraftAtlasDB.routeExcluded and ForeverCraftAtlasDB.routeExcluded[skillLine] then
        ForeverCraftAtlasDB.routeExcluded[skillLine] = nil
        ns.Changed("route")
    end
end

-- Apprendre une recette -------------------------------------------------------------------------------------------------
-- Le prix le plus bas chez un marchand qui vend ce parchemin (Data.lua recipeItems : "V\tpnj\tnom\tzone\tprix"), et sa ligne.
local function VendorScroll(scroll)
    local data = ns.DATA.recipeItems and ns.DATA.recipeItems[scroll]
    local best, line
    for i = 2, #(data or {}) do
        local kind, _, _, _, extra = strsplit("\t", data[i])
        local price = tonumber(extra)
        if kind == "V" and price and price > 0 and (not best or price < best) then best, line = price, data[i] end
    end
    return best, line
end

-- Comment la route apprend une recette : { cost, kind = "known" (apprise), "profession" (apprise avec le métier),
-- "trainer", "vendor" (parchemin chez un marchand : scroll, line) ou "ah" (parchemin au dernier relevé de l'hôtel des
-- ventes : scroll, live) }, la moins chère ; nil : elle ne s'apprend ni d'elle-même, ni chez un formateur, ni par un
-- parchemin qui s'achète.
function ns.LearnOption(r)
    if r.learned then return { cost = 0, kind = "known" } end
    if r.sources[10] then return { cost = 0, kind = "profession" } end
    local best
    local function Offer(o) if not best or o.cost < best.cost then best = o end end
    if r.sources[6] then Offer({ cost = r.trainingCost or 0, kind = "trainer" }) end
    for _, scroll in ipairs(r.scrolls) do
        local price, line = VendorScroll(scroll)
        if price then Offer({ cost = price, kind = "vendor", scroll = scroll, line = line }) end
        local live = PX.Live(scroll)
        if live then Offer({ cost = live.price, kind = "ah", scroll = scroll, live = live }) end
    end
    return best
end

-- « Apprise », « Formateur (1 pa 50) », « Parchemin : Ulthir, Darnassus (50 pc) », « Parchemin à l'HV (2 po) ».
function ns.LearnText(o)
    if not o then return "ne s'apprend pas" end
    if o.kind == "known" then return "Apprise" end
    if o.kind == "profession" then return "Apprise avec le métier" end
    if o.kind == "trainer" then
        return o.cost > 0 and ("Formateur (" .. ns.Money(o.cost) .. ")") or "Formateur"
    end
    if o.kind == "vendor" then
        return "Parchemin : " .. ns.SourceLine(o.line, true) .. " (" .. ns.Money(o.cost) .. ")"
    end
    return "Parchemin à l'HV (" .. ns.Money(o.cost) .. ")"
end

-- Acheter des composants --------------------------------------------------------------------------------------------
-- Ce qui est en vente d'un composant : ses offres relevées sous le prix du marchand (segs : { prix, quantité } du moins
-- cher), puis le marchand, sans limite ; nil : rien à acheter. Sans ses offres (seulement son prix le plus bas
-- relevé), toute la quantité relevée à ce prix (estimate).
local function NewSupply(itemID)
    local vendor = ns.VendorPrice(itemID)
    local segs, total, estimate = {}, 0, false
    local book = PX.Book(itemID)
    if book then
        local levels = book.levels
        for i = 1, #levels - 1, 2 do
            local p, q = levels[i], levels[i + 1]
            if vendor and p >= vendor then break end
            if q > 0 then
                segs[#segs + 1] = { p, q }
                total = total + q
            end
        end
    else
        local live = PX.Live(itemID)
        if live and not (vendor and live.price >= vendor) then
            local q = math.max(1, live.qty or 0)
            segs[1], total, estimate = { live.price, q }, q, true
        end
    end
    if not vendor and total == 0 then return nil end
    return { id = itemID, vendor = vendor, segs = segs, total = total, used = 0, estimate = estimate }
end

-- n unités après les start déjà achetées : (coût, unités trouvées, détail { ah, low, top, vendor, vendorPrice }).
local function Take(sup, start, n)
    local cost, got, skip, ah, low, top = 0, 0, start, 0, nil, nil
    for _, seg in ipairs(sup.segs) do
        if got >= n then break end
        local q = seg[2]
        if skip >= q then
            skip = skip - q
        else
            local take = math.min(q - skip, n - got)
            skip = 0
            cost, got, ah = cost + take * seg[1], got + take, ah + take
            low, top = low or seg[1], seg[1]
        end
    end
    local vendor = 0
    if got < n and sup.vendor then
        vendor = n - got
        cost, got = cost + vendor * sup.vendor, n
    end
    return cost, got, { ah = ah, low = low, top = top, vendor = vendor, vendorPrice = sup.vendor }
end

local function Remaining(sup)
    if sup.vendor then return INF end
    return sup.total - sup.used
end

-- Le prix d'un composant pour le calcul : la moyenne des q prochaines unités (1 : la prochaine offre) ; nil : il n'en
-- reste plus.
local function UnitPrice(sup, q)
    q = math.max(1, q or 1)
    local n = sup.vendor and q or math.min(q, sup.total - sup.used)
    if n <= 0 then return nil end
    return (Take(sup, sup.used, n)) / n
end

-- Le calcul ---------------------------------------------------------------------------------------------------------
-- (la chance d'un point au niveau s, comme ns.SkillUp : 0 sous le niveau requis et dès le gris, 1 sous le jaune)
local function Chance(c, s)
    if s < c.need or s >= c.gray then return 0 end
    if s < c.yellow then return 1 end
    return c.gray > c.yellow and (c.gray - s) / (c.gray - c.yellow) or 0
end

-- (fabrications pour un point au niveau s, en moyenne)
local function PerLevel(c, s)
    local chance = Chance(c, s)
    if chance <= 0 then return nil end
    return 1 / (chance * c.points)
end

-- (le critère : la plus rapide, le temps puis le coût ; la moins chère, le coût puis le temps)
local function Weight(mode, cost, seconds)
    if mode == "cheap" then return cost + seconds * 1e-6 end
    return seconds + cost * 1e-9
end

-- Les recettes du métier que la route peut utiliser, et pourquoi les autres ne le peuvent pas (info).
local function Candidates(skillLine, excluded)
    local list, supplies = {}, {}
    local info = { waiting = 0, excluded = 0, unlearnable = 0, unbuyable = 0, noColors = 0, recharge = 0 }
    local recharge = ns.DATA.recharge or {}
    for _, r in ipairs(ns.AllRecipes()) do
        if r.skillLine == skillLine then
            if excluded[r.id] then
                info.excluded = info.excluded + 1
            elseif not r.colors then
                info.noColors = info.noColors + 1
            elseif (recharge[r.id] or 0) > 0 then
                info.recharge = info.recharge + 1
            else
                local ready = ns.RecipeReady(r)
                local learn = ready and ns.LearnOption(r)
                if ready == nil then
                    info.waiting = info.waiting + 1
                elseif ready and not learn then
                    info.unlearnable = info.unlearnable + 1
                elseif ready then
                    local ok = true
                    for _, reagent in ipairs(r.reagents) do
                        local id = reagent[1]
                        if supplies[id] == nil then supplies[id] = NewSupply(id) or false end
                        if not supplies[id] then ok = false end
                    end
                    if not ok then
                        info.unbuyable = info.unbuyable + 1
                    else
                        local col = r.colors
                        local cast = ns.CraftTime(r.id)
                        local sell = r.out and ns.SellPrice(r.out) or nil
                        list[#list + 1] = {
                            r = r, learn = learn, points = r.ups or 1,
                            need = (r.learnedAt and r.learnedAt < 9999) and r.learnedAt or col[1],
                            yellow = col[2], gray = col[4],
                            cast = cast or DEFAULT_CAST, castKnown = cast ~= nil,
                            sellEach = sell and sell * (r.qmin + r.qmax) / 2 or 0,
                            unsellable = (r.out and not sell) or nil,
                        }
                    end
                end
            end
        end
    end
    return list, supplies, info
end

-- La meilleure route de from vers 300 aux prix du moment (quantities : combien de chaque composant la route achète, pour
-- son prix moyen ; nil : sa prochaine offre) : { { c, from, to } }, et le niveau où elle s'arrête (300, ou le premier
-- niveau où aucune recette ne fait monter le métier).
local function Plan(from, cands, supplies, learned, exhausted, mode, quantities)
    local usable = {}
    for _, c in ipairs(cands) do
        local unit, ok = 0, true
        for _, reagent in ipairs(c.r.reagents) do
            local price = not exhausted[reagent[1]] and UnitPrice(supplies[reagent[1]], quantities and quantities[reagent[1]])
            if not price then ok = false break end
            unit = unit + price * reagent[2]
        end
        if ok then
            c.net = unit - c.sellEach
            c.lo, c.hi = math.max(from, c.need), math.min(TARGET, c.gray)
            if c.lo < c.hi then usable[#usable + 1] = c end
        end
    end
    local covered = {}
    for _, c in ipairs(usable) do for s = c.lo, c.hi - 1 do covered[s] = true end end
    local stop = from
    while stop < TARGET and covered[stop] do stop = stop + 1 end
    if stop == from then return {}, stop end
    -- (P : le poids cumulé de la recette depuis son premier niveau utilisable ; M : le meilleur P(t) + f(t) pour une
    -- fin t après s, tenu à jour en descendant)
    for _, c in ipairs(usable) do
        c.top = math.min(c.hi, stop)
        c.P, c.M, c.Mt = { [c.lo] = 0 }, INF, nil
        for s = c.lo, c.top - 1 do
            local e = PerLevel(c, s)
            c.P[s + 1] = c.P[s] + Weight(mode, e * c.net, e * c.cast)
        end
    end
    local f, choice = { [stop] = 0 }, {}
    for s = stop - 1, from, -1 do
        local best, pick, to = INF, nil, nil
        for _, c in ipairs(usable) do
            if s >= c.lo and s < c.top then
                local t = s + 1
                local v = c.P[t] + f[t]
                if v < c.M then c.M, c.Mt = v, t end
                local learn = learned[c.r.id] and 0 or c.learn.cost
                local value = Weight(mode, learn, 0) + c.M - c.P[s]
                if value < best then best, pick, to = value, c, c.Mt end
            end
        end
        f[s], choice[s] = best, { pick, to }
    end
    local runs, s = {}, from
    while s < stop do
        local ch = choice[s]
        local last = runs[#runs]
        if last and last.c == ch[1] then last.to = ch[2] else runs[#runs + 1] = { c = ch[1], from = s, to = ch[2] } end
        s = ch[2]
    end
    return runs, stop
end

-- (combien de chaque composant une route achète, en moyenne)
local function Quantities(runs)
    local q = {}
    for _, run in ipairs(runs) do
        local crafts = 0
        for s = run.from, run.to - 1 do crafts = crafts + PerLevel(run.c, s) end
        for _, reagent in ipairs(run.c.r.reagents) do q[reagent[1]] = (q[reagent[1]] or 0) + crafts * reagent[2] end
    end
    return q
end

-- (les étapes coupées aux rangs : une étape ne passe pas 75, 150 ni 225)
local function SplitAtRanks(runs)
    local out = {}
    for _, run in ipairs(runs) do
        local s = run.from
        for _, rank in ipairs(RANKS) do
            if rank[1] > s and rank[1] < run.to then
                out[#out + 1] = { c = run.c, from = s, to = rank[1] }
                s = rank[1]
            end
        end
        out[#out + 1] = { c = run.c, from = s, to = run.to }
    end
    return out
end

-- Acheter la route, étape par étape (state : steps, learned, supplies) : le niveau atteint, et true quand un composant
-- sans marchand n'a plus assez d'offres (state.exhausted : la suite est à recalculer sans lui).
local function Commit(runs, state)
    for _, run in ipairs(SplitAtRanks(runs)) do
        local c, r = run.c, run.c.r
        local expected, sums = 0, {}
        for s = run.from, run.to - 1 do
            expected = expected + PerLevel(c, s)
            sums[s + 1] = expected
        end
        local crafts = math.ceil(expected - 1e-9)
        local affordable, short = crafts, {}
        for _, reagent in ipairs(r.reagents) do
            local left = Remaining(state.supplies[reagent[1]])
            if left < crafts * reagent[2] then
                short[#short + 1] = reagent[1]
                affordable = math.min(affordable, math.floor(left / reagent[2] + 1e-9))
            end
        end
        local to = run.to
        if #short > 0 then -- (pas assez en vente : l'étape s'arrête au dernier niveau qu'on peut payer)
            to = run.from
            for s = run.from + 1, run.to do
                if math.ceil(sums[s] - 1e-9) <= affordable then to = s end
            end
            crafts = to > run.from and math.ceil(sums[to] - 1e-9) or 0
            expected = to > run.from and sums[to] or 0
        end
        if to > run.from then
            local step = { kind = "step", r = r, c = c, from = run.from, to = to, crafts = crafts, expected = expected,
                time = crafts * c.cast, castKnown = c.castKnown, resale = crafts * c.sellEach, unsellable = c.unsellable,
                buy = 0, reagents = {}, chanceFrom = Chance(c, run.from), chanceTo = Chance(c, to - 1) }
            if not state.learned[r.id] then
                state.learned[r.id] = true
                step.learn, step.learnCost = c.learn, c.learn.cost
            else
                step.learnCost = 0
            end
            for i, reagent in ipairs(r.reagents) do
                local sup = state.supplies[reagent[1]]
                local n = crafts * reagent[2]
                local cost, _, d = Take(sup, sup.used, n)
                sup.used = sup.used + n
                d.n, d.cost, d.id, d.estimate = n, cost, reagent[1], sup.estimate
                step.reagents[i] = d
                step.buy = step.buy + cost
            end
            step.net = step.buy + step.learnCost - step.resale
            state.steps[#state.steps + 1] = step
        end
        if #short > 0 then
            for _, id in ipairs(short) do state.exhausted[id] = true end
            return to, true
        end
    end
    return runs[#runs] and runs[#runs].to or nil, false
end

-- La route d'un métier : {
--   skillLine, mode ("fast" ou "cheap"), from (départ : niveau simulé, sinon celui du personnage, sinon 1), target (300),
--   reached (le niveau où elle s'arrête), done (déjà à 300), rows (dans l'ordre : { kind = "start" | "step" | "rank" |
--   "gap" }), steps (les étapes : r, from, to, crafts, expected, time, buy, learn, learnCost, resale, net, reagents =
--   { { id, n, cost, ah, low, top, vendor, vendorPrice, estimate } }, chanceFrom, chanceTo), shopping (ce qu'il faut
--   acheter, dans l'ordre de la route : { id, n, cost, ah, low, top, vendor, vendorPrice, estimate } ou un parchemin :
--   { id, n = 1, cost, learn, r }), totals { crafts, time, buy, learn, resale, net }, info (recettes pas utilisables :
--   waiting, excluded, unlearnable, unbuyable, noColors, recharge), estimate (un temps ou des offres estimés) }.
function ns.Route(skillLine, mode, start)
    mode = mode == "cheap" and "cheap" or "fast"
    local mine = ns.MyProfessions()[skillLine]
    local from = math.max(1, math.floor(tonumber(start) or ns.SkillLevel(skillLine) or 1))
    local route = { skillLine = skillLine, mode = mode, from = from, target = TARGET, reached = from, rows = {}, steps = {},
        shopping = {}, totals = { crafts = 0, time = 0, buy = 0, learn = 0, resale = 0, net = 0 } }
    if from >= TARGET then
        route.done = true
        return route
    end
    local cands, supplies, info = Candidates(skillLine, ns.RouteExcluded(skillLine))
    route.info = info
    local state = { steps = route.steps, learned = {}, supplies = supplies, exhausted = {} }
    local level = from
    for _ = 1, 500 do -- (chaque nouveau calcul retire un composant : la boucle finit)
        local runs = Plan(level, cands, supplies, state.learned, state.exhausted, mode)
        if #runs == 0 then break end
        for _ = 1, 2 do
            runs = Plan(level, cands, supplies, state.learned, state.exhausted, mode, Quantities(runs))
        end
        if #runs == 0 then break end
        local reached, ranOut = Commit(runs, state)
        level = reached or level
        if not ranOut or level >= TARGET then break end
    end
    route.reached = level
    -- Totaux, liste d'achats, lignes
    local t, byItem = route.totals, {}
    if not mine then route.rows[#route.rows + 1] = { kind = "start" } end
    local nextRank = 1
    local function Ranks(upTo)
        while RANKS[nextRank] and RANKS[nextRank][1] <= upTo do
            local rank = RANKS[nextRank]
            if rank[1] > from and rank[1] >= ((mine and mine.max) or 0) and rank[1] < TARGET then
                route.rows[#route.rows + 1] = { kind = "rank", level = rank[1], name = rank[2] }
            end
            nextRank = nextRank + 1
        end
    end
    for _, step in ipairs(route.steps) do
        Ranks(step.from)
        route.rows[#route.rows + 1] = step
        t.crafts, t.time = t.crafts + step.crafts, t.time + step.time
        t.buy, t.learn, t.resale = t.buy + step.buy, t.learn + step.learnCost, t.resale + step.resale
        route.estimate = route.estimate or not step.castKnown or nil
        if step.learn and step.learn.scroll then
            route.shopping[#route.shopping + 1] = { id = step.learn.scroll, n = 1, cost = step.learn.cost,
                learn = step.learn, r = step.r }
        end
        for _, d in ipairs(step.reagents) do
            local e = byItem[d.id]
            if not e then
                e = { id = d.id, n = 0, cost = 0, ah = 0, vendor = 0, vendorPrice = d.vendorPrice }
                byItem[d.id] = e
                route.shopping[#route.shopping + 1] = e
            end
            e.n, e.cost, e.ah, e.vendor = e.n + d.n, e.cost + d.cost, e.ah + d.ah, e.vendor + d.vendor
            if d.low and (not e.low or d.low < e.low) then e.low = d.low end
            if d.top and (not e.top or d.top > e.top) then e.top = d.top end
            e.estimate = e.estimate or d.estimate or nil
            route.estimate = route.estimate or d.estimate or nil
        end
    end
    Ranks(level - 1)
    t.net = t.buy + t.learn - t.resale
    if level < TARGET then route.rows[#route.rows + 1] = { kind = "gap", level = level, info = info } end
    return route
end
