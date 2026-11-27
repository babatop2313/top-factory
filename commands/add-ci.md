---
description: Installe la CI du projet (GitHub Actions ou GitLab CI) — tests du backend et du frontend sur chaque Pull/Merge Request, sans aucun vrai secret — et explique comment la rendre obligatoire.
argument-hint: [github | gitlab]
---

Plateforme demandée : $ARGUMENTS

But : qu'aucune PR/MR ne puisse être fusionnée avec des tests rouges (une régression comme des secrets réintroduits
doit bloquer la fusion, pas être découverte plus tard).

1. **Constat** (sans rien écrire) :
   - plateforme : `$ARGUMENTS`, sinon déduite de `git remote get-url origin` (`github.com` → GitHub, sinon GitLab) ;
     confirme-la-moi ;
   - CI existante (`.github/workflows/`, `.gitlab-ci.yml`) : si elle lance déjà les tests, arrête-toi et dis-moi ce
     qui manque au lieu de la remplacer ;
   - parties à tester : `<backend>` (si `pom.xml`), `<frontend>` (si `package.json` ; « aucun » → pas de job frontend) ;
   - versions : Java (`<java.version>` ou `maven.compiler.release` du `pom.xml`), Node (`.nvmrc`, champ `engines` de
     `package.json`, sinon la version majeure installée) ;
   - **variables exigées au démarrage** par les tests qui chargent le contexte Spring (vérification des secrets au
     démarrage, `.env.example`) : liste leurs **noms**.
   Point de départ comme l'étape 1 de `/feature` (arbre propre, `baseBranch` à jour), puis branche `chore/ci`.
2. **Fichier** : copie le modèle du kit, `<kit>/skills/conventions/references/ci/github-actions.yml` vers
   `.github/workflows/ci.yml`, ou `<kit>/skills/conventions/references/ci/gitlab-ci.yml` vers `.gitlab-ci.yml`, et remplace :
   - `__BACKEND__`, `__FRONTEND__` par les dossiers du projet (retire le job d'une partie absente) ;
   - `__JAVA__`, `__NODE__` par les versions trouvées ;
   - `__TEST_ENV__` par une ligne par variable exigée, avec une **valeur de test générée à chaque exécution**, jamais
     une vraie valeur ni une valeur écrite en dur. GitHub : `echo "JWT_SECRET=$(openssl rand -base64 48)" >> "$GITHUB_ENV"`
     (10 espaces d'indentation) ; GitLab : `    - export JWT_SECRET="$(openssl rand -base64 48)"`. Une variable au
     format imposé (e-mail, fuseau) reçoit une valeur de test valide et neutre (`ci@example.invalid`) ; une variable
     facultative reste absente. Aucune variable : supprime l'étape (GitHub) ou la ligne (GitLab).
   - Lanceur de tests du frontend : Karma (ancien projet) → `npx ng test --watch=false --browsers=ChromeHeadless`.
3. **Vérification** : YAML valide (`python -c "import yaml…"` ou `npx --yes yaml-lint`, si disponible) ; aucune
   valeur sensible dans le fichier ; les commandes de la CI tournent en local depuis chaque dossier
   (`./mvnw -B verify`, `npm ci && npx ng build && npx ng test --watch=false`). Signale-moi un test qui dépend de mon
   poste (fichier local, `.env` réel, base locale au lieu de Testcontainers) : il échouera en CI.
4. **Commit**, après mon accord sur le fichier : `ci: tests du backend et du frontend sur chaque PR`, fichier ajouté
   seul (`git add -- <fichier>`).
5. **Ce que je dois faire moi-même** (la CI n'est utile que si elle bloque la fusion) :
   - pousser `chore/ci`, ouvrir la PR/MR et vérifier que les jobs passent ;
   - **GitHub** : Settings → Branches (ou Rules → Rulesets) → règle pour `develop` et `main` → « Require a pull
     request before merging » et « Require status checks to pass » → cocher `backend` et `frontend` ;
   - **GitLab** : Settings → Merge requests → « Pipelines must succeed » ; Settings → Repository → Protected branches
     (`develop`, `main` : personne ne pousse directement).
   Si un job échoue sur `develop` dès le départ (tests déjà rouges), dis-le-moi : on corrige d'abord (`/fix-bug`),
   sinon la règle bloquerait toutes les PR.

Ne pousse rien et ne modifie aucun réglage du dépôt distant : c'est moi qui active la règle.
À l'arrêt, termine ton message par une ligne qui commence par « ⏸ » et dit ce que tu attends de moi.
