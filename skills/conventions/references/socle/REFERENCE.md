# Socle des conventions Spring Boot (non négociable)

> S'applique à **tous** les projets, quels que soient l'architecture, le profil et les options.
> **L'architecture** (packages, couches, règle de dépendance) n'est pas ici : elle est dans la référence d'architecture active.
> **Les choix qui varient d'un projet à l'autre** (mapping, Lombok, format des erreurs, ids) sont des **options**
> (`.claude/stack.json`, puis `options/`). **Les technologies** (PostgreSQL, Redis, Kafka…) sont dans le skill `integrations`.
> Priorités en cas de conflit : architecture > **socle** > options du projet > profil.

## Injection
- Par constructeur uniquement. Jamais de `@Autowired` sur un champ ni sur un setter.
- Une classe a peu de dépendances : au-delà de 5, c'est le signe qu'elle fait trop de choses.

## Transactions
- Portées par la couche qui exécute les cas d'utilisation (services ou use cases, selon la référence d'architecture).
- Jamais de `@Transactional` sur un contrôleur, un outil MCP ou un adapter entrant.
- Lectures : `@Transactional(readOnly = true)`.
- Pas d'appel réseau lent (HTTP externe, envoi de mail) **à l'intérieur** d'une transaction de base de données :
  le faire après la validation (événement après commit) ou en dehors.

## Mapping
- Les conversions (DTO ↔ objets internes, entités JPA ↔ objets internes) se font dans des **mappers**,
  placés là où la référence d'architecture l'indique. La technique (MapStruct ou manuel) est une option.
- Un contrôleur ne renvoie jamais une entité JPA.

## Gestion d'erreurs
- Les exceptions métier portent un **`code` métier stable** et aucune notion de statut HTTP.
- La traduction en réponse HTTP se fait dans la couche web uniquement ; le format est une option (`errors`).
- Jamais de stack trace ni de message technique (SQL, nom de classe) dans une réponse.

## Logs
- SLF4J. `info` pour les événements métier, `debug` pour le détail, `warn`/`error` pour ce qui demande une action.
- **Jamais** de donnée personnelle, de token, de mot de passe ni de secret dans un log.
- Pas de `System.out`, pas de `printStackTrace`.

## Flyway
- Fichier : `V<n>__<verbe>_<objet>.sql` (ex. `V3__create_table_loan.sql`). **Ne jamais modifier une migration existante.**
- snake_case, contraintes nommées (`pk_book`, `uk_book_isbn`, `fk_loan_member`, `ck_…`), index sur chaque clé
  étrangère et chaque colonne filtrée.
- `spring.jpa.hibernate.ddl-auto=validate` : le schéma n'est géré que par Flyway.
- Données de développement : `docs/dev/`, jamais `db/migration/`.

## Sécurité
- `@PreAuthorize` sur chaque point d'entrée qui modifie des données (contrôleur, outil MCP, consommateur exposé).
- L'identité de l'utilisateur vient du JWT, jamais d'un champ de la requête (pas d'IDOR).
- Transport du JWT vers un navigateur : option `auth-token` (cookie HttpOnly + CSRF, ou corps de réponse + en-tête
  `Authorization`). Les clients non navigateurs utilisent toujours l'en-tête `Authorization: Bearer`.
- Configuration de sécurité dans le package de configuration globale.
- Validation des entrées avec Jakarta Validation sur les DTO d'entrée.

## Configuration
- `application.yml` **sans secret** : uniquement des références `${VARIABLE}`. Valeurs par défaut autorisées
  seulement pour ce qui n'est pas secret (`${DB_HOST:localhost}`, `${APP_TIMEZONE:Africa/Dakar}`), jamais pour un mot
  de passe, une clé, un jeton ni un identifiant dans une URL. Un secret absent **empêche le démarrage**, avec un
  message qui nomme la variable (jamais sa valeur).
- **Fichier `.env`** (poste du développeur) : lu par Spring au démarrage, sans outil supplémentaire :
  ```yaml
  spring:
    config:
      import: "optional:file:.env[.properties],optional:file:../.env[.properties]"   # racine du dépôt recommandée
  ```
  Format `.properties` : `NOM=valeur`, sans guillemets ni `export` (un `\` se double). Les variables d'environnement
  du système restent prioritaires (CI, production). Un **seul** `.env`, à la racine du dépôt.
- **`.gitignore`** : `.env*` puis `!.env.example` — jamais une règle qui ré-inclut `.env`. **`.env.example`** est
  versionné, liste toutes les variables, **sans aucune valeur** (`NOM=` uniquement). Claude ne lit ni n'écrit `.env` :
  c'est l'humain qui le remplit ; Claude ne l'ajoute jamais à Git (hooks).
- **Tests modèles du kit** (`<kit>/skills/conventions/references/socle/tests/`, installés par `/init-architecture`
  dans le package `config` des tests) : `ApplicationYamlSecretsTest` (aucun secret ni valeur par défaut de secret,
  aucun identifiant dans une URL) et `RepositorySecretsHygieneTest` (aucun `.env` suivi par Git, `.gitignore` correct,
  `.env.example` sans valeur et complet). On corrige la configuration, jamais ces tests ; une exception (propriété au
  nom trompeur) s'ajoute à la liste commentée `NOT_SECRETS`, avec l'accord de l'humain.
- Chaque intégration se configure comme l'indique sa référence (skill `integrations`).
- Un `@Bean Clock` (`Clock.systemDefaultZone()`) dans la configuration globale, remplacé par `Clock.fixed(...)` dans les tests.

## Tests
- Nommage : `methode_quandCondition_alorsResultat` ; Given / When / Then visibles.
- Base de données réelle via Testcontainers pour la persistance, jamais H2. Pas de dépendance à la date système.
