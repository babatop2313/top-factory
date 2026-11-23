#!/usr/bin/env bash
# PostToolUse (Edit|Write) : vérifie la règle de dépendance de l'architecture ACTIVE après chaque écriture d'un .java.
# Moteur générique : les règles viennent de <kit>/skills/architecture/references/<architecture>/rules.conf,
# puis du rules.conf de chaque intégration active (.claude/stack.json), lu avec le roles.conf de l'architecture.
# exit 2 = le message (stderr) est renvoyé à Claude, qui corrige dans la foulée.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
need_jq block

file=$(norm_path "$(jq -r '.tool_input.file_path // ""')")
root=$(project_root)

[[ "$file" == *.java ]] || exit 0
[[ "$file" == */src/main/java/* ]] || exit 0
[ -f "$file" ] || exit 0

arch=$(active_architecture)
rules="$(kit_root)/skills/architecture/references/$arch/rules.conf"
[ -n "$arch" ] || exit 0

rel="${file#*/src/main/java/}"             # chemin à partir du package racine
shown="${file#"$root"/}"                   # chemin affiché, relatif au projet si possible
violations=""

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  segment="${line%% :: *}"
  rest="${line#* :: }"
  regex="${rest%% :: *}"
  message="${rest#* :: }"
  [[ "/$rel" == */"$segment"/* ]] || continue
  bad=$(tr -d '\r' < "$file" | grep -nE "$regex" || true)
  if [ -n "$bad" ]; then
    violations+="• couche « $segment » : $message"$'\n'"$bad"$'\n'
  fi
done < <( [ -f "$rules" ] && cat "$rules" )

# --- Intégrations actives (.claude/stack.json) : une bibliothèque d'intégration ne s'utilise que dans ses rôles ---
# Format des règles : roles :: regex :: message. Les packages « config » sont toujours autorisés.
integ_violations=""
case "/$rel" in */config/*) in_config=1 ;; *) in_config=0 ;; esac
if [ "$in_config" -eq 0 ]; then
  for integ in $(active_integrations); do
    irules="$(kit_root)/skills/integrations/references/$integ/rules.conf"
    [ -f "$irules" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      roles="${line%% :: *}"
      rest="${line#* :: }"
      regex="${rest%% :: *}"
      message="${rest#* :: }"
      allowed=0
      for role in $(printf '%s' "$roles" | tr ',' ' '); do
        for seg in $(role_segments "$role"); do
          [[ "/$rel" == */"$seg"/* ]] && allowed=1
        done
      done
      [ "$allowed" -eq 1 ] && continue
      bad=$(tr -d '\r' < "$file" | grep -nE "$regex" || true)
      if [ -n "$bad" ]; then
        integ_violations+="• intégration « $integ » (rôles autorisés : $roles) : $message"$'\n'"$bad"$'\n'
      fi
    done < "$irules"
  done
fi

# --- Modules concernés (.claude/stack.json, champ « modules ») : une intégration ou le serveur MCP ne s'utilise que
# dans les modules choisis par l'humain, par exemple { "modules": { "redis": ["catalog"], "mcp": ["catalog"] } }.
# Clé absente : pas de restriction (projets d'avant la v4.5.1). Les packages « config » restent toujours autorisés.
scope_violations=""
stackf="$root/.claude/stack.json"
if [ "$in_config" -eq 0 ] && [ -f "$stackf" ]; then
  for key in $(jq -r '(.modules // {}) | keys[]' "$stackf" 2>/dev/null | tr -d '\r'); do
    case "$key" in
      mcp) patterns='^import (static )?org\.springframework\.ai\.mcp\.|^[[:space:]]*@McpTool([^A-Za-z]|$)' ;;
      *)
        irules="$(kit_root)/skills/integrations/references/$key/rules.conf"
        [ -f "$irules" ] || continue
        patterns=$(tr -d '\r' < "$irules" | grep -vE '^[[:space:]]*(#|$)' | awk -F ' :: ' '{ printf "%s(%s)", (NR > 1 ? "|" : ""), $2 }') ;;
    esac
    [ -n "$patterns" ] || continue
    bad=$(tr -d '\r' < "$file" | grep -nE "$patterns" || true)
    [ -n "$bad" ] || continue
    mods=$(jq -r --arg k "$key" '(.modules[$k] // [])[]' "$stackf" 2>/dev/null | tr -d '\r')
    ok=0
    for m in $mods; do [[ "/$rel" == */"$m"/* ]] && ok=1; done
    [ "$ok" -eq 1 ] && continue
    list=$(printf '%s' "$mods" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    scope_violations+="• « $key » n'est prévu que pour les modules : ${list:-aucun pour le moment}."$'\n'"$bad"$'\n'
  done
fi

if [ -n "$violations" ] || [ -n "$integ_violations" ] || [ -n "$scope_violations" ]; then
  if [ -n "$violations" ]; then
    echo "Violation de l'architecture « $arch » dans $shown :" >&2
    printf '%s' "$violations" >&2
    echo "Corrige le code pour respecter $(kit_path "skills/architecture/references/$arch/REFERENCE.md")." >&2
  fi
  if [ -n "$integ_violations" ]; then
    echo "Intégration utilisée hors de ses rôles dans $shown :" >&2
    printf '%s' "$integ_violations" >&2
    echo "Place ce code dans le package du rôle indiqué par $(kit_path "skills/architecture/references/$arch/roles.conf")," >&2
    echo "ou dans un package config, et passe par un port (voir la référence de l'intégration)." >&2
  fi
  if [ -n "$scope_violations" ]; then
    echo "Intégration utilisée dans un module qui n'en a pas besoin, dans $shown :" >&2
    printf '%s' "$scope_violations" >&2
    echo "Ce module n'utilise pas cette technologie : retire ce code. S'il en a vraiment besoin, propose-le à l'humain ;" >&2
    echo "c'est lui qui décide d'ajouter le module au champ « modules » de .claude/stack.json." >&2
  fi
  exit 2
fi
exit 0
