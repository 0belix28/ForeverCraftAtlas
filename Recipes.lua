-- Recipes.lua : chaque recette, d'après les données (Data.lua : tous les métiers) et la lecture du jeu (Scan.lua : les
-- métiers du personnage, plus sûre pour ce qui le concerne : apprise ou non, difficulté), avec son coût, ce que
-- rapporte sa revente, son bénéfice et les points de compétence qu'elle donne au niveau du personnage.
--
-- Prix (Libs\Prices.lua) : ceux du dernier relevé de l'hôtel des ventes, fait en jeu (« Scanner l'HDV », l'analyse
-- de ForeverExchange suivie au passage, ou ce que tu y parcours ; quel que soit son âge, dit à côté), et, à défaut,
-- ceux de ForeverExchange (lus dans ses données). Un composant se compte à ses offres de l'hôtel des ventes (le plus
-- bas d'abord ; sans relevé, le réglage « Achat sans relevé », par défaut la moyenne sur 7 jours de ForeverExchange)
-- ou, si un marchand le vend moins cher, à son prix chez lui (les marchands de Forever d'après ses tables, Data.lua
-- buy) ; l'objet créé (ns.AuctionPrice) : son prix le plus bas au dernier relevé de l'hôtel des ventes, sinon le prix
-- minimum que ForeverExchange a vu en dernier ; x la quantité moyenne créée, moins les 5 % de commission.
-- Sans prix à l'hôtel des ventes, la revente est son prix de vente à un marchand (ce que le jeu en dit ; sans la fiche de l'objet, Data.lua sell), sans commission. Case
-- « Revente au marchand » : toujours ce prix-là (bénéfice d'une revente aux PNJ) ; un objet que le marchand n'achète
-- pas (sans prix de vente) compte une revente de 0 : tout son coût en perte.
-- Plusieurs fabrications (case « Fabrications » de la fenêtre, X) : le coût est celui des X x quantité de chaque
-- composant, achetés tout de suite aux offres les moins chères de l'hôtel des ventes, une à une (toutes ses offres :
-- relevées par « Scanner l'HDV », ou quand tu ouvres le composant), celles sous le prix du marchand quand il en vend ; ce
-- qu'il n'y a pas en vente se compte chez le marchand, sinon au prix de ForeverExchange (« il en manque »). Sans ses offres
-- (pas encore relevées, ou seulement son prix le plus bas), toutes au même prix, et le coût est dit estimé (« ~ »). Une seule
-- fabrication aussi : 3 composants, ce sont les 3 moins chers, pas 3 fois le moins cher. La revente, le bénéfice et
-- le temps de fabrication (ns.CraftsTime) sont ceux des X ; le bénéfice par seconde, celui d'une fabrication en moyenne.
-- Un enchantement ne crée pas d'objet : gravé sur un parchemin (« Enchantement de brassards (Endurance mineure) »), il
-- se vend à l'hôtel des ventes ; ce parchemin (Data.lua engraved) est l'objet revendu, un par fabrication. Le marchand
-- n'en donne rien (pas de prix de vente) : avec « Revente au marchand », une revente de 0.
--
-- « Le mieux pour l'xp » : la chance de gagner un point d'abord (chance x points, au pour cent affiché ; sans seuils,
-- la couleur du jeu donne une chance estimée : jaune 75 %, vert 25 %) ; à chance égale, le temps de fabrication, la
-- plus rapide d'abord (il compte plus que le bénéfice) ; à temps égal, le bénéfice, le plus haut d'abord (une perte :
-- la plus petite ; ns.XpRank) ; à la fin, celles qui ne donnent rien (grises, niveau trop bas, métier que le
-- personnage n'a pas).
--
-- Recettes cachées (ns.RecipeReady) : celles dont le jeu n'a pas encore la fiche d'un objet qu'elles montrent (l'objet
-- créé, un composant, le parchemin qui l'apprend), le temps qu'il la demande au serveur, et pour de bon celles dont le
-- serveur n'a pas l'objet : les tables du client de Forever ont des recettes de la Saison de la découverte, de Burning
-- Crusade et d'objets retirés, dont l'infobulle resterait sur « Récupération des informations de l'objet ».
-- Cachées aussi, celles dont un composant ne s'achète pas (ns.RecipeBuyable) : un composant s'achète chez un marchand
-- qui le vend, ou à l'hôtel des ventes s'il y était en vente à son dernier relevé complet (ou y a été vu en vente
-- depuis) ; absent de ce relevé et sans marchand (lié quand ramassé, objet de quête, ou que personne n'y vend en ce
-- moment), il ne s'achète pas, et la recette revient au premier relevé où il est en vente. Sans relevé complet de
-- l'hôtel des ventes depuis 14 jours, on ne sait pas : rien n'est caché.
--
-- Tri « Bénéfice » : le bénéfice en % du coût (ce que rapporte chaque pièce d'or investie) ; sans coût ou revente
-- connus, après les autres ; les pertes en bas.
--
-- Type d'objet (ns.Kind, menu « Type d'objet » de la fenêtre) : celui de l'objet créé, d'après le jeu (son genre et son
-- sous-genre, noms du jeu) : l'équipement par emplacement (torse, taille...), les armes par genre (épée, arc...), les
-- consommables par recharge commune (ceux qui la partagent : les potions, 2 min ; les explosifs et grenades, 1 min ;
-- les élixirs et flacons, 3 s ; d'après les tables du jeu, Data.lua cooldown), les autres par sous-genre (bandage,
-- nourriture et boissons...) ; les enchantements par ce qu'ils enchantent (l'emplacement, ou l'arme, à une ou à deux
-- mains : Data.lua enchants, d'après les tables du jeu) ; le reste par genre et sous-genre du jeu (artisanat, conteneur...).
--
-- Points de compétence (seuils de couleur des tables du jeu) : sous le seuil jaune, la recette est orange et
-- donne toujours ses points ; entre jaune et gris, la chance est (gris - niveau) / (gris - jaune) ; grise : rien.
-- « Niveau simulé » (ns.SkillLevel) : ces points, la couleur et le tri « Le mieux pour l'xp » à un niveau choisi du
-- métier plutôt qu'au vrai, pour préparer sa montée.
-- Sans seuils (recette vue seulement dans le jeu), la couleur du jeu.
local _, ns = ...

ns.SOURCES = { [1] = "Fabriqué", [2] = "Butin", [3] = "JcJ", [4] = "Quête", [5] = "Marchand", [6] = "Formateur",
    [7] = "Découverte", [8] = "Échange", [10] = "Apprise avec le métier", [12] = "Haut fait", [16] = "Pêche",
    [21] = "Vol à la tire" }
ns.DIFFICULTY = { orange = "ffff8040", yellow = "ffffff00", green = "ff40c040", gray = "ff808080", red = "ffff2020" }

-- Prix --------------------------------------------------------------------------------------------------------------
local PX = ns.Prices

-- (ForeverExchange : facultatif, ses données lues telles quelles ; ns.HasTSM, ancien nom)
function ns.HasExchange() return PX.Ready() end
ns.HasTSM = ns.HasExchange
-- (les analyses de ForeverExchange font suivre la fenêtre, comme nos relevés : Prices.OnLive)
PX.FollowExchange()
function ns.BuySource() return PX.Source(ns.Get("buySource"), PX.DEFAULT) end
-- (pas de ventes par jour connues sur WoW Forever : plus de seuil de ventes)
function ns.MinSold() return 0 end
function ns.MinSaleRate() return 0 end

-- « Revente au marchand » : la case.
function ns.VendorResale() return ns.Get("vendorResale") and true or false end

-- Ce que rapporte l'objet créé à l'hôtel des ventes, un seul prix pour le bénéfice : l'offre la moins chère. D'abord
-- le dernier relevé de ForeverCraftAtlas (Prices.Live : « Scanner l'HDV », l'analyse de ForeverExchange suivie au
-- passage, ce que tu y parcours), sinon le prix minimum que ForeverExchange a vu en dernier (même si l'objet n'y est
-- plus en vente : how.gone). Un prix aberrant (une annonce seule à plus de Prices.ODD fois ses moyennes chez
-- ForeverExchange : how.liveOdd) est écarté. Rend (prix ou nil, how ; how.none sans prix relevé).
function ns.AuctionPrice(itemID)
    local how = { item = itemID, lowest = true, gone = PX.Gone(itemID) or nil }
    local ref = PX.Reference(itemID)
    local function Odd(price) return ref and price > PX.ODD * ref end
    local price
    local live = PX.Live(itemID)
    if live then
        if Odd(live.price) then how.liveOdd = live.price
        else price, how.source, how.live = live.price, PX.LIVE, live end
    end
    if not price then
        local e = PX.Exchange(itemID)
        if e and not Odd(e.price) then price, how.source, how.exchange = e.price, PX.EXCHANGE, e
        elseif e then how.liveOdd = how.liveOdd or e.price end
    end
    if not price then
        how.none = true
        return nil, how
    end
    how.wanted = how.source
    return price, how
end

-- Ce que coûte un composant à l'hôtel des ventes : (prix, source prise : Prices.LIVE pour son dernier relevé) ou nil.
function ns.BuyPrice(itemID)
    return PX.Buy(itemID, ns.BuySource(), true)
end

-- Le prix d'un composant chez un marchand : celui des tables du jeu Forever pour ce qu'un marchand y vend (Data.lua buy,
-- à l'unité) ; nil sinon.
function ns.VendorPrice(itemID)
    local v = ns.DATA.buy and ns.DATA.buy[itemID]
    if v and v > 0 then return v end
    return PX.VendorBuy(itemID)
end

-- Prix de vente d'un objet à un marchand (cuivre), ou nil. Ce que le jeu en dit d'abord (le prix du serveur : Forever
-- en a corrigé, la grenade en fer se vend 1 pa 25 pc, 5 pa dans les tables du jeu) ; 0 : le marchand ne l'achète pas.
-- Sans la fiche de l'objet, les tables du jeu (Data.lua sell).
function ns.SellPrice(itemID)
    if C_Item and C_Item.GetItemInfo then
        local sell = select(11, C_Item.GetItemInfo(itemID))
        if type(sell) == "number" then return sell > 0 and sell or nil end
    end
    local v = ns.DATA.sell and ns.DATA.sell[itemID]
    if v and v > 0 then return v end
    return nil
end

-- Prix d'achat d'un composant : (prix, "vendor" ou "ah", et pour "ah" la source prise et le prix du marchand
-- plus cher) ou nil. Case « Prix des marchands » : le moins cher du marchand et de l'hôtel des ventes (sur Forever, des
-- marchands vendent la poussière étrange 8 pa, 87 pc aux enchères) ; décochée : l'hôtel des ventes, le marchand faute
-- de mieux.
function ns.UnitCost(itemID)
    local vendor = ns.VendorPrice(itemID)
    local ah, source = ns.BuyPrice(itemID)
    if vendor and ns.Get("vendorFirst") and not (ah and ah < vendor) then return vendor, "vendor" end
    if ah then return ah, "ah", source, vendor end
    if vendor then return vendor, "vendor" end
    return nil
end

-- Combien de fois fabriquer chaque recette (case « Fabrications » de la fenêtre) : 1 à 9999.
function ns.Crafts()
    return math.max(1, math.min(9999, math.floor(tonumber(ns.Get("crafts")) or 1)))
end

-- Les composants de toutes les recettes (données et métiers lus) : de ceux-là, ForeverCraftAtlas garde toutes les offres de
-- l'hôtel des ventes (Libs\Prices.lua), pour ce que coûtent plusieurs.
local reagentSet, reagentData
function ns.IsReagent(itemID)
    if not reagentSet or reagentData ~= ns.DATA then
        reagentSet, reagentData = {}, ns.DATA
        local function Add(text)
            for id in tostring(text or ""):gmatch("(%d+):%d+") do reagentSet[tonumber(id)] = true end
        end
        for _, d in pairs(ns.DATA.recipes or {}) do Add(d[5]) end
        for _, perChar in pairs(ForeverCraftAtlasDB and ForeverCraftAtlasDB.scans or {}) do
            for _, scan in pairs(type(perChar) == "table" and perChar or {}) do
                for _, s in pairs(type(scan) == "table" and scan.recipes or {}) do Add(s.reagents) end
            end
        end
    end
    return reagentSet[tonumber(itemID)] or false
end
ns.OnChange(function(key) if key == "scan" then reagentSet = nil end end) -- (un métier lu : ses composants aussi)

-- Ce que coûtent n unités d'un composant achetées tout de suite : (coût, détail), ou nil (pas de prix ; le détail
-- quand il en manque sans prix pour le reste). Avec ses offres de l'hôtel des ventes (Libs\Prices.lua), les moins
-- chères une à une, celles sous le prix du marchand quand il en vend et que la case « Prix des marchands » est
-- cochée ; le reste chez le marchand, sinon au prix de ForeverExchange (pas assez en vente). Sans ses offres, toutes à un même
-- prix (ns.UnitCost : le plus bas du moment, celui de ForeverExchange, ou celui du marchand).
-- Détail : n ; ah = unités prises aux offres, low et top = le prix à l'unité de la moins chère et de la plus chère
-- prises, qty = combien en vente en tout, age, partial (des offres pas chargées), none (rien en vente) ; vendor =
-- unités chez le marchand, vendorPrice ; short = unités qui manquent, shortPrice et shortSource = leur prix (ForeverExchange) ;
-- sans offres : unit, kind et source (ceux de ns.UnitCost), estimate = un prix de l'hôtel des ventes pour toutes.
function ns.ReagentCost(itemID, n)
    local vendor = ns.VendorPrice(itemID)
    local fill = PX.Fill(itemID, n, (vendor and ns.Get("vendorFirst")) and vendor or nil)
    if fill then
        local d = { n = n, ah = fill.got, low = fill.low, top = fill.top, qty = fill.qty, age = fill.age,
            partial = fill.partial, none = fill.none }
        local cost, rest = fill.cost, n - fill.got
        if rest > 0 then
            if vendor then
                d.vendor, d.vendorPrice = rest, vendor
                cost = cost + vendor * rest
            else
                local price, source = PX.Price(itemID, ns.BuySource())
                if not price then return nil, d end
                d.short, d.shortPrice, d.shortSource = rest, price, source
                cost = cost + price * rest
            end
        end
        d.cost = cost
        return cost, d
    end
    local unit, kind, source = ns.UnitCost(itemID)
    if not unit then return nil end
    -- (un seul au prix le plus bas relevé : exact ; plusieurs, ou au prix de ForeverExchange : estimé)
    local estimate = kind == "ah" and not (n <= 1 and source == PX.LIVE)
    return unit * n, { n = n, cost = unit * n, unit = unit, kind = kind, source = source, estimate = estimate }
end

-- Un composant s'achète-t-il ? true : un marchand le vend, ou il est en vente à l'hôtel des ventes (à son dernier
-- relevé, ou vu en vente depuis) ; false : aucun marchand ne le vend, et il n'était pas en vente au dernier relevé
-- complet de l'hôtel des ventes (ni vu en vente depuis) ; nil : on ne sait pas (pas de relevé complet depuis
-- Prices.LIVE_KEEP).
function ns.Buyable(itemID)
    if ns.VendorPrice(itemID) or PX.Live(itemID) then return true end
    if PX.Gone(itemID) then return false end
    return nil
end

-- Une recette dont un composant ne s'achète pas (ns.Buyable : false) n'est pas montrée.
function ns.RecipeBuyable(r)
    for _, reagent in ipairs(r.reagents) do
        if ns.Buyable(reagent[1]) == false then return false end
    end
    return true
end

-- Type d'objet ---------------------------------------------------------------------------------------------------------
-- Le menu : ces genres d'abord, dans cet ordre (les autres ensuite, par nom ; « Sans objet créé » à la fin) ; les
-- emplacements dans l'ordre de la fiche du personnage.
local KIND_ORDER = { equip = 1, weapon = 2, consumable = 3, enchant = 4, none = 99 }
local KIND_NAMES = { equip = "Équipement", weapon = "Armes", consumable = "Consommables", enchant = "Enchantements",
    none = "Sans objet créé" }
local SLOTS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
    "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
    "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RELIC" }
local SLOT_ORDER = {}
for i, slot in ipairs(SLOTS) do SLOT_ORDER[slot] = i end
-- (le même emplacement sous deux noms : la robe est un torse)
local SAME_SLOT = { INVTYPE_ROBE = "INVTYPE_CHEST" }
-- (sans le nom du jeu, GlobalStrings)
local SLOT_NAMES = { INVTYPE_HEAD = "Tête", INVTYPE_NECK = "Cou", INVTYPE_SHOULDER = "Épaules", INVTYPE_CLOAK = "Dos",
    INVTYPE_CHEST = "Torse", INVTYPE_BODY = "Chemise", INVTYPE_TABARD = "Tabard", INVTYPE_WRIST = "Poignets",
    INVTYPE_HAND = "Mains", INVTYPE_WAIST = "Taille", INVTYPE_LEGS = "Jambes", INVTYPE_FEET = "Pieds",
    INVTYPE_FINGER = "Doigt", INVTYPE_TRINKET = "Bijou", INVTYPE_HOLDABLE = "Tenu en main gauche",
    INVTYPE_RELIC = "Relique", INVTYPE_BAG = "Sac", INVTYPE_QUIVER = "Carquois" }
-- (nos noms, avant ceux du jeu : le jeu dit « Main gauche » pour le bouclier)
local OWN_SLOT_NAMES = { INVTYPE_SHIELD = "Bouclier" }

local function ItemInstant(id)
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not get then return nil end
    local ok, _, className, subName, equipLoc, _, classID, subclassID = pcall(get, id)
    if not ok or not classID then return nil end
    return classID, subclassID, className, subName, equipLoc
end

local function SlotName(slot)
    if OWN_SLOT_NAMES[slot] then return OWN_SLOT_NAMES[slot] end
    local name = _G[slot]
    return type(name) == "string" and name ~= "" and name or SLOT_NAMES[slot] or slot
end

-- (une recharge commune : « Potions · 2 min », « Feux d'artifice · 1,5 à 2 s » ; sans nom dans les données, le
-- sous-genre de l'objet)
local function CooldownName(category, fallback)
    local g = ns.DATA.cooldownGroups and ns.DATA.cooldownGroups[category]
    if not g then return fallback end
    local name = (g[1] or "") ~= "" and g[1] or fallback or ("Recharge " .. category)
    local low, high = ns.TimeText((g[2] or 0) / 1000), ns.TimeText((g[3] or g[2] or 0) / 1000)
    if low == high then return name .. " · " .. low end
    return ("%s · %s à %s"):format(name, (low:gsub(" s$", "")), high)
end

-- (ce qu'enchante un enchantement : l'emplacement, sous le nom du jeu ; une arme)
local ENCHANT_NAMES = { INVTYPE_WEAPON = "Arme", INVTYPE_2HWEAPON = "Arme à deux mains" }
local ENCHANT_ORDER = { INVTYPE_WEAPON = 40, INVTYPE_2HWEAPON = 41 }

-- Le type d'une recette : { kind, kindName, sub, subName, order (des sous-types), key = "kind/sub" } ; gardé.
local kinds, kindNames = {}, {}   -- (kindNames : le nom de chaque type vu, pour le bouton du menu)
function ns.Kind(r)
    local cacheKey = r.id .. ":" .. (r.out or 0) .. (r.engraved and "e" or "")
    local k = kinds[cacheKey]
    if k then return k end
    local kind, kindName, sub, subName, order
    if r.engraved or (not r.out and r.skillLine == 333) then
        kind = "enchant"
        local slot = ns.DATA.enchants and ns.DATA.enchants[r.id]
        if slot then
            sub, subName = slot, ENCHANT_NAMES[slot] or SlotName(slot)
            order = ENCHANT_ORDER[slot] or SLOT_ORDER[slot] or 50
        else
            sub, subName, order = "other", "Autres", 99
        end
    elseif not r.out then
        kind, sub, subName, order = "none", "none", "Sans objet créé", 1
    else
        local classID, subclassID, className, itemSub, equipLoc = ItemInstant(r.out)
        local category = ns.DATA.cooldown and ns.DATA.cooldown[r.out]
        local equippable = (classID == 2 or classID == 4) and equipLoc and equipLoc ~= ""
            and equipLoc ~= "INVTYPE_NON_EQUIP" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        if not classID then
            kind, kindName, sub, subName, order = "class:?", "Autres", "?", "Autres", 1
        elseif classID == 2 and equippable then
            kind, sub, subName, order = "weapon", "w" .. (subclassID or 0), itemSub or ("Arme " .. (subclassID or 0)), 1
        elseif classID == 4 and equippable then
            local slot = SAME_SLOT[equipLoc] or equipLoc
            kind, sub, subName, order = "equip", slot, SlotName(slot), SLOT_ORDER[slot] or 50
        elseif classID == 0 or category then
            kind = "consumable"
            if category and ns.DATA.cooldownGroups and ns.DATA.cooldownGroups[category] then
                -- (recharge commune d'abord dans le menu)
                sub, subName, order = "cd" .. category, CooldownName(category, itemSub), 1
            else
                sub, subName, order = "s" .. (classID or 0) .. ":" .. (subclassID or 0), itemSub or "Autres", 2
            end
        else
            kind, kindName = "class:" .. classID, className or ("Genre " .. classID)
            sub, subName, order = "s" .. (subclassID or 0), itemSub or kindName, 1
        end
    end
    k = { kind = kind, kindName = kindName or KIND_NAMES[kind], sub = sub, subName = subName, order = order or 1,
        kindOrder = KIND_ORDER[kind] or 50 }
    k.key = kind .. "/" .. sub
    kinds[cacheKey] = k
    kindNames[k.key], kindNames[kind] = k.subName, k.kindName
    return k
end

-- Le filtre « Type d'objet » : "" (tous), un genre ("equip") ou un genre et un sous-type ("equip/INVTYPE_CHEST").
function ns.KindMatches(k, filter)
    if not filter or filter == "" then return true end
    if filter == k.kind then return true end
    return filter == k.key
end

-- (les noms dans l'ordre alphabétique, sans tenir compte des accents ni des majuscules : « Élixirs » avant « Potions »)
local FOLD = { ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["œ"] = "oe",
    ["À"] = "a", ["Â"] = "a", ["Ç"] = "c", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Î"] = "i", ["Ô"] = "o", ["Œ"] = "oe" }
local function Folded(name)
    return (tostring(name):gsub("[\195\197][\128-\191]", FOLD):lower())
end
local function ByName(a, b)
    if a.order ~= b.order then return a.order < b.order end
    local fa, fb = Folded(a.name), Folded(b.name)
    if fa ~= fb then return fa < fb end
    return a.name < b.name
end

-- Les types des recettes d'une liste, pour le menu : { { kind, name, count, subs = { { key, name, count } } } }, dans
-- l'ordre du menu.
function ns.KindMenu(counts)
    local out = {}
    for _, c in pairs(counts or {}) do
        local subs = {}
        for _, s in pairs(c.subs) do subs[#subs + 1] = s end
        table.sort(subs, ByName)
        out[#out + 1] = { kind = c.kind, name = c.name, count = c.count, order = c.order, subs = subs }
    end
    table.sort(out, ByName)
    return out
end

-- Le nom d'un filtre de type (le menu de la fenêtre) : « Torse », « Équipement », « Tous les objets ».
function ns.KindLabel(filter, counts)
    if not filter or filter == "" then return "Tous les objets" end
    local kind, sub = filter:match("^(.-)/(.+)$")
    kind = kind or filter
    local c = counts and counts[kind]
    if sub then
        local s = c and c.subs[sub]
        if s then return s.name end
    elseif c then
        return c.name
    end
    -- (le type choisi n'a plus de recette : un autre métier...)
    return kindNames[filter] or (sub and SLOT_NAMES[sub]) or KIND_NAMES[kind] or sub or kind
end

-- Recettes ------------------------------------------------------------------------------------------------------------
local function Split(text, pattern)
    local out = {}
    for a in tostring(text or ""):gmatch(pattern or "%S+") do out[#out + 1] = a end
    return out
end

local function ParseReagents(text)
    local out = {}
    for id, qty in tostring(text or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(id), tonumber(qty) } end
    return out
end

local function IsKnownSpell(id)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, id)
        if ok then return known and true or false end
    end
    return false
end

-- Une recette : ce que disent les données (d) et le jeu (s : la fenêtre des métiers ; t : celle d'un formateur), le
-- jeu d'abord pour ce qui concerne le personnage, et pour le niveau et le prix chez le formateur.
local function Merge(id, skillLine, d, s, t)
    local r = { id = id, skillLine = skillLine }
    if d then
        r.name, r.learnedAt = d[2], d[3]
        local c = Split(d[4], "%d+")
        if #c == 4 then r.colors = { tonumber(c[1]), tonumber(c[2]), tonumber(c[3]), tonumber(c[4]) } end
        r.reagents = ParseReagents(d[5])
        r.out = (d[6] or 0) > 0 and d[6] or nil
        r.qmin, r.qmax = d[7] or 1, d[8] or d[7] or 1
        r.sources = {}
        for _, code in ipairs(Split(d[9], "%d+")) do r.sources[tonumber(code)] = true end
        r.trainingCost = (d[10] or 0) > 0 and d[10] or nil
        r.scrolls = {}
        for _, item in ipairs(Split(d[11], "%d+")) do r.scrolls[#r.scrolls + 1] = tonumber(item) end
        r.ups = d[12] or 1
    end
    if s then
        r.name = s.name or r.name
        r.learned = s.learned
        r.difficulty, r.trivial = s.difficulty, s.trivial
        r.ups = s.ups or r.ups
        r.sourceText = s.source
        r.icon = s.icon
        if s.reagents and s.reagents ~= "" then r.reagents = ParseReagents(s.reagents) end
        if s.out then r.out, r.qmin, r.qmax = s.out, s.qmin or r.qmin or 1, s.qmax or s.qmin or r.qmax or 1 end
    end
    -- (un enchantement : le parchemin où il est gravé, qui se vend à l'hôtel des ventes)
    local engraved = ns.DATA.engraved and ns.DATA.engraved[id]
    if engraved and (not r.out or r.out == engraved) then r.out, r.qmin, r.qmax, r.engraved = engraved, 1, 1, true end
    if r.learned == nil then r.learned = IsKnownSpell(id) end
    r.reagents = r.reagents or {}
    r.sources = r.sources or {}
    r.scrolls = r.scrolls or {}
    r.qmin, r.qmax = r.qmin or 1, r.qmax or r.qmin or 1
    r.name = r.name or ("Recette " .. id)
    -- (vue chez un formateur, Trainer.lua : son niveau et son prix, ceux du jeu, à la place de ceux de Data.lua)
    if t and t.rank then
        r.learnedAt = t.rank
        r.trainingCost = (t.cost or 0) > 0 and t.cost or nil
        r.sources[6], r.trainerSeen = true, true
    end
    return r
end

-- Toutes les recettes connues (données et jeu réunis), sans calcul de prix.
function ns.AllRecipes()
    local out, seen = {}, {}
    local scans, trainers = ns.Scans(), ns.Trainers()
    for id, d in pairs(ns.DATA.recipes or {}) do
        local scan = scans[d[1]]
        out[#out + 1] = Merge(id, d[1], d, scan and scan.recipes and scan.recipes[id], trainers[id])
        seen[id] = true
    end
    for skillLine, scan in pairs(scans) do
        for id, s in pairs(scan.recipes or {}) do
            if not seen[id] then
                out[#out + 1] = Merge(id, skillLine, nil, s, trainers[id])
                seen[id] = true
            end
        end
    end
    return out
end

-- Temps de fabrication d'une recette (secondes), d'après le jeu (le temps d'incantation du sort de la recette, connu
-- du jeu même pour une recette non apprise), ou nil.
local castTimes = {}
function ns.CraftTime(spellID)
    local t = castTimes[spellID]
    if t == nil then
        local ms
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            ms = ok and type(info) == "table" and info.castTime or nil
        elseif GetSpellInfo then
            ms = select(4, GetSpellInfo(spellID))
        end
        if type(ms) == "number" and issecretvalue and issecretvalue(ms) then ms = nil end
        t = type(ms) == "number" and ms >= 0 and ms / 1000 or false
        castTimes[spellID] = t
    end
    return t or nil
end

-- « instantané », « 3 s », « 2,5 s », « 1 min 30 », « 1 h 05 », « 2 h » (plusieurs fabrications : des heures).
function ns.TimeText(seconds)
    if not seconds then return nil end
    if seconds <= 0 then return "instantané" end
    if seconds < 60 then
        local text = seconds == math.floor(seconds) and ("%d s"):format(seconds) or (("%.1f s"):format(seconds):gsub("%.", ","))
        return text
    end
    if seconds < 3600 then
        local m, s = math.floor(seconds / 60), math.floor(seconds % 60 + 0.5)
        if s == 60 then m, s = m + 1, 0 end
        if m < 60 then return s > 0 and ("%d min %02d"):format(m, s) or (m .. " min") end
    end
    local total = math.floor(seconds / 60 + 0.5)
    local h, m = math.floor(total / 60), total % 60
    return m > 0 and ("%d h %02d"):format(h, m) or (h .. " h")
end

-- Le temps de toutes les fabrications d'une recette (r.crafts fois celui d'une), ou nil sans temps connu.
function ns.CraftsTime(r)
    local t = ns.CraftTime(r.id)
    return t and t * (r.crafts or 1) or nil
end

-- Les métiers : ceux des données, ceux du personnage, ceux lus dans le jeu.
function ns.AllProfessions()
    local set = {}
    for skillLine in pairs(ns.DATA.professions or {}) do set[skillLine] = true end
    for skillLine in pairs(ns.MyProfessions()) do set[skillLine] = true end
    for skillLine in pairs(ns.Scans()) do set[skillLine] = true end
    local list = {}
    for skillLine in pairs(set) do list[#list + 1] = skillLine end
    table.sort(list, function(a, b) return ns.ProfessionName(a) < ns.ProfessionName(b) end)
    return list
end

-- Points de compétence à ce niveau : { kind = couleur, chance = 0..1, points } ; nil sans le métier. Sans seuils de
-- couleur, la difficulté lue dans la fenêtre des métiers (au vrai niveau) : rien pour un niveau simulé (simulated),
-- qu'elle ne dit pas.
function ns.SkillUp(r, skill, simulated)
    if not skill then return nil end
    local c = r.colors
    if c then
        local need = r.learnedAt and r.learnedAt < 9999 and r.learnedAt or c[1]
        if need and skill < need then return { kind = "red", chance = 0, points = 0, need = need } end
        if skill < c[2] then return { kind = "orange", chance = 1, points = r.ups or 1 } end
        if skill < c[4] then
            local chance = c[4] > c[2] and (c[4] - skill) / (c[4] - c[2]) or 0
            return { kind = skill < c[3] and "yellow" or "green", chance = chance, points = 1 }
        end
        return { kind = "gray", chance = 0, points = 0 }
    end
    if simulated then return nil end
    local d = r.difficulty
    if d == 0 then return { kind = "orange", chance = 1, points = r.ups or 1 } end
    if d == 1 then return { kind = "yellow", points = 1 } end
    if d == 2 then return { kind = "green", points = 1 } end
    if d == 3 then return { kind = "gray", chance = 0, points = 0 } end
    return nil
end

local GUESS = { yellow = 0.75, green = 0.25 }

-- Les points de compétence espérés d'une fabrication (chance x points), en pour cent arrondi comme à l'écran
-- (« +1 (88 %) » : 88) : deux recettes affichées à la même chance sont à égalité. Sans seuils, la chance estimée de la
-- couleur du jeu ; 0 pour une recette qui n'en donne pas (grise, niveau trop bas, métier que le personnage n'a pas).
function ns.ExpectedPoints(r)
    local up = r.up
    if not up or up.kind == "red" or up.kind == "gray" then return 0 end
    local chance = up.chance or GUESS[up.kind] or 0
    return math.floor((up.points or 1) * chance * 100 + 0.5)
end

-- À points espérés égaux (tri « Le mieux pour l'xp »), le temps de fabrication compte d'abord (la plus rapide en tête,
-- un temps inconnu à la fin) ; à temps égal : (rang, clé), le plus petit rang puis la plus haute clé d'abord.
-- Rang 1 : le bénéfice d'une fabrication, le plus haut d'abord (une perte : la plus petite) ; sans revente connue
-- (parchemin sans prix, objet sans prix, recette qui ne crée rien), le coût compte comme une perte. Rang 2 : un
-- composant sans prix.
function ns.XpRank(r)
    local cost = r.cost or (#r.reagents == 0 and 0 or nil)
    if not cost then return 2, 0 end
    return 1, ((r.value or 0) - cost) / (r.crafts or 1) -- (d'une fabrication, en moyenne)
end

function ns.SkillThresholdText(r)
    local c = r.colors
    if not c or not c[2] or not c[3] or not c[4] then return "Seuils de compétence inconnus" end
    return ("|c%sJaune dès %d|r · |c%sVert dès %d|r · |c%sGris dès %d|r"):format(
        ns.DIFFICULTY.yellow, c[2], ns.DIFFICULTY.green, c[3], ns.DIFFICULTY.gray, c[4])
end

function ns.SkillUpText(up)
    if not up then return nil end
    local color = ns.DIFFICULTY[up.kind]
    local text
    if up.kind == "red" then text = ("il faut %d"):format(up.need)
    elseif up.kind == "gray" then text = "0 (grise)"
    elseif up.chance then text = ("+%d (%s)"):format(up.points, ns.Percent(up.chance))
    else text = up.kind == "yellow" and "+1 (probable)" or "+1 (peu probable)" end
    return "|c" .. color .. text .. "|r"
end

-- Coût, revente et bénéfice d'une recette fabriquée ns.Crafts() fois (fixés dans r : crafts, cost, missing, value,
-- profit ; reagentCosts : le détail de chaque composant, ns.ReagentCost ; estimate : un composant compté sans ses
-- offres ; short : il en manque à l'hôtel des ventes ; unsellable : revendu au marchand, qui ne l'achète pas, value 0),
-- son bénéfice par seconde de fabrication (perSecond : bénéfice /
-- temps d'incantation de toutes ; nil sans bénéfice, sans temps connu ou instantanée ; affiché) et son bénéfice en %
-- du coût (profitPct : bénéfice / coût, 0,5 pour +50 % ; nil sans bénéfice ou sans coût ; le tri « Bénéfice » : ce
-- que rapporte chaque pièce d'or investie). Revente, bénéfice, par seconde et en % reposent sur le même prix : ils ont
-- le même signe.
function ns.Price(r, crafts)
    crafts = crafts or ns.Crafts() -- (1 pour le filtre : coût réel d'une seule fabrication, indépendant du lot)
    local cost, missing, parts, estimate, short = 0, {}, {}, false, false
    for i, reagent in ipairs(r.reagents) do
        local c, d = ns.ReagentCost(reagent[1], reagent[2] * crafts)
        parts[i] = d or false
        if c then
            cost = cost + c
            estimate = estimate or d.estimate or false
            short = short or (d.short or 0) > 0
        else
            missing[#missing + 1] = reagent[1]
        end
    end
    r.crafts, r.reagentCosts, r.estimate, r.short = crafts, parts, estimate, short
    r.cost = #r.reagents > 0 and #missing == 0 and cost or nil
    r.partialCost, r.missing = cost, missing
    r.value, r.valueKind, r.how, r.unsellable, r.ahPrice = nil, nil, nil, nil, nil
    if r.out then
        local qty = (r.qmin + r.qmax) / 2 * crafts
        local price, how = nil, nil
        if not ns.VendorResale() then price, how = ns.AuctionPrice(r.out) end
        r.how = how -- (sur quoi repose la revente : le relevé, ou ForeverExchange)
        if price then -- (ahPrice : le prix relevé d'un objet, avant la commission)
            r.value, r.valueKind, r.ahPrice = price * qty * (ns.Get("ahCut") and 0.95 or 1), "ah", price
        else
            local sell = ns.SellPrice(r.out)
            if sell then
                r.value, r.valueKind = sell * qty, "vendor"
            elseif ns.VendorResale() then
                -- (revendu au marchand, qui ne l'achète pas, sans prix de vente : 0, tout le coût en perte)
                r.value, r.valueKind, r.unsellable = 0, "vendor", true
            end
        end
    end
    r.profit = (r.cost and r.value) and (r.value - r.cost) or nil
    local seconds = r.profit and ns.CraftTime(r.id)
    r.perSecond = seconds and seconds > 0 and r.profit / (seconds * crafts) or nil
    r.profitPct = r.profit and r.cost > 0 and r.profit / r.cost or nil
    return r
end

-- Objets du jeu -------------------------------------------------------------------------------------------------------
-- Une recette ne se montre que quand le jeu a la fiche de chaque objet qu'elle fait voir au survol : sans elle,
-- l'infobulle reste sur « Récupération des informations de l'objet ». Une fiche qui manque est demandée au serveur
-- (C_Item.RequestLoadItemDataByID, comme le jeu le fait) et la liste suit quand elle arrive ; refusée (le serveur n'a
-- pas l'objet), ou sans réponse après ITEM_TRIES demandes, l'objet est inconnu du serveur (une réponse plus tard le
-- ramène). Un objet chargé une fois reste prêt : le jeu peut oublier sa fiche, il la retrouve aussitôt.
local ITEM_RETRY, ITEM_TRIES = 4, 3   -- (redemandée toutes les 4 s ; inconnue après 3 demandes sans réponse)
local itemState = {}   -- [n°] = true (prête), false (inconnu du serveur), { tries, at } (demandée, sans réponse)

local function Cached(id)
    if C_Item and C_Item.IsItemDataCachedByID then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
        return ok and cached and true or false
    end
    return (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) ~= nil
end

-- (un n° qui n'est même pas dans les tables du client : rien à demander)
local function Exists(id)
    if not (C_Item and C_Item.DoesItemExistByID) then return true end
    local ok, exists = pcall(C_Item.DoesItemExistByID, id)
    return not ok or exists ~= false
end

local function Request(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- (des réponses arrivent par paquets : la liste suit une fois, un instant après)
local notifying = false
local function ItemsChanged()
    if notifying then return end
    notifying = true
    C_Timer.After(0.3, function()
        notifying = false
        ns.Changed("items")
    end)
end

-- (tant que des fiches sont demandées sans réponse : redemandées, puis tenues pour inconnues du serveur)
local watching = false
local function Watch()
    if watching then return end
    watching = true
    C_Timer.After(ITEM_RETRY, function()
        watching = false
        local now, again, changed = GetTime(), false, false
        for id, state in pairs(itemState) do
            if type(state) == "table" then
                if Cached(id) then
                    itemState[id], changed = true, true
                elseif now - state.at < ITEM_RETRY - 0.01 then
                    again = true -- (demandée il y a peu : au prochain tour)
                elseif state.tries >= ITEM_TRIES then
                    itemState[id], changed = false, true
                else
                    state.tries, state.at, again = state.tries + 1, now, true
                    Request(id)
                end
            end
        end
        if changed then ItemsChanged() end
        if again then Watch() end
    end)
end

-- La fiche d'un objet : true (prête), nil (demandée au serveur, en attente), false (inconnu du serveur).
function ns.ItemReady(id)
    local state = itemState[id]
    if state == true then return true end
    if Cached(id) then
        itemState[id] = true
        return true
    end
    if state == false then return false end
    if state == nil then
        if not Exists(id) then
            itemState[id] = false
            return false
        end
        itemState[id] = { tries = 1, at = GetTime() }
        Request(id)
        Watch()
    end
    return nil
end

local itemEvents = CreateFrame("Frame")
pcall(itemEvents.RegisterEvent, itemEvents, "ITEM_DATA_LOAD_RESULT")   -- (la réponse à RequestLoadItemDataByID)
pcall(itemEvents.RegisterEvent, itemEvents, "GET_ITEM_INFO_RECEIVED")  -- (une fiche arrivée pour une autre raison)
itemEvents:SetScript("OnEvent", function(_, _, id, success)
    local state = itemState[id]
    if state == nil or state == true then return end
    if success or Cached(id) then
        itemState[id] = true
        ItemsChanged()
    elseif state ~= false then
        itemState[id] = false
        ItemsChanged()
    end
end)

local function SpellExists(id)
    if not (C_Spell and C_Spell.DoesSpellExist) then return true end
    local ok, exists = pcall(C_Spell.DoesSpellExist, id)
    return not ok or exists ~= false
end

-- Ce que la recette fait voir au survol est-il prêt ? true : oui ; nil : une fiche en attente ; false : un objet
-- inconnu du serveur. L'objet créé (sans objet créé, le sort de la recette), chaque composant et, pour une recette non
-- apprise, un parchemin qui l'apprend : r.scrolls ne garde que ceux que le jeu connaît. Sans aucun, la recette reste si
-- elle s'apprend aussi chez le formateur, avec le métier ou d'après le texte du jeu (sans icône de parchemin) ; sinon
-- elle ne s'apprend pas sur Forever. Un enchantement dont le serveur n'a pas le parchemin où le graver reste (il fait
-- monter le métier), sans revente : l'infobulle de son sort.
function ns.RecipeReady(r)
    local waiting = false
    local function Item(id)
        local ready = ns.ItemReady(id)
        if ready == nil then waiting = true end
        return ready ~= false
    end
    if r.out and not Item(r.out) then
        if not r.engraved then return false end
        r.out, r.engraved = nil, nil
    end
    if not r.out and not SpellExists(r.id) then return false end
    for _, reagent in ipairs(r.reagents) do
        if not Item(reagent[1]) then return false end
    end
    if not r.learned and #r.scrolls > 0 then
        local known, loading = {}, false
        for _, id in ipairs(r.scrolls) do
            local ready = ns.ItemReady(id)
            if ready then known[#known + 1] = id elseif ready == nil then loading = true end
        end
        if #known == 0 then
            if loading then
                waiting = true
            elseif not (r.sources[6] or r.sources[10] or (r.sourceText or "") ~= "") then
                return false
            end
        end
        r.scrolls = known
    end
    if waiting then return nil end
    return true
end

local function Matches(r, opts)
    if opts.profession ~= 0 and r.skillLine ~= opts.profession then return false end
    if opts.maxLevel > 0 and r.learnedAt and r.learnedAt < 9999 and r.learnedAt > opts.maxLevel then return false end
    if opts.mine and not opts.myProfessions[r.skillLine] then return false end
    if opts.favoritesOnly and not ns.IsFavorite(r.id) then return false end
    if opts.show == "learned" and not r.learned then return false end
    if opts.show == "unlearned" and r.learned then return false end
    if opts.search ~= "" and not r.name:lower():find(opts.search, 1, true) then return false end
    return true
end

-- (le tri par bénéfice : d'abord ce qui rapporte, puis les pertes, puis sans bénéfice connu)
local function ProfitTier(r)
    if not r.profit then return 3 end
    return r.profit > 0 and 1 or 2
end

local SORTS = {
    -- (bénéfice, à l'hôtel des ventes ou au marchand selon la case : ce qui rapporte le plus par rapport à
    -- l'investissement, le bénéfice en % du coût des composants, décroissant ; puis les pertes, la plus petite en %
    -- d'abord ; à pourcentage égal (ou sans coût, après), le plus gros bénéfice ; à la fin, sans bénéfice connu)
    profit = function(a, b)
        local ta, tb = ProfitTier(a), ProfitTier(b)
        if ta ~= tb then return ta < tb end
        if ta < 3 then
            if (a.profitPct ~= nil) ~= (b.profitPct ~= nil) then return a.profitPct ~= nil end
            if a.profitPct and a.profitPct ~= b.profitPct then return a.profitPct > b.profitPct end
            if a.profit ~= b.profit then return a.profit > b.profit end
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end,
    cost = function(a, b)
        if (a.cost ~= nil) ~= (b.cost ~= nil) then return a.cost ~= nil end
        if a.cost and a.cost ~= b.cost then return a.cost < b.cost end
        return a.name < b.name
    end,
    level = function(a, b)
        local la, lb = a.learnedAt or 0, b.learnedAt or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end,
    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end,
    -- (le mieux pour l'xp : la chance d'un point ; à chance égale, la plus rapide à fabriquer ; à temps égal, le
    -- bénéfice, ns.XpRank)
    xp = function(a, b)
        local pa, pb = a.xp or 0, b.xp or 0
        if pa ~= pb then return pa > pb end
        local ta, tb = ns.CraftTime(a.id) or math.huge, ns.CraftTime(b.id) or math.huge
        if ta ~= tb then return ta < tb end
        if a.xpRank ~= b.xpRank then return a.xpRank < b.xpRank end
        if a.xpKey ~= b.xpKey then return a.xpKey > b.xpKey end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end,
    skillup = function(a, b)
        local ca, cb = a.up and (a.up.chance or 0.5) or -1, b.up and (b.up.chance or 0.5) or -1
        if a.up and a.up.kind == "red" then ca = -0.5 end
        if b.up and b.up.kind == "red" then cb = -0.5 end
        if ca ~= cb then return ca > cb end
        return a.name < b.name
    end,
}

-- Ce qu'une ligne montre d'une recette prête (ns.RecipeReady) : ses montants pour les « Fabrications », ses points de
-- compétence (au niveau simulé d'abord) et son rang pour le tri « Le mieux pour l'xp ». k : son type, s'il est connu.
function ns.Decorate(r, k)
    r.kind = k or ns.Kind(r)
    ns.Price(r) -- (montants affichés pour toutes les fabrications)
    local skill, simulated = ns.SkillLevel(r.skillLine)
    r.up = ns.SkillUp(r, skill, simulated)
    r.simulated = simulated or nil
    r.xp = ns.ExpectedPoints(r)
    r.xpRank, r.xpKey = ns.XpRank(r)
    return r
end

-- Trier une liste de recettes décorées (ns.Decorate) : le tri choisi.
function ns.SortRecipes(list, sortKey)
    table.sort(list, SORTS[sortKey] or SORTS.profit)
    return list
end

-- La liste à afficher : filtrée, chiffrée, triée. Les recettes dont un objet n'est pas prêt (ns.RecipeReady) n'y sont
-- pas : list.waiting compte celles qui attendent une fiche du serveur, list.unknown celles dont il n'a pas l'objet ;
-- ni celles dont un composant ne s'achète pas (ns.RecipeBuyable) : list.unbuyable. Filtre « Type d'objet » (ns.Kind) :
-- list.kinds compte les recettes montrables de chaque type, les autres filtres appliqués (le menu). « Bénéfice plus
-- de » (minProfit, en cuivre) : bénéfice d'une seule fabrication, indépendant du nombre demandé ; celles au bénéfice
-- plus petit ou égal, ou inconnu, ne sont ni montrées ni comptées. opts.lazy (la fenêtre, qui montre la liste par
-- pages) : avec un tri qui n'a besoin ni des prix ni des points de compétence (nom, niveau requis), les recettes ne
-- sont pas chiffrées ici (list.lazy) ; la fenêtre chiffre (ns.Decorate) seulement celles de la page affichée.
function ns.List(opts)
    opts = opts or {}
    local lazyOpt = opts.lazy
    local my = ns.MyProfessions()
    opts = {
        profession = opts.profession or ns.Get("profession"),
        show = opts.show or ns.Get("show"),
        search = (opts.search or ns.Get("search") or ""):lower(),
        mine = opts.mine == nil and ns.Get("mine") or opts.mine,
        favoritesOnly = opts.favoritesOnly == nil and ns.Get("favoritesOnly") or opts.favoritesOnly,
        sort = opts.sort or ns.Get("sort"),
        maxLevel = tonumber(opts.maxLevel or ns.Get("maxLevel")) or 0,
        itemType = opts.itemType or ns.Get("itemType") or "",
        -- (false : pas de limite, quel que soit le réglage)
        minProfit = tonumber(opts.minProfit == nil and ns.Get("minProfit") or opts.minProfit or nil),
        myProfessions = my,
    }
    local lazy = lazyOpt and (opts.sort == "name" or opts.sort == "level") or false
    local list, waiting, unknown, unbuyable = {}, 0, 0, 0
    -- (combien de recettes de chaque type, les autres filtres appliqués : le menu « Type d'objet »)
    local counts = {}
    local function Count(k)
        local c = counts[k.kind]
        if not c then
            c = { kind = k.kind, name = k.kindName, order = k.kindOrder, count = 0, subs = {} }
            counts[k.kind] = c
        end
        c.count = c.count + 1
        local s = c.subs[k.sub]
        if not s then
            s = { key = k.key, name = k.subName, order = k.order, count = 0 }
            c.subs[k.sub] = s
        end
        s.count = s.count + 1
    end
    for _, r in ipairs(ns.AllRecipes()) do
        if Matches(r, opts) then
            local ready = ns.RecipeReady(r)
            -- RecipeReady peut retirer un parchemin gravé absent du serveur : filtrer son objet après cette étape.
            if ready then
                local k = ns.Kind(r)
                local shown = ns.KindMatches(k, opts.itemType)
                if not ns.RecipeBuyable(r) then
                    if shown then unbuyable = unbuyable + 1 end
                elseif not opts.minProfit or (ns.Price(r, 1).profit or -math.huge) > opts.minProfit then
                    Count(k) -- (d'un autre type aussi : comptée pour le menu, mais pas montrée)
                    -- (montants affichés pour toutes les fabrications, après le filtre unitaire)
                    if shown then
                        if lazy then r.kind = k else ns.Decorate(r, k) end
                        list[#list + 1] = r
                    end
                end
            elseif ready == nil then
                waiting = waiting + 1
            elseif not ready then
                unknown = unknown + 1
            end
        end
    end
    ns.SortRecipes(list, opts.sort)
    list.waiting, list.unknown, list.unbuyable = waiting, unknown, unbuyable
    list.kinds, list.lazy = counts, lazy
    return list
end

-- Comment apprendre une recette : texte court, et les parchemins (n° d'objet) à montrer.
function ns.HowToLearn(r)
    if r.learned then return "Apprise", {} end
    local parts = {}
    if r.sources[6] then
        parts[#parts + 1] = "Formateur" .. (r.trainingCost and (" (" .. ns.Money(r.trainingCost) .. ")") or "")
    end
    if #r.scrolls > 0 then
        local scroll = ns.DATA.recipeItems and ns.DATA.recipeItems[r.scrolls[1]]
        local first = scroll and scroll[2] and ns.SourceLine(scroll[2], true)
        parts[#parts + 1] = "Parchemin" .. (first and (" : " .. first) or "")
    end
    if #parts == 0 and r.sourceText and r.sourceText ~= "" then
        local line = r.sourceText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"):match("^[^\n]+")
        if line then parts[#parts + 1] = line end
    end
    if #parts == 0 then
        for code in pairs(r.sources) do if ns.SOURCES[code] and code ~= 6 then parts[#parts + 1] = ns.SOURCES[code] end end
        table.sort(parts)
    end
    if #parts == 0 then parts[1] = "Source inconnue" end
    return table.concat(parts, " · "), r.scrolls
end

-- Une façon d'obtenir un parchemin (Data.lua : "genre\tn°\tnom\tzone\tplus") en texte ; les noms de monstres et de
-- quêtes dans la langue du jeu quand il les connaît.
local function ZoneName(id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    return C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id) or nil
end

local function ItemNameByID(id, fallback)
    local name = id and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and id and C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(id) end
    return name or fallback
end

function ns.SourceLine(raw, short)
    local kind, id, name, zone, extra = strsplit("\t", raw)
    id = tonumber(id)
    name = name or ""
    local where = ZoneName(zone)
    local pct = tonumber(extra)
    local rate = pct and (" : " .. ns.Rate(pct)) or ""
    local at = where and (" (" .. where .. ")") or ""
    if kind == "V" then
        name = ns.NpcName(id, name)
        if short then return ("%s%s"):format(name, where and (", " .. where) or "") end
        return ("Vendu par %s%s%s"):format(name, at, pct and pct > 0 and (" : " .. ns.Money(pct)) or "")
    elseif kind == "D" then
        name = ns.NpcName(id, name)
        if short then return ("butin de %s"):format(name) end
        return ("Butin de %s%s%s"):format(name, at, rate)
    elseif kind == "W" then
        local count, levels = tostring(extra or ""):match("^(%d*):?(.*)$")
        if short then return "butin aléatoire" end
        return ("Butin aléatoire de %s monstres%s"):format(count ~= "" and count or "nombreux",
            levels ~= "" and (" (niveaux " .. levels .. ")") or "")
    elseif kind == "Q" then
        name = ns.QuestName(id, name)
        if short then return ("quête « %s »"):format(name) end
        return ("Récompense de la quête « %s »%s"):format(name, at)
    elseif kind == "O" then
        if short then return ("dans %s"):format(name) end
        return ("Dans %s%s%s"):format(name, at, rate)
    elseif kind == "C" then
        name = ItemNameByID(id, name)
        if short then return ("dans %s"):format(name) end
        return ("Dans %s%s"):format(name, rate)
    elseif kind == "F" then
        return short and "pêche" or ("Pêché%s%s"):format(at, rate)
    elseif kind == "P" then
        name = ns.NpcName(id, name)
        return short and "vol à la tire" or ("Vol à la tire%s%s%s"):format(name ~= "" and (" sur " .. name) or "", at, rate)
    end
    return name
end
