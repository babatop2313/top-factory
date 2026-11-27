---
description: Orchestre la factory de bout en bout pour une nouvelle fonctionnalité (spec → plan et contrat d'API → design au choix → code, tests et revue par partie ou ensemble), en backend, en frontend ou les deux ; --resume reprend la partie restante
argument-hint: <description de la fonctionnalité> [--back | --front]  ·  --resume <slug> [--back | --front]
---

Fonctionnalité demandée : $ARGUMENTS

Tu es l'orchestrateur de la software factory. Délègue chaque étape au sous-agent indiqué et ne code pas toi-même.
**Ne passe jamais à l'étape suivante tant que l'agent de l'étape en cours n'a pas rendu son résultat**,
y compris quand il tourne en arrière-plan.
Dans chaque délégation, indique à l'agent le chemin de `<kit>`, les dossiers `<backend>` et `<frontend>` (annoncés au
début de la session) et le chemin de la référence d'architecture active : un agent ne reçoit pas le message de début de session.

0. **Architecture, périmètre et reprise** : lis `.claude/factory.json` avec l'outil Read et annonce-moi l'architecture du
   projet. Si le fichier est absent ou si la référence correspondante n'existe pas, arrête-toi.
   Transmets ce nom d'architecture à chaque agent.
   - **Périmètre** : `--back` (backend seul), `--front` (frontend seul, sur le contrat d'API et des données simulées :
     équipe frontend qui avance sans le backend) ou, par défaut, les deux. Sans option et si la feature a une interface,
     demande-moi le périmètre. Une spec ou un contrat déjà écrits par l'autre équipe se **réutilisent** (étapes 2 et 3 :
     relis-les et demande-moi s'ils sont toujours valables au lieu de les réécrire).
   - **Reprise** (`--resume <slug>`) : une partie de la feature est déjà faite. Lis `docs/specs/<slug>.md`,
     `docs/specs/<slug>-plan.md` (section **« Avancement »**), `docs/api/<slug>.md` et le design (`docs/design/design.json`).
     S'ils sont absents, arrête-toi. Annonce-moi ce qui est fait et ce qui reste (la partie indiquée par `--back` /
     `--front`, sinon celle qui reste) ; **ne refais ni la spec ni le plan**. Puis le point de départ en mode reprise
     (étape 1) et directement l'étape 4 (design, si la partie restante est le frontend) et l'étape 5 pour cette partie.
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
   **En reprise** : si la première partie est **déjà fusionnée** dans `origin/<baseBranch>` (son commit en est un
   ancêtre : `git merge-base --is-ancestor <commit> origin/<baseBranch>`), mêmes vérifications, puis nouvelle branche
   `feature/<slug>-front` (ou `-back`) depuis `baseBranch` à jour. Si elle **n'est pas encore fusionnée**, dis-le et
   **⏸ ARRÊTE-TOI** : je choisis entre continuer sur `feature/<slug>` ou attendre la fusion.
2. **Spec** → agent `spec-writer`, qui écrit `docs/specs/<slug>.md`.
   Présente-moi le chemin de la spec et les questions ouvertes, puis **⏸ ARRÊTE-TOI et ATTENDS** mes réponses et ma validation.
   Reporte mes réponses dans la spec (section « Décisions ») avant de continuer.
3. **Plan, contrat d'API et ordre du code** → agent `architect` avec le chemin de la spec. Il rend le plan et, si la
   feature expose ou consomme des endpoints, le **contrat d'API** (chemins, méthodes, DTO, codes d'erreur, rôles,
   exemples). Si des écrans de la feature ont déjà un design validé (`/design-project`), transmets-les : le contrat
   s'aligne sur eux et l'architecte signale tout écart.
   Présente-moi le plan et, si le périmètre comprend backend **et** frontend, demande-moi l'**ordre du code** :
   - **les deux ensemble** : backend et frontend codés, testés et revus en une fois (un verdict, un commit) ;
   - **backend d'abord** : la partie backend va jusqu'à son commit ; je peux tester l'API réelle avant le frontend ;
   - **frontend d'abord** : la partie frontend va jusqu'à son commit, sur des données simulées conformes au contrat.
   **⏸ ARRÊTE-TOI et ATTENDS** ma validation du plan (et mon choix d'ordre). Une fois validé, enregistre le plan **et mes
   décisions** dans `docs/specs/<slug>-plan.md` et le contrat dans `docs/api/<slug>.md` (jamais dans un dossier
   temporaire) : c'est ce que tu transmets aux agents suivants. Le contrat est la référence commune du backend et du
   frontend. Termine le plan par la section :
   ```
   ## Avancement
   Ordre : <les deux ensemble | backend d'abord | frontend d'abord>
   | Partie | État | Branche |
   |---|---|---|
   | Backend | à faire | feature/<slug> |
   | Frontend | à faire | — |
   Design : <rempli à l'étape 4>
   ```
   (une seule ligne si le périmètre est `--back` ou `--front`). Tu la tiens à jour à chaque étape (`en cours`,
   `terminé — <date>`) : c'est elle que lit `--resume`, y compris sur le poste d'un autre développeur.
4. **Design — facultatif, à ton choix** (avant de coder une partie frontend qui a une interface). Ne lance **pas** le
   designer d'office. Vérifie d'abord, sans rien écrire (skill `design`) :
   - les écrans de la feature **déjà présents** dans `<frontend>` (seule l'intégration de l'API sera à faire) ;
   - ceux qui ont un design **validé** dans `docs/design/design.json` (`/design-project`, Claude Design, Figma) ;
   - l'outil de design du projet (bloc `design` de `.claude/stack.json`) et son lien.
   Présente-moi ce constat écran par écran, avec **ta recommandation** (par exemple : « 2 écrans sans design ; je
   recommande de passer par le design pour la liste, nouvel écran central ; le dialogue peut suivre le design system »),
   puis **⏸ ARRÊTE-TOI** : pour les écrans sans design validé, je choisis
   - **designer de la factory** → agent `designer` (fiche + maquette, statut `proposé`) ; écrans visibles dans
     `/dashboard`, onglet Design ; **⏸ ARRÊTE-TOI et ATTENDS** ma validation, puis statut `validé` ;
   - **design externe** (Claude Design ou Figma, lien de `stack.json`, sinon `/design-link`) → je dessine dans l'outil ;
     quand je te le dis, agent `designer` pour le reporter dans `docs/design/`, puis ma validation comme ci-dessus ;
   - **sans design** → `frontend-dev` code à partir de la spec, du design system et des écrans existants (source
     `aucun` dans `design.json`).
   Reporte mes choix dans la ligne « Design » de l'Avancement. Les écrans déjà présents ou validés ne demandent rien.
5. **Code, tests et revue** — pour chaque partie, dans l'ordre choisi (ou les deux ensemble) :
   a. **Implémentation** :
      - partie backend : agent `backend-dev` avec `docs/specs/<slug>-plan.md` (partie backend) et le contrat, dans
        l'ordre d'implémentation de la référence ; il implémente et compile, **il n'écrit pas les tests** ;
      - partie frontend : agent `frontend-dev` avec le plan, le contrat, les écrans et mes choix de design (skill
        `design`, section Implémentation). Backend déjà terminé (même branche ou fusionné) → il travaille directement sur
        la **vraie API** ; sinon, sur des **données simulées** conformes au contrat (skill `angular-conventions`), et le
        branchement se fera par `/integrate <slug>`. Il met à jour le statut des écrans (`implémenté` ou `intégré`).
        Si la feature a une interface mais que `<frontend>` vaut « aucun », arrête-toi et propose `/add-frontend`.
   b. **Tests** → agent `test-writer` avec la spec, le plan et la liste des fichiers produits par cette partie.
      Il écrit **tous** les tests de la partie, couche par couche, selon la section « Tests par couche » de la
      référence, et les exécute. S'il détecte un bug dans le code de production, renvoie-le à l'agent dev concerné,
      puis relance `test-writer`.
   c. **Revue** → agent `reviewer`, sur les changements de la partie. S'il y a des remarques BLOQUANT ou MAJEUR,
      renvoie-les à l'agent dev concerné, puis relance la revue. Maximum 2 boucles ; au-delà, arrête-toi et fais-moi un point.
   d. **Verdict → ⏸ ARRÊT** : présente-moi le verdict de la revue (points bloquants, majeurs, mineurs, suggestions),
      le nombre de tests et les écarts au plan. **Attends ma décision avant tout commit** : je peux demander des
      corrections (second passage par les agents concernés, puis revue rapide) ou valider tel quel.
   e. **Commit de la partie**, après mon accord : Avancement mis à jour (partie `terminé — <date>`), fichiers ajoutés
      **un par un** (`git add -- <chemin>`, jamais de `.env`), `git status --short` et liste des fichiers indexés
      montrés avant le commit (règle « Commit sûr »), puis commit au format Conventional Commits (code, tests, spec,
      plan, contrat et design de la partie).
   f. **S'il reste une partie** → **⏸ ARRÊTE-TOI** avec :
      - ce qui est utilisable maintenant, avec une **procédure de test qui marche** (règle « Commandes proposées à
        l'humain ») : backend terminé → l'API se teste pour de vrai, avec un compte et un rôle qui existent selon la
        spec, les chemins exacts du contrat et des commandes prêtes pour le terminal de l'humain (PowerShell sous
        Windows) ; frontend terminé → écrans avec `npx ng serve` (ou `--configuration mock`), et ce qu'il faut vérifier
        dans le navigateur ;
      - la reprise : continuer tout de suite sur cette branche, ou plus tard (par moi ou un autre développeur, après
        poussée et fusion de cette partie) avec `/feature --resume <slug> --front` (ou `--back`).
      Frontend terminé avant le backend : une fois le backend commité, propose `/integrate <slug>`.
6. **Clôture** : donne-moi un résumé — architecture appliquée, parties terminées et restantes, fichiers modifiés par
   couche, tests (passés/échoués), verdict de la revue, et la commande pour pousser la branche.

À chaque arrêt « ⏸ », termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi
(règle « Attendre l'humain ») : c'est elle qui me prévient et qui affiche le panneau de réponse du tableau de bord.

Ne pousse rien et n'ouvre pas de PR/MR sans mon accord.
