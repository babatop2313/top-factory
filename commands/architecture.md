---
description: Schéma d'architecture global du projet (Mermaid), proposé par l'architecte à partir des choix du projet, visible dans le tableau de bord (onglet Architecture) ; sert aussi à le mettre à jour ou à demander une modification.
argument-hint: [modification souhaitée, ex. « ajouter le service de paiement »]
---

Demande : $ARGUMENTS

Délègue à l'agent `architect` (avec `<kit>`, `<backend>`, `<frontend>` et l'architecture de `.claude/factory.json`) la
création ou la mise à jour de **`docs/architecture/overview.md`**, selon la section « Schéma d'architecture global » de
ses instructions. L'architecte ne modifie aucun fichier : il rend le document complet, que **tu écris** toi-même dans
`docs/architecture/overview.md` (statut `proposé`) pour qu'il s'affiche dans le tableau de bord avant ma validation.

1. **Ce qu'il lit** (sans rien écrire) : `.claude/factory.json` (architecture, dossiers), `.claude/stack.json` (profil,
   intégrations et leurs modules, serveur MCP, outil de design), `CLAUDE.md` (contexte, modules prévus), le code
   existant (modules réels du backend, features du frontend, migrations) et `docs/architecture/overview.md` s'il existe.
2. **Ce qu'il propose** :
   - sans `overview.md` : le schéma global à partir de ces choix, même si le code n'existe pas encore ;
   - avec `overview.md` et une demande (`$ARGUMENTS`) : la modification demandée ;
   - avec `overview.md` sans demande : la mise à jour qui aligne le schéma sur le projet réel (intégration ajoutée,
     nouveau module, frontend créé…), en listant les écarts trouvés.
3. **Statut** : `proposé` (première ligne du document : `> Statut : proposé — <date>`). Présente-moi le schéma (il s'affiche dans `/dashboard`, onglet **Architecture** du projet),
   ce qui change par rapport à la version précédente, et **⏸ ARRÊTE-TOI** jusqu'à ma validation. Mes remarques
   repartent à l'architecte. Après mon accord : statut `validé — <date>` et une ligne dans l'historique du document.

Ne commite rien sans mon accord (fichier ajouté seul : `git add -- docs/architecture/overview.md`).
À l'arrêt, termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
