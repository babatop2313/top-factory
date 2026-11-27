---
description: Propose le design d'un écran (fiche + maquette HTML) dans docs/design/, à partir de la spec et du contrat d'API, puis attend ta validation.
argument-hint: <écran ou feature, ex. catalog-list>
---

Écran : $ARGUMENTS

1. Lis le skill `design`, `docs/design/design.json` et `docs/design/design-system.md`.
   - Un design **validé** existe déjà pour cet écran : dis-le et propose `/design-improve` à la place.
   - Outil de design du projet (bloc `design` de `.claude/stack.json`) : `claude-design` ou `figma` → l'écran est dessiné
     dans l'outil (lien du projet, ou lien propre à l'écran dans `design.json`) : il fait référence, `designer` le reporte
     au lieu de l'inventer ; s'il n'y est pas encore, dis-le-moi et attends. `factory` (ou bloc absent) → `designer` propose.
   - Pas de design system : `designer` le propose en même temps (il sera validé avec l'écran).
2. Trouve la spec (`docs/specs/`) et le contrat d'API (`docs/api/<feature>.md`) de la feature. Sans contrat d'API,
   l'écran peut quand même être conçu : les données seront à confirmer (dis-le).
3. Délègue à l'agent `designer` avec `<kit>`, `<frontend>`, l'identifiant d'écran, la spec, le contrat, l'outil de design
   et le lien (projet ou écran).
3 bis. Puis contrôle qualité Impeccable (skill `design`, « Contrôle qualité (Impeccable) » : corrections ordinaires appliquées,
   propositions critiques à côté de l'actuel ; s'il n'est pas installé, propose-le une fois).
4. Présente-moi : le chemin de la fiche et de la maquette, le résumé du design, le bilan du contrôle qualité (corrigé,
   proposé à comparer, écarté), les choix ouverts, et rappelle que je
   peux voir la maquette dans le tableau de bord (`/dashboard`, onglet Design du projet).
   **⏸ ARRÊT : attends ma validation.** Mes remarques repartent à `designer` (nouvelle proposition).
5. Après mon accord : statut `validé` dans `design.json`. Ne commite rien sans mon accord.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
