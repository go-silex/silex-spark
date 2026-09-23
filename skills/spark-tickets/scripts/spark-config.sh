#!/usr/bin/env bash
# spark-config.sh — résolution config non-secrète (client / project / url).
# Sourcé par spark.sh. Secrets restent dans spark.env / SPARK_USER_API_KEY.
#
# Priorité client|project :
#   1. arg CLI / --client explicite
#   2. env SPARK_CLIENT / SPARK_PROJECT
#   3. config projet (cwd → parents) : config/spark.yml | .spark.yml | spark.yml
#   4. ~/.config/silex/spark.yml
#   5. SPARK_CONFIG=path (force un fichier unique, max priorité après env explicite fichier)

# shellcheck shell=bash

spark_config_read_key() {
  # $1=file $2=key → stdout value (simple YAML flat key: value)
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  KEY="$key" FILE="$file" python3 - <<'PY'
import os, re, sys
path, want = os.environ["FILE"], os.environ["KEY"]
try:
    text = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(1)
for raw in text.splitlines():
    line = raw.split("#", 1)[0].rstrip()
    if not line.strip() or ":" not in line:
        continue
    k, _, v = line.partition(":")
    k = k.strip()
    if k != want:
        continue
    v = v.strip().strip("\"'")
    if v.lower() in ("", "null", "~", "none"):
        sys.exit(1)
    print(v)
    sys.exit(0)
sys.exit(1)
PY
}

spark_find_project_config() {
  local dir="${SPARK_CWD:-$PWD}"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for name in config/spark.yml .spark.yml spark.yml; do
      if [ -f "$dir/$name" ]; then
        printf '%s' "$dir/$name"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  return 1
}

spark_config_files() {
  # ordre de lecture (premier match gagne pour une clé)
  if [ -n "${SPARK_CONFIG:-}" ] && [ -f "${SPARK_CONFIG}" ]; then
    printf '%s\n' "$SPARK_CONFIG"
    return 0
  fi
  local proj
  if proj="$(spark_find_project_config 2>/dev/null)"; then
    printf '%s\n' "$proj"
  fi
  if [ -f "${HOME}/.config/silex/spark.yml" ]; then
    printf '%s\n' "${HOME}/.config/silex/spark.yml"
  fi
}

spark_config_get() {
  # $1=key
  local key="$1" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if spark_config_read_key "$f" "$key" 2>/dev/null; then
      return 0
    fi
  done < <(spark_config_files)
  return 1
}

default_client() {
  if [ -n "${SPARK_CLIENT:-}" ]; then
    printf '%s' "$SPARK_CLIENT"
    return 0
  fi
  spark_config_get client 2>/dev/null
}

default_project() {
  if [ -n "${SPARK_PROJECT:-}" ]; then
    printf '%s' "$SPARK_PROJECT"
    return 0
  fi
  spark_config_get project 2>/dev/null
}

default_url_from_config() {
  spark_config_get url 2>/dev/null
}

# Slug client Spark : a-z0-9- (évite de confondre un titre avec un client).
is_client_slug() {
  local s="${1:-}"
  [[ "$s" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && [ "${#s}" -le 64 ]
}

# Flag à valeur : `shift 2 || true` dans un `while` relit le même $1 à l'infini.
need_value() {
  [ "$#" -ge 2 ] && [ -n "${2}" ] || {
    echo "spark.sh: $1 attend une valeur" >&2
    exit 1
  }
  case "$2" in
    --*)
      echo "spark.sh: $1 attend une valeur" >&2
      exit 1
      ;;
  esac
}

need_eq() {
  local v="${1#*=}"
  [ -n "$v" ] || {
    echo "spark.sh: ${1%%=*} attend une valeur" >&2
    exit 1
  }
}

# Parse premier argument positionnel client (pas un flag).
# Pose PARSED_CLIENT + NEED_SHIFT (pas de stdout — évite subshell).
# $2 = "strict" → n'accepte $1 que si is_client_slug (create title-first).
# exit 1 si aucun client résolu.
parse_client_positional() {
  PARSED_CLIENT=""
  NEED_SHIFT=0
  local raw="${1:-}"
  local mode="${2:-}"
  if [ -n "$raw" ] && [[ "$raw" != --* ]]; then
    if [ "$mode" = "strict" ] && ! is_client_slug "$raw"; then
      : # titre ou autre → fallback défaut
    else
      NEED_SHIFT=1
      PARSED_CLIENT="$raw"
      return 0
    fi
  fi
  local d
  d="$(default_client)" || d=""
  if [ -n "$d" ]; then
    PARSED_CLIENT="$d"
    return 0
  fi
  return 1
}

# Pour flags --client déjà parsés : remplit PARSED_CLIENT si vide.
# Usage: fill_client_if_empty "$client"; client="$PARSED_CLIENT"
fill_client_if_empty() {
  PARSED_CLIENT="${1:-}"
  if [ -n "$PARSED_CLIENT" ]; then
    return 0
  fi
  local d
  d="$(default_client)" || d=""
  if [ -n "$d" ]; then
    PARSED_CLIENT="$d"
    return 0
  fi
  PARSED_CLIENT=""
  return 1
}

# Args après un <id> de tâche : [clientSlug] ou --client slug — un seul, validé.
# Pose PARSED_CLIENT. Jamais de défaut spark.yml : l'espace d'un CUID ne se
# devine pas (un mauvais défaut ferait d'un DELETE un faux succès). Sans client,
# l'API tranche : owner → 400 « client requis », compte mono-espace → son espace.
parse_client_args() {
  PARSED_CLIENT=""
  local v
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        need_value "$@"
        v="$2"
        shift 2
        ;;
      --client=*)
        need_eq "$1"
        v="${1#--client=}"
        shift
        ;;
      --*)
        echo "Arg inconnu: $1" >&2
        exit 1
        ;;
      *)
        v="$1"
        shift
        # Positionnel vide (script qui passe "$CLIENT" non défini) = pas de client.
        [ -n "$v" ] || continue
        ;;
    esac
    if [ -n "$PARSED_CLIENT" ]; then
      echo "spark.sh: un seul client (« $PARSED_CLIENT » puis « $v »)" >&2
      exit 1
    fi
    if ! is_client_slug "$v"; then
      echo "spark.sh: slug client invalide : $v" >&2
      exit 1
    fi
    PARSED_CLIENT="$v"
  done
}

# <id> d'une tâche = CUID Prisma (c + ~24 car.). Un slug ou un flag pris pour l'id
# (args inversés, --client en tête) produirait un DELETE sur un id inconnu, auquel
# l'API répond 200 {ok:true} sans rien supprimer : l'erreur doit tomber ici.
is_task_cuid() {
  [[ "${1:-}" =~ ^c[a-z0-9]{20,32}$ ]]
}

client_missing_hint() {
  cat >&2 <<'EOF'
client requis : passe <clientSlug> en argument, ou configure un défaut :
  spark.sh config init --client <slug>           # projet (config/spark.yml)
  spark.sh config init --client <slug> --global  # ~/.config/silex/spark.yml
  # ou skill spark-setup
EOF
}

spark_config_init() {
  # --client --project --global --url --force
  local client="" project="" url="" global=0 force=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        need_value "$@"
        client="$2"
        shift 2
        ;;
      --client=*)
      need_eq "$1"
        client="${1#--client=}"
        shift || true
        ;;
      --project)
        need_value "$@"
        project="$2"
        shift 2
        ;;
      --project=*)
      need_eq "$1"
        project="${1#--project=}"
        shift || true
        ;;
      --url)
        need_value "$@"
        url="$2"
        shift 2
        ;;
      --url=*)
      need_eq "$1"
        url="${1#--url=}"
        shift || true
        ;;
      --global | -g)
        global=1
        shift || true
        ;;
      --force | -f)
        force=1
        shift || true
        ;;
      -h | --help)
        cat <<'EOF'
spark.sh config init [--client slug] [--project name|cuid] [--url url] [--global] [--force]
  --global  → ~/.config/silex/spark.yml  (sinon ./config/spark.yml)
EOF
        return 0
        ;;
      *)
        echo "Option inconnue: $1" >&2
        return 1
        ;;
    esac
  done

  local target dir
  if [ "$global" = 1 ]; then
    dir="${HOME}/.config/silex"
    target="${dir}/spark.yml"
    mkdir -p "$dir"
    chmod 700 "$dir" 2>/dev/null || true
  else
    dir="${PWD}/config"
    target="${dir}/spark.yml"
    mkdir -p "$dir"
  fi

  if [ -f "$target" ] && [ "$force" != 1 ]; then
    echo "Existe déjà: $target (passe --force pour écraser)" >&2
    return 1
  fi

  # defaults from existing env / config if not passed
  if [ -z "$client" ]; then
    client="$(default_client 2>/dev/null || true)"
  fi
  if [ -z "$project" ]; then
    project="$(default_project 2>/dev/null || true)"
  fi
  if [ -z "$url" ]; then
    url="${SPARK_URL:-}"
    [ -n "$url" ] || url="$(default_url_from_config 2>/dev/null || true)"
  fi

  if [ -z "$client" ]; then
    echo "client requis pour init : --client <slug>" >&2
    return 1
  fi

  {
    echo "# Spark agent defaults (pas de secrets — PAT dans ~/.config/silex/spark.env)"
    echo "# Généré par spark.sh config init / spark-setup"
    echo "client: ${client}"
    if [ -n "$project" ]; then
      echo "project: ${project}"
    else
      echo "# project: mon-projet   # optionnel — create/search --project défaut"
    fi
    if [ -n "$url" ]; then
      echo "url: ${url}"
    else
      echo "# url: https://spark.gosilex.com"
    fi
  } >"$target"

  if [ "$global" = 1 ]; then
    chmod 600 "$target" 2>/dev/null || true
  fi
  echo "Écrit: $target"
  echo "  client: $client"
  [ -n "$project" ] && echo "  project: $project"
  [ -n "$url" ] && echo "  url: $url"
}

spark_config_show() {
  echo "=== config files (ordre) ==="
  local f found=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    found=1
    echo "— $f"
    sed 's/^/  /' "$f" 2>/dev/null || true
  done < <(spark_config_files)
  if [ "$found" = 0 ]; then
    echo "(aucun — spark.sh config init --client <slug>)"
  fi
  echo "=== resolved ==="
  echo "  client:  $(default_client 2>/dev/null || echo '(unset)')"
  echo "  project: $(default_project 2>/dev/null || echo '(unset)')"
  echo "  url cfg: $(default_url_from_config 2>/dev/null || echo '(unset)')"
  echo "  SPARK_URL env: ${SPARK_URL:-'(unset)'}"
  echo "  SPARK_CLIENT env: ${SPARK_CLIENT:-'(unset)'}"
}

spark_config_set() {
  # spark config set client acme | set project Foo | set url …
  local key="${1:-}" val="${2:-}"
  if [ -z "$key" ] || [ -z "$val" ]; then
    echo "Usage: spark.sh config set <client|project|url> <value> [--global]" >&2
    return 1
  fi
  local global=0
  shift 2 || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --global | -g) global=1; shift || true ;;
      *) echo "Option inconnue: $1" >&2; return 1 ;;
    esac
  done
  case "$key" in
    client | project | url) ;;
    *)
      echo "Clé invalide: $key (client|project|url)" >&2
      return 1
      ;;
  esac

  local target
  if [ "$global" = 1 ]; then
    mkdir -p "${HOME}/.config/silex"
    target="${HOME}/.config/silex/spark.yml"
  else
    target="$(spark_find_project_config 2>/dev/null || true)"
    if [ -z "$target" ]; then
      mkdir -p "${PWD}/config"
      target="${PWD}/config/spark.yml"
    fi
  fi

  if [ ! -f "$target" ]; then
    if [ "$key" = "client" ]; then
      spark_config_init --client "$val" $([ "$global" = 1 ] && echo --global)
      return $?
    fi
    echo "Pas de config — crée d'abord: spark.sh config init --client <slug>" >&2
    return 1
  fi

  KEY="$key" VAL="$val" FILE="$target" python3 - <<'PY'
import os, re
path, key, val = os.environ["FILE"], os.environ["KEY"], os.environ["VAL"]
lines = open(path, encoding="utf-8").read().splitlines()
out, found = [], False
pat = re.compile(rf"^(\s*)#?\s*{re.escape(key)}\s*:")
for line in lines:
    if pat.match(line.split("#")[0] if False else line) or (
        ":" in line and line.split("#")[0].split(":", 1)[0].strip() == key
    ):
        out.append(f"{key}: {val}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}: {val}")
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(path)
PY
  echo "Mis à jour: $key=$val → $target"
}
