#!/usr/bin/env bash
# PreToolUse (Bash|PowerShell) : bloque les commandes dangereuses avant leur exécution.
# Claude Code envoie le contexte en JSON sur stdin ; exit 2 = blocage, stderr est renvoyé à Claude.
# Chaque règle est indépendante : une commande est vérifiée par toutes les règles.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
need_jq block

cmd=$(jq -r '.tool_input.command // ""' | tr -d '\r')
ncmd="${cmd//\\//}"                        # séparateurs Windows → / pour les comparaisons de chemins

block() {
  echo "Commande bloquée par la factory : $1" >&2
  exit 2
}
has() { printf '%s' "$ncmd" | grep -Eq "$1"; }

# Fin d'un argument : espace, fin de commande, guillemet ou séparateur de commandes.
END='(["'"'"']?([[:space:]]|$|[;&|]))'

# --- Git : branches protégées, push forcé ---
if has 'git[[:space:]]+push'; then
  has 'git[[:space:]]+push.*([[:space:]:+]|refs/heads/)(main|master|develop)'"$END" \
    && block "push direct sur une branche protégée (main, master, develop). Pousse une branche feature/* et ouvre une PR/MR."
  has 'git[[:space:]]+push.*([[:space:]]--force|[[:space:]]-f'"$END"'|[[:space:]]\+[A-Za-z0-9_./-]+)' \
    && block "push forcé interdit."
fi

# --- Commit sûr : fichiers ajoutés un par un, jamais de .env dans un commit ---
if has 'git[[:space:]]+add([[:space:]]|$)'; then
  has 'git[[:space:]]+add([[:space:]]+[^;&|]*)?[[:space:]](-A|--all|-u|--update|\.|\./|:/|\*)'"$END" \
    && block "ajout en bloc (git add -A, git add ., git add -u…) : ajoute les fichiers un par un (git add -- <chemin>), puis montre la liste des fichiers indexés à l'humain avant le commit."
  envs=$(printf '%s' "$ncmd" | grep -oE 'git[[:space:]]+add[^;&|]*' | tr -s ' \t' '\n\n' | sed "s/[\"']//g" \
    | grep -E '(^|/)\.env(\.[A-Za-z0-9_-]+)?$' | grep -vE '(^|/)\.env\.example$' || true)
  [ -n "$envs" ] \
    && block "un fichier .env contient des secrets : il ne s'ajoute jamais à Git (seul .env.example, sans valeur, est versionné)."
fi
if has 'git[[:space:]]+commit([[:space:]]|$)'; then
  has 'git[[:space:]]+commit([[:space:]]+[^;&|]*)?[[:space:]](-a|--all|-[A-Za-z]*a[A-Za-z]*)'"$END" \
    && block "git commit -a ajoute tous les fichiers modifiés : indexe-les un par un (git add -- <chemin>), montre la liste à l'humain, puis git commit sans -a."
  staged=$(cd "$(project_root)" 2>/dev/null && git diff --cached --name-only 2>/dev/null | tr -d '\r' \
    | grep -E '(^|/)\.env(\.[A-Za-z0-9_-]+)?$' | grep -vE '(^|/)\.env\.example$' || true)
  [ -n "$staged" ] && block "un fichier .env est indexé ($(printf '%s' "$staged" | tr '\n' ' ')) : il contient des secrets. Retire-le de l'index (git restore --staged <fichier>) ; s'il est suivi par Git, propose à l'humain git rm --cached <fichier> et la correction de .gitignore."
fi

# --- Fusion de PR/MR : toujours faite par un humain (vaut aussi pour l'outil PowerShell) ---
has '(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+merge|glab[[:space:]]+mr[[:space:]]+merge)'"$END" \
  && block "la fusion d'une Pull Request / Merge Request est réservée à un humain."

# --- Suppressions dangereuses ---
has '(^|[;&|[:space:]])rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+("|'"'"')?(/|~|\.|\*|\.\.)'"$END" \
  && block "suppression récursive dangereuse."
has 'DROP[[:space:]]+DATABASE|drop[[:space:]]+database' \
  && block "suppression de base de données."

# --- Migrations Flyway : jamais de modification, déplacement ou suppression d'un .sql existant ---
MIG='[^[:space:];&|]*db/migration/[^[:space:];&|]*\.sql'
if has "$MIG"; then
  has '(^|[;&|[:space:]])(rm|mv|truncate|sed[[:space:]]+-i|perl[[:space:]]+-i|git[[:space:]]+rm|Remove-Item|Move-Item|Set-Content|Clear-Content)[[:space:]][^;&|]*'"$MIG" \
    && block "les migrations Flyway existantes ne se modifient pas : crée une nouvelle migration V<n+1>__....sql avec l'outil Write."
  has '>>?[[:space:]]*("|'"'"')?'"$MIG" \
    && block "pas d'écriture de migration par le shell : utilise l'outil Write pour créer une nouvelle migration."
fi

# --- Verrou d'architecture : aucune écriture vers .claude/factory.json (la lecture reste autorisée) ---
FJ='[^[:space:];&|]*factory\.json'
if has 'factory\.json'; then
  has '>>?[[:space:]]*("|'"'"')?'"$FJ" \
    && block ".claude/factory.json est verrouillé : l'architecture du projet ne peut pas être modifiée par Claude."
  has '(^|[;&|[:space:]])(rm|mv|truncate|tee|sed[[:space:]]+-i|perl[[:space:]]+-i|git[[:space:]]+(checkout|restore|rm)|Set-Content|Out-File|Add-Content|Clear-Content|Remove-Item|Move-Item)[[:space:]][^;&|]*'"$FJ" \
    && block ".claude/factory.json est verrouillé : l'architecture du projet ne peut pas être modifiée par Claude."
  # copie VERS factory.json (factory.json est le dernier argument)
  has '(^|[;&|[:space:]])(cp|Copy-Item)[[:space:]][^;&|]*[[:space:]]("|'"'"')?'"$FJ"'("|'"'"')?[[:space:]]*($|[;&|])' \
    && block ".claude/factory.json est verrouillé : l'architecture du projet ne peut pas être modifiée par Claude."
fi

# --- Fichiers du projet : pas de suppression du dossier .claude/ entier ni de ses fichiers par motif (*.json…) ---
# (factory.json, stack.json, settings.json disparaîtraient avec lui ; la règle ci-dessus ne voit pas le nom factory.json)
CL='("|'"'"')?(\./)?\.claude(/|\\)?(\*[^[:space:];&|]*)?("|'"'"')?([[:space:]]|$|[;&|])'
has '(^|[;&|[:space:]])(rm|git[[:space:]]+rm|git[[:space:]]+clean|Remove-Item|rmdir|rd|del)[[:space:]]([^;&|]*[[:space:]])?'"$CL" \
  && block "suppression du dossier .claude/ (ou de ses fichiers par motif) : il contient les fichiers du projet (factory.json, stack.json, settings.json). Supprime un fichier précis, avec l'accord de l'humain."

exit 0
