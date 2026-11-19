-- ForeverCraftAtlas : toutes les recettes de tous les métiers, apprises ou non ; pour celles qui ne le sont pas, comment les
-- apprendre (formateur, ou parchemin : son icône montre son infobulle et où le trouver) ; pour chacune, ce que coûtent
-- ses composants à l'achat et ce que rapporte la revente de l'objet (son offre la moins chère relevée en jeu, sinon le
-- prix minimum vu par ForeverExchange ; un enchantement, gravé sur un parchemin, celle de ce parchemin), et les points
-- de compétence qu'elle donne à ton niveau du métier. Affichage : « <coût> (<+/- bénéfice>) », puis le bénéfice par
-- seconde.
--
-- Aucune dépendance : les prix viennent des relevés de l'addon (Libs\Prices.lua) et, s'il est installé, de
-- ForeverExchange (ses données lues sans rien y écrire ; une analyse lancée par l'un est lue par l'autre).
--
-- D'où viennent les recettes : les métiers du personnage sont lus dans le jeu quand leur fenêtre s'ouvre (Scan.lua) ;
-- tous les métiers, d'après les tables du jeu WoW Forever, la base libre de CMaNGOS et QuestieDB, rangés dans Data.lua ;
-- le niveau et le prix chez le formateur, lus dans la fenêtre des formateurs (Trainer.lua).
-- /fca ou /recettes ouvre la fenêtre (aussi : le bouton des addons près de la minicarte, et Options > AddOns).
local addonName, ns = ...

ns.DEFAULTS = {
    show = "all",         -- "all", "learned", "unlearned"
    profession = 0,       -- 0 : tous les métiers ; sinon la ligne de compétence (171 : Alchimie...)
    search = "",
    maxLevel = 0,         -- niveau de métier requis au plus (0 : pas de limite)
    -- minProfit : bénéfice plus grand que (cuivre, peut être négatif) ; nil : pas de limite
    itemType = "",        -- type d'objet créé : "" (tous), un genre ("equip"), ou genre/sous-type ("equip/INVTYPE_CHEST")
    sort = "profit",      -- "profit" (bénéfice en % du coût), "xp", "cost", "level", "name", "skillup"
    mine = false,         -- seulement les métiers du personnage
    favoritesOnly = false, -- seulement les recettes en favori (Wishlist.lua : ns.IsFavorite)
    buySource = "FXAvg7", -- achat des composants sans relevé : un prix de ForeverExchange (Libs\Prices.lua)
    vendorFirst = true,   -- prix des marchands : le moins cher du marchand et de l'hôtel des ventes
    vendorResale = false, -- revente de l'objet créé à un marchand (PNJ) plutôt qu'à l'hôtel des ventes
    ahCut = true,         -- 5 % de commission de l'hôtel des ventes sur la revente
    crafts = 1,           -- combien de fois fabriquer chaque recette : coût, revente et bénéfice pour toutes
    tab = "recipes",      -- l'onglet de la fenêtre : "recipes" (les recettes), "route" (XP Road, Route.lua), "wishlist"
    routeMode = "fast",   -- XP Road : "fast" (la plus rapide) ou "cheap" (la moins chère)
}
ns.DATA = ns.DATA or { professions = {}, recipes = {}, recipeItems = {} }

function ns.Get(key)
    local db = ForeverCraftAtlasDB
    local v = db and db.settings and db.settings[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

local listeners = {}
function ns.OnChange(fn) listeners[#listeners + 1] = fn end
function ns.Changed(key) for _, fn in ipairs(listeners) do fn(key) end end

function ns.Set(key, value)
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.settings = ForeverCraftAtlasDB.settings or {}
    if ForeverCraftAtlasDB.settings[key] == value then return end
    ForeverCraftAtlasDB.settings[key] = value
    ns.Changed(key)
end

-- (les métiers lus dans le jeu et la place de la fenêtre sont gardés)
function ns.Reset()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    local point = ForeverCraftAtlasDB.settings and ForeverCraftAtlasDB.settings.point
    ForeverCraftAtlasDB.settings = { point = point }
    ns.Changed()
end

-- Argent : pièces du jeu ; signé pour le bénéfice. (0 : « 0 » et la pièce de cuivre, écrits ici : une revente de 0
-- au marchand se lit.)
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function ns.Money(copper)
    copper = math.floor(math.abs(copper or 0) + 0.5)
    if copper > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD end
    if s > 0 or (g > 0 and c > 0) then parts[#parts + 1] = s .. SILVER end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
    return table.concat(parts, " ")
end

function ns.Signed(copper)
    if not copper then return "?" end
    if copper >= 0.5 then return "|cff40ff40+" .. ns.Money(copper) .. "|r" end
    if copper <= -0.5 then return "|cffff4040-" .. ns.Money(copper) .. "|r" end
    return "|cffd0d0d0" .. ns.Money(0) .. "|r"
end

-- Bénéfice en % du coût (0,5 : « +50 % ») : signé et coloré comme le bénéfice ; « +1 250 % » ; moins de 1 % : « +< 1 % ».
function ns.SignedPercent(ratio)
    if not ratio then return "?" end
    local n = math.floor(math.abs(ratio) * 100 + 0.5)
    local text = n == 0 and "< 1" or tostring(n):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    if ratio > 0 then return "|cff40ff40+" .. text .. " %|r" end
    if ratio < 0 then return "|cffff4040-" .. text .. " %|r" end
    return "|cffd0d0d00 %|r"
end

-- Bénéfice par seconde : signé comme le bénéfice ; moins d'un cuivre par seconde : « +< 1 pc ».
function ns.SignedRate(copper)
    if copper and copper > 0 and copper < 0.5 then return "|cff40ff40+< " .. ns.Money(1) .. "|r" end
    if copper and copper < 0 and copper > -0.5 then return "|cffff4040-< " .. ns.Money(1) .. "|r" end
    return ns.Signed(copper)
end

-- Des pièces d'or écrites (« 1,5 », « -0.25 », « 3 ») : en cuivre, ou nil (pas un nombre).
function ns.ParseGold(text)
    local v = tonumber((tostring(text or ""):gsub("%s", ""):gsub(",", ".")))
    if not v then return nil end
    return math.floor(v * 10000 + 0.5)
end

-- L'inverse, pour la case : « 1,5 », « -0,25 », « 3 » ; nil : « ».
function ns.GoldText(copper)
    if not copper then return "" end
    local text = ("%.4f"):format(copper / 10000):gsub("0+$", ""):gsub("%.$", "")
    return (text:gsub("%.", ","))
end

function ns.Percent(p)
    return ("%d %%"):format(math.floor(p * 100 + 0.5))
end

-- Un taux déjà en % : « 42 % », « 4,5 % », « 0,25 % », « < 0,01 % ».
function ns.Rate(pct)
    if pct >= 10 then return ("%d %%"):format(math.floor(pct + 0.5)) end
    if pct >= 1 then return (("%.1f %%"):format(pct):gsub("%.", ",")) end
    if pct >= 0.01 then return (("%.2f %%"):format(pct):gsub("%.", ",")) end
    return "< 0,01 %"
end

-- Noms dans la langue du jeu -----------------------------------------------------------------------------------------
-- Les noms de monstres et de quêtes des données sont en anglais : on demande au jeu les siens (monstre : infobulle
-- « unit:Creature-0-0-0-0-<n°>-0 » ; quête : C_QuestLog), gardés dans ForeverCraftAtlasDB ; la première fois le jeu les
-- demande au serveur : on réessaie un peu plus tard, puis ns.Changed("names").
local queue, queued, tries, pumping = {}, {}, {}, false
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function LookupNpc(id)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0"):format(id))
    local line = ok and type(data) == "table" and data.lines and data.lines[1]
    local name = line and line.leftText
    if type(name) == "string" and name ~= "" and not Secret(name) then return name end
    return nil
end

local function Names()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.names = ForeverCraftAtlasDB.names or {}
    return ForeverCraftAtlasDB.names
end

local function Pump()
    if pumping then return end
    pumping = true
    C_Timer.After(0.1, function()
        pumping = false
        local names, got, later = Names(), false, {}
        for _ = 1, 15 do
            local id = table.remove(queue, 1)
            if not id then break end
            queued[id] = nil
            local name = LookupNpc(id)
            if name then
                names[id], got = name, true
            else
                tries[id] = (tries[id] or 0) + 1
                if tries[id] < 3 then later[#later + 1] = id end
            end
        end
        if #later > 0 then C_Timer.After(1.5, function() for _, id in ipairs(later) do ns.NpcName(id) end end) end
        if got then ns.Changed("names") end
        if #queue > 0 then Pump() end
    end)
end

function ns.NpcName(id, fallback)
    id = tonumber(id)
    if not id or id <= 0 then return fallback end
    local known = Names()[id]
    if known then return known end
    if not queued[id] and (tries[id] or 0) < 3 then
        queued[id] = true
        queue[#queue + 1] = id
        Pump()
    end
    return fallback
end

local questAsked = {}
function ns.QuestName(id, fallback)
    id = tonumber(id)
    if not id or id <= 0 or not C_QuestLog then return fallback end
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if type(title) == "string" and title ~= "" and not Secret(title) then return title end
    if not questAsked[id] and C_QuestLog.RequestLoadQuestByID then
        questAsked[id] = true
        C_QuestLog.RequestLoadQuestByID(id)
    end
    return fallback
end

-- Personnage : « Nom-Royaume » (les métiers lus sont gardés par personnage)
function ns.CharKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetNormalizedRealmName and GetNormalizedRealmName() or "")
end

-- Métiers du personnage : { [ligne de compétence] = { name, skill, max } }, par GetProfessions (métiers principaux,
-- secourisme, pêche, cuisine) et, pour un métier ouvert, ce que la fenêtre des métiers en dit (Scan.lua).
function ns.MyProfessions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            if index then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
                if skillLine then out[skillLine] = { name = name, skill = rank or 0, max = maxRank or 0 } end
            end
        end
    end
    -- (sans GetProfessions seulement : sinon un métier oublié garderait le niveau de sa dernière lecture)
    if not (GetProfessions and GetProfessionInfo) then
        for skillLine, scan in pairs(ns.Scans()) do
            if not out[skillLine] and scan.skill then out[skillLine] = { name = scan.name, skill = scan.skill, max = scan.max } end
        end
    end
    return out
end

function ns.Scans()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.scans = ForeverCraftAtlasDB.scans or {}
    local key = ns.CharKey()
    ForeverCraftAtlasDB.scans[key] = ForeverCraftAtlasDB.scans[key] or {}
    return ForeverCraftAtlasDB.scans[key]
end

-- Ce qu'enseignent les formateurs de métier, lu dans leur fenêtre (Trainer.lua), pour tout le compte :
-- { [recette] = { rank = niveau du métier requis, cost = prix (cuivre), time = date de la lecture } }.
function ns.Trainers()
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.trainer = ForeverCraftAtlasDB.trainer or {}
    return ForeverCraftAtlasDB.trainer
end

-- Niveau simulé (champ « Niveau simulé » de la fenêtre) : pour préparer la montée d'un métier, les points de
-- compétence (couleur, chance, tri « Le mieux pour l'xp ») sont comptés à ce niveau au lieu du vrai. Un par métier et
-- par personnage, gardé d'une session à l'autre : ForeverCraftAtlasDB.simSkill[personnage][ligne de compétence] = niveau.
local SIM_MAX = 999
function ns.SimSkill(skillLine)
    local db = ForeverCraftAtlasDB and ForeverCraftAtlasDB.simSkill
    local mine = db and db[ns.CharKey()]
    return mine and mine[skillLine] or nil
end

-- (vide, 0 ou nil : plus de simulation pour ce métier)
function ns.SetSimSkill(skillLine, value)
    if not skillLine or skillLine == 0 then return end
    value = tonumber(value)
    value = value and value >= 1 and math.min(SIM_MAX, math.floor(value)) or nil
    if ns.SimSkill(skillLine) == value then return end
    ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
    ForeverCraftAtlasDB.simSkill = ForeverCraftAtlasDB.simSkill or {}
    local key = ns.CharKey()
    ForeverCraftAtlasDB.simSkill[key] = ForeverCraftAtlasDB.simSkill[key] or {}
    ForeverCraftAtlasDB.simSkill[key][skillLine] = value
    if not next(ForeverCraftAtlasDB.simSkill[key]) then ForeverCraftAtlasDB.simSkill[key] = nil end
    ns.Changed("simSkill")
end

-- Le niveau d'un métier pour les points de compétence : le niveau simulé s'il y en a un (même pour un métier que le
-- personnage n'a pas : préparer un nouveau métier), sinon le vrai ; nil sans le métier. 2e valeur : simulé ou non.
function ns.SkillLevel(skillLine)
    local sim = ns.SimSkill(skillLine)
    if sim then return sim, true end
    local mine = ns.MyProfessions()[skillLine]
    return mine and mine.skill or nil, false
end

function ns.ProfessionName(skillLine)
    local mine = ns.MyProfessions()[skillLine]
    if mine and mine.name then return mine.name end
    local data = ns.DATA.professions and ns.DATA.professions[skillLine]
    if data then return data end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
        if ok and name and name ~= "" then return name end
    end
    return "Métier " .. tostring(skillLine)
end

-- Ouvrir / fermer
function ns.Toggle()
    if not ns.window then return end
    if ns.window:IsShown() then ns.window:Hide() else ns.window:Show() end
end

-- Ouvrir : déjà ouverte mais sous d'autres fenêtres, elle repasse devant
function ns.Open()
    if not ns.window then return end
    ns.window:Show()
    ns.window:Raise()
end

function ns.OpenSettings()
    if ns.page and ns.SettingsKit then ns.SettingsKit.Open(ns.page) end
end

SLASH_FOREVERCRAFTATLAS1 = "/recettes"
SLASH_FOREVERCRAFTATLAS2 = "/fca"
SLASH_FOREVERCRAFTATLAS3 = "/forevercraftatlas"
SlashCmdList.FOREVERCRAFTATLAS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "options" or msg == "reglages" or msg == "réglages" or msg == "config" then
        ns.OpenSettings()
    elseif msg ~= "" then
        ns.Set("search", msg)
        ns.Open() -- (une recherche ouvre la fenêtre, ou la remet devant les autres)
    else
        ns.Toggle()
    end
end

function ForeverCraftAtlas_OnCompartmentClick() ns.Toggle() end
function ForeverCraftAtlas_OnCompartmentEnter(_, button)
    local owner = type(button) == "table" and button or (MinimapCluster or UIParent)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverCraftAtlas")
    GameTooltip:AddLine("Toutes les recettes, comment les apprendre, leur coût et leur bénéfice.", 1, 1, 1, true)
    GameTooltip:Show()
end
function ForeverCraftAtlas_OnCompartmentLeave() GameTooltip:Hide() end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        ForeverCraftAtlasDB = ForeverCraftAtlasDB or {}
        ForeverCraftAtlasDB.settings = ForeverCraftAtlasDB.settings or {}
        ForeverCraftAtlasDB.scans = ForeverCraftAtlasDB.scans or {}
        -- (les prix relevés à l'hôtel des ventes : Libs\Prices.lua ; des composants, toutes leurs offres)
        ForeverCraftAtlasDB.live = ForeverCraftAtlasDB.live or {}
        ns.Prices.LiveAttach(ForeverCraftAtlasDB.live, function(itemID) return ns.IsReagent(itemID) end)
        ns.Prices.autoScan = false -- (pas de relevé à l'ouverture de l'hôtel des ventes : « Scanner l'HDV »)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        ns.Changed("names")
    elseif event == "SKILL_LINES_CHANGED" then -- (un métier appris, oublié ou monté : son niveau suit dans la fenêtre)
        ns.Changed("skills")
    end
end)
pcall(events.RegisterEvent, events, "QUEST_DATA_LOAD_RESULT")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
