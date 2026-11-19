# Changelog

## 0.1.1

- **Bouton de la minicarte** avec le logo de la fenêtre (le parchemin) : clic pour ouvrir / fermer, clic droit pour les réglages, glisser pour le déplacer. Case « Bouton de la minicarte » dans les réglages pour le cacher.
- Correction : dans la colonne de gauche, « Niveau simulé » était replacé sur la liste des métiers (textes superposés, champ impossible à remplir). Il est revenu sous « Bénéfice plus de ».

## 0.1.0

- Première version : nouvelle version de CraftAtlas 3.22.0, **sans aucune dépendance**.
- **Plus de TradeSkillMaster ni d'Auctionator** : leur module de prix (`Libs\TSMPrices.lua`) est remplacé par `Libs\Prices.lua`, qui garde les relevés de l'hôtel des ventes faits en jeu (bouton « Scanner l'HDV », ce que tu parcours à l'HV, chaque offre des composants).
- **Compatible ForeverExchange** (facultatif) :
  - ses données sont lues telles quelles (`ForeverExchangeDB`, rien n'y est écrit) : prix minimum, valeur marché, moyennes 7 j / 30 j, quantité en vente, évolution sur 7 j ;
  - elles servent de prix quand un objet n'a pas encore été relevé, et pour « Achat sans relevé » (par défaut : moyenne sur 7 jours) ;
  - une analyse lancée par ForeverExchange (à l'ouverture de l'HV) est lue en même temps par ForeverCraftAtlas, et inversement : une seule analyse pour les deux ;
  - la fenêtre suit les analyses de ForeverExchange ; le bouton « Actualiser TSM » devient « ForeverExchange » (ouvre sa fenêtre).
- Retirés, faute de données sur WoW Forever : ventes par jour, taux de vente, bénéfice par jour et leurs filtres (« Ventes/jour minimum », « % de vente minimum »). Le bénéfice se lit en % du coût et par seconde.
- Sous chaque recette : la quantité en vente et l'évolution sur 7 jours (ForeverExchange) à la place des ventes par jour.
- Nouveaux noms : dossier et TOC `ForeverCraftAtlas`, sauvegarde `ForeverCraftAtlasDB`, commandes `/fca`, `/recettes`, `/forevercraftatlas`.
