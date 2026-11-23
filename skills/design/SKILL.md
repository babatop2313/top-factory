---
name: design
description: Design des écrans du projet — design system, fiches d'écran, maquettes HTML, registre docs/design/design.json, sources (factory, Claude Design, Figma) et cycle de vie (proposé → validé → implémenté → intégré). À charger avant de proposer, modifier ou implémenter un écran.
---

# Design des écrans

> Le design vit **dans le dépôt**, dans `docs/design/`, versionné avec le code. Claude Design et Figma sont des sources,
> référencées par leur lien ; ce qui fait foi pour l'implémentation est ce qui est **validé** dans `docs/design/`.
> `<frontend>` et `<kit>` sont annoncés au début de la session.

## Structure
```
docs/design/
  design.json            registre : design system, écrans, liens, statuts (format ci-dessous)
  design-system.md       couleurs, typographie, espacements, rayons, ombres, composants de base, ton des textes
  screens/<ecran>.md     fiche d'un écran (modèle ci-dessous)
  mockups/<ecran>.html   maquette autonome de l'écran (règles ci-dessous)
```
Identifiant d'écran : `kebab-case`, préfixé par la feature si utile (`catalog-list`, `catalog-book-form`, `auth-login`).

## Registre `docs/design/design.json`
```json
{
  "designSystem": { "status": "validé", "source": "factory", "link": "" },
  "screens": [
    { "id": "catalog-list", "title": "Catalogue", "feature": "catalog",
      "status": "validé", "source": "factory", "link": "",
      "spec": "screens/catalog-list.md", "mockup": "mockups/catalog-list.html", "updated": "2026-11-23" }
  ]
}
```
- `status` : `proposé` (attend la validation humaine) → `validé` (l'humain a dit oui) → `implémenté` (écran Angular
  écrit, données simulées ou API) → `intégré` (branché sur la vraie API). On ne saute pas `validé` : **aucun écran n'est
  implémenté sans design validé** (factory, Claude Design ou Figma).
- `source` : `factory` (proposé par l'agent `designer`), `claude-design` (créé dans Claude Design), `figma`.
- `link` : URL Claude Design ou Figma (frame précise de préférence). Jamais de jeton dans une URL.
- Écrit uniquement par les commandes design et par `/feature` (statuts) ; toujours JSON valide, trié par `feature` puis `id`.

## Design system (`design-system.md`)
Point de départ : la bibliothèque de l'option `front-ui` (profil `top` : PrimeNG, thème Aura, grille Bootstrap).
Le design system **précise** le thème, il ne le contredit pas :
- **Couleurs** : primaire, surfaces, texte, états (succès, avertissement, erreur, info), avec leur jeton PrimeNG
  (`--p-primary-color`…) ; contraste AA minimum (4,5:1 pour le texte).
- **Typographie** : familles, tailles (échelle), graisses ; **espacements** (échelle 4 px), **rayons**, **ombres**.
- **Composants de base** et leur usage : boutons (principal, secondaire, danger), champs, tableaux, toasts, dialogues,
  badges d'état ; ce qu'on n'utilise pas.
- **Ton** : français, vouvoiement ou tutoiement (choisi une fois), libellés d'action à l'infinitif, messages d'erreur
  qui disent quoi faire.

## Fiche d'écran (`screens/<ecran>.md`)
1. **But** : qui l'utilise (rôle), pour quoi faire, en une phrase.
2. **Accès** : route, rôle(s), point d'entrée (menu, bouton).
3. **Mise en page** : zones (en-tête, filtres, contenu, actions), grille et comportement responsive (mobile d'abord).
4. **Composants** : pour chaque zone, le composant de la bibliothèque (`p-table`, `p-inputtext`, `p-button`…).
5. **Données** : champs affichés, avec leur DTO du contrat d'API (`docs/api/<feature>.md`) ; tri, pagination, recherche.
6. **États** : chargement, vide (message et action), erreur (réseau, 403, 400 par champ), succès (toast).
7. **Interactions** : actions, confirmations, navigation, raccourcis clavier.
8. **Accessibilité** : libellés, focus, ordre de tabulation, contrastes, annonce des erreurs.
9. **Textes** : tous les libellés et messages, en français.

## Maquette (`mockups/<ecran>.html`)
- **Un seul fichier autonome** : HTML + CSS en ligne, **aucun script, aucune ressource externe** (ni CDN, ni police
  distante, ni image distante) — elle s'affiche dans le tableau de bord en mode isolé, sans JavaScript.
- Reproduit l'aspect de la bibliothèque `front-ui` avec les jetons du design system (variables CSS) : c'est une image
  fidèle, pas une implémentation ; aucune donnée réelle, des données fictives réalistes en français.
- Montre l'état principal et, en dessous, les états vide et erreur (sections titrées).
- Largeur desktop ; une section « mobile » (≈ 390 px) si la mise en page change.

## Sources externes
- **Claude Design** : l'humain crée ou affine le design dans Claude Design (dans Claude Code : `/design` ; le design
  system du code se partage avec `/design-sync`). Pour l'importer : enregistrer le lien (`/design-link`), puis reporter
  dans `docs/design/` la fiche et une maquette conforme aux règles ci-dessus, à partir de ce que l'humain fournit
  (fichiers exportés, captures, description) ; statut `validé` seulement si l'humain le confirme.
- **Figma** : lien de la frame dans `design.json`. Si le serveur MCP Figma est branché (il est en lecture), s'en servir
  pour lire la frame (mise en page, couleurs, textes) ; sinon, travailler à partir des exports fournis par l'humain.
  Ne jamais inventer ce que la maquette Figma ne montre pas : poser la question.

## Implémentation (pour `frontend-dev`)
Avant d'écrire un écran, dans cet ordre :
1. **L'écran existe déjà** dans `<frontend>` (éventuellement avec des données simulées) → ne refais pas l'interface :
   branche-la sur l'API (service HTTP, retrait des données simulées pour ces endpoints) ; statut → `intégré`.
2. **Un design validé existe** (`design.json`, statut `validé`) → implémente **fidèlement** la fiche et la maquette
   (mise en page, composants, états, textes) ; un écart nécessaire se signale, il ne se décide pas seul ; statut →
   `implémenté` (ou `intégré` si l'API réelle est branchée).
3. **Aucun design validé** → arrête-toi : le design passe d'abord par l'agent `designer` et la validation humaine.
