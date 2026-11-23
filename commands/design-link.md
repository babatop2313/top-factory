---
description: Enregistre un lien de design externe (Figma ou Claude Design) pour un écran ou pour le design system, dans docs/design/design.json.
argument-hint: <url> [écran | design-system]
---

Lien et cible : $ARGUMENTS

1. Vérifie l'URL : `https://` uniquement ; source déduite du domaine (`figma.com` → `figma`, `claude.ai` ou
   `claude.com` → `claude-design`, sinon demande-moi). Refuse une URL qui contient un jeton ou un mot de passe.
2. Cible : l'écran indiqué (identifiant existant, ou nouvel écran à créer dans le registre avec son titre et sa
   feature — demande-les si besoin), ou `design-system`.
3. Mets à jour `docs/design/design.json` (créé s'il n'existe pas, selon le skill `design`) : `source`, `link`,
   `updated` ; statut `proposé` pour un nouvel écran.
4. Demande-moi si ce design est **validé** (il fera alors référence pour `frontend-dev`). Pour qu'il soit utilisable
   sans accès à l'outil externe, propose `/design-screen <écran>` : l'agent `designer` en tirera la fiche et une maquette
   dans `docs/design/` (avec le serveur MCP Figma s'il est branché, sinon à partir des exports que je fournis).
Ne commite rien sans mon accord.
