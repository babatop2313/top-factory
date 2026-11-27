---
description: Prépare le design au début du projet, avant les features — design system et tout ou partie des écrans prévus — avec la factory, Claude Design ou Figma, validé écran par écran.
argument-hint: [périmètre, ex. « design system seul » ou « écrans du catalogue et des prêts »]
---

Périmètre demandé : $ARGUMENTS

Lis le skill `design` (en particulier « Outil de design du projet » et « Design en début de projet »), l'option
`front-ui` (skill `conventions`), `docs/design/design.json` et `docs/design/design-system.md` s'ils existent.
Si `<frontend>` vaut « aucun », signale que le frontend n'existe pas encore : le design peut quand même se préparer
(il servira à `/add-frontend` puis aux features).

1. **Constat** (sans rien écrire) : outil de design du projet (bloc `design` de `.claude/stack.json` : designer de la
   factory, Claude Design ou Figma, et son lien), design system (absent, proposé, validé), écrans déjà au registre et
   leur statut, specs existantes (`docs/specs/`) et écrans déjà présents dans `<frontend>`.
2. **Liste des écrans prévus** : à partir de mon périmètre, des specs et de ce que je décris, propose une liste
   (identifiant `kebab-case`, titre, feature, rôle, but en une ligne), regroupée par feature, et ce que tu recommandes
   de faire maintenant (par exemple : le design system et les écrans centraux ; les écrans secondaires suivront le
   design system). **⏸ ARRÊTE-TOI** : je choisis ce qui se fait maintenant — design system seul, une partie des écrans
   ou tous — et je corrige la liste.
3. **Registre** : inscris dans `docs/design/design.json` les écrans retenus (statut `proposé`, feature, source de
   l'outil du projet), même ceux qui ne seront dessinés que plus tard : le tableau de bord les montre.
4. **Design**, selon l'outil du projet :
   - **designer de la factory** → agent `designer` avec `<kit>`, `<frontend>`, la liste retenue, les specs : design system
     d'abord s'il n'est pas validé, puis fiche et maquette de chaque écran. La section **Données** des fiches reste
     **provisoire** (« à confirmer par le contrat ») tant que le contrat d'API de la feature n'existe pas ;
   - **Claude Design ou Figma** → rappelle-moi le lien du projet (sinon `/design-link <url>`) : je dessine dans l'outil ;
     quand je te dis qu'un écran est prêt, agent `designer` pour le reporter dans `docs/design/` (skill `design`,
     « Sources externes »).
   Chaque lot passe par le contrôle qualité Impeccable (skill `design`, « Contrôle qualité (Impeccable) » : corrections ordinaires appliquées,
   propositions critiques à côté de l'actuel ; s'il n'est pas installé, propose-le une fois).
   Présente-moi les écrans par lots (design system, puis par feature), visibles dans `/dashboard`, onglet Design.
   **⏸ ARRÊTE-TOI et ATTENDS** ma validation de chaque lot ; mes remarques repartent à `designer`. Après mon accord :
   statut `validé` (et date `updated`).
5. **Bilan** : écrans validés, écrans restant à dessiner (avec la commande pour les faire plus tard :
   `/design-screen <écran>`), et rappel : quand une feature arrive, `/feature` retrouve ces écrans validés et l'architecte
   aligne le contrat d'API sur eux (tout écart se tranche avec moi). Ne commite rien sans mon accord.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
