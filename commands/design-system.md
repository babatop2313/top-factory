---
description: Définit ou fait évoluer le design system du projet (couleurs, typographie, espacements, composants de base, ton) dans docs/design/, puis attend ta validation.
argument-hint: [demande, ex. « couleur primaire plus sobre »]
---

Demande : $ARGUMENTS

1. Lis le skill `design` et l'option `front-ui` (skill `conventions`). Lis `docs/design/design.json` et
   `docs/design/design-system.md` s'ils existent.
2. Délègue à l'agent `designer` : créer `docs/design/design-system.md` s'il n'existe pas, sinon appliquer la demande ;
   statut du design system dans `design.json` → `proposé`. Transmets-lui `<kit>`, `<frontend>` et la demande.
3. Présente-moi le résultat : jetons (couleurs avec contraste, typographie, espacements), composants de base, ton,
   et les écrans déjà validés que la modification pourrait toucher.
   **⏸ ARRÊT : attends ma validation.** Mes remarques repartent à `designer`.
4. Après mon accord : statut `validé` dans `design.json` (et date `updated`). Rappelle que les écrans implémentés ne
   changent pas tout seuls : une mise à jour d'écran passe par `/design-improve` puis `/feature` ou `/fix-bug`.

Si le projet a un design system dans Claude Design, propose `/design-sync` (commande de Claude Code) pour partager
celui du code, ou `/design-link <url>` pour référencer celui de Claude Design.
Ne commite rien sans mon accord.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
