---
description: Définit ou fait évoluer le design system du projet (couleurs, typographie, espacements, composants de base, ton) dans docs/design/, puis attend ta validation.
argument-hint: [demande, ex. « couleur primaire plus sobre »]
---

Demande : $ARGUMENTS

1. Lis le skill `design` et l'option `front-ui` (skill `conventions`). Lis `docs/design/design.json` et
   `docs/design/design-system.md` s'ils existent.
2. Délègue à l'agent `designer` : créer `docs/design/design-system.md` s'il n'existe pas, sinon appliquer la demande ;
   statut du design system dans `design.json` → `proposé`. Transmets-lui `<kit>`, `<frontend>` et la demande.
   Le design system définit les **deux thèmes** (clair et sombre). Si `<frontend>` existe déjà et qu'aucun design system
   n'est écrit, `designer` part de ce qui est en place (thème, jetons, composants utilisés) au lieu d'inventer.
   Puis contrôle qualité Impeccable (skill `design`, « Contrôle qualité (Impeccable) » : corrections ordinaires appliquées,
   propositions critiques à côté de l'actuel ; s'il n'est pas installé, propose-le une fois).
3. Présente-moi le résultat : jetons en clair et en sombre (couleurs avec contraste), typographie, espacements, composants de base, ton,
   et les écrans déjà validés que la modification pourrait toucher.
   **⏸ ARRÊT : attends ma validation.** Mes remarques repartent à `designer`.
4. Après mon accord : statut `validé` dans `design.json` (et date `updated`). Rappelle que les écrans implémentés ne
   changent pas tout seuls : une mise à jour d'écran passe par `/design-improve` puis `/feature` ou `/fix-bug`.

Outil de design du projet (bloc `design` de `.claude/stack.json`) : avec `claude-design` ou `figma`, le design system
se définit dans l'outil ; `designer` le reporte dans `design-system.md` à partir du lien et de ce que je fournis, au lieu
de l'inventer. Pour partager celui du code vers Claude Design : `/design-sync` (commande de Claude Code, que je lance
moi-même ; design systems React). Pas encore de lien enregistré : `/design-link <url>`.
Ne commite rien sans mon accord.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
