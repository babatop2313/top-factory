---
description: Orchestre la factory de bout en bout pour une nouvelle fonctionnalité (spec → plan et contrat d'API → design → code → tests → revue), en backend, en frontend ou les deux
argument-hint: <description de la fonctionnalité> [--back | --front]
---

Fonctionnalité demandée : $ARGUMENTS

Tu es l'orchestrateur de la software factory. Délègue chaque étape au sous-agent indiqué et ne code pas toi-même.
**Ne passe jamais à l'étape suivante tant que l'agent de l'étape en cours n'a pas rendu son résultat**,
y compris quand il tourne en arrière-plan.
Dans chaque délégation, indique à l'agent le chemin de `<kit>`, les dossiers `<backend>` et `<frontend>` (annoncés au
début de la session) et le chemin de la référence d'architecture active : un agent ne reçoit pas le message de début de session.

0. **Architecture et périmètre** : lis `.claude/factory.json` avec l'outil Read et annonce-moi l'architecture du projet.
   Si le fichier est absent ou si la référence correspondante n'existe pas, arrête-toi.
   Transmets ce nom d'architecture à chaque agent.
   **Périmètre** : `--back` (backend seul), `--front` (frontend seul, sur le contrat d'API et des données simulées :
   équipe frontend qui avance sans le backend) ou, par défaut, les deux. Sans option et si la feature a une interface,
   demande-moi le périmètre. Une spec ou un contrat déjà écrits par l'autre équipe se **réutilisent** (étapes 2 et 3 :
   relis-les et demande-moi s'ils sont toujours valables au lieu de les réécrire).
1. **Point de départ** : lis `baseBranch` dans `.claude/factory.json` (`develop` s'il est absent), puis vérifie avec Git,
   **sans rien modifier** :
   - `git status --porcelain` est vide. Sinon, liste les fichiers modifiés ou non suivis et **⏸ ARRÊTE-TOI** :
     ils suivraient la nouvelle branche. C'est à moi de les commiter ailleurs, de les mettre de côté ou de les annuler ;
   - la branche courante est `baseBranch`. Si ce n'est pas le cas, indique-la et **⏸ ARRÊTE-TOI** :
     je décide s'il faut partir d'elle (feature qui dépend d'une autre) ou revenir sur `baseBranch` ;
   - `git fetch origin <baseBranch>` puis `git rev-list --count HEAD..origin/<baseBranch>` vaut `0`.
     Sinon, la branche locale est en retard : **⏸ ARRÊTE-TOI** et propose `git pull`. Si le fetch échoue (pas de dépôt distant,
     pas de réseau), signale-le et demande-moi si l'on continue.
   Tu ne fais jamais toi-même de `pull`, `stash`, `reset` ou `checkout` d'une autre branche pour « corriger » le point de départ.
   Si tout est bon, crée la branche `feature/<slug>` (`git checkout -b feature/<slug>`).
2. **Spec** → agent `spec-writer`, qui écrit `docs/specs/<slug>.md`.
   Présente-moi le chemin de la spec et les questions ouvertes, puis **⏸ ARRÊTE-TOI et ATTENDS** mes réponses et ma validation.
   Reporte mes réponses dans la spec (section « Décisions ») avant de continuer.
3. **Plan et contrat d'API** → agent `architect` avec le chemin de la spec. Il rend le plan et, si la feature expose ou
   consomme des endpoints, le **contrat d'API** (chemins, méthodes, DTO, codes d'erreur, rôles, exemples). Présente-moi
   le plan et **⏸ ARRÊTE-TOI et ATTENDS** ma validation explicite. Une fois validé, enregistre le plan **et mes décisions**
   dans `docs/specs/<slug>-plan.md` et le contrat dans `docs/api/<slug>.md` (jamais dans un dossier temporaire) : c'est
   ce que tu transmets aux agents suivants. Le contrat est la référence commune du backend et du frontend.
3 bis. **Design** (périmètre frontend ou complet, si la feature a une interface) : lis `docs/design/design.json`
   (skill `design`). Pour chaque écran de la feature :
   - écran **déjà présent** dans `<frontend>` → pas de design à faire : `frontend-dev` ne fera que l'intégration de l'API ;
   - design **validé** (factory, Claude Design ou Figma) → il fait référence ;
   - sinon → agent `designer` (fiche + maquette dans `docs/design/`, statut `proposé`) ; présente-moi les écrans
     (visibles dans `/dashboard`, onglet Design) et **⏸ ARRÊTE-TOI et ATTENDS** ma validation ; reporte-la
     (statut `validé`) avant de continuer.
4. **Implémentation** :
   - (périmètre backend ou complet) agent `backend-dev` avec `docs/specs/<slug>-plan.md` (partie backend) et le contrat,
     dans l'ordre d'implémentation de la référence ; il implémente et compile, **il n'écrit pas les tests** ;
   - (périmètre frontend ou complet) agent `frontend-dev` avec le plan, le contrat, les écrans validés et leur statut
     (skill `design`, section Implémentation). En périmètre frontend seul, ou si le backend n'est pas encore prêt, il
     travaille sur des **données simulées** conformes au contrat (skill `angular-conventions`) ; le branchement sur la
     vraie API se fera par `/integrate <slug>`. Il met à jour le statut des écrans (`implémenté` ou `intégré`).
     Si la feature a une interface mais que `<frontend>` vaut « aucun », arrête-toi à l'étape du plan et propose
     `/add-frontend` avant de continuer.
5. **Tests** → agent `test-writer` avec la spec, le plan et la liste des fichiers produits.
   Il écrit **tous** les tests, couche par couche, selon la section « Tests par couche » de la référence, et les exécute.
   S'il détecte un bug dans le code de production, renvoie-le à `backend-dev`, puis relance `test-writer`.
6. **Revue** → agent `reviewer`. S'il y a des remarques BLOQUANT ou MAJEUR, renvoie-les à l'agent dev concerné, puis relance la revue.
   Maximum 2 boucles ; au-delà, arrête-toi et fais-moi un point.
7. **Verdict → ⏸ ARRÊT** : présente-moi le verdict de la revue (points bloquants, majeurs, mineurs, suggestions),
   le nombre de tests et les écarts au plan. **Attends ma décision avant tout commit** : je peux demander des corrections
   (second passage par les agents concernés, puis revue rapide) ou valider tel quel.
8. **Clôture**, après mon accord : commit au format Conventional Commits (code, tests, spec, plan, contrat et design),
   puis donne-moi un résumé :
   architecture appliquée, fichiers modifiés par couche, tests (passés/échoués), verdict de la revue,
   et la commande pour pousser la branche.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi
(règle « Attendre l'humain ») : c'est elle qui me prévient et qui affiche le panneau de réponse du tableau de bord.

Ne pousse rien et n'ouvre pas de PR/MR sans mon accord.
