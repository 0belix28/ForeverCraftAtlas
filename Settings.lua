-- La page de réglages : Options > AddOns > ForeverCraftAtlas, au format des réglages du jeu, chaque description affichée.
-- Le bouton du haut ouvre la fenêtre (comme /fca). Les filtres (afficher, tri, métier, recherche) sont dans la fenêtre.
local _, ns = ...
local UI = ns.SettingsKit
local PX = ns.Prices

local page = UI.NewPage({
    name = "ForeverCraftAtlas",
    title = "ForeverCraftAtlas",
    about = "Toutes les recettes de tous les métiers, apprises ou non : comment apprendre celles qui ne le sont pas "
        .. "(l'icône du parchemin montre son infobulle et où le trouver), ce que coûtent leurs composants, ce que rapporte "
        .. "la revente (les prix du dernier relevé de l'hôtel des ventes, fait en jeu, sinon ceux de ForeverExchange ; "
        .. "un enchantement se vend gravé sur un parchemin : le prix de ce parchemin), affichés « coût "
        .. "(+/- bénéfice) », et les points de compétence à ton niveau. Case « Fabrications » de la fenêtre : les mêmes "
        .. "pour plusieurs fabrications, les composants achetés aux offres les moins chères de l'hôtel des ventes. Une "
        .. "recette dont un composant ne s'achète pas (pas en vente au dernier relevé de l'hôtel des ventes, et aucun "
        .. "marchand ne le vend) n'est pas montrée. Aucune dépendance : ForeverExchange est facultatif. "
        .. "« /fca » ou « /recettes » ouvre la fenêtre (« /fca <nom> » y cherche une recette) ; « /fca options » cette page.",
    limits = {
        "Les recettes de tes métiers sont lues dans le jeu quand tu ouvres leur fenêtre (une fois suffit, puis à "
            .. "chaque changement). Celles de tous les métiers, leurs seuils de couleur et leurs parchemins viennent "
            .. "des tables du jeu WoW Forever ; formateurs, marchands, butins et quêtes, de la base libre de CMaNGOS "
            .. "(le monde de vanilla) et de QuestieDB (Data.lua).",
        "Les prix sont ceux du dernier relevé de l'hôtel des ventes : « Scanner l'HDV » (en bas de la fenêtre, "
            .. "l'hôtel des ventes ouvert) relève toutes ses annonces, et ce que tu y parcours l'est aussitôt. Une "
            .. "analyse lancée par ForeverExchange (à l'ouverture de l'HV, par exemple) est lue en même temps : une "
            .. "seule suffit pour les deux addons. ForeverExchange donne aussi le prix des objets pas encore relevés "
            .. "et les moyennes sur 7 et 30 jours.",
        "Aucun addon de WoW Forever ne connaît les ventes réelles : pas de ventes par jour ni de taux de vente, "
            .. "donc pas de bénéfice par jour. Le bénéfice se lit en % du coût et par seconde de fabrication.",
        "Le niveau et le prix chez le formateur sont ceux du jeu dès que tu as ouvert la fenêtre de ce formateur (coche "
            .. "« Non disponible » dans ses filtres pour qu'il montre aussi les recettes de plus haut niveau ; lus pour "
            .. "tous tes personnages). Avant, ceux de vanilla (CMaNGOS), le niveau décalé comme Forever a décalé les "
            .. "seuils de couleur de la recette : une estimation, et un prix que Forever peut avoir changé.",
    },
    defaultsQuestion = "Remettre tous les réglages et les filtres de ForeverCraftAtlas à leur valeur par défaut ? (Les "
        .. "métiers lus dans le jeu sont gardés.)",
    defaults = function() ns.Reset() end,
})
ns.page = page

page:Section("Fenêtre", "Les recettes, leurs prix et comment les apprendre.")
page:Button({ label = "Fenêtre de ForeverCraftAtlas", text = "Ouvrir ForeverCraftAtlas",
    desc = "Aussi : « /fca » ou « /recettes » dans le chat, ou le bouton des addons près de la minicarte.",
    onClick = function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then
            HideUIPanel(SettingsPanel)
        end
        ns.Open()
    end })
page:Checkbox({ label = "Bouton de la minicarte",
    desc = "Le logo de ForeverCraftAtlas près de la minicarte. Clic : ouvrir / fermer la fenêtre ; clic droit : ces "
        .. "réglages ; glisser : le déplacer autour de la minicarte.",
    get = function() return ns.Get("minimap") end, set = function(v) ns.Set("minimap", v and true or false) end })

page:Section("Prix", "Comment coût et bénéfice sont comptés. La revente de l'objet créé est son offre la moins chère : "
    .. "au dernier relevé de l'hôtel des ventes (« Scanner l'HDV », l'analyse de ForeverExchange, ce que tu y "
    .. "parcours), sinon le dernier prix minimum vu par ForeverExchange. Sans prix, ou à un prix aberrant (une annonce "
    .. "seule à plus de 5 fois ses moyennes chez ForeverExchange), la revente est celle du marchand.")
page:Dropdown({ label = "Achat sans relevé",
    desc = "Un composant s'achète aux offres du dernier relevé de l'hôtel des ventes, les moins chères d'abord. Ce prix de "
        .. "ForeverExchange quand il n'est pas encore relevé, ou pour ce qui manque en vente (par défaut sa moyenne sur "
        .. "7 jours ; sans elle, les autres prix de ForeverExchange). Sans ForeverExchange : le marchand, s'il en vend. "
        .. "L'infobulle d'un composant dit combien il y en a en vente.",
    choices = PX.Choices(),
    get = function() return ns.BuySource() end, set = function(v) ns.Set("buySource", v) end })
page:Checkbox({ label = "Prix des marchands",
    desc = "Un composant vendu par un marchand (fil, fiole, flux...) compte au moins cher : son prix chez lui (celui des "
        .. "tables du jeu WoW Forever pour ce que ses marchands vendent), ou celui de l'hôtel des ventes s'il y est "
        .. "moins cher. Décochée : le prix de l'hôtel des ventes, celui du marchand seulement quand il n'y en a pas.",
    get = function() return ns.Get("vendorFirst") end, set = function(v) ns.Set("vendorFirst", v) end })
page:Checkbox({ label = "Revente au marchand",
    desc = "Compter le bénéfice d'une revente de l'objet créé à un marchand (PNJ), à son prix de vente du jeu, plutôt "
        .. "qu'à l'hôtel des ventes (un objet qu'il n'achète pas, sans prix de vente, comme les parchemins "
        .. "d'enchantement, compte une revente de 0 : tout son coût en perte). Aussi : la case du même nom dans la "
        .. "fenêtre.",
    get = function() return ns.Get("vendorResale") end, set = function(v) ns.Set("vendorResale", v) end })
page:Checkbox({ label = "Commission de l'hôtel des ventes",
    desc = "Retirer de la revente les 5 % que garde l'hôtel des ventes. La revente compte la quantité moyenne créée "
        .. "par la recette.",
    get = function() return ns.Get("ahCut") end, set = function(v) ns.Set("ahCut", v) end })

page:Section("Données", "Ce que ForeverCraftAtlas sait des recettes et des prix.")
local info = page:Text("", "GameFontHighlightSmall", UI.colors.DESC)
local function InfoText()
    local lines = {}
    local d = ns.DATA or {}
    if (d.source or "") == "" then
        lines[#lines + 1] = "Pas de données de tous les métiers (Data.lua manque) : réinstalle l'addon."
    else
        local n = 0
        for _ in pairs(d.recipes or {}) do n = n + 1 end
        lines[#lines + 1] = ("%d recettes : %s, rangées le %s."):format(n, d.source, d.date or "?")
    end
    local names = {}
    for skillLine, scan in pairs(ns.Scans()) do
        local n = 0
        for _ in pairs(scan.recipes or {}) do n = n + 1 end
        names[#names + 1] = ("%s (%d recettes)"):format(scan.name or ns.ProfessionName(skillLine), n)
    end
    table.sort(names)
    lines[#lines + 1] = #names > 0 and ("Lus dans le jeu pour ce personnage : " .. table.concat(names, ", ") .. ".")
        or "Aucun métier lu dans le jeu pour ce personnage : ouvre la fenêtre d'un de tes métiers."
    lines[#lines + 1] = ("Prix : %s · %s."):format(PX.ScanText() or "pas encore de relevé de l'hôtel des ventes",
        PX.DataText())
    return table.concat(lines, "\n")
end
page.canvas:HookScript("OnShow", function() info:SetText(InfoText()) page:Reflow() end)
info:SetText(InfoText())
