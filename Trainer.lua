-- Trainer.lua : quand la fenêtre d'un formateur de métier s'ouvre (ou change), ForeverCraftAtlas lit ce qu'il enseigne : pour
-- chaque recette, le niveau du métier qu'elle demande et son prix, ceux du jeu. Les tables du client ne les ont pas
-- (le serveur les donne à la fenêtre du formateur) ; Data.lua n'a que ceux de vanilla (CMaNGOS), le niveau décalé comme
-- Forever a décalé les seuils de couleur de la recette : une estimation, que cette lecture remplace. Gardé pour tout le
-- compte dans ForeverCraftAtlasDB.trainer (ns.Trainers) ; la fenêtre de ForeverCraftAtlas s'en sert partout.
--
-- Rien n'est changé dans la fenêtre du formateur : seules les recettes qu'elle montre sont lues, avec les filtres du
-- joueur (« Non disponible » coché : aussi celles qui demandent un niveau plus haut que le sien).
-- (Fonctions du jeu : celles qu'appelle sa fenêtre du formateur, Blizzard_TrainerUI ; le sort d'un service, par son
-- infobulle : C_TooltipInfo.GetTrainerService, vérifiés dans le code d'interface de Forever 1.60.1.70938.)
local _, ns = ...

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

-- (une valeur secrète du jeu ne se lit pas)
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- La ligne de compétence d'un métier par son nom (celui que donne le formateur : « Travail du cuir »), ou nil.
local function LineByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    for line, n in pairs(ns.DATA.professions or {}) do if n == name then return line end end
    for line, p in pairs(ns.MyProfessions()) do if p.name == name then return line end end
    return nil
end

-- Les recettes connues (Data.lua, puis la fenêtre des métiers) : { [n°] = ligne de compétence } et, par nom,
-- { [nom] = { n°, ... } }.
local function Index()
    local lines, byName = {}, {}
    local function Add(id, line, name)
        if lines[id] then return end
        lines[id] = line
        if type(name) == "string" and name ~= "" then
            byName[name] = byName[name] or {}
            table.insert(byName[name], id)
        end
    end
    for id, d in pairs(ns.DATA.recipes or {}) do Add(id, d[1], d[2]) end
    for line, scan in pairs(ns.Scans()) do
        for id, s in pairs(scan.recipes or {}) do Add(id, line, s.name) end
    end
    return lines, byName
end

-- La recette du service n° i : le sort de son infobulle, s'il est une recette connue ; sinon la seule recette de ce
-- nom (du métier du formateur, quand il le dit) ; nil sans certitude (deux recettes du même nom : rien).
local function ServiceRecipe(i, lines, byName, line)
    local data = Call(C_TooltipInfo and C_TooltipInfo.GetTrainerService, i)
    local id = type(data) == "table" and Plain(data.id) or nil
    if type(id) == "number" and lines[id] then return id end
    local name = Plain((Call(GetTrainerServiceInfo, i)))
    local found
    for _, candidate in ipairs(type(name) == "string" and byName[name] or {}) do
        if not line or lines[candidate] == line then
            if found then return nil end
            found = candidate
        end
    end
    return found
end

local function TradeskillTrainer()
    local kind = Call(C_Trainer and C_Trainer.GetTrainerType)
    local tradeskills = Enum and Enum.TrainerType and Enum.TrainerType.Tradeskills
    if kind ~= nil and tradeskills ~= nil then return kind == tradeskills end
    return Call(IsTradeskillTrainer) and true or false
end

-- Lit la fenêtre du formateur ouverte : rend le nombre de recettes lues (false : pas celle d'un formateur de métier).
function ns.ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceSkillReq) or not TradeskillTrainer() then return false end
    local n = tonumber(Plain((Call(GetNumTrainerServices)))) or 0
    if n <= 0 then return 0 end
    local step = Plain((Call(GetTrainerServiceStepIndex))) -- (le rang du métier : pas une recette)
    local lines, byName = Index()
    local seen, now, count, changed = ns.Trainers(), time(), 0, false
    for i = 1, n do
        if i ~= step then
            local skill, rank = Call(GetTrainerServiceSkillReq, i)
            skill, rank = Plain(skill), Plain(rank)
            local id = ServiceRecipe(i, lines, byName, LineByName(skill))
            if id then
                rank = math.max(1, skill and tonumber(rank) or 1) -- (sans niveau demandé : dès le métier appris)
                local cost = tonumber(Plain((Call(GetTrainerServiceCost, i)))) or 0
                local old = seen[id]
                if not old or old.rank ~= rank or old.cost ~= cost then changed = true end
                seen[id] = { rank = rank, cost = cost, time = now }
                count = count + 1
            end
        end
    end
    if changed then ns.Changed("trainer") end
    return count
end

-- (un instant après la dernière mise à jour : le jeu en envoie plusieurs à l'ouverture, et des noms arrivent après)
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        ns.ScanTrainer()
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE" }) do
    pcall(events.RegisterEvent, events, e) -- (un événement inconnu du client ne bloque pas les autres)
end
events:SetScript("OnEvent", function() Soon() end)
