# ForeverCraftAtlas

**🇫🇷 Français** · [🇬🇧 English](#-english)

> Toutes les recettes des métiers de **World of Warcraft Forever**, apprises ou non : comment les apprendre, ce qu'elles coûtent, ce qu'elles rapportent et les points de compétence qu'elles donnent. **Aucune dépendance.**

ForeverCraftAtlas réunit dans une seule fenêtre **toutes les recettes de tous les métiers**, même celles que ton personnage ne connaît pas encore. Pour chacune, il te dit où l'apprendre, combien coûtent ses composants, combien rapporte l'objet fabriqué, et combien de points de compétence elle te fera gagner. Idéal pour monter un métier au meilleur prix, ou pour trouver ce qui rapporte de l'or.

## ✨ Fonctionnalités

- **Toutes les recettes de tous les métiers** : Alchimie, Forge, Travail du cuir, Couture, Ingénierie, Enchantement, Cuisine, Secourisme, Minage, Poisons. Les recettes de tes propres métiers sont lues dans le jeu dès que tu ouvres leur fenêtre.
- **Comment apprendre chaque recette** : formateur (niveau et prix lus quand tu lui parles), ou parchemin (son infobulle et où le trouver : marchand, butin, quête, vol à la tire…).
- **Coût et bénéfice** de chaque recette, affichés `coût (+/- bénéfice)`, avec le bénéfice en % du coût et par seconde de fabrication.
- **Fabrications multiples** : le coût de 10, 50 ou 200 fabrications, avec les composants achetés aux offres les moins chères de l'HV, une par une.
- **Points de compétence** à ton niveau (couleur, chance de gagner un point), et un **niveau simulé** pour préparer la montée d'un métier.
- **XP Road** : la route la plus rapide ou la moins chère pour monter un métier, étape par étape.
- **Favoris** et **wishlist** : la liste de courses à l'HV et chez les marchands, puis les achats.
- **Filtres et tris** : apprises / non apprises, métier, type d'objet créé (équipement par emplacement, armes, potions…), niveau requis, bénéfice minimum, recherche par nom.
- **Bouton sur la minicarte**, page de réglages dans Échap › Options › AddOns.

## 💰 D'où viennent les prix

1. **Les relevés de ForeverCraftAtlas** : le bouton « Scanner l'HDV » (hôtel des ventes ouvert) relève toutes les annonces, et tout ce que tu parcours à l'HV est relevé aussitôt.
2. **[ForeverExchange](https://github.com/)** (facultatif) : s'il est installé, ses prix servent pour les objets pas encore relevés (prix minimum, valeur marché, moyennes 7 et 30 jours, tendance). Une analyse lancée par ForeverExchange est lue en même temps par ForeverCraftAtlas : **une seule analyse pour les deux addons**.
3. **Les marchands** : les prix des composants vendus par les PNJ, d'après les tables du jeu WoW Forever.

Ni TradeSkillMaster, ni Auctionator, ni aucune bibliothèque externe ne sont nécessaires.

## 📦 Installation

1. Télécharge la dernière version et décompresse-la.
2. Copie le dossier `ForeverCraftAtlas` dans `World of Warcraft\_forever_\Interface\AddOns\`.
3. Lance le jeu (ou fais `/reload`).
4. Ouvre une fois la fenêtre de chacun de tes métiers pour que l'addon lise tes recettes.

## ⌨️ Commandes

| Commande | Action |
| --- | --- |
| `/fca` ou `/recettes` | Ouvrir / fermer la fenêtre |
| `/fca <nom>` | Chercher une recette |
| `/fca options` | Ouvrir les réglages |

Bouton de la minicarte : **clic** = fenêtre, **clic droit** = réglages, **glisser** = déplacer.

## ⚠️ Limites

- Les prix viennent **de tes propres relevés** (et de ceux de ForeverExchange) : l'addon ne partage aucune donnée avec d'autres joueurs.
- Aucun addon de WoW Forever ne connaît les ventes réelles : il n'y a donc **ni ventes par jour, ni bénéfice par jour**.
- Avant ta première visite chez un formateur, son niveau et son prix sont estimés d'après vanilla.
- Interface en français.

## 📚 Sources des données

- Recettes : tables du jeu WoW Forever, [CMaNGOS](https://github.com/cmangos) et [QuestieDB](https://github.com/Questie/Questie).

---

## 🇬🇧 English

[🇫🇷 Français](#forevercraftatlas)

> Every profession recipe in **World of Warcraft Forever**, learned or not: how to learn it, what it costs, what it earns and the skill points it gives. **No dependencies.**

ForeverCraftAtlas gathers **every recipe of every profession** in a single window, even the ones your character doesn't know yet. For each one it tells you where to learn it, how much its reagents cost, how much the crafted item sells for, and how many skill points it will give you. Perfect for levelling a profession as cheaply as possible, or for finding what makes gold.

> The in-game interface is in French.

## ✨ Features

- **Every recipe of every profession**: Alchemy, Blacksmithing, Leatherworking, Tailoring, Engineering, Enchanting, Cooking, First Aid, Mining, Poisons. Your own professions' recipes are read in-game as soon as you open their window.
- **How to learn each recipe**: trainer (level and price read when you talk to them), or recipe scroll (its tooltip and where to find it: vendor, loot, quest, pickpocketing…).
- **Cost and profit** for each recipe, shown as `cost (+/- profit)`, with profit as a % of cost and per second of crafting.
- **Multiple crafts**: the cost of 10, 50 or 200 crafts, buying reagents from the cheapest auction house listings one by one.
- **Skill points** at your level (colour, chance of a skill-up), and a **simulated level** to plan a profession's levelling.
- **XP Road**: the fastest or cheapest path to level a profession, step by step.
- **Favorites** and **wishlist**: a shopping list for the auction house and vendors, then the purchases.
- **Filters and sorting**: learned / not learned, profession, crafted item type (gear by slot, weapons, potions…), required level, minimum profit, name search.
- **Minimap button**, settings page in Esc › Options › AddOns.

## 💰 Where prices come from

1. **ForeverCraftAtlas scans**: the "Scanner l'HDV" button (auction house open) reads every listing, and everything you browse at the auction house is recorded instantly.
2. **[ForeverExchange](https://github.com/)** (optional): when installed, its prices are used for items not yet scanned (minimum price, market value, 7- and 30-day averages, trend). A scan started by ForeverExchange is read by ForeverCraftAtlas at the same time: **one scan for both addons**.
3. **Vendors**: prices of reagents sold by NPCs, from the WoW Forever game tables.

No TradeSkillMaster, no Auctionator, no external library required.

## 📦 Installation

1. Download the latest release and unzip it.
2. Copy the `ForeverCraftAtlas` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Start the game (or type `/reload`).
4. Open each of your professions' windows once so the addon can read your recipes.

## ⌨️ Commands

| Command | Action |
| --- | --- |
| `/fca` or `/recettes` | Open / close the window |
| `/fca <name>` | Search for a recipe |
| `/fca options` | Open the settings |

Minimap button: **click** = window, **right-click** = settings, **drag** = move.

## ⚠️ Limitations

- Prices come **from your own scans** (and ForeverExchange's): the addon shares no data with other players.
- No WoW Forever addon knows actual sales: so there are **no sales per day and no profit per day**.
- Before your first visit to a trainer, their level and price are estimated from vanilla data.
- French-only interface.

## 📚 Data sources

- Recipes: WoW Forever game tables, [CMaNGOS](https://github.com/cmangos) and [QuestieDB](https://github.com/Questie/Questie).
