---
description: Propose le design d'un écran (fiche + maquette HTML) dans docs/design/, à partir de la spec et du contrat d'API, puis attend ta validation.
argument-hint: <écran ou feature, ex. catalog-list>
---

Écran : $ARGUMENTS

1. Lis le skill `design`, `docs/design/design.json` et `docs/design/design-system.md`.
   - Un design **validé** existe déjà pour cet écran : dis-le et propose `/design-improve` à la place.
   - Un lien Figma ou Claude Design est enregistré pour cet écran : il fait référence pour l'agent.
   - Pas de design system : `designer` le propose en même temps (il sera validé avec l'écran).
2. Trouve la spec (`docs/specs/`) et le contrat d'API (`docs/api/<feature>.md`) de la feature. Sans contrat d'API,
   l'écran peut quand même être conçu : les données seront à confirmer (dis-le).
3. Délègue à l'agent `designer` avec `<kit>`, `<frontend>`, l'identifiant d'écran, la spec, le contrat, le lien éventuel.
4. Présente-moi : le chemin de la fiche et de la maquette, le résumé du design, les choix ouverts, et rappelle que je
   peux voir la maquette dans le tableau de bord (`/dashboard`, onglet Design du projet).
   **⏸ ARRÊT : attends ma validation.** Mes remarques repartent à `designer` (nouvelle proposition).
5. Après mon accord : statut `validé` dans `design.json`. Ne commite rien sans mon accord.
