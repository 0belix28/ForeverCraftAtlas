-- Scan.lua : quand la fenêtre d'un métier du personnage s'ouvre (ou change), ForeverCraftAtlas lit ses recettes dans le jeu
-- (C_TradeSkillUI, comme la fenêtre des métiers de Forever) : nom, apprise ou non, difficulté et points de compétence,
-- composants et objet créé, et pour les recettes non apprises le texte du jeu qui dit comment les apprendre
-- (GetRecipeSourceText). Gardé par personnage dans ForeverCraftAtlasDB : la fenêtre de ForeverCraftAtlas s'en sert ensuite partout.
--
-- Seulement les métiers du personnage (pas ceux d'un lien, d'un membre de guilde ou d'un PNJ). Rien n'est changé dans
-- la fenêtre des métiers : ses filtres restent ceux du joueur (les recettes non apprises n'y sont lues que si le jeu
-- les donne : GetAllRecipeIDs, ou le filtre « non apprises » de la fenêtre).
local _, ns = ...

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function Reagents(schematic)
    local parts = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
        if (basic == nil or slot.reagentType == basic or slot.reagentType == nil) and slot.reagents and slot.reagents[1]
            and slot.reagents[1].itemID and (slot.quantityRequired or 0) > 0 then
            parts[#parts + 1] = slot.reagents[1].itemID .. ":" .. slot.quantityRequired
        end
    end
    return table.concat(parts, " ")
end

function ns.ScanOpenProfession()
    local T = C_TradeSkillUI
    if not T then return false end
    if Call(T.IsTradeSkillLinked) or Call(T.IsTradeSkillGuild) or Call(T.IsNPCCrafting) then return false end
    local info = Call(T.GetBaseProfessionInfo)
    if not (info and info.professionID) then return false end
    local ids = Call(T.GetAllRecipeIDs) or Call(T.GetFilteredRecipeIDs)
    if type(ids) ~= "table" or #ids == 0 then return false end
    local skillLine = info.professionID
    local scans = ns.Scans()
    local scan = scans[skillLine] or { recipes = {} }
    scan.name = info.professionName or scan.name
    scan.skill = info.skillLevel or scan.skill
    scan.max = info.maxSkillLevel or scan.max
    scan.time = time()
    local n = 0
    for _, id in ipairs(ids) do
        local r = Call(T.GetRecipeInfo, id)
        if r and not r.isRecraft and not r.isDummyRecipe then
            local schematic = Call(T.GetRecipeSchematic, id, false)
            local rec = scan.recipes[id] or {}
            rec.name = r.name
            rec.learned = r.learned and true or false
            rec.difficulty = r.relativeDifficulty
            rec.ups = r.numSkillUps
            rec.trivial = r.maxTrivialLevel
            rec.icon = r.icon
            if schematic then
                rec.reagents = Reagents(schematic)
                rec.out = schematic.outputItemID
                rec.qmin, rec.qmax = schematic.quantityMin, schematic.quantityMax
            end
            if not rec.learned then rec.source = Call(T.GetRecipeSourceText, id) or rec.source else rec.source = nil end
            scan.recipes[id] = rec
            n = n + 1
        end
    end
    scans[skillLine] = scan
    ns.Changed("scan")
    return n
end

-- (un instant après la dernière mise à jour de la liste : le jeu en envoie plusieurs à l'ouverture)
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        if C_TradeSkillUI and (not C_TradeSkillUI.IsTradeSkillReady or C_TradeSkillUI.IsTradeSkillReady()) then
            ns.ScanOpenProfession()
        end
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    pcall(events.RegisterEvent, events, e)   -- (un événement inconnu du client ne bloque pas les autres)
end
events:SetScript("OnEvent", function() Soon() end)
