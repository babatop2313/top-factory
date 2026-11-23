---
description: Améliore le design d'un écran existant (ou du design system) selon ta demande, dans docs/design/, puis attend ta validation.
argument-hint: <écran> <demande>
---

Demande : $ARGUMENTS

1. Lis le skill `design` et `docs/design/design.json`. Trouve l'écran visé (ou le design system). S'il n'existe pas,
   propose `/design-screen`.
2. Délègue à l'agent `designer` : appliquer la demande sur la fiche et la maquette, en gardant la cohérence avec le
   design system ; statut → `proposé`. Si l'écran était `implémenté` ou `intégré`, l'agent liste ce qu'il faudra changer
   dans le code (fichiers, composants), sans y toucher.
3. Présente-moi : l'avant / après (résumé), les fichiers modifiés, l'impact sur le code.
   **⏸ ARRÊT : attends ma validation.**
4. Après mon accord : statut `validé`. Si du code est concerné, propose la suite : `/feature` (évolution) ou `/fix-bug`
   (défaut visuel), où `frontend-dev` appliquera le design validé. Ne commite rien sans mon accord.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
