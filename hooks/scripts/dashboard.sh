#!/usr/bin/env bash
# Génère le tableau de bord de la factory : ${TOP_FACTORY_HOME:-~/.top-factory}/dashboard.html
# Page autonome (aucun serveur, aucune ressource externe) : vue d'ensemble, process de chaque feature, activité,
# documentation de la factory (commandes et agents lus dans le kit). Actualisée toutes les 15 s.
#
#   bash dashboard.sh            régénère la page
#   bash dashboard.sh --open     régénère et l'ouvre dans le navigateur
#   bash dashboard.sh --prune    retire du registre les projets dont le dossier n'existe plus
#   bash dashboard.sh --path     affiche le chemin de la page
#   bash dashboard.sh --vendor   télécharge l'afficheur de schémas Mermaid (une fois, empreinte SHA-256 vérifiée)
# Icônes : Lucide (https://lucide.dev), licence ISC. Schémas : Mermaid (https://mermaid.js.org), licence MIT,
# téléchargé une seule fois dans ~/.top-factory/vendor/ puis utilisé hors ligne.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "jq est requis pour le tableau de bord." >&2; exit 1; }
source "$(dirname "$0")/lib.sh"

home="${TOP_FACTORY_HOME:-$HOME/.top-factory}"
reg="$home/projects.json"
out="$home/dashboard.html"
mkdir -p "$home/events"
[ -s "$reg" ] || printf '{}' > "$reg"

# --- Afficheur Mermaid : version figée, empreinte vérifiée, jamais chargé depuis Internet par la page ---
MERMAID_VERSION="11.17.2"
MERMAID_SHA256="581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8"
vendor="$home/vendor"; mfile="$vendor/mermaid-$MERMAID_VERSION.min.js"
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else openssl dgst -sha256 "$1" 2>/dev/null | sed 's/.*= //'; fi
}
fetch_mermaid() {
  [ -f "$mfile" ] && return 0
  command -v curl >/dev/null 2>&1 || { echo "curl est introuvable : schémas affichés en texte." >&2; return 1; }
  mkdir -p "$vendor" || return 1
  local tmp="$mfile.$$.part" url
  for url in "https://cdn.jsdelivr.net/npm/mermaid@$MERMAID_VERSION/dist/mermaid.min.js" \
             "https://unpkg.com/mermaid@$MERMAID_VERSION/dist/mermaid.min.js"; do
    if curl -fsSL --max-time 180 -o "$tmp" "$url" 2>/dev/null && [ "$(sha256_of "$tmp")" = "$MERMAID_SHA256" ]; then
      mv "$tmp" "$mfile" && echo "Afficheur de schémas installé : $mfile" && return 0
    fi
    rm -f "$tmp"
  done
  # Windows : dernier essai par PowerShell, qui passe par le proxy du système (et ses identifiants).
  if command -v powershell.exe >/dev/null 2>&1; then
    local wtmp="$tmp"; command -v cygpath >/dev/null 2>&1 && wtmp="$(cygpath -w "$tmp")"
    powershell.exe -NoProfile -NonInteractive -Command "\$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; [Net.WebRequest]::DefaultWebProxy.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials; Invoke-WebRequest -UseBasicParsing -Uri 'https://cdn.jsdelivr.net/npm/mermaid@$MERMAID_VERSION/dist/mermaid.min.js' -OutFile '$wtmp'" >/dev/null 2>&1
    if [ -f "$tmp" ] && [ "$(sha256_of "$tmp")" = "$MERMAID_SHA256" ]; then
      mv "$tmp" "$mfile" && echo "Afficheur de schémas installé (par PowerShell) : $mfile" && return 0
    fi
    rm -f "$tmp"
  fi
  echo "Téléchargement de Mermaid impossible (réseau, ou empreinte différente) : schémas affichés en texte." >&2
  return 1
}

case "${1:-}" in
  --path) echo "$out"; exit 0 ;;
  --vendor) fetch_mermaid; exit $? ;;
  --prune)
    tmp="$reg.$$.tmp"; keep='{}'
    for id in $(jq -r 'keys[]' "$reg"); do
      p=$(jq -r --arg id "$id" '.[$id].path' "$reg")
      if [ -d "$p" ]; then keep=$(printf '%s' "$keep" | jq --arg id "$id" --slurpfile r "$reg" '.[$id] = $r[0][$id]')
      else echo "Retiré : $(jq -r --arg id "$id" '.[$id].name' "$reg") ($p)"; fi
    done
    printf '%s\n' "$keep" > "$tmp" && mv "$tmp" "$reg" ;;
esac

# Première fois : téléchargement de Mermaid en arrière-plan (une tentative par jour au plus ; TOP_FACTORY_VENDOR=off l'évite).
if [ ! -f "$mfile" ] && [ "${TOP_FACTORY_VENDOR:-on}" != "off" ] && \
   { [ ! -f "$home/.vendor-try" ] || [ -n "$(find "$home/.vendor-try" -mtime +0 2>/dev/null)" ]; }; then
  touch "$home/.vendor-try" 2>/dev/null
  ( bash "$0" --vendor >/dev/null 2>&1 & )
fi
mermaid_rel=""; [ -f "$mfile" ] && mermaid_rel="vendor/mermaid-$MERMAID_VERSION.min.js"

# Les données passent par des fichiers, jamais par la ligne de commande : sous Windows, une ligne de commande est
# limitée à 32 000 caractères environ (sous Linux, 128 Ko par argument), ce qu'atteignent vite les specs et maquettes.
work=$(mktemp -d "$home/.gen.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
log="$home/dashboard.log"
[ -f "$log" ] && [ "$(wc -c < "$log" | tr -d ' ')" -gt 100000 ] && tail -c 20000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
: > "$work/projects.jsonl"

# --- Projets : registre + 300 derniers événements + specs + documents + design + Git ---
for id in $(jq -r 'keys[]' "$reg" 2>/dev/null); do
  p=$(jq -r --arg id "$id" '.[$id].path' "$reg")
  echo '[]' > "$work/ev.json"
  if [ -f "$home/events/$id.jsonl" ]; then
    tail -n 300 "$home/events/$id.jsonl" | jq -cs '[.[] | objects]' > "$work/ev.json" 2>/dev/null || echo '[]' > "$work/ev.json"
  fi
  exists=false; br=""; last=""
  echo '[]' > "$work/specs.json"; : > "$work/docs.jsonl"; echo 'null' > "$work/design.json"
  if [ -d "$p" ]; then
    exists=true
    br=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    last=$(git -C "$p" log -1 --format='%s|%cI' 2>/dev/null | cut -c1-200 || true)
    if [ -d "$p/docs/specs" ]; then
      for f in "$p"/docs/specs/*.md; do
        [ -f "$f" ] || continue
        printf '%s\t%s\n' "$(basename "$f")" "$(date -r "$f" +%s 2>/dev/null || echo 0)"
      done | sort -t"$(printf '\t')" -k2 -nr | head -20 \
        | jq -Rcs 'split("\n") | map(select(length > 0) | split("\t") | {name: .[0], mtime: (.[1] | tonumber)})' > "$work/specs.json"
    fi
    # Documents lisibles dans la page : schéma d'architecture, 20 specs et plans, 10 contrats d'API les plus récents,
    # puis CLAUDE.md (200 Ko maximum chacun).
    { [ -f "$p/docs/architecture/overview.md" ] && echo "$p/docs/architecture/overview.md"
      for f in "$p"/docs/specs/*.md; do [ -f "$f" ] && printf '%s\t%s\n' "$(date -r "$f" +%s 2>/dev/null || echo 0)" "$f"; done \
        | sort -nr | head -20 | cut -f2-
      for f in "$p"/docs/api/*.md; do [ -f "$f" ] && printf '%s\t%s\n' "$(date -r "$f" +%s 2>/dev/null || echo 0)" "$f"; done \
        | sort -nr | head -10 | cut -f2-
      for c in CLAUDE.md claude.md; do [ -f "$p/$c" ] && { echo "$p/$c"; break; }; done; } > "$work/list.txt"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if command -v cygpath >/dev/null 2>&1; then url="file:///$(cygpath -m "$f")"; else url="file://$f"; fi
      url=$(printf '%s' "$url" | sed 's/ /%20/g')
      head -c 200000 "$f" > "$work/doc"
      big=false; [ "$(wc -c < "$f" | tr -d ' ')" -gt 200000 ] && big=true
      jq -cn --arg n "$(basename "$f")" --arg rel "${f#"$p"/}" --arg url "$url" \
            --argjson m "$(date -r "$f" +%s 2>/dev/null || echo 0)" --rawfile c "$work/doc" --argjson big "$big" \
         '{name: $n, rel: $rel, url: $url, mtime: $m, content: $c, truncated: $big}' >> "$work/docs.jsonl" 2>>"$log"
    done < "$work/list.txt"
    # Design : registre docs/design/design.json, design system, fiches et maquettes des écrans.
    dj="$p/docs/design/design.json"
    if [ -f "$dj" ] && jq -e 'type == "object"' "$dj" >/dev/null 2>&1; then
      jq -c '{designSystem: (.designSystem // null), screens: [(.screens // [])[] | objects]}' "$dj" > "$work/design.json"
      if [ -f "$p/docs/design/design-system.md" ]; then
        head -c 150000 "$p/docs/design/design-system.md" > "$work/doc"
        jq -c --rawfile c "$work/doc" '.designSystemDoc = $c' "$work/design.json" > "$work/d2" && mv "$work/d2" "$work/design.json"
      fi
      n=$(jq '.screens | length' "$work/design.json")
      k=0
      while [ "$k" -lt "$n" ] && [ "$k" -lt 60 ]; do
        for kind in spec mockup; do
          rel=$(jq -r --argjson k "$k" --arg f "$kind" '.screens[$k][$f] // empty' "$work/design.json")
          case "$rel" in ''|/*|*..*) continue ;; esac
          f="$p/docs/design/$rel"; [ -f "$f" ] || continue
          lim=150000; [ "$kind" = mockup ] && lim=400000
          head -c "$lim" "$f" > "$work/doc"
          jq -c --argjson k "$k" --arg f "${kind}Content" --rawfile c "$work/doc" '.screens[$k][$f] = $c' "$work/design.json" > "$work/d2" \
            && mv "$work/d2" "$work/design.json"
        done
        k=$((k + 1))
      done
    fi
  fi
  # Outil de design du projet (.claude/stack.json, bloc « design ») ; à défaut, projet Claude Design épinglé par
  # /design-sync (.design-sync/config.json, lu seulement pour en tirer un lien https).
  echo '{}' > "$work/dtool.json"
  if [ -d "$p" ]; then
    jq -c '(.design // {}) | {tool: (.tool // ""), link: (.link // "")} | with_entries(select(.value | type == "string"))' \
      "$p/.claude/stack.json" > "$work/dtool.json" 2>/dev/null || echo '{}' > "$work/dtool.json"
    if [ -f "$p/.design-sync/config.json" ]; then
      sync=$(jq -r '[.. | strings | select(test("^https://(claude\\.ai|claude\\.com)/"))][0] // empty' "$p/.design-sync/config.json" 2>/dev/null | head -n 1)
      [ -n "$sync" ] && jq -c --arg s "$sync" '. + {syncLink: $s}' "$work/dtool.json" > "$work/d2" 2>/dev/null && mv "$work/d2" "$work/dtool.json"
    fi
  fi
  jq -s '.' "$work/docs.jsonl" > "$work/docs.json" 2>>"$log" || echo '[]' > "$work/docs.json"
  jq -cn --arg id "$id" --slurpfile r "$reg" --slurpfile ev "$work/ev.json" --slurpfile specs "$work/specs.json" \
        --slurpfile docs "$work/docs.json" --slurpfile design "$work/design.json" --slurpfile dtool "$work/dtool.json" \
        --argjson exists "$exists" --arg br "$br" --arg last "$last" \
    '$r[0][$id] + {id: $id, exists: $exists, branch: $br, lastCommit: $last,
                   specs: $specs[0], docs: $docs[0], design: $design[0], designTool: $dtool[0], events: $ev[0]}' >> "$work/projects.jsonl" 2>>"$log" \
    || echo "$(date -u +%FT%TZ) projet $id ignoré (données illisibles)" >> "$log"
done
jq -s '.' "$work/projects.jsonl" > "$work/projects.json"

# --- Documentation : commandes et agents lus dans le kit (toujours à jour) ---
kit=$(kit_root)
front() { awk -v k="$2" 'NR==1 && /^---/ {f=1; next} f && /^---/ {exit} f && index($0, k ":") == 1 {sub("^" k ":[[:space:]]*", ""); print; exit}' "$1" | tr -d '\r'; }
docs_list() {
  for f in "$kit/$1"/*.md; do
    [ -f "$f" ] || continue
    printf '%s\t%s\t%s\n' "$(basename "$f" .md)" "$(front "$f" description)" "$(front "$f" argument-hint)"
  done | jq -Rcs 'split("\n") | map(select(length > 0) | split("\t")
         | {name: .[0], description: ((.[1] // "") | gsub("^\"|\"$"; "")), hint: ((.[2] // "") | gsub("^\"|\"$"; ""))})'
}
docs_list commands > "$work/commands.json"
docs_list agents > "$work/agents.json"
prefix="/"; [ "$(kit_mode)" = "plugin" ] && prefix="/top-factory:"
user=$(git config --global user.name 2>/dev/null | awk '{print $1}')
[ -n "$user" ] || user="${USERNAME:-${USER:-}}"
# Aucun « < » brut dans les données : rien ne peut fermer la balise <script>.
if ! jq -cn --slurpfile p "$work/projects.json" --arg g "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg v "$(kit_version)" \
          --arg prefix "$prefix" --arg user "$user" --arg home "$home" --arg mermaid "$mermaid_rel" \
          --slurpfile commands "$work/commands.json" --slurpfile agents "$work/agents.json" \
          '{generated: $g, kit: $v, prefix: $prefix, user: $user, home: $home, mermaid: $mermaid,
            projects: $p[0], docs: {commands: $commands[0], agents: $agents[0]}}' 2>>"$log" \
     | sed 's#<#\\u003c#g' > "$work/data.json" || [ ! -s "$work/data.json" ]; then
  echo "$(date -u +%FT%TZ) génération impossible : la page précédente est conservée (détails ci-dessus)" >> "$log"
  echo "Tableau de bord : génération impossible, voir $log" >&2
  exit 1
fi

tmp="$out.$$.tmp"
{
cat <<'TF_HTML_END'
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Top Factory</title>
<script>try { var t = localStorage.getItem('tf-theme'); if (t === 'light' || t === 'dark') document.documentElement.setAttribute('data-theme', t); } catch (e) {}</script>
<style>
  :root {
    --bg: #f5f6f8; --surface: #ffffff; --surface-2: #f9fafb; --text: #111827; --text-2: #4b5563; --text-3: #9ca3af;
    --line: #e5e7eb; --accent: #4f46e5; --accent-soft: #eef2ff;
    --amber: #b45309; --amber-soft: #fef3c7; --sky: #0369a1; --sky-soft: #e0f2fe;
    --emerald: #047857; --emerald-soft: #d1fae5; --slate: #64748b; --slate-soft: #f1f5f9; --rose: #be123c; --rose-soft: #ffe4e6;
    --shadow: 0 1px 2px rgba(16,24,40,.04), 0 1px 3px rgba(16,24,40,.06);
    --radius: 14px;
  }
  :root[data-theme="dark"] {
      --bg: #0b0d12; --surface: #141821; --surface-2: #1a1f2a; --text: #f3f4f6; --text-2: #c2c8d2; --text-3: #7c8594;
      --line: #262c38; --accent: #a5b4fc; --accent-soft: #1e1b4b;
      --amber: #fbbf24; --amber-soft: #3a2a08; --sky: #7dd3fc; --sky-soft: #0c2a3d;
      --emerald: #6ee7b7; --emerald-soft: #0b2e22; --slate: #94a3b8; --slate-soft: #1c2230; --rose: #fda4af; --rose-soft: #3b0f1a;
      --shadow: 0 1px 2px rgba(0,0,0,.3);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #0b0d12; --surface: #141821; --surface-2: #1a1f2a; --text: #f3f4f6; --text-2: #c2c8d2; --text-3: #7c8594;
      --line: #262c38; --accent: #a5b4fc; --accent-soft: #1e1b4b;
      --amber: #fbbf24; --amber-soft: #3a2a08; --sky: #7dd3fc; --sky-soft: #0c2a3d;
      --emerald: #6ee7b7; --emerald-soft: #0b2e22; --slate: #94a3b8; --slate-soft: #1c2230; --rose: #fda4af; --rose-soft: #3b0f1a;
      --shadow: 0 1px 2px rgba(0,0,0,.3);
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body { font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
         background: var(--bg); color: var(--text); -webkit-font-smoothing: antialiased; }
  a { color: inherit; }
  .icon { width: 18px; height: 18px; flex: none; stroke-width: 1.8; }
  .icon.sm { width: 15px; height: 15px; } .icon.lg { width: 22px; height: 22px; }
  .app { display: grid; grid-template-columns: 248px 1fr; min-height: 100vh;
         background: linear-gradient(to right, var(--surface) 247px, var(--line) 247px, var(--line) 248px, var(--bg) 248px); }
  aside { background: var(--surface); border-right: 1px solid var(--line); padding: 22px 14px; position: sticky; top: 0; height: 100vh;
          display: flex; flex-direction: column; gap: 6px; }
  .brand { display: flex; align-items: center; gap: 10px; padding: 0 10px 18px; font-weight: 650; font-size: 16px; letter-spacing: -.01em; }
  .brand .logo { width: 34px; height: 34px; border-radius: 10px; background: var(--accent); color: #fff; display: grid; place-items: center; }
  :root[data-theme="dark"] .brand .logo { color: #0b0d12; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .brand .logo { color: #0b0d12; } }
  .brand small { display: block; font-weight: 450; color: var(--text-3); font-size: 12px; }
  nav a { display: flex; align-items: center; gap: 10px; padding: 9px 12px; border-radius: 10px; text-decoration: none; color: var(--text-2); font-weight: 500; }
  nav a:hover { background: var(--surface-2); color: var(--text); }
  nav a.active { background: var(--accent-soft); color: var(--accent); }
  nav a .count { margin-left: auto; font-size: 12px; background: var(--surface-2); color: var(--text-2); border-radius: 999px; padding: 0 8px; }
  nav a .count.alert { background: var(--amber-soft); color: var(--amber); }
  .aside-foot { margin-top: auto; padding: 12px; font-size: 12px; color: var(--text-3); display: grid; gap: 8px; }
  .aside-foot button { all: unset; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; color: var(--text-2); }
  .theme { display: inline-flex; padding: 3px; border-radius: 10px; background: var(--surface-2); border: 1px solid var(--line); gap: 2px; }
  .theme button { all: unset; cursor: pointer; display: inline-flex; align-items: center; gap: 5px; padding: 5px 8px; border-radius: 7px; font-size: 12px; color: var(--text-2); }
  .theme button[aria-pressed="true"] { background: var(--surface); color: var(--text); box-shadow: var(--shadow); }
  .theme-mobile { display: none; }
  main { padding: 32px 40px 56px; max-width: 1180px; width: 100%; }
  .page-title { font-size: 26px; font-weight: 680; letter-spacing: -.02em; margin: 0 0 4px; }
  .lead { color: var(--text-2); margin: 0 0 28px; font-size: 16px; }
  h2.section { display: flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 620; margin: 32px 0 12px; color: var(--text); }
  h2.section .hint { font-weight: 400; color: var(--text-3); font-size: 13px; }
  .card { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); }
  .stack { display: grid; gap: 12px; }
  .grid-2 { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 14px; }
  .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; }
  .kpi { padding: 16px 18px; display: flex; gap: 14px; align-items: center; }
  .kpi .badge { width: 40px; height: 40px; border-radius: 12px; display: grid; place-items: center; }
  .kpi b { font-size: 24px; font-weight: 680; display: block; line-height: 1.1; }
  .kpi span { color: var(--text-2); font-size: 13px; }
  .tone-amber { background: var(--amber-soft); color: var(--amber); } .tone-sky { background: var(--sky-soft); color: var(--sky); }
  .tone-emerald { background: var(--emerald-soft); color: var(--emerald); } .tone-slate { background: var(--slate-soft); color: var(--slate); }
  .tone-rose { background: var(--rose-soft); color: var(--rose); } .tone-accent { background: var(--accent-soft); color: var(--accent); }
  .action { padding: 16px 18px; display: grid; grid-template-columns: auto 1fr auto; gap: 14px; align-items: center; border-left: 4px solid var(--amber); }
  .action .badge { width: 38px; height: 38px; border-radius: 11px; display: grid; place-items: center; }
  .action p { margin: 0; } .action .what { font-weight: 560; } .muted { color: var(--text-2); } .faint { color: var(--text-3); font-size: 13px; }
  .btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 12px; border-radius: 10px; border: 1px solid var(--line);
         background: var(--surface); text-decoration: none; font-weight: 520; font-size: 14px; color: var(--text); white-space: nowrap; }
  .btn:hover { border-color: var(--accent); color: var(--accent); }
  .empty { padding: 22px; text-align: center; color: var(--text-2); display: grid; justify-items: center; gap: 8px; }
  .pill { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px; border-radius: 999px; font-size: 12.5px; font-weight: 560; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { font-size: 12.5px; padding: 3px 9px; border-radius: 8px; background: var(--surface-2); border: 1px solid var(--line); color: var(--text-2); }
  code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12.5px; }
  .feature-mini { padding: 16px 18px; display: grid; gap: 10px; text-decoration: none; }
  .feature-mini:hover { border-color: var(--accent); }
  .row { display: flex; align-items: center; gap: 10px; } .row.between { justify-content: space-between; }
  .bar { height: 6px; border-radius: 99px; background: var(--slate-soft); overflow: hidden; }
  .bar i { display: block; height: 100%; background: var(--accent); border-radius: 99px; }
  .feed { padding: 6px 0; }
  .feed-item { display: grid; grid-template-columns: 34px 1fr auto; gap: 12px; padding: 10px 18px; align-items: start; }
  .feed-item + .feed-item { border-top: 1px solid var(--line); }
  .feed-item .badge { width: 30px; height: 30px; border-radius: 9px; display: grid; place-items: center; }
  .project-card { padding: 18px; display: grid; gap: 12px; text-decoration: none; }
  .project-card:hover { border-color: var(--accent); }
  .project-card h3 { margin: 0; font-size: 17px; font-weight: 640; }
  /* Process d'une feature */
  .process { padding: 22px 20px 18px; overflow-x: auto; }
  .steps { display: flex; align-items: flex-start; min-width: 720px; }
  .step { flex: 1; display: grid; justify-items: center; text-align: center; gap: 8px; position: relative; padding: 0 4px; }
  .step::before { content: ""; position: absolute; top: 21px; left: calc(-50% + 26px); right: calc(50% + 26px); height: 2px; background: var(--line); }
  .step:first-child::before { display: none; }
  .step.s-done::before, .step.s-active::before, .step.s-waiting::before { background: var(--accent); }
  .step .dot { width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; border: 2px solid var(--line); background: var(--surface); color: var(--text-3); z-index: 1; }
  .step.s-done .dot { background: var(--accent); border-color: var(--accent); color: #fff; }
  :root[data-theme="dark"] .step.s-done .dot { color: #0b0d12; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .step.s-done .dot { color: #0b0d12; } }
  .step.s-active .dot { border-color: var(--sky); color: var(--sky); background: var(--sky-soft); box-shadow: 0 0 0 5px var(--sky-soft); }
  .step.s-waiting .dot { border-color: var(--amber); color: var(--amber); background: var(--amber-soft); box-shadow: 0 0 0 5px var(--amber-soft); }
  .step.s-skipped .dot { border-style: dashed; }
  .step .label { font-weight: 580; font-size: 13.5px; }
  .step .state { font-size: 12px; color: var(--text-3); }
  .step.s-active .state { color: var(--sky); } .step.s-waiting .state { color: var(--amber); font-weight: 560; } .step.s-done .state { color: var(--text-2); }
  .spin { animation: spin 1.6s linear infinite; } @keyframes spin { to { transform: rotate(360deg); } }
  .callout { margin-top: 18px; padding: 12px 14px; border-radius: 12px; display: flex; gap: 10px; align-items: flex-start; font-size: 14px; }
  .callout ul.plain { margin: 4px 0 8px; padding-left: 18px; } .callout ul.plain li { margin: 2px 0; }
  .two-cols { display: grid; grid-template-columns: 1.4fr 1fr; gap: 14px; }
  .kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 16px; font-size: 14px; padding: 16px 18px; }
  .kv dt { color: var(--text-3); } .kv dd { margin: 0; }
  .list { margin: 0; padding: 6px 0; list-style: none; }
  .list li { padding: 9px 18px; display: flex; gap: 10px; align-items: center; font-size: 14px; }
  .list li + li { border-top: 1px solid var(--line); }
  .back { display: inline-flex; align-items: center; gap: 6px; color: var(--text-2); text-decoration: none; font-size: 14px; margin-bottom: 14px; }
  /* Documentation */
  .doc { display: grid; grid-template-columns: 200px 1fr; gap: 28px; align-items: start; }
  .toc { position: sticky; top: 24px; display: grid; gap: 2px; font-size: 14px; }
  .toc a { text-decoration: none; color: var(--text-2); padding: 6px 10px; border-radius: 8px; }
  .toc a:hover { background: var(--surface); color: var(--text); }
  .doc section { scroll-margin-top: 20px; }
  .doc h3 { font-size: 19px; margin: 0 0 6px; letter-spacing: -.01em; }
  .doc p { margin: 0 0 12px; color: var(--text-2); }
  .doc .block { padding: 20px 22px; margin-bottom: 18px; }
  .flow { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin-top: 14px; }
  .flow-step { padding: 14px; border-radius: 12px; background: var(--surface-2); border: 1px solid var(--line); display: grid; gap: 6px; font-size: 13.5px; }
  .flow-step b { display: flex; align-items: center; gap: 8px; font-size: 14px; }
  .flow-step.gate { border-color: var(--amber); background: var(--amber-soft); }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 10px 12px; vertical-align: top; border-top: 1px solid var(--line); }
  th { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: var(--text-3); border-top: none; }
  td code { white-space: nowrap; color: var(--accent); }
  .steps-num { counter-reset: n; display: grid; gap: 10px; margin: 8px 0 0; padding: 0; list-style: none; }
  .steps-num li { counter-increment: n; display: grid; grid-template-columns: 28px 1fr; gap: 10px; color: var(--text-2); }
  .steps-num li::before { content: counter(n); width: 26px; height: 26px; border-radius: 50%; background: var(--accent-soft); color: var(--accent); display: grid; place-items: center; font-weight: 650; font-size: 13px; }
  .faq dt { font-weight: 580; margin-top: 12px; } .faq dd { margin: 4px 0 0; color: var(--text-2); }
  /* Documents */
  .doc-view { display: grid; grid-template-columns: 1fr 220px; gap: 24px; align-items: start; }
  .doc-toc { position: sticky; top: 24px; font-size: 13px; display: grid; gap: 2px; max-height: 80vh; overflow: auto; }
  .doc-toc a { text-decoration: none; color: var(--text-2); padding: 4px 8px; border-radius: 6px; }
  .doc-toc a:hover { background: var(--surface); color: var(--text); }
  .doc-toc a.h3 { padding-left: 18px; }
  .md { padding: 28px 32px; font-size: 15px; line-height: 1.65; overflow-wrap: anywhere; }
  .md h1, .md h2, .md h3, .md h4 { letter-spacing: -.01em; line-height: 1.3; margin: 1.6em 0 .5em; scroll-margin-top: 20px; }
  .md h1 { font-size: 24px; margin-top: 0; } .md h2 { font-size: 19px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
  .md h3 { font-size: 16px; } .md h4 { font-size: 14px; }
  .md p, .md ul, .md ol, .md blockquote, .md pre, .md table { margin: 0 0 14px; }
  .md ul, .md ol { padding-left: 22px; } .md li { margin: 3px 0; }
  .md code { background: var(--surface-2); border: 1px solid var(--line); border-radius: 5px; padding: 1px 5px; color: var(--text); white-space: normal; }
  .md pre { background: var(--surface-2); border: 1px solid var(--line); border-radius: 10px; padding: 14px; overflow-x: auto; }
  .md pre code { background: none; border: none; padding: 0; white-space: pre; }
  .md blockquote { border-left: 3px solid var(--accent); padding: 4px 14px; color: var(--text-2); background: var(--surface-2); border-radius: 0 8px 8px 0; }
  .md .table-wrap { overflow-x: auto; margin: 0 0 14px; } .md .table-wrap table { margin: 0; min-width: 60%; }
  .md table { border-collapse: collapse; } .md th, .md td { border: 1px solid var(--line); padding: 7px 10px; vertical-align: top; }
  .md tbody tr:nth-child(even) td { background: var(--surface-2); }
  .md del { color: var(--text-3); }
  .md .codeblock { position: relative; margin: 0 0 14px; } .md .codeblock pre { margin: 0; }
  .md .codeblock .lang { position: absolute; top: 6px; right: 10px; font-size: 11px; color: var(--text-3); text-transform: uppercase; letter-spacing: .04em; }
  .mmd { margin: 0 0 16px; padding: 16px; border: 1px solid var(--line); border-radius: 12px; background: var(--surface); overflow-x: auto; text-align: center; }
  .mmd pre.mermaid { margin: 0; text-align: left; background: none; border: none; padding: 0; white-space: pre; font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; color: var(--text-2); }
  .mmd pre.mermaid[data-processed] { text-align: center; white-space: normal; }
  .mmd .mmd-note { display: block; margin-top: 8px; font-size: 12px; color: var(--text-3); text-align: left; }
  .md th { text-transform: none; font-size: 13px; letter-spacing: 0; color: var(--text); background: var(--surface-2); }
  .md hr { border: none; border-top: 1px solid var(--line); margin: 22px 0; }
  .md a { color: var(--accent); }
  .doc-actions { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 18px; }
  .doclink { text-decoration: none; } .doclink:hover span:first-of-type { color: var(--accent); }
  /* Design */
  .screens { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
  .screen-card { text-decoration: none; display: grid; gap: 0; overflow: hidden; }
  .screen-card:hover { border-color: var(--accent); }
  .screen-thumb { height: 170px; overflow: hidden; background: var(--surface-2); border-bottom: 1px solid var(--line); position: relative; }
  .screen-thumb iframe { width: 1280px; height: 850px; border: 0; transform: scale(.25); transform-origin: 0 0; pointer-events: none; background: #fff; }
  .screen-thumb .ph { position: absolute; inset: 0; display: grid; place-items: center; color: var(--text-3); }
  .screen-body { padding: 12px 14px; display: grid; gap: 6px; }
  .mockup-frame { width: 100%; height: 820px; border: 1px solid var(--line); border-radius: var(--radius); background: #fff; }
  .seg { display: inline-flex; gap: 4px; padding: 3px; border-radius: 10px; background: var(--surface-2); border: 1px solid var(--line); margin-bottom: 14px; }
  .seg a { text-decoration: none; padding: 6px 12px; border-radius: 7px; font-size: 14px; color: var(--text-2); display: inline-flex; gap: 6px; align-items: center; }
  .seg a.on { background: var(--surface); color: var(--text); box-shadow: var(--shadow); }
  /* Répondre à une validation */
  .reply { margin-top: 14px; padding: 16px; border-radius: 12px; border: 1px solid var(--line); background: var(--surface-2); display: grid; gap: 12px; }
  .reply-choices { display: flex; flex-wrap: wrap; gap: 8px; }
  .reply-choices button { all: unset; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; padding: 8px 12px; border-radius: 10px;
                          border: 1px solid var(--line); background: var(--surface); font-size: 14px; font-weight: 520; }
  .reply-choices button[aria-pressed="true"] { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }
  .reply textarea { width: 100%; min-height: 84px; resize: vertical; border-radius: 10px; border: 1px solid var(--line); background: var(--surface);
                    color: var(--text); padding: 10px 12px; font: inherit; }
  .reply pre { margin: 0; white-space: pre-wrap; font-size: 13px; background: var(--surface); border: 1px dashed var(--line); border-radius: 10px; padding: 10px 12px; }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  .btn.primary:hover { color: #fff; opacity: .92; }
  :root[data-theme="dark"] .btn.primary { color: #0b0d12; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .btn.primary { color: #0b0d12; } }
  .copied { color: var(--emerald); font-size: 13px; font-weight: 560; }
  .print-only { display: none; }
  /* Activité : projets actifs, agent au travail */
  .live { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; color: var(--emerald); background: var(--emerald-soft); padding: 2px 9px; border-radius: 999px; }
  .live::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; animation: pulse 1.6s ease-in-out infinite; }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .25; } }
  @media (prefers-reduced-motion: reduce) { .live::before { animation: none; } }
  .card.is-live { border-color: color-mix(in srgb, var(--emerald) 45%, var(--line)); }
  .now { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-radius: 10px; background: var(--sky-soft); color: var(--sky); font-weight: 560; margin: 0 0 14px; }
  /* Parcours d'une feature : tronc commun, voies backend et frontend, intégration */
  .lanes-wrap { overflow-x: auto; padding: 4px 2px 8px; }
  .lanes { display: block; min-width: 860px; width: 100%; height: auto; }
  .lanes text { font: 600 14px ui-sans-serif, system-ui, sans-serif; fill: var(--text); }
  .lanes text.sub { font-weight: 450; font-size: 12px; fill: var(--text-3); }
  .lanes text.lane { font-weight: 650; font-size: 12.5px; fill: var(--text-2); letter-spacing: .03em; }
  .mmd svg { height: auto; }
  .lanes .edge { fill: none; stroke: var(--line); stroke-width: 2; } .lanes .edge.on { stroke: var(--accent); }
  .lanes .node rect { fill: var(--surface); stroke: var(--line); stroke-width: 1.5; }
  .lanes .node.s-done rect { fill: var(--accent-soft); stroke: var(--accent); }
  .lanes .node.s-active rect { fill: var(--sky-soft); stroke: var(--sky); stroke-width: 2; }
  .lanes .node.s-waiting rect { fill: var(--amber-soft); stroke: var(--amber); stroke-width: 2; }
  .lanes .node.s-skipped rect, .lanes .node.s-out rect { stroke-dasharray: 4 3; }
  .lanes .node.s-out text { fill: var(--text-3); }
  .lanes .node svg { color: var(--text-3); } .lanes .node.s-done svg { color: var(--accent); }
  .lanes .node.s-active svg { color: var(--sky); } .lanes .node.s-waiting svg { color: var(--amber); }
  .legend { display: flex; flex-wrap: wrap; gap: 14px; font-size: 12.5px; color: var(--text-2); margin-top: 6px; }
  .legend i { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 6px; border: 1.5px solid var(--line); vertical-align: -1px; }
  .legend .l-done { background: var(--accent-soft); border-color: var(--accent); } .legend .l-active { background: var(--sky-soft); border-color: var(--sky); }
  .legend .l-waiting { background: var(--amber-soft); border-color: var(--amber); } .legend .l-out { border-style: dashed; }
  /* Qui a fait quoi */
  .runs { width: 100%; border-collapse: collapse; font-size: 14px; }
  .runs th { text-align: left; font-size: 12px; color: var(--text-3); font-weight: 600; padding: 10px 14px; border-bottom: 1px solid var(--line); }
  .runs td { padding: 10px 14px; border-bottom: 1px solid var(--line); vertical-align: top; }
  .runs tr:last-child td { border-bottom: none; }
  .runs details summary { cursor: pointer; color: var(--text-2); } .runs details ul { margin: 6px 0 0; padding-left: 18px; font-size: 12.5px; }
  @page { size: A4; margin: 18mm 15mm 18mm; }
  @page { @bottom-right { content: counter(page) " / " counter(pages); font-size: 9pt; color: #666; } }
  @media print {
    :root, :root[data-theme="dark"] { --bg: #fff; --surface: #fff; --surface-2: #f6f7f9; --text: #111; --text-2: #333; --text-3: #666; --line: #d9dce1;
      --accent: #3730a3; --accent-soft: #eef2ff; --amber-soft: #fef3c7; --sky-soft: #e0f2fe; }
    html, body { background: #fff !important; color: #111; font-size: 10.5pt; }
    aside, .no-print, .back, .doc-toc, .doc-actions, .callout, .page-title, .lead { display: none !important; }
    .print-only { display: block; }
    .app { display: block; background: #fff; } main { padding: 0; max-width: none; }
    .card { box-shadow: none; border: none; } .md { padding: 0; font-size: 10.5pt; line-height: 1.5; }
    .doc-view { display: block; }
    .print-head { border-bottom: 2px solid #111; padding-bottom: 8px; margin-bottom: 14px; }
    .print-head .t { font-size: 18pt; font-weight: 700; } .print-head .m { font-size: 9pt; color: #555; margin-top: 2px; }
    .print-toc { border: 1px solid #d9dce1; border-radius: 6px; padding: 10px 14px; margin: 0 0 16px; font-size: 9.5pt; }
    .print-toc b { display: block; margin-bottom: 4px; } .print-toc .h3 { padding-left: 14px; }
    .md h1, .md h2, .md h3, .md h4 { break-after: avoid; page-break-after: avoid; }
    .md h2 { margin-top: 1.3em; }
    .md pre, .md .codeblock, .md blockquote, .mmd, .md tr, .md img { break-inside: avoid; page-break-inside: avoid; }
    .md .table-wrap { overflow: visible; } .md table { width: 100%; } .md thead { display: table-header-group; }
    .md pre { white-space: pre-wrap; } .md pre code { white-space: pre-wrap; }
    .md a { color: #111; text-decoration: underline; }
    .md pre, .md code, .md tbody tr:nth-child(even) td, .mmd { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .mmd { border-color: #d9dce1; } .mmd .mmd-note { display: none; }
  }
  @media (max-width: 900px) {
    .app { grid-template-columns: 1fr; background: var(--bg); }
    aside { position: static; height: auto; flex-direction: row; flex-wrap: wrap; align-items: center; padding: 12px 16px; }
    .brand { padding: 0 8px 0 0; } nav { display: flex; gap: 4px; flex-wrap: wrap; } .aside-foot { display: none; }
    .theme-mobile { display: inline-flex; margin-left: auto; }
    main { padding: 22px 16px 40px; } .two-cols, .doc { grid-template-columns: 1fr; } .toc { position: static; display: none; }
    .action { grid-template-columns: auto 1fr; } .action .btn { grid-column: 1 / -1; justify-self: start; }
    .doc-view { grid-template-columns: 1fr; } .doc-toc { display: none; } .md { padding: 20px 18px; }
  }
</style>
</head>
<body>
<div class="app">
  <aside>
    <div class="brand"><span class="logo" data-icon="workflow"></span><span>Top Factory<small>Tableau de bord</small></span></div>
    <nav id="nav"></nav>
    <div class="theme theme-mobile" id="theme-m" role="group" aria-label="Thème"></div>
    <div class="aside-foot">
      <div class="theme" id="theme" role="group" aria-label="Thème"></div>
      <span id="updated"></span>
      <button id="auto" type="button"></button>
      <span id="kit"></span>
    </div>
  </aside>
  <main id="view" aria-live="polite"></main>
</div>
<script id="data" type="application/json">
TF_HTML_END
cat "$work/data.json"
cat <<'TF_HTML_END'
</script>
<script>
const ICONS = {"layout-dashboard": "<rect width=\"7\" height=\"9\" x=\"3\" y=\"3\" rx=\"1\" /> <rect width=\"7\" height=\"5\" x=\"14\" y=\"3\" rx=\"1\" /> <rect width=\"7\" height=\"9\" x=\"14\" y=\"12\" rx=\"1\" /> <rect width=\"7\" height=\"5\" x=\"3\" y=\"16\" rx=\"1\" />", "folder-kanban": "<path d=\"M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z\" /> <path d=\"M8 10v4\" /> <path d=\"M12 10v2\" /> <path d=\"M16 10v6\" />", "book-open": "<path d=\"M12 7v14\" /> <path d=\"M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z\" />", "git-branch": "<line x1=\"6\" x2=\"6\" y1=\"3\" y2=\"15\" /> <circle cx=\"18\" cy=\"6\" r=\"3\" /> <circle cx=\"6\" cy=\"18\" r=\"3\" /> <path d=\"M18 9a9 9 0 0 1-9 9\" />", "file-text": "<path d=\"M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z\" /> <path d=\"M14 2v4a2 2 0 0 0 2 2h4\" /> <path d=\"M10 9H8\" /> <path d=\"M16 13H8\" /> <path d=\"M16 17H8\" />", "circle-pause": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <line x1=\"10\" x2=\"10\" y1=\"15\" y2=\"9\" /> <line x1=\"14\" x2=\"14\" y1=\"15\" y2=\"9\" />", "compass": "<path d=\"m16.24 7.76-1.804 5.411a2 2 0 0 1-1.265 1.265L7.76 16.24l1.804-5.411a2 2 0 0 1 1.265-1.265z\" /> <circle cx=\"12\" cy=\"12\" r=\"10\" />", "code": "<polyline points=\"16 18 22 12 16 6\" /> <polyline points=\"8 6 2 12 8 18\" />", "flask-conical": "<path d=\"M10 2v7.527a2 2 0 0 1-.211.896L4.72 20.55a1 1 0 0 0 .9 1.45h12.76a1 1 0 0 0 .9-1.45l-5.069-10.127A2 2 0 0 1 14 9.527V2\" /> <path d=\"M8.5 2h7\" /> <path d=\"M7 16h10\" />", "search-check": "<path d=\"m8 11 2 2 4-4\" /> <circle cx=\"11\" cy=\"11\" r=\"8\" /> <path d=\"m21 21-4.3-4.3\" />", "git-commit-horizontal": "<circle cx=\"12\" cy=\"12\" r=\"3\" /> <line x1=\"3\" x2=\"9\" y1=\"12\" y2=\"12\" /> <line x1=\"15\" x2=\"21\" y1=\"12\" y2=\"12\" />", "git-pull-request": "<circle cx=\"18\" cy=\"18\" r=\"3\" /> <circle cx=\"6\" cy=\"6\" r=\"3\" /> <path d=\"M13 6h3a2 2 0 0 1 2 2v7\" /> <line x1=\"6\" x2=\"6\" y1=\"9\" y2=\"21\" />", "bug": "<path d=\"m8 2 1.88 1.88\" /> <path d=\"M14.12 3.88 16 2\" /> <path d=\"M9 7.13v-1a3.003 3.003 0 1 1 6 0v1\" /> <path d=\"M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6\" /> <path d=\"M12 20v-9\" /> <path d=\"M6.53 9C4.6 8.8 3 7.1 3 5\" /> <path d=\"M6 13H2\" /> <path d=\"M3 21c0-2.1 1.7-3.9 3.8-4\" /> <path d=\"M20.97 5c0 2.1-1.6 3.8-3.5 4\" /> <path d=\"M22 13h-4\" /> <path d=\"M17.2 17c2.1.1 3.8 1.9 3.8 4\" />", "hammer": "<path d=\"m15 12-8.373 8.373a1 1 0 1 1-3-3L12 9\" /> <path d=\"m18 15 4-4\" /> <path d=\"m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172V7l-2.26-2.26a6 6 0 0 0-4.202-1.756L9 2.96l.92.82A6.18 6.18 0 0 1 12 8.4V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5\" />", "circle-check-big": "<path d=\"M21.801 10A10 10 0 1 1 17 3.335\" /> <path d=\"m9 11 3 3L22 4\" />", "loader-circle": "<path d=\"M21 12a9 9 0 1 1-6.219-8.56\" />", "lock-keyhole": "<circle cx=\"12\" cy=\"16\" r=\"1\" /> <rect x=\"3\" y=\"10\" width=\"18\" height=\"12\" rx=\"2\" /> <path d=\"M7 10V7a5 5 0 0 1 10 0v3\" />", "message-circle-question": "<path d=\"M7.9 20A9 9 0 1 0 4 16.1L2 22Z\" /> <path d=\"M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3\" /> <path d=\"M12 17h.01\" />", "bot": "<path d=\"M12 8V4H8\" /> <rect width=\"16\" height=\"12\" x=\"4\" y=\"8\" rx=\"2\" /> <path d=\"M2 14h2\" /> <path d=\"M20 14h2\" /> <path d=\"M15 13v2\" /> <path d=\"M9 13v2\" />", "play": "<polygon points=\"6 3 20 12 6 21 6 3\" />", "square": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" />", "moon-star": "<path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9\" /> <path d=\"M20 3v4\" /> <path d=\"M22 5h-4\" />", "triangle-alert": "<path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" /> <path d=\"M12 9v4\" /> <path d=\"M12 17h.01\" />", "bell": "<path d=\"M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9\" /> <path d=\"M10.3 21a1.94 1.94 0 0 0 3.4 0\" />", "sparkles": "<path d=\"M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z\" /> <path d=\"M20 3v4\" /> <path d=\"M22 5h-4\" /> <path d=\"M4 17v2\" /> <path d=\"M5 18H3\" />", "history": "<path d=\"M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8\" /> <path d=\"M3 3v5h5\" /> <path d=\"M12 7v5l4 2\" />", "list-checks": "<path d=\"m3 17 2 2 4-4\" /> <path d=\"m3 7 2 2 4-4\" /> <path d=\"M13 6h8\" /> <path d=\"M13 12h8\" /> <path d=\"M13 18h8\" />", "terminal": "<polyline points=\"4 17 10 11 4 5\" /> <line x1=\"12\" x2=\"20\" y1=\"19\" y2=\"19\" />", "users-round": "<path d=\"M18 21a8 8 0 0 0-16 0\" /> <circle cx=\"10\" cy=\"8\" r=\"5\" /> <path d=\"M22 20c0-3.37-2-6.5-4-8a5 5 0 0 0-.45-8.3\" />", "layers": "<path d=\"m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z\" /> <path d=\"m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65\" /> <path d=\"m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65\" />", "settings-2": "<path d=\"M20 7h-9\" /> <path d=\"M14 17H5\" /> <circle cx=\"17\" cy=\"17\" r=\"3\" /> <circle cx=\"7\" cy=\"7\" r=\"3\" />", "shield-check": "<path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\" /> <path d=\"m9 12 2 2 4-4\" />", "cloud-upload": "<path d=\"M12 13v8\" /> <path d=\"M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242\" /> <path d=\"m8 17 4-4 4 4\" />", "clock": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <polyline points=\"12 6 12 12 16 14\" />", "check": "<path d=\"M20 6 9 17l-5-5\" />", "life-buoy": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"m4.93 4.93 4.24 4.24\" /> <path d=\"m14.83 9.17 4.24-4.24\" /> <path d=\"m14.83 14.83 4.24 4.24\" /> <path d=\"m9.17 14.83-4.24 4.24\" /> <circle cx=\"12\" cy=\"12\" r=\"4\" />", "workflow": "<rect width=\"8\" height=\"8\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M7 11v4a2 2 0 0 0 2 2h4\" /> <rect width=\"8\" height=\"8\" x=\"13\" y=\"13\" rx=\"2\" />", "hand": "<path d=\"M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2\" /> <path d=\"M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2\" /> <path d=\"M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8\" /> <path d=\"M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15\" />", "server": "<rect width=\"20\" height=\"8\" x=\"2\" y=\"2\" rx=\"2\" ry=\"2\" /> <rect width=\"20\" height=\"8\" x=\"2\" y=\"14\" rx=\"2\" ry=\"2\" /> <line x1=\"6\" x2=\"6.01\" y1=\"6\" y2=\"6\" /> <line x1=\"6\" x2=\"6.01\" y1=\"18\" y2=\"18\" />", "monitor-smartphone": "<path d=\"M18 8V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h8\" /> <path d=\"M10 19v-3.96 3.15\" /> <path d=\"M7 19h5\" /> <rect width=\"6\" height=\"10\" x=\"16\" y=\"12\" rx=\"2\" />", "arrow-right": "<path d=\"M5 12h14\" /> <path d=\"m12 5 7 7-7 7\" />", "folder": "<path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" />", "rocket": "<path d=\"M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z\" /> <path d=\"m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z\" /> <path d=\"M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0\" /> <path d=\"M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5\" />", "plug": "<path d=\"M12 22v-5\" /> <path d=\"M9 8V2\" /> <path d=\"M15 8V2\" /> <path d=\"M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z\" />", "palette": "<circle cx=\"13.5\" cy=\"6.5\" r=\".5\" fill=\"currentColor\" /> <circle cx=\"17.5\" cy=\"10.5\" r=\".5\" fill=\"currentColor\" /> <circle cx=\"8.5\" cy=\"7.5\" r=\".5\" fill=\"currentColor\" /> <circle cx=\"6.5\" cy=\"12.5\" r=\".5\" fill=\"currentColor\" /> <path d=\"M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z\" />", "circle": "<circle cx=\"12\" cy=\"12\" r=\"10\" />", "info": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M12 16v-4\" /> <path d=\"M12 8h.01\" />", "file-search": "<path d=\"M14 2v4a2 2 0 0 0 2 2h4\" /> <path d=\"M4.268 21a2 2 0 0 0 1.727 1H18a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v3\" /> <path d=\"m9 18-1.5-1.5\" /> <circle cx=\"5\" cy=\"14\" r=\"3\" />", "sun": "<circle cx=\"12\" cy=\"12\" r=\"4\" /> <path d=\"M12 2v2\" /> <path d=\"M12 20v2\" /> <path d=\"m4.93 4.93 1.41 1.41\" /> <path d=\"m17.66 17.66 1.41 1.41\" /> <path d=\"M2 12h2\" /> <path d=\"M20 12h2\" /> <path d=\"m6.34 17.66-1.41 1.41\" /> <path d=\"m19.07 4.93-1.41 1.41\" />", "moon": "<path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z\" />", "printer": "<path d=\"M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2\" /> <path d=\"M6 9V3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v6\" /> <rect x=\"6\" y=\"14\" width=\"12\" height=\"8\" rx=\"1\" />", "external-link": "<path d=\"M15 3h6v6\" /> <path d=\"M10 14 21 3\" /> <path d=\"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\" />", "copy": "<rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\" /> <path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\" />", "smartphone": "<rect width=\"14\" height=\"20\" x=\"5\" y=\"2\" rx=\"2\" ry=\"2\" /> <path d=\"M12 18h.01\" />", "reply": "<polyline points=\"9 17 4 12 9 7\" /> <path d=\"M20 18v-2a4 4 0 0 0-4-4H4\" />", "pencil-line": "<path d=\"M12 20h9\" /> <path d=\"M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z\" /> <path d=\"m15 5 3 3\" />", "check-check": "<path d=\"M18 6 7 17l-5-5\" /> <path d=\"m22 10-7.5 7.5L13 16\" />", "arrow-left": "<path d=\"m12 19-7-7 7-7\" /> <path d=\"M19 12H5\" />", "file-pen": "<path d=\"M12.5 22H18a2 2 0 0 0 2-2V7l-5-5H6a2 2 0 0 0-2 2v9.5\" /> <path d=\"M14 2v4a2 2 0 0 0 2 2h4\" /> <path d=\"M13.378 15.626a1 1 0 1 0-3.004-3.004l-5.01 5.012a2 2 0 0 0-.506.854l-.837 2.87a.5.5 0 0 0 .62.62l2.87-.837a2 2 0 0 0 .854-.506z\" />", "figma": "<path d=\"M5 5.5A3.5 3.5 0 0 1 8.5 2H12v7H8.5A3.5 3.5 0 0 1 5 5.5z\" /> <path d=\"M12 2h3.5a3.5 3.5 0 1 1 0 7H12V2z\" /> <path d=\"M12 12.5a3.5 3.5 0 1 1 7 0 3.5 3.5 0 1 1-7 0z\" /> <path d=\"M5 19.5A3.5 3.5 0 0 1 8.5 16H12v3.5a3.5 3.5 0 1 1-7 0z\" /> <path d=\"M5 12.5A3.5 3.5 0 0 1 8.5 9H12v7H8.5A3.5 3.5 0 0 1 5 12.5z\" />", "swatch-book": "<path d=\"M11 17a4 4 0 0 1-8 0V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2Z\" /> <path d=\"M16.7 13H19a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H7\" /> <path d=\"M 7 17h.01\" /> <path d=\"m11 8 2.3-2.3a2.4 2.4 0 0 1 3.404.004L18.6 7.6a2.4 2.4 0 0 1 .026 3.434L9.9 19.8\" />", "layout-template": "<rect width=\"18\" height=\"7\" x=\"3\" y=\"3\" rx=\"1\" /> <rect width=\"9\" height=\"7\" x=\"3\" y=\"14\" rx=\"1\" /> <rect width=\"5\" height=\"7\" x=\"16\" y=\"14\" rx=\"1\" />", "eye": "<path d=\"M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0\" /> <circle cx=\"12\" cy=\"12\" r=\"3\" />"};
(function () {
  'use strict';
  const D = JSON.parse(document.getElementById('data').textContent);
  const P = D.prefix || '/top-factory:';
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = (name, cls) => `<svg class="icon ${cls || ''}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ICONS.circle}</svg>`;
  const ago = iso => {
    if (!iso) return '';
    const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 45) return 'à l\'instant';
    if (s < 3600) return 'il y a ' + Math.round(s / 60) + ' min';
    if (s < 86400) return 'il y a ' + Math.round(s / 3600) + ' h';
    const d = Math.round(s / 86400); return d === 1 ? 'hier' : 'il y a ' + d + ' jours';
  };
  const fmt = iso => iso ? new Date(iso).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';
  const AGENTS = { 'spec-writer': 'la rédactrice de specs', architect: 'l\'architecte', 'backend-dev': 'le développeur backend',
    'frontend-dev': 'le développeur frontend', 'test-writer': 'l\'auteur des tests', reviewer: 'le relecteur' };
  const agentName = a => (a || '').replace(/^.*:/, '');


  // ---------- Markdown → HTML (tout le texte est échappé : aucun HTML d'un document ne s'exécute) ----------
  function inlineMd(t) {
    return t.split(/(`[^`]+`)/).map(part => {
      if (/^`[^`]+`$/.test(part)) return '<code>' + esc(part.slice(1, -1)) + '</code>';
      let h = esc(part);
      h = h.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+|#[^)\s]*)\)/g, (m0, txt, url) => `<a href="${url}"${url[0] === '#' ? '' : ' target="_blank" rel="noopener noreferrer"'}>${txt}</a>`);
      h = h.replace(/&lt;(https?:\/\/[^\s&]+)&gt;/g, (m0, url) => `<a href="${url}" target="_blank" rel="noopener noreferrer">${url}</a>`);
      h = h.replace(/~~([^~]+)~~/g, '<del>$1</del>');
      h = h.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/__([^_]+)__/g, '<strong>$1</strong>');
      h = h.replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>').replace(/(^|[\s(])_([^_\s][^_]*)_(?=[\s.,;:!?)]|$)/g, '$1<em>$2</em>');
      return h;
    }).join('');
  }
  function renderMd(src) {
    const lines = String(src || '').replace(/\r/g, '').split('\n');
    const out = [], toc = [];
    let i = 0, n = 0;
    const slug = () => 'h-' + (++n);
    const isTableSep = l => /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(l);
    // Cellules d'un tableau : « | » ignoré dans du code (`a|b`) et quand il est échappé (\|).
    const split = l => {
      const t = l.trim().replace(/^\|/, '').replace(/\|$/, ''), out = []; let cur = '', code = false;
      for (let k = 0; k < t.length; k++) {
        const c = t[k];
        if (c === '\\' && t[k + 1] === '|') { cur += '|'; k++; continue; }
        if (c === '`') code = !code;
        if (c === '|' && !code) { out.push(cur); cur = ''; continue; }
        cur += c;
      }
      out.push(cur); return out.map(c => c.trim());
    };
    const cells = l => split(l).map(inlineMd);
    const aligns = l => split(l).map(c => /^:-+:$/.test(c) ? 'center' : /-+:$/.test(c) ? 'right' : '');
    const td = (tag, c, a) => `<${tag}${a ? ` style="text-align:${a}"` : ''}>${c}</${tag}>`;
    while (i < lines.length) {
      const l = lines[i];
      if (/^\s*```/.test(l)) {
        const lang = (l.trim().slice(3).trim().split(/\s+/)[0] || '').toLowerCase();
        const buf = []; i++;
        while (i < lines.length && !/^\s*```/.test(lines[i])) buf.push(lines[i++]);
        i++;
        const src = buf.join('\n');
        // Schéma Mermaid : dessiné par l'afficheur local s'il est installé, sinon montré en texte.
        if (lang === 'mermaid') out.push(`<figure class="mmd"><pre class="mermaid" data-src="${esc(src)}">${esc(src)}</pre></figure>`);
        else out.push(`<div class="codeblock">${lang ? `<span class="lang">${esc(lang)}</span>` : ''}<pre><code>${esc(src)}</code></pre></div>`);
        continue;
      }
      let m = l.match(/^(#{1,6})\s+(.*)$/);
      if (m) {
        const lvl = m[1].length, id = slug(), txt = m[2].replace(/\s+#+\s*$/, '');
        if (lvl <= 3) toc.push({ lvl, id, txt: txt.replace(/[`*_]/g, '') });
        out.push(`<h${lvl} id="${id}">${inlineMd(txt)}</h${lvl}>`); i++; continue;
      }
      if (/^\s*([-*_])\s*\1\s*\1[\s\1]*$/.test(l)) { out.push('<hr>'); i++; continue; }
      if (/\|/.test(l) && i + 1 < lines.length && isTableSep(lines[i + 1])) {
        const head = cells(l), al = aligns(lines[i + 1]); i += 2; const rows = [];
        while (i < lines.length && /\|/.test(lines[i]) && lines[i].trim()) rows.push(cells(lines[i++]));
        out.push('<div class="table-wrap"><table><thead><tr>' + head.map((c, k) => td('th', c, al[k])).join('') + '</tr></thead><tbody>' +
                 rows.map(r => '<tr>' + r.map((c, k) => td('td', c, al[k])).join('') + '</tr>').join('') + '</tbody></table></div>');
        continue;
      }
      if (/^\s*>/.test(l)) {
        const buf = [];
        while (i < lines.length && /^\s*>/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
        out.push('<blockquote>' + renderMd(buf.join('\n')).html + '</blockquote>'); continue;
      }
      if (/^\s*([-*+]|\d+[.)])\s+/.test(l)) {
        const stack = [];
        while (i < lines.length && (/^\s*([-*+]|\d+[.)])\s+/.test(lines[i]) || (/^\s{2,}\S/.test(lines[i]) && stack.length))) {
          const li = lines[i];
          const mm = li.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
          if (!mm) { out.push(' ' + inlineMd(li.trim())); i++; continue; }
          const ind = mm[1].replace(/\t/g, '  ').length, tag = /\d/.test(mm[2]) ? 'ol' : 'ul';
          while (stack.length && ind < stack[stack.length - 1].ind) out.push('</li></' + stack.pop().tag + '>');
          if (!stack.length || ind > stack[stack.length - 1].ind) { out.push('<' + tag + '>'); stack.push({ ind, tag }); }
          else out.push('</li>');
          out.push('<li>' + inlineMd(mm[3].replace(/^\[ \]\s/, '☐ ').replace(/^\[x\]\s/i, '☑ ')));
          i++;
        }
        while (stack.length) out.push('</li></' + stack.pop().tag + '>');
        continue;
      }
      if (!l.trim()) { i++; continue; }
      const buf = [];
      while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|\s*```|\s*>|\s*([-*+]|\d+[.)])\s+)/.test(lines[i]) &&
             !(/\|/.test(lines[i]) && i + 1 < lines.length && isTableSep(lines[i + 1]))) buf.push(lines[i++].trim());
      out.push('<p>' + inlineMd(buf.join(' ')) + '</p>');
    }
    return { html: out.join(''), toc };
  }

  // ---------- Process d'une feature ----------
  const FEATURE = [
    { id: 'branch', label: 'Branche', icon: 'git-branch', help: 'Une branche dédiée, partie de la branche d\'intégration à jour.' },
    { id: 'spec', label: 'Spec', icon: 'file-text', agents: ['spec-writer'], gate: 'valider la spec', ask: 'valides la spec', help: 'Le besoin reformulé : règles, cas limites, questions ouvertes.' },
    { id: 'plan', label: 'Plan technique', icon: 'compass', agents: ['architect'], gate: 'valider le plan technique', ask: 'valides le plan technique', help: 'Couches, classes, migrations, contrat d\'API.' },
    { id: 'design', label: 'Design', icon: 'palette', agents: ['designer'], gate: 'valider le design', ask: 'valides le design', help: 'Facultatif, à ton choix : fiche et maquette de chaque écran (factory, Claude Design ou Figma), à valider avant le code.' },
    { id: 'code', label: 'Code', icon: 'code', agents: ['backend-dev', 'frontend-dev'], back: true, help: 'Backend et frontend ensemble, ou une partie après l\'autre : chacune va jusqu\'à sa revue et son commit.' },
    { id: 'tests', label: 'Tests', icon: 'flask-conical', agents: ['test-writer'], help: 'Tests par couche, intégration avec Testcontainers, ArchUnit.' },
    { id: 'integration', label: 'Intégration API', icon: 'plug', command: 'integrate', help: 'Le frontend quitte les données simulées pour la vraie API.' },
    { id: 'review', label: 'Revue', icon: 'search-check', agents: ['reviewer'], gate: 'décider de la suite à partir du verdict de la revue', ask: 'décides de la suite à partir du verdict de la revue', help: 'Architecture, sécurité, qualité, tests.' },
    { id: 'commit', label: 'Commit', icon: 'git-commit-horizontal', event: 'commit', help: 'Commit au format Conventional Commits, après ton accord.' },
    { id: 'pr', label: 'Pull Request', icon: 'git-pull-request', event: 'push', help: 'Branche poussée ; tu ouvres la PR et tu fusionnes.' },
  ];
  const FIX = [
    { id: 'branch', label: 'Branche', icon: 'git-branch' },
    { id: 'repro', label: 'Reproduire', icon: 'bug', agents: ['test-writer'], help: 'Un test qui échoue prouve le bug.' },
    { id: 'code', label: 'Corriger', icon: 'hammer', agents: ['backend-dev', 'frontend-dev'], back: true, help: 'Correction minimale de la cause racine.' },
    { id: 'review', label: 'Revue', icon: 'search-check', agents: ['reviewer'], gate: 'décider de la suite à partir du verdict de la revue', ask: 'décides de la suite à partir du verdict de la revue' },
    { id: 'commit', label: 'Commit', icon: 'git-commit-horizontal', event: 'commit' },
    { id: 'pr', label: 'Pull Request', icon: 'git-pull-request', event: 'push' },
  ];
  const STATE_TEXT = { done: 'Terminé', active: 'En cours', waiting: 'Ta validation', todo: 'À venir', skipped: 'Non utilisée' };

  function buildProcess(branch, events) {
    const model = /^(fix|bugfix|hotfix)\//.test(branch) ? FIX : FEATURE;
    const st = model.map(() => 'todo');
    const running = {};
    let cur = -1, lastTs = null;
    const idxAgent = a => model.findIndex(s => (s.agents || []).includes(agentName(a)));
    const idxEvent = k => model.findIndex(s => s.event === k);
    const reach = i => {
      for (let k = 1; k < i; k++) if (st[k] === 'todo') st[k] = 'skipped';
      for (let k = 0; k < i; k++) if (st[k] === 'active' || st[k] === 'waiting') st[k] = 'done';
      cur = Math.max(cur, i);
    };
    events.forEach((e, n) => {
      lastTs = e.ts;
      if (n === 0) { st[0] = 'done'; cur = 0; }
      const ag = agentName(e.agent || (e.title || '').replace(/^Agent (\S+).*$/, '$1'));
      if (e.kind === 'agent_start') {
        const i = idxAgent(ag); if (i < 0) return;
        running[i] = (running[i] || 0) + 1;
        if (i < cur && model[i].back) { for (let k = i + 1; k < model.length; k++) if (st[k] !== 'skipped') st[k] = 'todo'; cur = i; }
        else if (i < cur) return;
        reach(i); st[i] = 'active';
      } else if (e.kind === 'agent_end') {
        const i = idxAgent(ag); if (i < 0) return;
        running[i] = Math.max(0, (running[i] || 1) - 1);
        if (!running[i] && st[i] === 'active') st[i] = 'done';
      } else if (e.kind === 'validation') {
        let i = cur; while (i > 0 && !model[i].gate && st[i] !== 'active') i--;
        if (i > 0 && model[i].gate && (st[i] === 'done' || st[i] === 'active')) st[i] = 'waiting';
      } else if (e.kind === 'prompt' && e.command && model.findIndex(s => s.command === e.command) >= 0) {
        const i = model.findIndex(s => s.command === e.command);
        for (let k = 0; k < st.length; k++) if (st[k] === 'waiting') st[k] = 'done';
        reach(i); st[i] = 'active';
      } else if (e.kind === 'prompt') {
        // Tu as répondu : la validation attendue est donnée.
        for (let k = 0; k < st.length; k++) if (st[k] === 'waiting') st[k] = 'done';
      } else if (e.kind === 'commit' || e.kind === 'push') {
        const i = idxEvent(e.kind); if (i < 0) return;
        reach(i); st[i] = 'done';
      }
    });
    const counted = st.filter(s => s !== 'skipped').length;
    const done = st.filter(s => s === 'done').length;
    const curStep = model[Math.max(0, st.findIndex(s => s === 'waiting') >= 0 ? st.findIndex(s => s === 'waiting') : (st.lastIndexOf('active') >= 0 ? st.lastIndexOf('active') : cur))];
    return { model, st, done, total: counted, pct: counted ? Math.round(done * 100 / counted) : 0, current: curStep,
             waiting: st.indexOf('waiting'), lastTs, kind: model === FIX ? 'Correction' : 'Feature' };
  }

  // ---------- Parcours d'une feature en graphe : tronc commun, voies backend et frontend, intégration ----------
  const STATE_TEXT2 = Object.assign({}, STATE_TEXT, { out: 'Hors périmètre' });
  const featSlug = b => b.replace(/^[^/]+\//, '').replace(/-(front|back|frontend|backend)$/i, '').toLowerCase();
  function planOf(p, f) {
    const slug = featSlug(f.branch);
    return (p.docs || []).find(d => /^docs\/specs\//.test(d.rel) && d.name.toLowerCase() === slug + '-plan.md')
        || (p.docs || []).find(d => /^docs\/specs\//.test(d.rel) && /-plan\.md$/i.test(d.name) && d.name.toLowerCase().includes(slug)) || null;
  }
  // Section « Avancement » du plan : état de chaque partie (à faire, en cours, terminé) et ordre choisi.
  function progressOf(plan) {
    if (!plan) return null;
    const m = plan.content.replace(/\r/g, '').match(/^##\s+Avancement\s*$([\s\S]*?)(?=^##\s|(?![\s\S]))/m);
    if (!m) return null;
    const res = { order: '', parts: {} };
    const o = m[1].match(/Ordre\s*:\s*(.+)/i); if (o) res.order = o[1].trim();
    m[1].split('\n').forEach(l => {
      const c = l.split('|').map(x => x.trim()).filter(Boolean);
      if (c.length < 2) return;
      const part = /^back/i.test(c[0]) ? 'back' : /^front/i.test(c[0]) ? 'front' : null;
      if (!part) return;
      const t = c[1].toLowerCase();
      res.parts[part] = /termin/.test(t) ? 'done' : /en cours/.test(t) ? 'active' : 'todo';
    });
    return res;
  }
  function lanesOf(p, f) {
    const evs = (p.events || []).filter(e => e.branch === f.branch);
    const S = { 'code-b': 'todo', 'tests-b': 'todo', 'review-b': 'todo', 'commit-b': 'todo',
                design: 'todo', 'code-f': 'todo', 'tests-f': 'todo', 'review-f': 'todo', 'commit-f': 'todo' };
    const lane = id => (id === 'design' || /-f$/.test(id)) ? 'front' : 'back';
    const ORDER = ['code', 'tests', 'review', 'commit'];
    const idOf = (step, pt) => step + (pt === 'back' ? '-b' : '-f');
    let cur = [], lastStep = null, lastParts = [];
    // Avant une étape : les précédentes de la même voie sont faites (ou sautées si elles n'ont jamais eu lieu).
    const advance = (step, pts) => pts.forEach(pt => ORDER.slice(0, ORDER.indexOf(step)).forEach(o => {
      const id = idOf(o, pt); if (S[id] === 'todo') S[id] = 'skipped'; if (S[id] === 'active' || S[id] === 'waiting') S[id] = 'done';
    }));
    evs.forEach(e => {
      const a = agentName(e.agent);
      if (e.kind === 'agent_start') {
        if (a === 'designer') { S.design = 'active'; lastStep = 'design'; return; }
        let pts, step;
        if (a === 'backend-dev') { pts = ['back']; step = 'code'; }
        else if (a === 'frontend-dev') { pts = ['front']; step = 'code'; if (S.design === 'todo') S.design = 'skipped'; }
        else if (a === 'test-writer' || a === 'reviewer') { pts = cur.length ? cur : lastParts; step = a === 'test-writer' ? 'tests' : 'review'; }
        else return;
        pts.forEach(pt => { if (!cur.includes(pt)) cur.push(pt); });
        advance(step, pts); pts.forEach(pt => { S[idOf(step, pt)] = 'active'; });
        lastStep = step; lastParts = pts;
      } else if (e.kind === 'agent_end') {
        if (a === 'designer') { if (S.design === 'active') S.design = 'done'; return; }
        Object.keys(S).forEach(k => { if (k !== 'design' && S[k] === 'active') S[k] = 'done'; });
      } else if (e.kind === 'validation') {
        if (lastStep === 'design') { if (['active', 'done'].includes(S.design)) S.design = 'waiting'; }
        else if (lastStep) lastParts.forEach(pt => { const id = idOf(lastStep, pt); if (['active', 'done'].includes(S[id])) S[id] = 'waiting'; });
      } else if (e.kind === 'prompt') {
        Object.keys(S).forEach(k => { if (S[k] === 'waiting') S[k] = 'done'; });
      } else if (e.kind === 'commit' && cur.length) {
        advance('commit', cur); cur.forEach(pt => { S[idOf('commit', pt)] = 'done'; });
        lastParts = cur; cur = []; lastStep = null;
      }
    });
    const plan = planOf(p, f), prog = progressOf(plan);
    const scope = prog && Object.keys(prog.parts).length ? prog.parts : null;
    ['back', 'front'].forEach(pt => {
      const ids = Object.keys(S).filter(k => lane(k) === pt);
      if (scope && !(pt in scope)) ids.forEach(k => { S[k] = 'out'; });
      else if (scope && scope[pt] === 'done') ids.forEach(k => { if (S[k] !== 'done') S[k] = k === 'design' ? 'skipped' : 'done'; });
    });
    if (f.st[3] === 'skipped' && S.design === 'todo' && ['done', 'active'].includes(S['code-f'])) S.design = 'skipped';
    const trunk = { branch: f.st[0], spec: f.st[1], plan: f.st[2] };
    if (prog) ['spec', 'plan'].forEach(k => { if (trunk[k] === 'todo' || trunk[k] === 'skipped') trunk[k] = 'done'; });
    const inScope = ['back', 'front'].filter(pt => S[pt === 'back' ? 'code-b' : 'code-f'] !== 'out');
    const laneDone = pt => S[pt === 'back' ? 'commit-b' : 'commit-f'] === 'done';
    const integ = inScope.length && inScope.every(laneDone) ? 'done' : inScope.some(laneDone) || evs.some(e => e.command === 'integrate') ? 'active' : 'todo';
    const pr = f.st[f.st.length - 1] === 'done' && integ === 'done' ? 'done' : 'todo';
    return { S, trunk, integ, pr, prog, plan };
  }
  function laneGraph(L) {
    const W = 106, H = 50, NODE = (id, x, yc, label, ic, st) => {
      const y = yc - H / 2, glyph = st === 'done' ? 'check' : st === 'waiting' ? 'circle-pause' : st === 'active' ? 'loader-circle' : ic;
      return `<g class="node s-${st}"><title>${esc(label)} : ${esc(STATE_TEXT2[st] || '')}</title><rect x="${x}" y="${y}" width="${W}" height="${H}" rx="11"/>
        <svg x="${x + 9}" y="${yc - 8}" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[glyph] || ICONS.circle}</svg>
        <text x="${x + 31}" y="${yc - 2}">${esc(label)}</text><text class="sub" x="${x + 31}" y="${yc + 13}">${esc(STATE_TEXT2[st] || '')}</text></g>`;
    };
    const yT = 127, yB = 50, yF = 204, X = [10, 126, 242], XL = [376, 492, 608, 724, 840], XI = 976, XP = 1092;
    const on = st => st === 'done' ? ' on' : '';
    const line = (x1, y1, x2, y2, st) => y1 === y2 ? `<path class="edge${on(st)}" d="M${x1} ${y1} L${x2} ${y2}"/>`
      : `<path class="edge${on(st)}" d="M${x1} ${y1} C ${(x1 + x2) / 2} ${y1}, ${(x1 + x2) / 2} ${y2}, ${x2} ${y2}"/>`;
    const S = L.S, out = [];
    out.push(line(X[0] + W, yT, X[1], yT, L.trunk.branch), line(X[1] + W, yT, X[2], yT, L.trunk.spec));
    out.push(line(X[2] + W, yT, XL[1], yB, L.trunk.plan), line(X[2] + W, yT, XL[0], yF, L.trunk.plan));
    const back = ['code-b', 'tests-b', 'review-b', 'commit-b'], front = ['design', 'code-f', 'tests-f', 'review-f', 'commit-f'];
    back.forEach((id, k) => { if (k) out.push(line(XL[k] + W, yB, XL[k + 1], yB, S[back[k - 1]])); });
    front.forEach((id, k) => { if (k) out.push(line(XL[k - 1] + W, yF, XL[k], yF, S[front[k - 1]])); });
    out.push(line(XL[4] + W, yB, XI, yT, S['commit-b']), line(XL[4] + W, yF, XI, yT, S['commit-f']), line(XI + W, yT, XP, yT, L.integ));
    const laneTxt = pt => { const st = L.prog && L.prog.parts[pt]; return st === 'done' ? ' · terminé' : st === 'active' ? ' · en cours' : st === 'todo' ? ' · à faire' : ''; };
    out.push(`<text class="lane" x="${XL[1]}" y="16">BACKEND${laneTxt('back')}</text><text class="lane" x="${XL[0]}" y="248">FRONTEND${laneTxt('front')}</text>`);
    out.push(NODE('branch', X[0], yT, 'Branche', 'git-branch', L.trunk.branch), NODE('spec', X[1], yT, 'Spec', 'file-text', L.trunk.spec), NODE('plan', X[2], yT, 'Plan', 'compass', L.trunk.plan));
    [['Code', 'code'], ['Tests', 'flask-conical'], ['Revue', 'search-check'], ['Commit', 'git-commit-horizontal']].forEach(([l, ic], k) => out.push(NODE(back[k], XL[k + 1], yB, l, ic, S[back[k]])));
    [['Design', 'palette'], ['Code', 'code'], ['Tests', 'flask-conical'], ['Revue', 'search-check'], ['Commit', 'git-commit-horizontal']].forEach(([l, ic], k) => out.push(NODE(front[k], XL[k], yF, l, ic, S[front[k]])));
    out.push(NODE('integ', XI, yT, 'Intégration', 'plug', L.integ), NODE('pr', XP, yT, 'Pull Request', 'git-pull-request', L.pr));
    return `<div class="lanes-wrap"><svg class="lanes" viewBox="0 0 1206 256" role="img" aria-label="Parcours de la feature : tronc commun, voies backend et frontend, intégration">${out.join('')}</svg></div>
      <div class="legend"><span><i class="l-done"></i>Terminé</span><span><i class="l-active"></i>En cours</span><span><i class="l-waiting"></i>Ta validation</span><span><i></i>À venir</span><span><i class="l-out"></i>Non utilisé ou hors périmètre</span>${L.prog && L.prog.order ? `<span>· Ordre : ${esc(L.prog.order)}</span>` : ''}</div>`;
  }
  // Schémas Mermaid d'un document (section « Schémas » d'un plan, par exemple).
  function mermaidBlocks(content, max) {
    const out = [], re = /^\s*```mermaid\s*\n([\s\S]*?)^\s*```/gm; let m;
    while ((m = re.exec(String(content || '').replace(/\r/g, ''))) && out.length < (max || 3)) out.push(m[1].replace(/\n$/, ''));
    return out;
  }
  const mmdFigure = src => `<figure class="mmd"><pre class="mermaid" data-src="${esc(src)}">${esc(src)}</pre></figure>`;
  const archDoc = p => (p.docs || []).find(d => d.rel === 'docs/architecture/overview.md') || null;

  // ---------- État d'un projet ----------
  const STATES = {
    validation: { tone: 'amber', icon: 'circle-pause', label: 'Attend ta validation', todo: true },
    permission: { tone: 'amber', icon: 'lock-keyhole', label: 'Attend ton autorisation', todo: true },
    attention: { tone: 'amber', icon: 'message-circle-question', label: 'Attend ta réponse', todo: true },
    turn_end: { tone: 'emerald', icon: 'hand', label: 'À toi de jouer', todo: true },
    agent_start: { tone: 'sky', icon: 'bot', label: 'Un agent travaille', work: true },
    prompt: { tone: 'sky', icon: 'loader-circle', label: 'Claude travaille', work: true },
    agent_end: { tone: 'sky', icon: 'bot', label: 'Claude enchaîne', work: true },
    session_start: { tone: 'sky', icon: 'play', label: 'Session ouverte' },
    commit: { tone: 'emerald', icon: 'git-commit-horizontal', label: 'Commit effectué' },
    push: { tone: 'emerald', icon: 'cloud-upload', label: 'Branche poussée' },
    session_end: { tone: 'slate', icon: 'square', label: 'Session fermée' },
    idle: { tone: 'slate', icon: 'moon-star', label: 'Au repos' },
    missing: { tone: 'rose', icon: 'triangle-alert', label: 'Dossier introuvable' },
  };
  const EVENT_ICON = { prompt: 'message-circle-question', session_start: 'play', session_end: 'square', agent_start: 'bot', agent_end: 'circle-check-big', validation: 'circle-pause',
    permission: 'lock-keyhole', attention: 'message-circle-question', turn_end: 'hand', commit: 'git-commit-horizontal', push: 'cloud-upload' };
  const EVENT_TONE = { validation: 'amber', permission: 'amber', attention: 'amber', turn_end: 'emerald', commit: 'emerald', push: 'emerald',
    agent_start: 'sky', agent_end: 'sky', session_start: 'slate', session_end: 'slate' };

  function analyse(p) {
    const ev = p.events || [];
    const last = ev[ev.length - 1];
    let key = 'idle';
    if (!p.exists) key = 'missing';
    else if (last && Date.now() - new Date(last.ts).getTime() < 86400000) {
      key = STATES[last.kind] ? last.kind : 'idle';
      // Agents encore au travail depuis l'ouverture de la session : Claude n'a pas vraiment rendu la main.
      let open = 0;
      ev.slice(-80).forEach(e => { if (e.kind === 'session_start') open = 0; if (e.kind === 'agent_start') open++; if (e.kind === 'agent_end') open = Math.max(0, open - 1); });
      if (open && ['agent_end', 'turn_end', 'prompt', 'session_start'].includes(key)) key = 'agent_start';
    }
    const base = p.baseBranch || 'develop';
    const byBranch = {};
    ev.forEach(e => { const b = e.branch || ''; if (!b || b === base || b === 'main' || b === 'master' || b === 'HEAD') return; (byBranch[b] = byBranch[b] || []).push(e); });
    const features = Object.entries(byBranch).map(([b, list]) => ({ branch: b, name: b.replace(/^[^/]+\//, '').replace(/[-_]/g, ' '), ...buildProcess(b, list) }))
      .sort((a, b) => (b.lastTs || '').localeCompare(a.lastTs || ''));
    const current = features.find(f => f.branch === p.branch) || null;
    // Actif : une session ouverte (pas encore fermée) avec de l'activité dans les 2 dernières heures, ou une activité
    // de moins de 20 minutes. Agents au travail : démarrés et pas encore terminés depuis l'ouverture de la session.
    let sessionOpen = false;
    ev.forEach(e => { if (e.kind === 'session_start') sessionOpen = true; if (e.kind === 'session_end') sessionOpen = false; });
    const age = last ? Date.now() - new Date(last.ts).getTime() : Infinity;
    const active = p.exists && (age < 1200000 || (sessionOpen && age < 7200000));
    const runs = agentRuns(ev);
    const workingNow = active ? runs.filter(r => r.running) : [];
    features.forEach(f => { f.runs = runs.filter(r => r.branch === f.branch); f.live = active && f.branch === p.branch; });
    return { ...p, key, state: STATES[key], last, features, current, active, runs, workingNow };
  }
  // Qui a fait quoi : chaque passage d'un agent (début, fin, durée, fichiers modifiés, bilan).
  function agentRuns(ev) {
    const runs = [], open = [];
    ev.forEach(e => {
      if (e.kind === 'session_start') { open.splice(0).forEach(r => { r.running = false; r.lost = true; }); }
      if (e.kind === 'agent_start') {
        const r = { agent: agentName(e.agent), id: e.agentId || '', start: e.ts, end: null, branch: e.branch || '', running: true, files: [], nfiles: 0, bilan: '' };
        runs.push(r); open.push(r);
      } else if (e.kind === 'agent_end') {
        let k = -1;
        for (let n = open.length - 1; n >= 0; n--) if ((e.agentId && open[n].id === e.agentId) || (!e.agentId && open[n].agent === agentName(e.agent))) { k = n; break; }
        const r = k >= 0 ? open.splice(k, 1)[0] : (() => { const x = { agent: agentName(e.agent), id: e.agentId || '', start: null, branch: e.branch || '' }; runs.push(x); return x; })();
        Object.assign(r, { end: e.ts, running: false, files: e.files || [], nfiles: e.nfiles || (e.files || []).length, bilan: e.detail || '' });
      }
    });
    return runs;
  }
  const dur = (a, b) => {
    if (!a || !b) return '';
    const m = Math.round((new Date(b) - new Date(a)) / 60000);
    return m < 1 ? '< 1 min' : m < 60 ? m + ' min' : Math.floor(m / 60) + ' h ' + String(m % 60).padStart(2, '0');
  };
  const AGENT_LABEL = { 'spec-writer': 'Spécification', architect: 'Architecte', designer: 'Designer', 'backend-dev': 'Développeur backend',
    'frontend-dev': 'Développeur frontend', 'test-writer': 'Tests', reviewer: 'Relecteur' };
  const agentLabel = a => AGENT_LABEL[a] || (a ? a : 'Agent');
  function runsTable(runs) {
    if (!runs.length) return emptyBox('history', 'Aucun passage d\'agent', 'Chaque agent apparaîtra ici avec sa durée, ses fichiers modifiés et son bilan.');
    return `<div class="card" style="overflow-x:auto"><table class="runs"><thead><tr><th>Agent</th><th>Quand</th><th>Durée</th><th>Fichiers</th><th>Bilan</th></tr></thead><tbody>${
      runs.slice(-20).reverse().map(r => `<tr><td><b>${esc(agentLabel(r.agent))}</b>${r.running ? ' <span class="live">au travail</span>' : ''}</td>
        <td class="faint" title="${esc(fmt(r.start || r.end))}">${ago(r.start || r.end)}</td>
        <td>${r.running ? dur(r.start, new Date().toISOString()) : dur(r.start, r.end) || '—'}</td>
        <td>${r.nfiles ? `<details><summary>${r.nfiles} fichier${r.nfiles > 1 ? 's' : ''}</summary><ul>${r.files.map(f => `<li class="mono">${esc(f)}</li>`).join('')}${r.nfiles > r.files.length ? `<li class="faint">… et ${r.nfiles - r.files.length} autres</li>` : ''}</ul></details>` : '<span class="faint">—</span>'}</td>
        <td>${r.bilan ? esc(r.bilan) : r.running ? '<span class="faint">en cours…</span>' : '<span class="faint">—</span>'}</td></tr>`).join('')}</tbody></table></div>`;
  }
  const projects = (D.projects || []).map(analyse).sort((a, b) =>
    (b.state.todo ? 2 : b.active ? 1 : 0) - (a.state.todo ? 2 : a.active ? 1 : 0) || ((b.last || {}).ts || '').localeCompare((a.last || {}).ts || ''));
  const todo = projects.filter(p => p.state.todo);
  const working = projects.filter(p => p.state.work);

  function sentence(p) {
    const f = p.current, e = p.last || {};
    const what = f ? `<b>${esc(f.name)}</b>` : (e.branch ? `la branche <code>${esc(e.branch)}</code>` : 'le projet');
    switch (p.key) {
      case 'validation': {
        const g = f && f.waiting >= 0 ? f.model[f.waiting].ask : null;
        return g ? `Claude attend que tu ${esc(g)} de ${what}.` : `Claude attend ta validation pour continuer ${what}.`;
      }
      case 'permission': return `Claude a besoin de ton autorisation pour continuer ${what}.`;
      case 'attention': return `Claude t'a posé une question sur ${what}.`;
      case 'turn_end': return `Claude a terminé ce que tu lui as demandé sur ${what} et te rend la main.`;
      default: return '';
    }
  }


  // ---------- Répondre à une validation (réponse prête à copier dans la session Claude) ----------
  const REPLIES = {
    spec: { what: 'la spec', ok: 'Spec validée. Tu peux lancer l\'architecte.',
            notes: 'Spec validée avec ces remarques, à reporter dans la section « Décisions » avant de lancer l\'architecte :\n',
            fix: 'Corrige d\'abord la spec, puis présente-la-moi de nouveau :\n' },
    plan: { what: 'le plan technique', ok: 'Plan validé. Enregistre-le et lance l\'implémentation.',
            notes: 'Plan validé avec ces décisions, à reporter dans le plan avant de lancer l\'implémentation :\n',
            fix: 'Le plan doit être revu avant l\'implémentation :\n' },
    design: { what: 'le design', ok: 'Design validé. Passe le statut des écrans à « validé » et lance l\'implémentation.',
              notes: 'Design validé avec ces remarques, à reporter dans les fiches avant l\'implémentation :\n',
              fix: 'Le design doit être revu avant l\'implémentation (nouvelle proposition du designer) :\n' },
    review: { what: 'le verdict de la revue', ok: 'Verdict accepté : commite au format Conventional Commits, sans pousser.',
              notes: 'Verdict accepté. Avant de commiter, corrige seulement ces points, puis revue rapide et nouveau verdict :\n',
              fix: 'Ne commite pas. Corrige ces points, puis revue rapide et nouveau verdict :\n' },
    other: { what: 'la proposition de Claude', ok: 'C\'est validé, tu peux continuer.',
             notes: 'Validé, avec ces remarques :\n', fix: 'Pas encore. Reprends ces points :\n' },
  };
  function docFor(p, f, gate) {
    if (!f) return -1;
    const slug = f.branch.replace(/^[^/]+\//, '').toLowerCase();
    const docs = p.docs || [];
    const want = gate === 'plan' ? d => /plan/i.test(d.name) : d => !/plan/i.test(d.name);
    let i = docs.findIndex(d => d.name.toLowerCase().includes(slug) && want(d));
    if (i < 0) i = docs.findIndex(d => /^docs\/specs\//.test(d.rel) && want(d));
    return gate === 'review' || gate === 'design' ? -1 : i;
  }
  function replyPanel(p, f, forced) {
    const gate = forced || (f && f.waiting >= 0 ? f.model[f.waiting].id : 'other');
    const R = REPLIES[gate] || REPLIES.other;
    const di = docFor(p, f, gate);
    return `<div class="reply no-print" data-gate="${gate}">
      <div class="row between" style="flex-wrap:wrap"><b>${icon('reply')} Ta réponse</b>
        ${di >= 0 ? `<a class="btn" href="#/projet/${encodeURIComponent(p.id)}/doc/${di}">${icon('file-text', 'sm')} Relire ${esc(R.what)}</a>` : ''}
        ${gate === 'design' && p.design && !/\/design/.test(location.hash || '') ? `<a class="btn" href="#/projet/${encodeURIComponent(p.id)}/design">${icon('palette', 'sm')} Voir les maquettes</a>` : ''}</div>
      <div class="reply-choices">
        <button type="button" data-choice="ok" aria-pressed="true">${icon('check-check', 'sm')} Valider et continuer</button>
        <button type="button" data-choice="notes" aria-pressed="false">${icon('pencil-line', 'sm')} Valider avec remarques</button>
        <button type="button" data-choice="fix" aria-pressed="false">${icon('reply', 'sm')} Demander des corrections</button>
      </div>
      <textarea placeholder="Tes remarques ou corrections, une par ligne…" hidden></textarea>
      <pre class="reply-preview"></pre>
      <div class="row" style="flex-wrap:wrap"><button type="button" class="btn primary" data-copy>${icon('copy', 'sm')} Copier la réponse</button>
        <span class="copied" hidden>Copié ! Colle-la dans ta session Claude (Ctrl+V), puis Entrée.</span></div>
      <span class="faint">Loin de ton ordinateur ? Avec <b>Remote Control</b> (<code>/remote-control</code> dans Claude Code), tu réponds depuis l'application Claude sur ton téléphone. Voir Documentation › Répondre à distance.</span>
    </div>`;
  }
  function wireReplies() {
    document.querySelectorAll('.reply').forEach(box => {
      const R = REPLIES[box.dataset.gate] || REPLIES.other;
      const ta = box.querySelector('textarea'), pv = box.querySelector('.reply-preview'), ok = box.querySelector('.copied');
      let choice = 'ok';
      const text = () => choice === 'ok' ? R.ok : R[choice] + (ta.value.trim() ? ta.value.trim().split('\n').map(x => '- ' + x.replace(/^\s*[-*]\s*/, '')).join('\n') : '- …');
      const draw = () => { pv.textContent = text(); ta.hidden = choice === 'ok'; ok.hidden = true; };
      box.querySelectorAll('[data-choice]').forEach(b => b.addEventListener('click', () => {
        choice = b.dataset.choice; box.querySelectorAll('[data-choice]').forEach(x => x.setAttribute('aria-pressed', String(x === b))); draw(); if (!ta.hidden) ta.focus();
      }));
      ta.addEventListener('input', draw);
      box.querySelector('[data-copy]').addEventListener('click', async () => {
        const t = text();
        try { await navigator.clipboard.writeText(t); }
        catch (e) { const tmp = document.createElement('textarea'); tmp.value = t; document.body.appendChild(tmp); tmp.select(); try { document.execCommand('copy'); } catch (e2) {} tmp.remove(); }
        ok.hidden = false;
      });
      draw();
    });
  }


  // ---------- Design ----------
  const DSTATUS = { 'proposé': { tone: 'amber', icon: 'circle-pause', label: 'Proposé — à valider' }, 'validé': { tone: 'accent', icon: 'check', label: 'Validé' },
    'implémenté': { tone: 'sky', icon: 'code', label: 'Implémenté (données simulées)' }, 'intégré': { tone: 'emerald', icon: 'plug', label: 'Intégré à l\'API' } };
  const SOURCE = { factory: ['palette', 'Factory (agent designer)'], 'claude-design': ['sparkles', 'Claude Design'], figma: ['figma', 'Figma'],
    aucun: ['circle', 'Sans design (ton choix)'] };
  // Liens externes : https uniquement (jamais javascript:, data:…).
  const safeUrl = u => /^https:\/\/[^\s"'<>]+$/.test(u || '') ? u : '';
  // Outil de design du projet : bloc « design » de .claude/stack.json (lien enregistré une fois par /design-link).
  function designTool(p) {
    const t = p.designTool || {};
    const link = safeUrl(t.link);
    const tool = SOURCE[t.tool] && t.tool !== 'aucun' ? t.tool : link ? (/figma\.com/.test(link) ? 'figma' : 'claude-design') : 'factory';
    const sync = tool === 'claude-design' && !link ? safeUrl(t.syncLink) : '';
    return { tool, link: link || sync, fromSync: !!sync };
  }
  function toolCard(p) {
    const t = designTool(p), x = SOURCE[t.tool];
    const text = t.tool === 'factory'
      ? `Les écrans sont proposés par l'agent <b>designer</b>, quand tu le choisis. Tu dessines dans Claude Design ou Figma ? Enregistre son lien une fois : <code>${esc(P)}design-link &lt;url&gt;</code>.`
      : t.link
        ? `Le design se fait dans <b>${esc(x[1])}</b>${t.fromSync ? ' (projet épinglé par <code>/design-sync</code>)' : ''}. Le lien est enregistré dans <code>.claude/stack.json</code> : il reste valable d'une session à l'autre.`
        : `Le design se fait dans <b>${esc(x[1])}</b>, mais aucun lien n'est enregistré : <code>${esc(P)}design-link &lt;url&gt;</code>.`;
    return `<div class="card" style="padding:14px 18px;display:flex;flex-wrap:wrap;gap:12px;align-items:center;justify-content:space-between;margin-bottom:18px">
      <div class="row" style="gap:12px;align-items:center">${badge(x[0], 'accent')}<div><b>Outil de design : ${esc(x[1])}</b><div class="faint" style="font-size:13.5px">${text}</div></div></div>
      ${t.link ? `<a class="btn" href="${esc(t.link)}" target="_blank" rel="noopener noreferrer">${icon('external-link', 'sm')} Ouvrir dans ${esc(x[1])}</a>` : ''}</div>`;
  }
  const dpill = st => { const d = DSTATUS[st] || { tone: 'slate', icon: 'circle', label: st || 'Sans statut' }; return `<span class="pill tone-${d.tone}">${icon(d.icon, 'sm')}${esc(d.label)}</span>`; };
  const srcChip = src => { const x = SOURCE[src] || ['circle', src || '—']; return `<span class="chip">${icon(x[0], 'sm')} ${esc(x[1])}</span>`; };
  const frame = (html, cls) => `<iframe class="${cls}" sandbox="" referrerpolicy="no-referrer" loading="lazy" srcdoc="${esc(html)}" title="Maquette"></iframe>`;
  function projectTabs(p, on) {
    const id = encodeURIComponent(p.id);
    return `<nav class="seg no-print"><a href="#/projet/${id}" class="${on === 'suivi' ? 'on' : ''}">${icon('workflow', 'sm')} Suivi</a>` +
      `<a href="#/projet/${id}/architecture" class="${on === 'architecture' ? 'on' : ''}">${icon('layers', 'sm')} Architecture${archDoc(p) && /statut\s*:\s*propos/i.test(archDoc(p).content.slice(0, 300)) ? ' <span class="count alert" style="margin:0">!</span>' : ''}</a>` +
      `<a href="#/projet/${id}/design" class="${on === 'design' ? 'on' : ''}">${icon('palette', 'sm')} Design${p.design && p.design.screens.some(x => x.status === 'proposé') ? ' <span class="count alert" style="margin:0">!</span>' : ''}</a></nav>`;
  }
  function viewDesign(id) {
    const p = projects.find(x => x.id === id);
    if (!p) return emptyBox('triangle-alert', 'Projet introuvable', '');
    const d = p.design, pid = encodeURIComponent(p.id);
    const head = `<a class="back" href="#/projets">${icon('folder-kanban', 'sm')} Projets</a><div class="row between" style="flex-wrap:wrap"><h1 class="page-title">${esc(p.name)}</h1>${headPill(p)}</div>
      <p class="lead">Un design validé fait référence pour le frontend. Passer par le design reste ton choix, feature par feature.</p>${projectTabs(p, 'design')}${toolCard(p)}`;
    if (!d) return head + emptyBox('palette', 'Pas encore de design', `Pour tout préparer avant les features : <code>${esc(P)}design-project</code>. Sinon, écran par écran : <code>${esc(P)}design-system</code> puis <code>${esc(P)}design-screen &lt;écran&gt;</code>.`);
    const ds = d.designSystem || {};
    const groups = {};
    d.screens.forEach((sc, k) => { (groups[sc.feature || 'Autres écrans'] = groups[sc.feature || 'Autres écrans'] || []).push({ sc, k }); });
    const count = st => d.screens.filter(x => x.status === st).length;
    return head + `
      ${count('proposé') || ds.status === 'proposé' ? `<div class="callout tone-amber">${icon('circle-pause')}<div><b>${count('proposé') ? count('proposé') + ' écran' + (count('proposé') > 1 ? 's attendent' : ' attend') + ' ta validation' : 'Le design system attend ta validation'}.</b>
        Ouvre chaque écran pour voir sa maquette et sa fiche, puis choisis ta réponse ci-dessous et colle-la dans ta session Claude.</div></div>${replyPanel(p, null, 'design')}<div style="height:18px"></div>` : ''}
      <div class="kpis"><div class="card kpi">${badge('layout-template', 'accent')}<div><b>${d.screens.length}</b><span>écran${d.screens.length > 1 ? 's' : ''}</span></div></div>
        <div class="card kpi">${badge('circle-pause', 'amber')}<div><b>${count('proposé')}</b><span>à valider</span></div></div>
        <div class="card kpi">${badge('code', 'sky')}<div><b>${count('implémenté')}</b><span>sur données simulées</span></div></div>
        <div class="card kpi">${badge('plug', 'emerald')}<div><b>${count('intégré')}</b><span>intégré${count('intégré') > 1 ? 's' : ''} à l'API</span></div></div></div>
      <h2 class="section">${icon('swatch-book')} Design system</h2>
      <div class="card" style="padding:16px 18px;display:flex;flex-wrap:wrap;gap:12px;align-items:center;justify-content:space-between">
        <div class="row" style="flex-wrap:wrap">${dpill(ds.status)} ${srcChip(ds.source || 'factory')}</div>
        <div class="row">${safeUrl(ds.link) ? `<a class="btn" href="${esc(ds.link)}" target="_blank" rel="noopener noreferrer">${icon('external-link', 'sm')} Ouvrir dans ${esc((SOURCE[ds.source] || ['', 'l\'outil'])[1])}</a>` : ''}
          ${d.designSystemDoc ? `<a class="btn" href="#/projet/${pid}/design/system">${icon('eye', 'sm')} Voir le design system</a>` : ''}</div></div>
      ${Object.entries(groups).map(([g, list]) => `<h2 class="section">${icon('layout-template')} ${esc(g)} <span class="hint">· ${list.length} écran${list.length > 1 ? 's' : ''}</span></h2>
        <div class="screens">${list.map(({ sc, k }) => `<a class="card screen-card" href="#/projet/${pid}/design/${k}">
          <div class="screen-thumb">${sc.mockupContent ? frame(sc.mockupContent, '') : `<div class="ph">${icon(sc.source === 'figma' ? 'figma' : 'layout-template', 'lg')}</div>`}</div>
          <div class="screen-body"><b>${esc(sc.title || sc.id)}</b><div class="faint mono">${esc(sc.id)}</div><div class="row" style="flex-wrap:wrap;gap:6px">${dpill(sc.status)}${srcChip(sc.source)}</div></div></a>`).join('')}</div>`).join('')}`;
  }
  function viewScreen(id, k) {
    const p = projects.find(x => x.id === id);
    const d = p && p.design, pid = p ? encodeURIComponent(p.id) : '';
    if (!d) return emptyBox('triangle-alert', 'Design introuvable', '');
    if (k === 'system') {
      const r = renderMd(d.designSystemDoc || '');
      return `<a class="back" href="#/projet/${pid}/design">${icon('arrow-left', 'sm')} Design de ${esc(p.name)}</a><h1 class="page-title">Design system</h1>
        <div class="doc-actions"><button type="button" class="btn" onclick="window.print()">${icon('printer', 'sm')} Imprimer / PDF</button></div>
        <div class="doc-view"><article class="card md">${r.html}</article>${r.toc.length > 2 ? `<nav class="doc-toc">${r.toc.map(t => `<a href="#" data-anchor="${t.id}" class="h${t.lvl}">${esc(t.txt)}</a>`).join('')}</nav>` : ''}</div>`;
    }
    const sc = d.screens[+k];
    if (!sc) return emptyBox('triangle-alert', 'Écran introuvable', '');
    const r = renderMd(sc.specContent || '');
    return `<a class="back" href="#/projet/${pid}/design">${icon('arrow-left', 'sm')} Design de ${esc(p.name)}</a>
      <div class="row between" style="flex-wrap:wrap"><h1 class="page-title">${esc(sc.title || sc.id)}</h1>${dpill(sc.status)}</div>
      <p class="lead mono" style="font-size:13px">${esc(sc.id)}${sc.feature ? ' · feature ' + esc(sc.feature) : ''}${sc.updated ? ' · mis à jour le ' + esc(sc.updated) : ''}</p>
      <div class="doc-actions">${srcChip(sc.source)}
        ${safeUrl(sc.link) ? `<a class="btn" href="${esc(sc.link)}" target="_blank" rel="noopener noreferrer">${icon('external-link', 'sm')} Ouvrir dans ${esc((SOURCE[sc.source] || ['', 'l\'outil'])[1])}</a>` : ''}
        <button type="button" class="btn" onclick="window.print()">${icon('printer', 'sm')} Imprimer / PDF</button></div>
      ${sc.status === 'proposé' ? `<div class="callout tone-amber">${icon('circle-pause')}<div><b>Ce design attend ta validation.</b> Choisis ta réponse ci-dessous et colle-la dans ta session Claude ; pour l'améliorer plus tard : <code>${esc(P)}design-improve ${esc(sc.id)} &lt;demande&gt;</code>.</div></div>${replyPanel(p, null, 'design')}` : ''}
      <h2 class="section">${icon('eye')} Maquette</h2>
      ${sc.mockupContent ? frame(sc.mockupContent, 'mockup-frame') : emptyBox('layout-template', 'Pas de maquette dans le dépôt', sc.link ? 'Le design est dans l\'outil externe (bouton ci-dessus). <code>' + esc(P) + 'design-screen ' + esc(sc.id) + '</code> en tire une fiche et une maquette.' : '')}
      <h2 class="section">${icon('file-text')} Fiche de l'écran</h2>
      ${sc.specContent ? `<div class="doc-view"><article class="card md">${r.html}</article>${r.toc.length > 2 ? `<nav class="doc-toc">${r.toc.map(t => `<a href="#" data-anchor="${t.id}" class="h${t.lvl}">${esc(t.txt)}</a>`).join('')}</nav>` : ''}</div>` : emptyBox('file-text', 'Pas de fiche', '')}`;
  }

  // ---------- Rendu ----------
  const badge = (name, tone, size) => `<span class="badge tone-${tone}">${icon(name, size)}</span>`;
  const pill = (st) => `<span class="pill tone-${st.tone}">${icon(st.icon, 'sm')}${esc(st.label)}</span>`;
  // Dans l'en-tête d'un projet : l'état « à toi » est un bouton qui mène au panneau de réponse.
  const headPill = (p) => p.state.todo
    ? `<button type="button" class="pill tone-${p.state.tone}" data-goto-reply="${esc(p.id)}" style="border:0;cursor:pointer" title="Aller au panneau de réponse">${icon(p.state.icon, 'sm')}${esc(p.state.label)} ${icon('arrow-right', 'sm')}</button>`
    : pill(p.state);
  function stepper(f) {
    return `<div class="steps">${f.model.map((s, i) => {
      const k = f.st[i];
      const ic = k === 'done' ? 'check' : k === 'waiting' ? 'circle-pause' : k === 'active' ? 'loader-circle' : s.icon;
      return `<div class="step s-${k}" title="${esc(s.help || '')}"><span class="dot">${icon(ic, (k === 'active' ? 'spin ' : '') + 'lg')}</span>
        <span class="label">${esc(s.label)}</span><span class="state">${STATE_TEXT[k]}</span></div>`;
    }).join('')}</div>`;
  }
  function feedItem(e, p) {
    const tone = EVENT_TONE[e.kind] || 'slate';
    if (e.kind === 'agent_end' && (e.nfiles || e.detail)) e = Object.assign({}, e, { detail: [e.detail, e.nfiles ? e.nfiles + ' fichier' + (e.nfiles > 1 ? 's' : '') + ' modifié' + (e.nfiles > 1 ? 's' : '') : ''].filter(Boolean).join(' · ') });
    return `<div class="feed-item">${badge(EVENT_ICON[e.kind] || 'circle', tone, 'sm')}
      <div><div>${p ? `<b>${esc(p.name)}</b> · ` : ''}${esc((e.title || '').replace(/Agent [\w-]+:/, 'Agent '))}</div>${e.detail ? `<div class="faint">${esc(e.detail)}</div>` : ''}
      ${e.branch ? `<div class="faint">${icon('git-branch', 'sm')} <span class="mono">${esc(e.branch)}</span></div>` : ''}</div>
      <span class="faint" title="${esc(fmt(e.ts))}">${ago(e.ts)}</span></div>`;
  }
  function emptyBox(ic, title, text) { return `<div class="card empty">${badge(ic, 'slate', 'lg')}<b>${esc(title)}</b><span>${text}</span></div>`; }

  function viewOverview() {
    const h = new Date().getHours();
    const hello = (h < 5 || h >= 18 ? 'Bonsoir' : 'Bonjour') + (D.user ? ' ' + esc(D.user) : '');
    const sum = projects.length === 0 ? 'Aucun projet suivi pour l\'instant.'
      : todo.length ? `${todo.length === 1 ? 'Un projet attend' : todo.length + ' projets attendent'} une action de ta part.`
      : working.length ? 'Les agents travaillent, rien ne t\'attend pour le moment.' : 'Tout est calme : rien ne t\'attend.';
    const feats = projects.flatMap(p => p.features.slice(0, 3).map(f => ({ p, f }))).sort((a, b) => (b.f.live ? 1 : 0) - (a.f.live ? 1 : 0) || (b.f.lastTs || '').localeCompare(a.f.lastTs || '')).slice(0, 6);
    const live = projects.filter(p => p.active);
    const feed = projects.flatMap(p => (p.events || []).filter(e => e.kind !== 'prompt').map(e => ({ e, p }))).sort((a, b) => b.e.ts.localeCompare(a.e.ts)).slice(0, 8);
    return `<h1 class="page-title">${hello} 👋</h1><p class="lead">${sum}</p>
    <div class="kpis">
      <div class="card kpi">${badge('folder-kanban', 'accent')}<div><b>${live.length}<small class="faint" style="font-size:14px;font-weight:500"> / ${projects.length}</small></b><span>projet${live.length > 1 ? 's' : ''} actif${live.length > 1 ? 's' : ''}</span></div></div>
      <div class="card kpi">${badge('bell', 'amber')}<div><b>${todo.length}</b><span>en attente de toi</span></div></div>
      <div class="card kpi">${badge('bot', 'sky')}<div><b>${working.length}</b><span>agent${working.length > 1 ? 's' : ''} au travail</span></div></div>
      <div class="card kpi">${badge('list-checks', 'emerald')}<div><b>${feats.length}</b><span>feature${feats.length > 1 ? 's' : ''} en cours</span></div></div>
    </div>
    <h2 class="section">${icon('bell')} Ça t'attend</h2>
    <div class="stack">${todo.length ? todo.map(p => `<div class="card action">${badge(p.state.icon, p.state.tone)}
        <div><p class="what">${esc(p.name)} — ${esc(p.state.label)}</p><p class="muted">${sentence(p)}</p>
        ${p.last && p.last.detail ? `<p class="faint">« ${esc(p.last.detail)} »</p>` : ''}<p class="faint">${ago((p.last || {}).ts)}</p></div>
        <a class="btn" href="#/projet/${encodeURIComponent(p.id)}">${p.key === 'validation' ? 'Répondre' : 'Voir le projet'} ${icon('arrow-right', 'sm')}</a></div>`).join('')
      : emptyBox('sparkles', 'Rien à faire pour toi', 'Tu seras prévenu dès qu\'une validation ou une autorisation sera nécessaire.')}</div>
    <h2 class="section">${icon('workflow')} Features en cours</h2>
    ${feats.length ? `<div class="grid-2">${feats.map(({ p, f }) => `<a class="card feature-mini${f.live ? ' is-live' : ''}" href="#/projet/${encodeURIComponent(p.id)}">
        <div class="row between"><b>${esc(f.name)} ${f.live ? '<span class="live">en cours</span>' : ''}</b><span class="faint">${esc(p.name)}</span></div>
        ${f.live && p.workingNow.length ? `<div class="faint">${icon('bot', 'sm')} ${p.workingNow.map(r => esc(agentLabel(r.agent))).join(', ')} au travail</div>` : ''}
        <div class="bar"><i style="width:${f.pct}%"></i></div>
        <div class="row between faint"><span>${f.waiting >= 0 ? `<span style="color:var(--amber)">${icon('circle-pause', 'sm')} ${esc(f.model[f.waiting].label)} : ta validation</span>` : `Étape : ${esc(f.current.label)}`}</span><span>${f.done}/${f.total}</span></div></a>`).join('')}</div>`
      : emptyBox('workflow', 'Aucune feature en cours', `Lance <code>${esc(P)}feature</code> dans un projet : son avancement apparaîtra ici.`)}
    <h2 class="section">${icon('history')} Activité récente</h2>
    ${feed.length ? `<div class="card feed">${feed.map(x => feedItem(x.e, x.p)).join('')}</div>` : emptyBox('history', 'Pas encore d\'activité', 'Ouvre Claude dans un projet initialisé avec la factory.')}`;
  }

  function viewProjects() {
    return `<h1 class="page-title">Projets</h1><p class="lead">Chaque projet initialisé avec la factory apparaît ici dès que Claude y est ouvert.</p>
    ${projects.length ? `<div class="grid-2">${projects.map(p => `<a class="card project-card${p.active ? ' is-live' : ''}" href="#/projet/${encodeURIComponent(p.id)}">
      <div class="row between"><h3>${esc(p.name)} ${p.active ? '<span class="live">actif</span>' : ''}</h3>${pill(p.state)}</div>
      ${p.workingNow.length ? `<div class="faint">${icon('bot', 'sm')} ${p.workingNow.map(r => esc(agentLabel(r.agent))).join(', ')} au travail</div>` : ''}
      <div class="faint mono">${esc(p.path)}</div>
      ${p.current ? `<div><div class="row between faint"><span>${icon('workflow', 'sm')} ${esc(p.current.name)}</span><span>${p.current.done}/${p.current.total}</span></div><div class="bar" style="margin-top:6px"><i style="width:${p.current.pct}%"></i></div></div>` : ''}
      <div class="chips"><span class="chip">${esc(p.architecture || '—')}</span><span class="chip">backend : ${esc(p.backend || '—')}</span>
        <span class="chip">frontend : ${esc(p.frontend == null ? 'aucun' : p.frontend)}</span>${p.branch ? `<span class="chip mono">${esc(p.branch)}</span>` : ''}</div>
      <div class="faint">${p.last ? 'Dernière activité ' + ago(p.last.ts) : 'Aucune activité'}</div></a>`).join('')}</div>`
      : emptyBox('folder', 'Aucun projet', 'Ouvre Claude dans un projet initialisé avec la factory : il apparaîtra ici.')}`;
  }

  function viewProject(id) {
    const p = projects.find(x => x.id === id);
    if (!p) return `<a class="back" href="#/projets">${icon('arrow-right')} Projets</a>${emptyBox('triangle-alert', 'Projet introuvable', '')}`;
    const f = p.current || p.features[0];
    const lc = (p.lastCommit || '').split('|');
    let callout = '';
    if (f && f.waiting >= 0) callout = `<div class="callout tone-amber">${icon('circle-pause')}<div><b>À toi : ${esc(f.model[f.waiting].gate)}.</b><br>Relis le document, choisis ta réponse ci-dessous, copie-la et colle-la dans ta session Claude.</div></div>` + replyPanel(p, f);
    else if (p.key === 'validation') callout = `<div class="callout tone-amber">${icon('circle-pause')}<div><b>Claude attend ta validation.</b></div></div>` + replyPanel(p, null);
    else if (p.key === 'permission') {
      // Ancien format (avant la v4.5) : message anglais de Claude Code, remplacé par une phrase claire.
      const det = /needs your permission|permission to use/i.test((p.last || {}).detail || '') ? 'Claude demande ton autorisation pour continuer.' : ((p.last || {}).detail || 'Claude demande ton autorisation pour continuer.');
      callout = `<div class="callout tone-amber">${icon('lock-keyhole')}<div><b>${esc(det)}</b>
        <p style="margin:6px 0 4px">Ce n'est pas une validation de la factory : c'est <b>Claude Code</b> qui demande l'autorisation d'agir. Réponds dans ta session
        (ou depuis ton téléphone avec Remote Control) :</p>
        <ul class="plain"><li><b>1 · Oui</b> — autorise cette fois ;</li><li><b>2 · Oui, et ne plus demander</b> — autorise ce type d'action dans ce projet (enregistré dans <code>.claude/settings.local.json</code>) ;</li><li><b>3 · Non</b> — refuse, et dis à Claude ce qu'il doit faire autrement.</li></ul>
        <span class="faint">Ce tableau de bord ne répond pas à ta place : une page web qui autorise des commandes contournerait tes garde-fous.</span></div></div>`;
    }
    else if (f && f.st.includes('active')) callout = `<div class="callout tone-sky">${icon('bot')}<div><b>${esc(f.current.label)} en cours.</b> ${esc(f.current.help || '')}</div></div>`;
    const others = p.features.filter(x => x !== f);
    const L = f && f.kind === 'Feature' ? lanesOf(p, f) : null;
    const schemas = L && L.plan ? mermaidBlocks(L.plan.content, 2) : [];
    const now = p.workingNow.length ? `<div class="now">${icon('bot')} ${p.workingNow.map(r => `<span>${esc(agentLabel(r.agent))} au travail depuis ${dur(r.start, new Date().toISOString())}</span>`).join(' · ')}</div>` : '';
    return `<a class="back" href="#/projets">${icon('folder-kanban', 'sm')} Projets</a>
    <div class="row between" style="flex-wrap:wrap"><h1 class="page-title">${esc(p.name)} ${p.active ? '<span class="live">actif</span>' : ''}</h1>${headPill(p)}</div>
    <p class="lead mono" style="font-size:13px">${esc(p.path)}</p>
    ${projectTabs(p, 'suivi')}
    <h2 class="section">${icon('workflow')} ${f ? esc(f.kind) + ' : ' + esc(f.name) : 'Process'} ${f && f.live ? '<span class="live">en cours</span>' : ''} ${f ? `<span class="hint">· <span class="mono">${esc(f.branch)}</span></span>` : ''}</h2>
    ${f ? `<div class="card process">${now}${L ? laneGraph(L) : stepper(f)}${callout}</div>`
      : (callout ? `<div class="card process">${callout}</div>` : emptyBox('workflow', 'Aucune feature en cours', `Le process s'affiche dès que tu travailles sur une branche de feature avec <code>${esc(P)}feature</code>.`))}
    ${schemas.length ? `<h2 class="section">${icon('layers')} Schémas de la feature <span class="hint">· ${esc(L.plan.name)}</span></h2><div class="card" style="padding:16px">${schemas.map(mmdFigure).join('')}</div>` : ''}
    ${f ? `<h2 class="section">${icon('users-round')} Qui a fait quoi <span class="hint">· ${esc(f.name)}</span></h2>${runsTable(f.runs || [])}` : ''}
    <div class="two-cols" style="margin-top:14px">
      <div><h2 class="section">${icon('history')} Activité</h2>
        ${(p.events || []).length ? `<div class="card feed">${(p.events || []).filter(e => e.kind !== 'prompt').slice(-25).reverse().map(e => feedItem(e)).join('')}</div>` : emptyBox('history', 'Pas encore d\'activité', '')}</div>
      <div><h2 class="section">${icon('info')} Projet</h2>
        <dl class="card kv"><dt>Branche</dt><dd>${p.branch ? `<span class="mono">${esc(p.branch)}</span>` : '—'}</dd>
          <dt>Dernier commit</dt><dd>${lc[0] ? esc(lc[0]) + `<div class="faint">${fmt(lc[1])}</div>` : '—'}</dd>
          <dt>Architecture</dt><dd>${esc(p.architecture || '—')}</dd><dt>Backend</dt><dd class="mono">${esc(p.backend || '—')}</dd>
          <dt>Frontend</dt><dd class="mono">${esc(p.frontend == null ? 'aucun' : p.frontend)}</dd><dt>Kit</dt><dd>${p.kit ? 'v' + esc(p.kit) : '—'}</dd></dl>
        <h2 class="section">${icon('file-text')} Documents</h2>
        ${(p.docs || []).length ? `<ul class="card list">${p.docs.map((d, k) => `<li><a class="doclink row" style="width:100%" href="#/projet/${encodeURIComponent(p.id)}/doc/${k}">${icon(/claude\.md$/i.test(d.name) ? 'book-open' : d.rel === 'docs/architecture/overview.md' ? 'layers' : /^docs\/api\//.test(d.rel) ? 'plug' : 'file-text', 'sm')}<span>${esc(/claude\.md$/i.test(d.name) ? 'Mémoire du projet (CLAUDE.md)' : d.rel === 'docs/architecture/overview.md' ? 'Architecture du projet' : /^docs\/api\//.test(d.rel) ? 'Contrat d\'API : ' + d.name : d.name)}</span><span class="faint" style="margin-left:auto">${d.mtime ? fmt(new Date(d.mtime * 1000).toISOString()) : ''}</span></a></li>`).join('')}</ul>` : emptyBox('file-search', 'Aucun document', 'Les specs et plans de <code>docs/specs</code> et le <code>CLAUDE.md</code> apparaîtront ici.')}
        ${others.length ? `<h2 class="section">${icon('git-branch')} Autres branches</h2><ul class="card list">${others.map(o => `<li>${icon('git-branch', 'sm')}<span>${esc(o.name)}</span><span class="faint" style="margin-left:auto">${o.done}/${o.total} · ${ago(o.lastTs)}</span></li>`).join('')}</ul>` : ''}
      </div></div>`;
  }

  function viewArchitecture(id) {
    const p = projects.find(x => x.id === id);
    if (!p) return `<a class="back" href="#/projets">${icon('arrow-left', 'sm')} Projets</a>${emptyBox('triangle-alert', 'Projet introuvable', '')}`;
    const d = archDoc(p);
    const head = `<a class="back" href="#/projets">${icon('folder-kanban', 'sm')} Projets</a>
      <div class="row between" style="flex-wrap:wrap"><h1 class="page-title">${esc(p.name)}</h1>${headPill(p)}</div>
      <p class="lead">Le schéma global du projet, proposé par l'architecte et validé par toi ; il suit chaque intégration.</p>${projectTabs(p, 'architecture')}`;
    if (!d) return head + emptyBox('layers', 'Pas encore de schéma d\'architecture', `Lance <code>${esc(P)}architecture</code> : l'architecte propose un schéma à partir des choix du projet (architecture, modules, intégrations), que tu valides.`);
    const st = (d.content.slice(0, 300).match(/statut\s*:\s*([^\n]+)/i) || [])[1] || '';
    const proposed = /propos/i.test(st);
    const k = (p.docs || []).indexOf(d);
    return head + `${proposed ? `<div class="callout tone-amber">${icon('circle-pause')}<div><b>Schéma proposé : à valider.</b> Relis-le, puis réponds dans ta session (validé, ou les modifications voulues). Pour une modification plus tard : <code>${esc(P)}architecture &lt;modification&gt;</code>.</div></div>` : ''}
      <div class="doc-actions"><a class="btn" href="#/projet/${encodeURIComponent(p.id)}/doc/${k}">${icon('printer', 'sm')} Version imprimable / PDF</a>
        <a class="btn" href="${esc(d.url)}" target="_blank" rel="noopener">${icon('external-link', 'sm')} Ouvrir le fichier</a>${st ? `<span class="pill tone-${proposed ? 'amber' : 'emerald'}">${icon(proposed ? 'circle-pause' : 'check', 'sm')}${esc(st.replace(/[*_`]/g, '').trim())}</span>` : ''}</div>
      <article class="card md">${renderMd(d.content.replace(/^>\s*statut\s*:[^\n]*\n/i, '')).html}</article>`;
  }

  function viewDoc(id, k) {
    const p = projects.find(x => x.id === id), d = p && (p.docs || [])[k];
    if (!d) return `<a class="back" href="#/projets">${icon('arrow-left', 'sm')} Projets</a>${emptyBox('file-search', 'Document introuvable', 'Il a peut-être été renommé : reviens au projet.')}`;
    const r = renderMd(d.content);
    return `<a class="back" href="#/projet/${encodeURIComponent(p.id)}">${icon('arrow-left', 'sm')} ${esc(p.name)}</a>
      <h1 class="page-title">${esc(/claude\.md$/i.test(d.name) ? 'Mémoire du projet' : d.name.replace(/\.md$/, ''))}</h1>
      <p class="lead mono" style="font-size:13px">${esc(d.rel)} · modifié ${d.mtime ? fmt(new Date(d.mtime * 1000).toISOString()) : '—'}</p>
      <div class="doc-actions"><button type="button" class="btn" onclick="window.print()">${icon('printer', 'sm')} Imprimer / PDF</button>
        <a class="btn" href="${esc(d.url)}" target="_blank" rel="noopener">${icon('external-link', 'sm')} Ouvrir le fichier</a></div>
      ${d.truncated ? `<div class="callout tone-amber">${icon('triangle-alert')}<div>Document tronqué à 200 Ko dans cette page : ouvre le fichier pour le lire en entier.</div></div>` : ''}
      <div class="print-only print-head"><div class="t">${esc(/claude\.md$/i.test(d.name) ? 'Mémoire du projet' : d.name.replace(/\.md$/, ''))}</div>
        <div class="m">${esc(p.name)} · ${esc(d.rel)} · modifié ${d.mtime ? fmt(new Date(d.mtime * 1000).toISOString()) : '—'} · imprimé le ${new Date().toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}</div></div>
      ${r.toc.length > 3 ? `<div class="print-only print-toc"><b>Sommaire</b>${r.toc.filter(t => t.lvl > 1 || r.toc.filter(x => x.lvl === 1).length > 1).map(t => `<div class="h${t.lvl}">${esc(t.txt)}</div>`).join('')}</div>` : ''}
      <div class="doc-view"><article class="card md">${r.html || '<p class="faint">Document vide.</p>'}</article>
        ${r.toc.length > 2 ? `<nav class="doc-toc">${r.toc.map(t => `<a href="#" data-anchor="${t.id}" class="h${t.lvl}">${esc(t.txt)}</a>`).join('')}</nav>` : ''}</div>`;
  }

  function viewDocs() {
    const cmd = (D.docs.commands || []);
    const ag = (D.docs.agents || []);
    const flow = [
      ['lightbulb', 'file-text', 'Spec', 'L\'agent spec-writer reformule ton besoin : règles, cas limites, questions.', true],
      ['', 'compass', 'Plan', 'L\'architecte conçoit la solution et le contrat d\'API ; tu choisis l\'ordre du code : les deux ensemble, backend d\'abord ou frontend d\'abord.', true],
      ['', 'palette', 'Design (au choix)', 'La factory regarde ce qui existe et recommande ; tu choisis : designer de la factory, Claude Design ou Figma, ou sans design.', true],
      ['', 'code', 'Code', 'Les développeurs backend et frontend implémentent, ensemble ou une partie après l\'autre, contrôlés en continu par les garde-fous.', false],
      ['', 'flask-conical', 'Tests', 'Tests de chaque couche, intégration avec de vraies dépendances, règles d\'architecture.', false],
      ['', 'search-check', 'Revue', 'Le relecteur vérifie architecture, sécurité et qualité ; tu lis le verdict.', true],
      ['', 'git-pull-request', 'Commit et PR', 'Après ton accord : commit de la partie, branche poussée ; tu ouvres la PR et tu fusionnes. Une partie reste ? --resume la reprend.', false],
    ];
    return `<h1 class="page-title">Documentation</h1><p class="lead">Comment fonctionne la Top Factory, et tout ce que tu peux lui demander.</p>
    <div class="doc"><nav class="toc">
      <a href="#/docs" data-anchor="d-principe">Le principe</a><a href="#/docs" data-anchor="d-workflow">Le workflow</a>
      <a href="#/docs" data-anchor="d-demarrer">Démarrer un projet</a><a href="#/docs" data-anchor="d-commandes">Commandes</a>
      <a href="#/docs" data-anchor="d-agents">Agents</a><a href="#/docs" data-anchor="d-gardefous">Garde-fous</a>
      <a href="#/docs" data-anchor="d-fichiers">Fichiers du projet</a><a href="#/docs" data-anchor="d-notifs">Notifications</a>
      <a href="#/docs" data-anchor="d-repondre">Répondre à une validation</a>
      <a href="#/docs" data-anchor="d-design">Design des écrans</a><a href="#/docs" data-anchor="d-schemas">Schémas et historique</a><a href="#/docs" data-anchor="d-front">Backend et frontend séparés</a>
      <a href="#/docs" data-anchor="d-depannage">Dépannage</a></nav>
    <div>
      <section id="d-principe" class="card block"><h3>Le principe</h3>
        <p>La factory est un <b>plugin de Claude Code</b>. Elle transforme une demande en fonctionnalité livrée, en suivant toujours le même chemin :
        une spec, un plan, le code, les tests, une revue, puis un commit. Des <b>agents spécialisés</b> font chaque étape ; toi, tu valides aux moments clés.</p>
        <p>Elle respecte l'architecture choisie pour le projet (hexagonale ou en couches), tes conventions (profil, options) et tes intégrations
        (PostgreSQL, Redis…). Des <b>garde-fous</b> contrôlent chaque fichier écrit : une violation est corrigée tout de suite, pas découverte en revue.</p>
        <div class="chips"><span class="chip">Kit v${esc(D.kit || '?')}</span><span class="chip">Commandes : <code>${esc(P)}…</code></span></div></section>
      <section id="d-workflow" class="card block"><h3>Le workflow d'une feature</h3>
        <p>Lancé par <code>${esc(P)}feature &lt;besoin&gt;</code>. Les étapes en orange s'arrêtent pour ta validation : rien ne continue sans ton accord.
        Avec backend <b>et</b> frontend, chaque partie peut aller seule jusqu'à son commit : la seconde se reprend plus tard, par toi ou un autre
        développeur, avec <code>${esc(P)}feature --resume &lt;slug&gt; --front</code> (ou <code>--back</code>) — l'avancement est noté dans le plan.</p>
        <div class="flow">${flow.map(f => `<div class="flow-step ${f[4] ? 'gate' : ''}"><b>${icon(f[1])} ${esc(f[2])}</b><span>${esc(f[3])}</span>${f[4] ? `<span class="faint" style="color:var(--amber)">${icon('circle-pause', 'sm')} ta validation</span>` : ''}</div>`).join('')}</div></section>
      <section id="d-demarrer" class="card block"><h3>Démarrer un projet</h3>
        <ol class="steps-num">
          <li><span>Une fois par poste, dans Claude Code : <code>/plugin marketplace add babatop2313/top-factory</code> puis <code>/plugin install top-factory@top</code>.</span></li>
          <li><span>Crée le dépôt Git et le backend Spring Boot (start.spring.io), dans le dossier de ton choix.</span></li>
          <li><span>Dans Claude, à la racine du projet : <code>${esc(P)}init</code> — architecture, branche d'intégration, intégrations, dossiers.</span></li>
          <li><span>Relance Claude, complète <code>CLAUDE.md</code>, puis <code>${esc(P)}init-architecture &lt;module&gt;</code>.</span></li>
          <li><span>Si besoin, le frontend : <code>${esc(P)}add-frontend</code> ; et, si tu veux, le design en amont : <code>${esc(P)}design-project</code>. Ensuite, chaque besoin passe par <code>${esc(P)}feature</code>.</span></li>
        </ol></section>
      <section id="d-commandes" class="card block"><h3>Commandes</h3><p>Lues directement dans le kit installé : cette liste est toujours à jour.</p>
        <table><thead><tr><th>Commande</th><th>À quoi elle sert</th></tr></thead><tbody>
        ${cmd.map(c => `<tr><td><code>${esc(P + c.name)}</code>${c.hint ? `<div class="faint mono">${esc(c.hint)}</div>` : ''}</td><td>${esc(c.description)}</td></tr>`).join('')}
        </tbody></table></section>
      <section id="d-agents" class="card block"><h3>Agents</h3><p>Chaque agent a un rôle précis et ne reçoit que les outils dont il a besoin.</p>
        <table><thead><tr><th>Agent</th><th>Rôle</th></tr></thead><tbody>
        ${ag.map(a => `<tr><td><b>${esc(a.name)}</b><div class="faint">${esc(AGENTS[a.name] || '')}</div></td><td>${esc(a.description)}</td></tr>`).join('')}
        </tbody></table></section>
      <section id="d-gardefous" class="card block"><h3>Garde-fous</h3>
        <p>Ils s'exécutent tout seuls, à chaque action de Claude. Un blocage est expliqué à Claude, qui corrige dans la foulée.</p>
        <table><tbody>
          <tr><td>${icon('layers')}</td><td><b>Architecture</b> — chaque fichier Java respecte les règles de dépendance de l'architecture et des intégrations ; <code>ArchitectureTest</code> le vérifie aussi dans les tests.</td></tr>
          <tr><td>${icon('monitor-smartphone')}</td><td><b>Frontend</b> — pas d'accès HTTP dans un composant, pas d'import entre features, jamais de jeton dans <code>localStorage</code>, pas d'URL d'API en dur.</td></tr>
          <tr><td>${icon('terminal')}</td><td><b>Compilation et types</b> — le backend est compilé et les types TypeScript vérifiés après chaque modification.</td></tr>
          <tr><td>${icon('shield-check')}</td><td><b>Commandes</b> — pas de push sur <code>main</code> ou <code>develop</code>, pas de fusion par Claude, pas de suppression de <code>.claude/</code>, pas de secret dans le code.</td></tr>
          <tr><td>${icon('server')}</td><td><b>Base de données</b> — le serveur MCP PostgreSQL est en lecture seule, avec trois lignes de défense.</td></tr>
        </tbody></table></section>
      <section id="d-fichiers" class="card block"><h3>Fichiers du projet</h3><table><tbody>
          <tr><td><code>.claude/factory.json</code></td><td>Architecture, branche d'intégration, dossiers backend et frontend. <b>Verrouillé</b> : écrit par <code>${esc(P)}init</code>, jamais modifié par Claude.</td></tr>
          <tr><td><code>.claude/stack.json</code></td><td>Profil, options de conventions (mapping, erreurs, transport du JWT, bibliothèque d'interface…), intégrations actives et modules qui les utilisent (<code>modules</code>), outil de design et son lien.</td></tr>
          <tr><td><code>.claude/settings.json</code></td><td>Permissions partagées et activation du plugin (réécrit par le script de la factory).</td></tr>
          <tr><td><code>.claude/settings.local.json</code></td><td>Tes autorisations personnelles ; jamais commité.</td></tr>
          <tr><td><code>CLAUDE.md</code></td><td>Contexte métier, règles et commandes du projet : à compléter par toi.</td></tr>
          <tr><td><code>docs/specs/</code></td><td>Une spec et un plan par fonctionnalité (avec l'avancement de chaque partie). Contrats d'API dans <code>docs/api/</code>, design dans <code>docs/design/</code>.</td></tr>
        </tbody></table></section>
      <section id="d-notifs" class="card block"><h3>Notifications</h3>
        <p>Tu n'es prévenu que lorsque c'est utile : <b>ta décision est nécessaire</b> pour continuer (arrêt ⏸ d'une commande),
        <b>Claude attend ton autorisation</b>, <b>tout est terminé</b> (aucun agent encore au travail, tâche d'au moins 30 s), ou
        <b>un agent passe la main à un autre</b>. Chaque message dit quoi faire et sur quelle feature. Réglages : <code>${esc(D.home)}/config.json</code>
        (ou <code>${esc(P)}dashboard notifications</code>).</p>
        <ul class="list" style="padding:0"><li>${icon('monitor-smartphone', 'sm')} <span><b>Sur l'ordinateur</b> : notification du système (Windows, macOS, Linux) — <code>"desktop": true</code>.</span></li>
          <li>${icon('bell', 'sm')} <span><b>Sur le téléphone</b> : application <b>ntfy</b>, gratuite et sans compte. Choisis un sujet long et imprévisible, abonne-toi dans l'application, puis renseigne <code>"topic"</code>.</span></li>
          <li>${icon('shield-check', 'sm')} <span>Les notifications ne contiennent que le projet, l'étape et la branche : jamais de code ni de texte de Claude.</span></li></ul></section>
      <section id="d-repondre" class="card block"><h3>Répondre à une validation</h3>
        <p><b>Depuis ce tableau de bord.</b> Quand un projet attend ta validation, sa page affiche le document à relire (spec ou plan)
        et trois réponses prêtes : « Valider et continuer », « Valider avec remarques », « Demander des corrections ». Tu écris tes
        remarques si besoin, tu copies la réponse et tu la colles dans ta session Claude. La page ne parle jamais directement à
        Claude : c'est toi qui envoies la réponse, rien ne part sans toi.</p>
        <p><b>Les demandes d'autorisation</b> (« Claude attend ton autorisation ») ne sont pas des validations de la factory : c'est Claude Code
        qui demande s'il peut modifier un fichier ou lancer une commande. La page dit ce qui est demandé ; tu réponds dans ta session
        (1 · oui, 2 · oui et ne plus demander, 3 · non). Le tableau de bord ne répond jamais à ta place.</p>
        <p><b>Depuis ton téléphone, avec Remote Control</b> (fonction officielle de Claude Code, abonnements Pro, Max, Team et Enterprise) :</p>
        <ol class="steps-num">
          <li><span>Dans ta session Claude Code, tape <code>/remote-control</code> (ou <code>/rc</code>) ; ou lance directement <code>claude --rc</code>. Accepte la confirmation la première fois.</span></li>
          <li><span>Ouvre l'application Claude sur ton téléphone (ou claude.ai/code) : la session apparaît dans la liste. La session continue de tourner sur ton ordinateur.</span></li>
          <li><span>Avec les notifications ntfy, tu es prévenu sur ton téléphone dès qu'une validation est requise : tu réponds directement dans l'application.</span></li>
        </ol></section>
      <section id="d-design" class="card block"><h3>Design des écrans</h3>
        <p>Le design est <b>facultatif</b> : à chaque feature, la factory regarde ce qui existe (écrans déjà codés, designs validés, outil du projet)
        et te fait une recommandation ; c'est toi qui choisis. Le design vit dans le dépôt (<code>docs/design/</code>) : un design system,
        une fiche et une maquette par écran, et un registre qui suit chaque écran : <b>proposé → validé → implémenté → intégré</b>.
        L'onglet <b>Design</b> de chaque projet les montre tous, avec un bouton vers ton outil.</p>
        <ol class="steps-num">
          <li><span><b>Outil du projet, enregistré une fois</b> : <code>${esc(P)}design-link &lt;url&gt;</code> écrit l'outil (Claude Design ou Figma) et son lien dans
            <code>.claude/stack.json</code>, avec ton accord. Le lien reste valable d'une session à l'autre et est annoncé à chaque démarrage.</span></li>
          <li><span><b>Avant les features</b> : <code>${esc(P)}design-project</code> — design system et tout ou partie des écrans prévus, validés lot par lot.</span></li>
          <li><span><b>Avec la factory</b> : <code>${esc(P)}design-system</code>, puis <code>${esc(P)}design-screen &lt;écran&gt;</code> — l'agent designer propose, tu valides.</span></li>
          <li><span><b>Avec Claude Design ou Figma</b> : tu dessines dans l'outil ; <code>${esc(P)}design-screen &lt;écran&gt;</code> reporte l'écran dans le dépôt (serveur MCP de l'outil s'il est branché, sinon ton export ou tes captures).</span></li>
          <li><span><b>Améliorer</b> : <code>${esc(P)}design-improve &lt;écran&gt; &lt;demande&gt;</code> — nouvelle proposition, ta validation, puis le code suit.</span></li>
        </ol>
        <p style="margin-top:12px">Avant d'écrire un écran, le développeur frontend vérifie dans l'ordre : l'écran existe déjà (il ne fait que brancher l'API) ;
        un design validé existe (il l'implémente fidèlement) ; tu as choisi « sans design » (il suit le design system et les écrans existants) ; sinon il s'arrête et te demande.</p></section>
      <section id="d-schemas" class="card block"><h3>Schémas, parcours et historique</h3>
        <ol class="steps-num">
          <li><span><b>Architecture du projet</b> : <code>${esc(P)}architecture</code> — l'architecte propose un schéma global (Mermaid) à partir de tes choix ;
            tu le valides dans l'onglet <b>Architecture</b>. Il te propose une mise à jour après chaque <code>add-integration</code>, <code>add-mcp-server</code>
            ou <code>add-frontend</code> ; <code>${esc(P)}architecture &lt;modification&gt;</code> pour en demander une.</span></li>
          <li><span><b>Schémas de chaque feature</b> : le plan contient un schéma des composants et une séquence du cas principal, affichés sur la page du projet et dans le plan.</span></li>
          <li><span><b>Parcours en graphe</b> : un tronc commun (spec, plan), deux voies — backend et frontend — qui se rejoignent à l'intégration, quel que soit l'ordre choisi.</span></li>
          <li><span><b>Qui a fait quoi</b> : chaque agent, sa durée, les fichiers modifiés (chemins seulement) et sa ligne de bilan ; aucun autre texte des agents n'est gardé.</span></li>
          <li><span><b>Documents</b> : rendu soigné (tableaux, code, schémas) et <b>Imprimer / PDF</b> avec en-tête, sommaire et numéros de page.</span></li>
        </ol>
        <p style="margin-top:12px" class="faint">Les schémas sont dessinés par Mermaid, téléchargé une seule fois dans <code>~/.top-factory/vendor/</code> (empreinte vérifiée), puis utilisé hors ligne. Sans lui, un schéma s'affiche en texte.</p></section>
      <section id="d-front" class="card block"><h3>Backend et frontend séparés</h3>
        <p>Pour tester l'API pour de vrai avant l'interface, ou pour une équipe frontend et une équipe backend qui avancent chacune de leur côté :</p>
        <ol class="steps-num">
          <li><span>Le <b>contrat d'API</b> de la feature est écrit par l'architecte dans <code>docs/api/&lt;feature&gt;.md</code> : c'est la référence commune.</span></li>
          <li><span><b>Backend d'abord</b> : au plan, choisis « backend d'abord ». La partie backend va jusqu'à sa revue et son commit ; tu testes l'API (Swagger, <code>curl</code>).
            Puis <code>${esc(P)}feature --resume &lt;slug&gt; --front</code> : le frontend se branche directement sur la vraie API (nouvelle branche si le backend est déjà fusionné).</span></li>
          <li><span><b>Frontend d'abord</b> : choisis « frontend d'abord », ou lance <code>${esc(P)}feature &lt;besoin&gt; --front</code> : écrans sur des <b>données simulées</b>
            conformes au contrat (<code>npx ng serve --configuration mock</code>), jamais présentes dans le build de production. Quand le backend est prêt :
            <code>${esc(P)}integrate &lt;feature&gt;</code>.</span></li>
          <li><span>Deux équipes : chacune lance <code>--back</code> ou <code>--front</code> (ou <code>--resume</code>) en réutilisant la spec, le plan et le contrat.</span></li>
        </ol></section>
      <section id="d-depannage" class="card block"><h3>Dépannage</h3><dl class="faq">
          <dt>Sous PowerShell, <code>bash</code> lance WSL au lieu de Git Bash.</dt><dd>Utilise Git Bash, ou <code>&amp; "C:\\Program Files\\Git\\bin\\bash.exe"</code>.</dd>
          <dt>Des dizaines d'erreurs Testcontainers dans les tests.</dt><dd>Docker Desktop n'est pas démarré.</dd>
          <dt>Après une mise à jour, Claude utilise encore l'ancienne version du kit.</dt><dd>Relance Claude. Si le problème persiste, désinstalle le plugin, supprime son dossier dans <code>~/.claude/plugins/cache/top</code>, puis réinstalle-le.</dd>
          <dt>Aucune notification Windows.</dt><dd>Paramètres Windows › Notifications : autorise « Windows PowerShell », et vérifie que le mode Ne pas déranger est désactivé.</dd>
          <dt>« Commande bloquée : ajout en bloc » ou « un fichier .env est indexé ».</dt><dd>Voulu : les fichiers s'ajoutent un par un, et un <code>.env</code> (secrets) n'entre jamais dans Git. Un <code>.env</code> déjà suivi se retire avec <code>git rm --cached .env</code> (ton fichier reste sur le disque), puis change les secrets qu'il contenait.</dd>
          <dt>Une commande <code>! cd C:\\…</code> ne fait rien dans Claude Code.</dt><dd>Après <code>!</code>, la commande passe par Git Bash, qui supprime les <code>\\</code>. Omets le <code>cd</code> (la session est déjà dans le projet) ou écris <code>/c/Users/…</code>.</dd>
          <dt>Le démarrage signale un <code>settings.json</code> illisible.</dt><dd>Claude Code l'ignore, et avec lui les permissions du kit. <code>git checkout -- .claude/settings.json</code> s'il est versionné, sinon corrige-le à la main.</dd>
          <dt>Un projet n'apparaît pas ici.</dt><dd>Il doit être initialisé (<code>.claude/factory.json</code>) et Claude doit y avoir été ouvert au moins une fois depuis la v4.3.</dd>
        </dl></section>
    </div></div>`;
  }

  // ---------- Navigation et actualisation ----------
  function render() {
    const h = location.hash || '#/';
    let html, active;
    const md = h.match(/^#\/projet\/([^/]+)\/doc\/(\d+)$/);
    const dz = h.match(/^#\/projet\/([^/]+)\/design(?:\/(system|\d+))?$/);
    const ar = h.match(/^#\/projet\/([^/]+)\/architecture$/);
    if (md) { html = viewDoc(decodeURIComponent(md[1]), +md[2]); active = 'projets'; }
    else if (ar) { html = viewArchitecture(decodeURIComponent(ar[1])); active = 'projets'; }
    else if (dz) { html = dz[2] != null ? viewScreen(decodeURIComponent(dz[1]), dz[2]) : viewDesign(decodeURIComponent(dz[1])); active = 'projets'; }
    else if (h.startsWith('#/projet/')) { html = viewProject(decodeURIComponent(h.slice(9))); active = 'projets'; }
    else if (h.startsWith('#/projets')) { html = viewProjects(); active = 'projets'; }
    else if (h.startsWith('#/docs')) { html = viewDocs(); active = 'docs'; }
    else { html = viewOverview(); active = 'home'; }
    document.getElementById('nav').innerHTML =
      `<a href="#/" class="${active === 'home' ? 'active' : ''}">${icon('layout-dashboard')} Vue d'ensemble${todo.length ? `<span class="count alert">${todo.length}</span>` : ''}</a>` +
      `<a href="#/projets" class="${active === 'projets' ? 'active' : ''}">${icon('folder-kanban')} Projets<span class="count">${projects.length}</span></a>` +
      `<a href="#/docs" class="${active === 'docs' ? 'active' : ''}">${icon('book-open')} Documentation</a>`;
    document.getElementById('view').innerHTML = html;
    document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
    wireReplies();
    document.querySelectorAll('.doc-toc a').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); const t = document.getElementById(a.dataset.anchor); if (t) t.scrollIntoView({ behavior: 'smooth' }); }));
    document.querySelectorAll('.toc a').forEach(a => a.addEventListener('click', ev => { ev.preventDefault(); const t = document.getElementById(a.dataset.anchor); if (t) t.scrollIntoView({ behavior: 'smooth' }); }));
    document.title = (todo.length ? `(${todo.length}) ` : '') + 'Top Factory';
    drawMermaid();
    if (typeof drawAuto === 'function' && document.getElementById('auto')) try { drawAuto(); } catch (e) {}
  }
  // ---------- Schémas Mermaid : afficheur local (~/.top-factory/vendor), chargé seulement s'il y a un schéma ----------
  let mmdLoading = null, mmdSeq = 0;
  const isDark = () => document.documentElement.getAttribute('data-theme') === 'dark' ||
    (document.documentElement.getAttribute('data-theme') !== 'light' && window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches);
  function loadMermaid() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (!D.mermaid) return Promise.reject(new Error('absent'));
    return mmdLoading || (mmdLoading = new Promise((ok, ko) => {
      const sc = document.createElement('script'); sc.src = D.mermaid;
      sc.onload = () => window.mermaid ? ok(window.mermaid) : ko(new Error('chargement'));
      sc.onerror = () => ko(new Error('chargement')); document.head.appendChild(sc);
    }));
  }
  function drawMermaid() {
    const nodes = [...document.querySelectorAll('pre.mermaid:not([data-processed])')];
    if (!nodes.length) return;
    const note = txt => nodes.forEach(n => { if (!n.parentNode.querySelector('.mmd-note')) n.insertAdjacentHTML('afterend', `<span class="mmd-note">${txt}</span>`); });
    loadMermaid().then(m => {
      // Thème sobre, accordé au tableau de bord : zones neutres, éléments indigo, en clair comme en sombre.
      const tv = isDark()
        ? { darkMode: true, background: '#151821', primaryColor: '#1e2140', primaryBorderColor: '#818cf8', primaryTextColor: '#e5e7eb', secondaryColor: '#1f2430', tertiaryColor: '#1a1d27',
            lineColor: '#94a3b8', textColor: '#e5e7eb', clusterBkg: '#1a1d27', clusterBorder: '#475569', edgeLabelBackground: '#151821', noteBkgColor: '#1f2430', noteTextColor: '#e5e7eb',
            actorBkg: '#1e2140', actorBorder: '#818cf8', actorTextColor: '#e5e7eb', signalColor: '#cbd5e1', signalTextColor: '#e5e7eb', labelBoxBkgColor: '#1e2140', labelTextColor: '#e5e7eb' }
        : { primaryColor: '#eef2ff', primaryBorderColor: '#6366f1', primaryTextColor: '#1e1b4b', secondaryColor: '#f1f5f9', tertiaryColor: '#f8fafc',
            lineColor: '#64748b', clusterBkg: '#f8fafc', clusterBorder: '#94a3b8', edgeLabelBackground: '#ffffff' };
      m.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'base', themeVariables: Object.assign({ fontSize: '15px' }, tv), fontFamily: 'ui-sans-serif, system-ui, sans-serif',
        // Largeur : le schéma se réduit pour tenir dans la page, sans jamais dépasser sa taille naturelle.
        flowchart: { useMaxWidth: true }, sequence: { useMaxWidth: true }, er: { useMaxWidth: true }, class: { useMaxWidth: true }, state: { useMaxWidth: true } });
      nodes.forEach(n => { n.id = n.id || 'mmd-' + (++mmdSeq); });
      return m.run({ nodes, suppressErrors: true });
    }).then(() => nodes.forEach(n => { if (!n.querySelector('svg')) { n.removeAttribute('data-processed'); n.textContent = n.dataset.src; note('Schéma non affiché : sa syntaxe Mermaid est invalide.'); } }))
      .catch(() => note(`Schéma montré en texte : l'afficheur s'installe tout seul à la prochaine actualisation si Internet est disponible (ou lance <code>${esc(P)}dashboard</code>).`));
  }
  function redrawMermaid() {
    document.querySelectorAll('pre.mermaid[data-processed]').forEach(n => { n.removeAttribute('data-processed'); n.textContent = n.dataset.src; });
    drawMermaid();
  }

  let auto = true;
  try { auto = sessionStorage.getItem('tf-auto') !== 'off'; } catch (e) {}
  function drawAuto() {
    const replying = !!document.querySelector('.reply');
    document.getElementById('auto').innerHTML = icon(auto && !replying ? 'loader-circle' : 'circle-pause', 'sm') +
      (!auto ? ' Actualisation auto : en pause' : replying ? ' Actualisation en pause pendant ta réponse' : ' Actualisation auto : active');
    document.getElementById('updated').textContent = 'Mis à jour ' + ago(D.generated);
  }
  document.getElementById('auto').addEventListener('click', () => { auto = !auto; try { sessionStorage.setItem('tf-auto', auto ? 'on' : 'off'); } catch (e) {} drawAuto(); });
  document.getElementById('kit').textContent = D.kit ? 'Kit v' + D.kit : '';
  let theme = 'auto';
  try { theme = localStorage.getItem('tf-theme') || 'auto'; } catch (e) {}
  function drawTheme() {
    const opts = [['auto', 'monitor-smartphone', 'Auto'], ['light', 'sun', 'Clair'], ['dark', 'moon', 'Sombre']];
    const html = opts.map(([k, ic, l]) => `<button type="button" data-theme-choice="${k}" aria-pressed="${theme === k}" title="Thème ${l.toLowerCase()}">${icon(ic, 'sm')}<span>${l}</span></button>`).join('');
    ['theme', 'theme-m'].forEach(id => { const el = document.getElementById(id); if (el) el.innerHTML = html; });
    if (theme === 'auto') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', theme);
  }
  document.addEventListener('click', ev => {
    const g = ev.target.closest('[data-goto-reply]');
    if (g) {
      const box = document.querySelector('.reply');
      if (box) { box.scrollIntoView({ behavior: 'smooth', block: 'center' }); const first = box.querySelector('[data-choice]'); if (first) first.focus(); }
      else location.hash = '#/projet/' + encodeURIComponent(g.dataset.gotoReply);
      return;
    }
    const b = ev.target.closest('[data-theme-choice]'); if (!b) return;
    theme = b.dataset.themeChoice; try { localStorage.setItem('tf-theme', theme); } catch (e) {} drawTheme(); redrawMermaid();
  });
  drawTheme();
  window.addEventListener('hashchange', () => { render(); window.scrollTo(0, 0); });
  render(); drawAuto();
  try { const y = sessionStorage.getItem('tf-scroll'); if (y) { window.scrollTo(0, +y); sessionStorage.removeItem('tf-scroll'); } } catch (e) {}
  setInterval(() => {
    drawAuto();
    const hh = location.hash || '';
    const typing = (document.activeElement && document.activeElement.tagName === 'TEXTAREA') || !!document.querySelector('.reply');
    if (!auto || typing || document.visibilityState !== 'visible' || hh.startsWith('#/docs') || /\/doc\/|\/design(\/|$)|\/architecture$/.test(hh)) return;
    try { sessionStorage.setItem('tf-scroll', String(window.scrollY)); } catch (e) {}
    location.reload();
  }, 15000);
})();
</script>
</body>
</html>
TF_HTML_END
} > "$tmp" && mv "$tmp" "$out"

if [ "${1:-}" = "--open" ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) cmd.exe //c start "" "$(cygpath -w "$out" 2>/dev/null || echo "$out")" >/dev/null 2>&1 ;;
    Darwin) open "$out" ;;
    *) command -v xdg-open >/dev/null 2>&1 && xdg-open "$out" >/dev/null 2>&1 ;;
  esac
  echo "$out"
fi
exit 0
