---
description: Enregistre une fois pour toutes l'outil de design du projet (Claude Design ou Figma) et son lien dans .claude/stack.json — ou le lien d'un écran précis dans docs/design/design.json.
argument-hint: <url> [écran]
---

Lien et cible : $ARGUMENTS

Lis le skill `design` (sections « Outil de design du projet » et « Sources externes »).

1. **Vérifie l'URL** : `https://` uniquement ; outil déduit du domaine (`figma.com` → `figma` ; `claude.ai` ou
   `claude.com` → `claude-design` ; sinon demande-moi). Refuse une URL qui contient un jeton, un mot de passe ou un
   paramètre d'authentification. Sans URL : si `.design-sync/config.json` existe, propose-moi le lien du projet Claude
   Design qu'il épingle (lecture seule) ; sinon, demande-moi le lien.
2. **Sans écran indiqué : lien du projet.** Montre-moi le bloc qui sera écrit dans `.claude/stack.json` :
   ```json
   "design": { "tool": "<claude-design | figma>", "link": "<url>" }
   ```
   (les autres clés de `stack.json` ne changent pas ; un lien déjà présent est remplacé, dis-moi lequel). Écris-le avec
   mon accord (Claude Code me demande l'autorisation : `stack.json` est en permission `ask`). Ce lien reste valable d'une
   session à l'autre : il est annoncé au début de chaque session et affiché dans le tableau de bord (onglet Design).
3. **Avec un écran : lien de cet écran** (frame Figma, artboard), seulement s'il diffère du lien du projet. Mets à jour
   `docs/design/design.json` (créé s'il n'existe pas, selon le skill `design`) : `source`, `link`, `updated` ; écran
   nouveau → titre et feature (demande-les si besoin), statut `proposé`.
4. Rappelle-moi la suite : quand un écran est prêt dans l'outil, `/design-screen <écran>` en tire la fiche et la maquette
   du dépôt (agent `designer` : serveur MCP de l'outil s'il est branché, sinon mes exports ou captures). Le design ne
   devient `validé` que si je le confirme.

Pour revenir au designer de la factory : bloc `design` retiré de `stack.json` (ou `"tool": "factory"`), avec mon accord.
Ne commite rien sans mon accord.
