# Option `front-ui` — bibliothèque d'interface du frontend Angular

Clé dans `.claude/stack.json` : `"conventions": { "front-ui": "<valeur>" }`. Sans frontend, l'option est ignorée.
Elle est appliquée par `/add-frontend` à la création de l'application, puis par `frontend-dev` à chaque écran.

## Valeur : primeng-bootstrap
- **PrimeNG** pour les composants (tableaux, formulaires, boutons, dialogues, toasts) et son thème (`@primeuix/themes`,
  preset `Aura` par défaut), **PrimeIcons** pour les icônes.
- **Bootstrap pour la mise en page uniquement** : `bootstrap-grid.min.css` et `bootstrap-utilities.min.css` dans les
  `styles` d'`angular.json` (grille, espacements, flex, affichage). **Ni** `bootstrap.min.css` complet (son reboot et ses
  composants entrent en conflit avec le thème PrimeNG), **ni** le JavaScript de Bootstrap.
- Un composant d'interface = un composant PrimeNG (`p-table`, `p-button`, `p-inputtext`, `p-password`, `p-toast`…) ;
  pas de composant Bootstrap (`.btn`, `.card`, `.modal`) ni de composant maison qui duplique PrimeNG.
- Versions : la version majeure de `primeng` suit celle d'Angular ; vérifier `npm view primeng@<majeure> peerDependencies`.
  L'installation (providers, animations, thème) suit la documentation officielle de la version installée
  (https://primeng.org/installation) : elle change d'une version majeure à l'autre.
- Notifications : `MessageService` + un seul `<p-toast />` dans le composant racine ; l'intercepteur d'erreurs l'utilise.
- **Thème clair et sombre** : `providePrimeNG({ theme: { preset: AppPreset, options: { darkModeSelector: '.app-dark' } } })`
  — jamais la valeur par défaut (`system`), qui bascule les composants selon Windows ou macOS sans le reste de la page.
  `AppPreset` = `definePreset(Aura, { … })` : couleur primaire et éventuelles surcharges déclarées pour
  `colorScheme.light` **et** `colorScheme.dark`. Fond et texte de la page : `--p-content-background`,
  `--p-text-color` (skill `angular-conventions`, « Thème clair et sombre »).
- Bootstrap (grille et utilitaires) n'a pas de couleurs à gérer ; ne pas utiliser ses classes de couleur
  (`.bg-*`, `.text-*`), qui ignorent le thème.
- Budget de taille : le thème PrimeNG fait dépasser le seuil d'avertissement par défaut du bundle initial (500 kB).
  `/add-frontend` le relève à 800 kB dans `angular.json` (budget `initial`, `maximumWarning`), sans toucher au seuil
  d'erreur : un avertissement permanent finirait par masquer un vrai problème.

## Valeur : material
- **Angular Material** (`ng add @angular/material`), thème Material 3 ; mise en page en CSS (flex, grid), sans Bootstrap.
- Thème clair et sombre : `color-scheme: light` sur `html`, `color-scheme: dark` sous `html.app-dark` (Material 3
  utilise `light-dark()`), jamais seulement `prefers-color-scheme`.
- Notifications : `MatSnackBar`, appelé par l'intercepteur d'erreurs.

## Valeur : aucune
- CSS maison (SCSS par composant + `styles.scss` global avec variables). Aucune bibliothèque de composants.
- Thème clair et sombre : variables CSS sur `:root`, redéfinies sous `:root.app-dark`.
- Notifications : un service `NotificationService` (signal de messages) et un composant d'affichage dans `shared/`.
