---
description: Branche sur la vraie API un frontend développé avec des données simulées (feature ou endpoints précis), vérifie contre le backend et met à jour les statuts du design.
argument-hint: <feature> [endpoints]
---

Feature : $ARGUMENTS

1. Lis le contrat d'API `docs/api/<feature>.md`, la section « Données simulées » du skill `angular-conventions` et
   `docs/design/design.json` (écrans de la feature).
2. Vérifie que le backend expose les endpoints : contrôleurs présents dans `<backend>`, chemins et DTO conformes au
   contrat. Un écart de contrat (champ renommé, code d'erreur différent) : **⏸ ARRÊT**, présente-le ; c'est à moi de
   décider qui s'aligne (frontend, backend ou contrat).
3. Délègue à `frontend-dev` : retirer les données simulées de ces endpoints (le reste du mode simulé continue de
   fonctionner), adapter le service si le contrat a bougé, garder les jeux de données pour les tests.
4. Vérifications : `npx ng build`, `npm run lint`, `npx ng test --watch=false` dans `<frontend>` ; tests d'intégration du
   backend pour ces endpoints ; puis, si le backend tourne en local, un appel réel de chaque endpoint par le proxy.
5. Revue par `reviewer` (contrat respecté, plus aucune donnée simulée dans le build de production, erreurs du backend
   affichées). Statut des écrans concernés → `intégré` dans `design.json`.
6. **⏸ ARRÊT : présente-moi le verdict** et attends ma décision avant tout commit (`feat(<feature>): intégration de l'API`).

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
