---
name: design
description: Design des écrans du projet — outil de design (bloc design de .claude/stack.json), design system, fiches d'écran, maquettes HTML, registre docs/design/design.json, sources (factory, Claude Design, Figma, aucun) et cycle de vie (proposé → validé → implémenté → intégré). À charger avant de proposer, modifier ou implémenter un écran.
---

# Design des écrans

> Le design vit **dans le dépôt**, dans `docs/design/`, versionné avec le code. Claude Design et Figma sont des sources,
> référencées par leur lien ; ce qui fait foi pour l'implémentation est ce qui est **validé** dans `docs/design/`.
> **Passer par le design est un choix de l'humain**, feature par feature : la factory recommande, elle n'impose pas.
> `<frontend>` et `<kit>` sont annoncés au début de la session.

## Outil de design du projet (`.claude/stack.json`)
L'outil et son lien s'enregistrent **une fois** dans le bloc `design` de `.claude/stack.json` (versionné : le lien reste
valable d'une session à l'autre, il est annoncé au début de chaque session) :
```json
"design": { "tool": "claude-design", "link": "https://claude.ai/…" }
```
- `tool` : `factory` (l'agent `designer` propose les écrans ; valeur par défaut, bloc absent), `claude-design` ou `figma`
  (l'humain dessine dans l'outil, l'agent `designer` en tire la fiche et la maquette du dépôt).
- `link` : lien du projet Claude Design ou du fichier Figma ; `https://` uniquement, jamais de jeton dans l'URL.
- Écrit par `/design-link` (avec l'accord de l'humain : `stack.json` est en permission `ask`), jamais « en passant ».
- Si `.design-sync/config.json` existe (projet Claude Design épinglé par la commande `/design-sync` de Claude Code), il
  est **lu seulement** : son lien peut être proposé à l'humain pour `/design-link`. La factory ne l'écrit jamais.

## Structure
```
docs/design/
  design.json            registre : design system, écrans, liens, statuts (format ci-dessous)
  design-system.md       couleurs, typographie, espacements, rayons, ombres, composants de base, ton des textes
  screens/<ecran>.md     fiche d'un écran (modèle ci-dessous)
  mockups/<ecran>.html   maquette autonome de l'écran (règles ci-dessous)
  mockups/<ecran>.proposition.html   proposition critique à comparer (contrôle qualité), tant que l'humain n'a pas choisi
```
Identifiant d'écran : `kebab-case`, préfixé par la feature si utile (`catalog-list`, `catalog-book-form`, `auth-login`).

## Registre `docs/design/design.json`
```json
{
  "designSystem": { "status": "validé", "source": "factory", "link": "" },
  "screens": [
    { "id": "catalog-list", "title": "Catalogue", "feature": "catalog",
      "status": "validé", "source": "factory", "link": "",
      "spec": "screens/catalog-list.md", "mockup": "mockups/catalog-list.html", "updated": "2026-11-23",
      "proposal": { "mockup": "mockups/catalog-list.proposition.html", "summary": "Mode sombre conçu : …", "by": "impeccable" } }
  ]
}
```
- `status` : `proposé` (attend la validation humaine) → `validé` (l'humain a dit oui) → `implémenté` (écran Angular
  écrit, données simulées) → `intégré` (branché sur la vraie API). Un design **proposé** n'est jamais implémenté ; un
  écran sans design n'est implémenté que si l'humain l'a choisi (source `aucun`, inscrit directement `implémenté`).
- `source` : `factory` (proposé par l'agent `designer`), `claude-design` (créé dans Claude Design), `figma`, ou `aucun`
  (l'humain a choisi de coder l'écran sans design : il reste visible comme tel dans le tableau de bord).
- `link` (facultatif) : lien **d'un écran précis** (frame Figma, artboard), seulement s'il diffère du lien du projet
  (`stack.json`). Jamais de jeton dans une URL.
- `proposal` (facultatif) : proposition **critique** en attente du choix de l'humain (contrôle qualité ci-dessous) ;
  retiré dès qu'il a choisi. Aussi possible sur `designSystem` (`"proposal": { "spec": "design-system.proposition.md", … }`).
- Écrit uniquement par les commandes design et par `/feature` (statuts) ; toujours JSON valide, trié par `feature` puis `id`.

## Design system (`design-system.md`)
Point de départ : la bibliothèque de l'option `front-ui` (profil `top` : PrimeNG, thème Aura, grille Bootstrap).
Le design system **précise** le thème, il ne le contredit pas :
- **Couleurs** : primaire, surfaces, texte, états (succès, avertissement, erreur, info), avec leur jeton PrimeNG
  (`--p-primary-color`…) ; contraste AA minimum (4,5:1 pour le texte).
- **Typographie** : familles, tailles (échelle), graisses ; **espacements** (échelle 4 px), **rayons**, **ombres**.
- **Composants de base** et leur usage : boutons (principal, secondaire, danger), champs, tableaux, toasts, dialogues,
  badges d'état ; ce qu'on n'utilise pas.
- **Thème clair et sombre** (les deux sont conçus) : pour chaque jeton, sa valeur en clair **et** en sombre, et le
  contraste vérifié dans les deux ; fond et texte de page sur des jetons qui suivent le thème ; bascule Auto / Clair /
  Sombre dans l'en-tête (skill `angular-conventions`, « Thème clair et sombre »).
- **Accessibilité de base** : focus visible, action principale de 44 px au toucher sur mobile, mouvement réduit.
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
- Montre l'état principal et, en dessous, les états vide et erreur (sections titrées), puis l'état principal **en
  mode sombre** (section « Sombre » : même structure, variables du thème sombre redéfinies sur son conteneur).
- Largeur desktop ; une section « mobile » (≈ 390 px) si la mise en page change.

## Sources externes
- **Claude Design** : l'humain crée ou affine le design dans Claude Design (lien du projet dans `stack.json`). Pour le
  reporter dans `docs/design/` (fiche + maquette conformes aux règles ci-dessus) :
  1. si le serveur MCP de Claude Design est branché (accès donné par l'humain avec `/design-consent`), s'en servir pour
     récupérer l'écran (artboard) — c'est un **plus**, jamais un prérequis ;
  2. sinon, ou s'il échoue, travailler à partir de ce que l'humain fournit : export HTML ou zip, « Handoff to Claude
     Code », captures, description.
  Le design system du code peut être partagé vers Claude Design par `/design-sync` (commande que **seul l'humain** lance ;
  elle vise les design systems React). Statut `validé` seulement si l'humain le confirme.
- **Figma** : lien du fichier dans `stack.json`, d'une frame dans `design.json`. Si le serveur MCP Figma est branché (il
  est en lecture), s'en servir pour lire la frame (mise en page, couleurs, textes) ; sinon, travailler à partir des
  exports fournis par l'humain. Ne jamais inventer ce que la maquette ne montre pas : poser la question.

## Contrôle qualité (Impeccable)
[Impeccable](https://impeccable.style) (plugin Claude Code de Paul Bakaus, licence Apache 2.0) vérifie et corrige la
qualité visuelle : typographie, couleurs et contraste, espacements, mouvement, interactions, adaptation, textes.
- **Installé ?** Le skill `impeccable` (commande `/impeccable`) est disponible dans la session. **Sinon**, propose-le
  une fois à l'humain, sans l'imposer, avec les commandes :
  `/plugin marketplace add pbakaus/impeccable` puis `/plugin install impeccable@impeccable` ; le process continue sans
  lui (ligne « Contrôle qualité : Impeccable non installé » dans le bilan).
- **Contexte à lui donner** : la référence de design est `docs/design/design-system.md` et les fiches de
  `docs/design/screens/` (pas de `DESIGN.md` séparé) ; la bibliothèque `front-ui` et ses options sont des choix de
  l'humain.
- **Quand** : par l'agent principal, **avant de présenter** un design (après `designer`) et **avant la revue** des écrans
  codés (après `frontend-dev`) : `/impeccable critique` ou `/impeccable audit` sur la maquette ou l'écran (en mode `mock`
  pour un écran codé), et `npx impeccable detect <fichiers> --fast` (détecteur sans IA).
- **Il peut tout toucher, en deux niveaux** :
  - **ordinaire** (contraste, espacements, typographie, états oubliés, textes, mouvement réduit, taille au toucher…) :
    corrigé directement (par `designer` dans la maquette, par `frontend-dev` dans le code), puis listé ;
  - **critique** : tout ce qui touche un **choix déjà fait** — la bibliothèque ou la grille (`front-ui`), un design
    **validé** ou les jetons du design system validé, la **structure** d'un écran (mise en page, parcours, action ou
    état ajouté ou retiré), un mode de thème (par exemple concevoir ou refondre le mode sombre). Jamais appliqué en
    silence : `designer` écrit la proposition **à côté** de l'actuel (`mockups/<ecran>.proposition.html`, résumé et
    raison dans `design.json` → `proposal`), l'actuel reste intact, et l'humain compare dans le tableau de bord (onglet
    Design) : **« Garder l'actuel »** (proposition supprimée) ou **« Adopter la proposition »** (elle remplace
    l'actuelle ; l'ancienne reste dans l'historique Git). Dans le code, un changement critique repasse toujours par une
    proposition de design ; le code n'implémente que la version choisie.
- **Bilan présenté à l'humain** : corrigé (ordinaire), proposé (critique, à comparer), écarté (avec la raison : contraire
  à un choix de l'humain, faux positif). Les alertes restantes du détecteur sont mineures dans la revue, jamais bloquantes.

## Design en début de projet
`/design-project` prépare tout ou partie du design avant les features : design system, liste d'écrans prévus (registre
`design.json`, feature indiquée), puis fiches et maquettes, validées écran par écran. Sans contrat d'API, la section
**Données** d'une fiche est **provisoire** (marquée « à confirmer par le contrat ») : quand la feature arrive, l'architecte
aligne le contrat sur l'écran validé et signale tout écart, qui se tranche avec l'humain.

## Implémentation (pour `frontend-dev`)
Avant d'écrire un écran, dans cet ordre :
1. **L'écran existe déjà** dans `<frontend>` (éventuellement avec des données simulées) → ne refais pas l'interface :
   branche-la sur l'API (service HTTP, retrait des données simulées pour ces endpoints) ; statut → `intégré`.
2. **Un design validé existe** (`design.json`, statut `validé`) → implémente **fidèlement** la fiche et la maquette
   (mise en page, composants, états, textes) ; un écart nécessaire se signale, il ne se décide pas seul ; statut →
   `implémenté` (ou `intégré` si l'API réelle est branchée).
3. **L'humain a choisi « sans design »** pour cet écran (transmis par l'orchestrateur) → implémente à partir de la spec,
   du design system (`design-system.md` s'il existe) et des écrans existants, avec la bibliothèque `front-ui` ; inscris
   l'écran dans `design.json` (source `aucun`, statut `implémenté` ou `intégré`).
4. **Sinon** (design `proposé`, ou aucun choix transmis) → arrête-toi et signale-le : c'est à l'humain de choisir.
