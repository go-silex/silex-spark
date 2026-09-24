#!/usr/bin/env bash
# spark.sh — mini-CLI API Spark (PAT spu_)
# Usage:
#   spark.sh meta
#   spark.sh meta-links
#   spark.sh meta-projects
#   spark.sh tickets list <clientSlug>
#   spark.sh tickets search <clientSlug> [options]
#   spark.sh tickets actionable [clientSlug] [--json] [--include-internal]
#   spark.sh tickets create <clientSlug> <title> [body] [--priority p0|p1|p2|p3] [--type bug|feature] [--project id|name] [--score n] [--internal|--public]
#     défaut PAT staff = internal true ; --public = visible client ; priority défaut API = p2
#   spark.sh tickets patch <id|ref> <json> [--client slug]
#   spark.sh tickets reject <id|ref> [--client slug] [--duplicate <ref|id>] [--comment "…"]
#   spark.sh tickets get <id|ref> [--client slug]
#   spark.sh tickets comments list <id|ref> [--client slug]
#   spark.sh tickets comments add <id|ref> "body" [--parent N] [--internal] [--client slug]
#   spark.sh tickets github-list <id|ref> [--client slug]
#   spark.sh tickets github-create <id|ref> [--client slug]
#   spark.sh tickets github-link <id|ref> <#n|url> [--client slug]
#   spark.sh tickets github-unlink <id|ref> <issueNumber> [--client slug]
#   spark.sh projects list <clientSlug> [--kind development|delivery]
#   spark.sh projects by-repo <owner>/<repo>
#   spark.sh projects create <clientSlug> <name> [kind] [color]
#   spark.sh projects patch <id> <json>
#   spark.sh projects delete <id> [clientSlug]
#   spark.sh links list <client> [--task <id|ref>] [--kind parent|blocks|duplicates]
#   spark.sh links add <client> <task> <relation> <other>
#   spark.sh links delete <client> <linkId>
#   spark.sh resources list|get|create|create-md|create-file|patch|delete …
#   spark.sh journeys list|create|get|patch|delete …
#   spark.sh orgchart get|put …
#   spark.sh accueil get|patch …
#   spark.sh tasks list|create …
#   spark.sh tasks get|delete <cuid> [clientSlug | --client slug]
#   spark.sh tasks patch <cuid> <json> [--client slug]
#   spark.sh tasks comments list <cuid> [clientSlug | --client slug]
#   spark.sh tasks comments add <cuid> "body" [--parent N] [--internal] [--client slug]
#     client explicite seulement (jamais le défaut spark.yml) ; <cuid> vérifié (c…)
#   spark.sh ideas create [clientSlug] <title> [--internal]
#     défaut visible (internal false), comme la capture UI ; --internal = staff Silex
#   spark.sh get|post|patch|delete <path> [json]
#   spark.sh config show|init|set …
# Config client/project : config/spark.yml | ~/.config/silex/spark.yml (voir spark-config.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=spark-config.sh
. "${SCRIPT_DIR}/spark-config.sh"

resolve_key() {
  if [ -n "${SPARK_USER_API_KEY:-}" ]; then
    printf '%s' "$SPARK_USER_API_KEY"
    return 0
  fi
  if [ -n "${SPARK_API_KEY:-}" ] && [[ "${SPARK_API_KEY}" == spu_* ]]; then
    printf '%s' "$SPARK_API_KEY"
    return 0
  fi
  if [ -f "$HOME/.config/silex/spark.env" ]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$HOME/.config/silex/spark.env"
    set +a
    if [ -n "${SPARK_USER_API_KEY:-}" ]; then
      printf '%s' "$SPARK_USER_API_KEY"
      return 0
    fi
  fi
  if [ -f "$HOME/.config/silex/spark-user-api-key" ]; then
    tr -d '\n\r' <"$HOME/.config/silex/spark-user-api-key"
    return 0
  fi
  if command -v bw >/dev/null 2>&1; then
    local notes
    notes="$(bw get notes 'gosilex/spark-user-api-key' 2>/dev/null || true)"
    if [ -n "$notes" ]; then
      printf '%s' "$notes" | grep -oE 'spu_[0-9a-f]+' | head -1
      return 0
    fi
  fi
  return 1
}

resolve_url() {
  if [ -n "${SPARK_URL:-}" ]; then
    printf '%s' "${SPARK_URL%/}"
    return 0
  fi
  if [ -f "$HOME/.config/silex/spark.env" ]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$HOME/.config/silex/spark.env"
    set +a
    if [ -n "${SPARK_URL:-}" ]; then
      printf '%s' "${SPARK_URL%/}"
      return 0
    fi
  fi
  local from_cfg
  from_cfg="$(default_url_from_config 2>/dev/null || true)"
  if [ -n "$from_cfg" ]; then
    printf '%s' "${from_cfg%/}"
    return 0
  fi
  printf '%s' "https://spark.gosilex.com"
}

api() {
  local method="$1" path="$2"
  shift 2
  local url key
  url="$(resolve_url)"
  key="$(resolve_key)" || {
    echo "Clé API introuvable. Configure SPARK_USER_API_KEY, ~/.config/silex/spark.env, ou skill spark-setup." >&2
    exit 1
  }
  # Refuse absolute URLs — never send Bearer PAT to a third-party host
  case "$path" in
    http://* | https://*)
      echo "spark.sh: URL absolue refusée (utilisez un path /api/... relatif à SPARK_URL)." >&2
      exit 1
      ;;
    /*) path="${url}${path}" ;;
    *) path="${url}/${path}" ;;
  esac
  if [ "$#" -gt 0 ]; then
    curl -sS --connect-timeout 10 --max-time 60 -X "$method" "$path" \
      -H "Authorization: Bearer $key" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      --data "$1"
  else
    curl -sS --connect-timeout 10 --max-time 60 -X "$method" "$path" \
      -H "Authorization: Bearer $key" \
      -H "Accept: application/json"
  fi
}

# Multipart POST (resources create-file). Extra args = curl -F fields after path resolution.
api_multipart() {
  local path="$1"
  shift || true
  local url key
  url="$(resolve_url)"
  key="$(resolve_key)" || {
    echo "Clé API introuvable. Configure SPARK_USER_API_KEY, ~/.config/silex/spark.env, ou skill spark-setup." >&2
    exit 1
  }
  case "$path" in
    http://* | https://*)
      echo "spark.sh: URL absolue refusée (utilisez un path /api/... relatif à SPARK_URL)." >&2
      exit 1
      ;;
    /*) path="${url}${path}" ;;
    *) path="${url}/${path}" ;;
  esac
  curl -sS --connect-timeout 10 --max-time 120 -X POST "$path" \
    -H "Authorization: Bearer $key" \
    -H "Accept: application/json" \
    "$@"
}

# PATCH body avec clientSlug forcé à l'espace résolu : les routes /[id] lisent
# body.clientSlug avant ?client=, les deux canaux ne doivent jamais diverger.
json_with_client_slug() {
  JSON="$1" CLIENT="$2" python3 - <<'PY'
import json, os
body = json.loads(os.environ["JSON"])
if not isinstance(body, dict):
    raise SystemExit("json body must be an object")
body["clientSlug"] = os.environ["CLIENT"]
print(json.dumps(body))
PY
}

json_payload() {
  python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])))' "$1" 2>/dev/null || {
    # build object from env KEY=val pairs is done by callers
    printf '%s' "$1"
  }
}

cmd="${1:-}"
shift || true

case "$cmd" in
  config)
    csub="${1:-}"
    shift || true
    case "$csub" in
      show | "")
        spark_config_show
        ;;
      init)
        spark_config_init "$@"
        ;;
      set)
        spark_config_set "$@"
        ;;
      *)
        echo "Usage: spark.sh config {show|init|set} …" >&2
        exit 1
        ;;
    esac
    ;;
  meta | help-api)
    api GET "/api/v1/tickets?meta=1"
    echo
    ;;
  meta-links)
    api GET "/api/v1/task-links?meta=1"
    echo
    ;;
  meta-projects)
    api GET "/api/v1/projects?meta=1"
    echo
    ;;
  meta-resources)
    api GET "/api/v1/resources?meta=1"
    echo
    ;;
  meta-journeys)
    api GET "/api/v1/journeys?meta=1"
    echo
    ;;
  meta-orgchart)
    api GET "/api/v1/orgchart?meta=1"
    echo
    ;;
  meta-accueil)
    api GET "/api/v1/accueil?meta=1"
    echo
    ;;
  meta-tasks)
    api GET "/api/v1/tasks?meta=1"
    echo
    ;;
  v1)
    api GET "/api/v1"
    echo
    ;;
  resources)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh resources list [clientSlug]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        api GET "/api/v1/resources?client=${client}"
        echo
        ;;
      get)
        id="${1:-}"
        shift || true
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh resources get <id> [clientSlug]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        if [ -z "$id" ]; then
          echo "Usage: spark.sh resources get <id> [clientSlug]" >&2
          exit 1
        fi
        api GET "/api/v1/resources/${id}?client=${client}"
        echo
        ;;
      create)
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh resources create [client] <title> <url> …" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        title="${1:-}"
        shift || true
        url="${1:-}"
        shift || true
        category="Autre"
        internal_flag=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --category)
              need_value "$@"
              category="$2"
              shift 2
              ;;
            --category=*)
              need_eq "$1"
              category="${1#--category=}"
              shift || true
              ;;
            --internal)
              internal_flag=1
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -z "$client" ] || [ -z "$url" ]; then
          echo "Usage: spark.sh resources create <client> <title> <url> [--category Lectures|Comptes-rendus|Autre] [--internal]" >&2
          exit 1
        fi
        if [ -z "$title" ]; then title="$url"; fi
        payload="$(
          CLIENT="$client" TITLE="$title" URL="$url" CAT="$category" INTERNAL="${internal_flag:-0}" python3 - <<'PY'
import json, os
payload = {
  "clientSlug": os.environ["CLIENT"],
  "title": os.environ["TITLE"],
  "url": os.environ["URL"],
  "category": os.environ.get("CAT") or "Autre",
}
if os.environ.get("INTERNAL") == "1":
  payload["internal"] = True
print(json.dumps(payload))
PY
        )"
        api POST "/api/v1/resources" "$payload"
        echo
        ;;
      create-md|create-markdown)
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh resources create-md [client] <title> [body] [--category …] [--public]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        title="${1:-}"
        shift || true
        body_md=""
        category="Autre"
        public_flag=0
        # body is next positional unless flag
        if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
          body_md="${1:-}"
          shift || true
        fi
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --category)
              need_value "$@"
              category="$2"
              shift 2
              ;;
            --category=*)
              need_eq "$1"
              category="${1#--category=}"
              shift || true
              ;;
            --public)
              public_flag=1
              shift || true
              ;;
            --body)
              need_value "$@"
              body_md="$2"
              shift 2
              ;;
            --body=*)
              need_eq "$1"
              body_md="${1#--body=}"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -z "$client" ] || [ -z "$title" ]; then
          echo "Usage: spark.sh resources create-md <client> <title> [body] [--category Comptes-rendus] [--public]" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" TITLE="$title" BODY="$body_md" CAT="$category" PUB="$public_flag" python3 - <<'PY'
import json, os
pub = os.environ.get("PUB") == "1"
payload = {
  "clientSlug": os.environ["CLIENT"],
  "kind": "markdown",
  "title": os.environ["TITLE"],
  "body": os.environ.get("BODY") or "",
  "category": os.environ.get("CAT") or "Autre",
}
if pub:
  payload["internal"] = False
# omit internal when default (agent = true server-side)
print(json.dumps(payload))
PY
        )"
        api POST "/api/v1/resources" "$payload"
        echo
        ;;
      create-file|create-upload)
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh resources create-file [client] <path/to/file> [title] [--category …] [--internal]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        file_path="${1:-}"
        shift || true
        title=""
        category="Autre"
        internal_flag=0
        if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
          title="${1:-}"
          shift || true
        fi
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --category)
              need_value "$@"
              category="$2"
              shift 2
              ;;
            --category=*)
              need_eq "$1"
              category="${1#--category=}"
              shift || true
              ;;
            --title)
              need_value "$@"
              title="$2"
              shift 2
              ;;
            --title=*)
              need_eq "$1"
              title="${1#--title=}"
              shift || true
              ;;
            --internal)
              internal_flag=1
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -z "$client" ] || [ -z "$file_path" ]; then
          echo "Usage: spark.sh resources create-file <client> <file> [title] [--category Lectures] [--internal]" >&2
          exit 1
        fi
        if [ ! -f "$file_path" ]; then
          echo "Fichier introuvable: $file_path" >&2
          exit 1
        fi
        if [ -z "$title" ]; then title="$(basename "$file_path")"; fi
        multipart_args=(
          -F "clientSlug=${client}"
          -F "title=${title}"
          -F "category=${category}"
          -F "file=@${file_path}"
        )
        if [ "$internal_flag" = 1 ]; then
          multipart_args+=(-F "internal=true")
        fi
        api_multipart "/api/v1/resources" "${multipart_args[@]}"
        echo
        ;;
      patch)
        id="${1:-}"
        shift || true
        parse_client_positional "${1:-}" || true
        # patch: resources patch <id> '{"title":"…"}' [--client slug]
        # or resources patch <id> <client> '{"…"}'
        json_body=""
        client="${PARSED_CLIENT:-}"
        if [ -n "${1:-}" ] && [[ "${1:-}" == \{* ]]; then
          json_body="$1"
          shift || true
        elif [ -n "${1:-}" ] && [[ "${1:-}" != --* ]]; then
          # maybe client then json
          if [ -z "$client" ]; then client="$1"; shift || true; fi
          json_body="${1:-}"
          shift || true
        fi
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
            \{*)
              json_body="$1"
              shift || true
              ;;
            *)
              if [ -z "$json_body" ]; then json_body="$1"; fi
              shift || true
              ;;
          esac
        done
        if [ -z "$id" ] || [ -z "$json_body" ]; then
          echo "Usage: spark.sh resources patch <id> '{\"title\":\"…\",\"body\":\"…\"}' [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client"
        client="${PARSED_CLIENT:-}"
        if [ -z "$client" ]; then
          echo "clientSlug requis (arg, --client, ou spark.yml)." >&2
          client_missing_hint
          exit 1
        fi
        api PATCH "/api/v1/resources/${id}?client=${client}" "$json_body"
        echo
        ;;
      delete)
        id="${1:-}"
        client="${2:-}"
        if [ -z "$id" ]; then
          echo "Usage: spark.sh resources delete <id> [clientSlug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api DELETE "/api/v1/resources/${id}?client=${client}"
        else
          api DELETE "/api/v1/resources/${id}"
        fi
        echo
        ;;
      *)
        echo "Usage: spark.sh resources {list|get|create|create-md|patch|delete} …" >&2
        exit 1
        ;;
    esac
    ;;
  tasks)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh tasks list [clientSlug] [--status s] [--project p] …" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        qs="client=${client}"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --status)
              need_value "$@"
              qs="${qs}&status=$2"
              shift 2
              ;;
            --project)
              need_value "$@"
              qs="${qs}&project=$2"
              shift 2
              ;;
            --query|-q)
              need_value "$@"
              qs="${qs}&query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$2")"
              shift 2
              ;;
            --include-comments)
              qs="${qs}&include=comments"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        api GET "/api/v1/tasks?${qs}"
        echo
        ;;
      create)
        client="${1:-}"
        shift || true
        title="${1:-}"
        shift || true
        if [ -z "$client" ] || [ -z "$title" ]; then
          echo "Usage: spark.sh tasks create <client> <title> [description]" >&2
          exit 1
        fi
        desc="${1:-}"
        payload="$(
          CLIENT="$client" TITLE="$title" DESC="$desc" python3 - <<'PY'
import json, os
print(json.dumps({
  "clientSlug": os.environ["CLIENT"],
  "title": os.environ["TITLE"],
  "description": os.environ.get("DESC") or "",
}))
PY
        )"
        api POST "/api/v1/tasks" "$payload"
        echo
        ;;
      get)
        id="${1:-}"
        shift || true
        parse_client_args "$@"
        client="$PARSED_CLIENT"
        if ! is_task_cuid "$id"; then
          echo "Usage: spark.sh tasks get <cuid> [clientSlug|--client slug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api GET "/api/v1/tasks/${id}?client=${client}"
        else
          api GET "/api/v1/tasks/${id}"
        fi
        echo
        ;;
      patch)
        id="${1:-}"
        shift || true
        # Même convention que tickets patch : 1er non-flag = JSON, rien d'autre.
        json=""
        client_args=()
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --client)
              need_value "$@"
              client_args+=("$1" "$2")
              shift 2
              ;;
            --client=*)
              client_args+=("$1")
              shift
              ;;
            --*)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
            *)
              if [ -n "$json" ]; then
                echo "Arg inconnu: $1" >&2
                exit 1
              fi
              json="$1"
              shift
              ;;
          esac
        done
        parse_client_args ${client_args[@]+"${client_args[@]}"}
        client="$PARSED_CLIENT"
        if ! is_task_cuid "$id" || [ -z "$json" ]; then
          echo "Usage: spark.sh tasks patch <cuid> '<json>' [--client slug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          payload="$(json_with_client_slug "$json" "$client")"
          api PATCH "/api/v1/tasks/${id}?client=${client}" "$payload"
        else
          api PATCH "/api/v1/tasks/${id}" "$json"
        fi
        echo
        ;;
      delete)
        id="${1:-}"
        shift || true
        parse_client_args "$@"
        client="$PARSED_CLIENT"
        if ! is_task_cuid "$id"; then
          echo "Usage: spark.sh tasks delete <cuid> [clientSlug|--client slug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api DELETE "/api/v1/tasks/${id}?client=${client}"
        else
          api DELETE "/api/v1/tasks/${id}"
        fi
        echo
        ;;
      comments)
        csub="${1:-}"
        shift || true
        case "$csub" in
          list)
            id="${1:-}"
            shift || true
            parse_client_args "$@"
            client="$PARSED_CLIENT"
            if ! is_task_cuid "$id"; then
              echo "Usage: spark.sh tasks comments list <cuid> [clientSlug|--client slug]" >&2
              exit 1
            fi
            if [ -n "$client" ]; then
              api GET "/api/v1/tasks/${id}/comments?client=${client}"
            else
              api GET "/api/v1/tasks/${id}/comments"
            fi
            echo
            ;;
          add)
            id="${1:-}"
            shift || true
            body_text=""
            parent=""
            internal=""
            client_args=()
            # Même garde que tickets comments add : un flag inconnu (ex. --intrenal)
            # ne doit jamais finir dans le texte d'un commentaire visible client.
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --parent)
                  need_value "$@"
                  parent="$2"
                  shift 2
                  ;;
                --parent=*)
                  need_eq "$1"
                  parent="${1#--parent=}"
                  shift
                  ;;
                --internal)
                  internal="1"
                  shift
                  ;;
                --client)
                  need_value "$@"
                  client_args+=("$1" "$2")
                  shift 2
                  ;;
                --client=*)
                  client_args+=("$1")
                  shift
                  ;;
                --*)
                  echo "Option inconnue: $1" >&2
                  exit 1
                  ;;
                *)
                  body_text="${body_text:+$body_text }$1"
                  shift
                  ;;
              esac
            done
            parse_client_args ${client_args[@]+"${client_args[@]}"}
            client="$PARSED_CLIENT"
            if ! is_task_cuid "$id" || [ -z "$body_text" ]; then
              echo "Usage: spark.sh tasks comments add <cuid> \"body\" [--parent N] [--internal] [--client slug]" >&2
              exit 1
            fi
            payload="$(
              BODY="$body_text" PARENT="$parent" INTERNAL="$internal" CLIENT="$client" python3 - <<'PY'
import json, os
p = {"body": (os.environ.get("BODY") or "").strip()}
if (os.environ.get("PARENT") or "").strip():
    p["parentId"] = int(os.environ["PARENT"])
if (os.environ.get("INTERNAL") or "").strip() in ("1", "true"):
    p["internal"] = True
if (os.environ.get("CLIENT") or "").strip():
    p["clientSlug"] = os.environ["CLIENT"]
print(json.dumps(p))
PY
            )"
            api POST "/api/v1/tasks/${id}/comments" "$payload"
            echo
            ;;
          *)
            echo "Usage: spark.sh tasks comments {list|add}" >&2
            exit 1
            ;;
        esac
        ;;
      *)
        echo "Usage: spark.sh tasks {list|create|get|patch|delete|comments} …" >&2
        exit 1
        ;;
    esac
    ;;
  accueil)
    sub="${1:-}"
    shift || true
    case "$sub" in
      get)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh accueil get [clientSlug]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        api GET "/api/v1/accueil?client=${client}"
        echo
        ;;
      patch)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh accueil patch [clientSlug] '<json>'" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        json="${1:-}"
        if [ -z "$client" ] || [ -z "$json" ]; then
          echo "Usage: spark.sh accueil patch [clientSlug] '<json partial>'" >&2
          echo "  fields: recap, livrables, roadmap, accueilData" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" JSON="$json" python3 - <<'PY'
import json, os
obj = json.loads(os.environ["JSON"])
if not isinstance(obj, dict):
    raise SystemExit("JSON object expected")
obj["clientSlug"] = os.environ["CLIENT"]
print(json.dumps(obj))
PY
        )"
        api PATCH "/api/v1/accueil" "$payload"
        echo
        ;;
      *)
        echo "Usage: spark.sh accueil {get|patch} …" >&2
        exit 1
        ;;
    esac
    ;;
  orgchart)
    sub="${1:-}"
    shift || true
    case "$sub" in
      get)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh orgchart get [clientSlug] [--kind orgchart]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        kind="orgchart"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --kind)
              need_value "$@"
              kind="$2"
              shift 2
              ;;
            --kind=*)
              need_eq "$1"
              kind="${1#--kind=}"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        api GET "/api/v1/orgchart?client=${client}&kind=${kind}"
        echo
        ;;
      put)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh orgchart put [clientSlug] '<json>'" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        json="${1:-}"
        if [ -z "$client" ] || [ -z "$json" ]; then
          echo "Usage: spark.sh orgchart put [clientSlug] '<json data or full body>'" >&2
          echo "  json = full body {data, kind?} or data object only" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" JSON="$json" python3 - <<'PY'
import json, os
raw = os.environ["JSON"]
client = os.environ["CLIENT"]
try:
    obj = json.loads(raw)
except json.JSONDecodeError as e:
    raise SystemExit(f"JSON invalide: {e}") from e
if isinstance(obj, dict) and "data" in obj:
    body = dict(obj)
    body.setdefault("clientSlug", client)
else:
    body = {"clientSlug": client, "data": obj}
print(json.dumps(body))
PY
        )"
        api PUT "/api/v1/orgchart" "$payload"
        echo
        ;;
      *)
        echo "Usage: spark.sh orgchart {get|put} …" >&2
        exit 1
        ;;
    esac
    ;;
  journeys)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh journeys list [clientSlug]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        api GET "/api/v1/journeys?client=${client}"
        echo
        ;;
      create)
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh journeys create [clientSlug] [name]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        name="${1:-}"
        if [ -z "$client" ]; then
          echo "Usage: spark.sh journeys create [clientSlug] [name]" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" NAME="$name" python3 - <<'PY'
import json, os
p = {"clientSlug": os.environ["CLIENT"]}
n = (os.environ.get("NAME") or "").strip()
if n:
    p["name"] = n
print(json.dumps(p))
PY
        )"
        api POST "/api/v1/journeys" "$payload"
        echo
        ;;
      get)
        id="${1:-}"
        client="${2:-}"
        if [ -z "$id" ]; then
          echo "Usage: spark.sh journeys get <id> [clientSlug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api GET "/api/v1/journeys/${id}?client=${client}"
        else
          api GET "/api/v1/journeys/${id}"
        fi
        echo
        ;;
      patch)
        id="${1:-}"
        json="${2:-}"
        if [ -z "$id" ] || [ -z "$json" ]; then
          echo "Usage: spark.sh journeys patch <id> '<json>'" >&2
          exit 1
        fi
        api PATCH "/api/v1/journeys/${id}" "$json"
        echo
        ;;
      delete)
        id="${1:-}"
        client="${2:-}"
        if [ -z "$id" ]; then
          echo "Usage: spark.sh journeys delete <id> [clientSlug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api DELETE "/api/v1/journeys/${id}?client=${client}"
        else
          api DELETE "/api/v1/journeys/${id}"
        fi
        echo
        ;;
      *)
        echo "Usage: spark.sh journeys {list|create|get|patch|delete} …" >&2
        exit 1
        ;;
    esac
    ;;
  projects)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh projects list [clientSlug] [--kind development|delivery]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        q="client=${client}"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --kind)
              need_value "$@"
              q="${q}&kind=$2"
              shift 2
              ;;
            --include-archived)
              q="${q}&includeArchived=1"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        api GET "/api/v1/projects?${q}"
        echo
        ;;
      create)
        client="${1:-}"
        name="${2:-}"
        kind="${3:-development}"
        color="${4:-slate}"
        if [ -z "$client" ] || [ -z "$name" ]; then
          echo "Usage: spark.sh projects create <clientSlug> <name> [kind=development] [color=slate]" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" NAME="$name" KIND="$kind" COLOR="$color" python3 - <<'PY'
import json, os
print(json.dumps({
  "clientSlug": os.environ["CLIENT"],
  "name": os.environ["NAME"],
  "kind": os.environ.get("KIND") or "development",
  "color": os.environ.get("COLOR") or "slate",
}))
PY
        )"
        api POST "/api/v1/projects" "$payload"
        echo
        ;;
      patch)
        id="${1:-}"
        json="${2:-}"
        if [ -z "$id" ] || [ -z "$json" ]; then
          echo "Usage: spark.sh projects patch <id> '<json>'" >&2
          exit 1
        fi
        api PATCH "/api/v1/projects/${id}" "$json"
        echo
        ;;
      delete)
        id="${1:-}"
        client="${2:-}"
        if [ -z "$id" ]; then
          echo "Usage: spark.sh projects delete <id> [clientSlug]" >&2
          exit 1
        fi
        if [ -n "$client" ]; then
          api DELETE "/api/v1/projects/${id}?client=${client}"
        else
          api DELETE "/api/v1/projects/${id}"
        fi
        echo
        ;;
      by-repo)
        repo_spec="${1:-}"
        if [ -z "$repo_spec" ]; then
          echo "Usage: spark.sh projects by-repo <owner>/<repo>" >&2
          exit 1
        fi
        if [ "$(printf '%s' "$repo_spec" | tr -cd '/' | wc -c)" -ne 1 ]; then
          echo "Usage: spark.sh projects by-repo <owner>/<repo> (owner et repo requis, un seul slash)" >&2
          exit 1
        fi
        owner="${repo_spec%%/*}"
        repo="${repo_spec#*/}"
        if [ -z "$owner" ] || [ -z "$repo" ]; then
          echo "Usage: spark.sh projects by-repo <owner>/<repo> (owner et repo requis)" >&2
          exit 1
        fi
        owner_enc="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$owner")"
        repo_enc="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$repo")"
        api GET "/api/v1/projects/by-repo?owner=${owner_enc}&repo=${repo_enc}"
        echo
        ;;
      *)
        echo "Usage: spark.sh projects {list|by-repo|create|patch|delete} …" >&2
        exit 1
        ;;
    esac
    ;;
  tickets)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh tickets list [clientSlug]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        api GET "/api/v1/tickets?client=${client}"
        echo
        ;;
      actionable)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh tickets actionable [clientSlug] [--json] [--include-internal]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        as_json=0
        include_internal=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json)
              as_json=1
              shift || true
              ;;
            --include-internal)
              include_internal=1
              shift || true
              ;;
            *)
              echo "Usage: spark.sh tickets actionable [clientSlug] [--json] [--include-internal]" >&2
              exit 1
              ;;
          esac
        done
        py_args=(--slug "$client")
        [ "$as_json" = 1 ] && py_args+=(--json)
        [ "$include_internal" = 1 ] && py_args+=(--include-internal)
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT
        python3 -c 'import json,sys; json.dump({"tickets": []}, sys.stdout)' >"$work/all.json"
        offset=0
        limit=200
        while true; do
          api GET "/api/v1/tickets?client=${client}&limit=${limit}&offset=${offset}" >"$work/page.json"
          added="$(
            python3 -c '
import json, sys
all_p, page_p = sys.argv[1], sys.argv[2]
with open(all_p, encoding="utf-8") as f:
    acc = json.load(f)
with open(page_p, encoding="utf-8") as f:
    page = json.load(f)
chunk = page["tickets"] if isinstance(page, dict) else page
if not isinstance(chunk, list):
    raise SystemExit("tickets-actionable: unexpected page shape")
acc["tickets"].extend(chunk)
with open(all_p, "w", encoding="utf-8") as f:
    json.dump(acc, f, ensure_ascii=False)
print(len(chunk))
' "$work/all.json" "$work/page.json"
          )"
          [ "$added" -lt "$limit" ] && break
          offset=$((offset + limit))
        done
        python3 "${SCRIPT_DIR}/tickets-actionable.py" "${py_args[@]}" <"$work/all.json"
        ;;
      search)
        parse_client_positional "${1:-}" || {
          cat <<'USAGE' >&2
Usage: spark.sh tickets search [clientSlug] [options]
  (client optionnel si config/spark.yml ou SPARK_CLIENT)

  --priority p0|p1|p2|p3     (CSV ok : p0,p1)
  --status new|todo|doing|staging|done|rejected
  --type bug|feature
  --project <id|name>
  --onRoadmap | --onRoadmap=true|false
  --internal  | --internal=true|false
  --assignee <userId>
  --query "texte"            (title + body)
  --limit N                  (défaut 100)
  --offset N                 (défaut 0)
  --score <csv>              (entiers, match exact : 8 ou 34,55)
  --unscored                 (tickets sans Score ; exclusif avec --score)
  --scoreMode manual|automatic
USAGE
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        # défauts search (list reste sans plafond)
        limit="100"
        offset="0"
        priority=""
        status=""
        type=""
        project=""
        on_roadmap=""
        internal=""
        assignee=""
        query=""
        score=""
        unscored=""
        score_mode=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --priority)
              need_value "$@"
              priority="$2"
              shift 2
              ;;
            --priority=*)
              need_eq "$1"
              priority="${1#--priority=}"
              shift || true
              ;;
            --status)
              need_value "$@"
              status="$2"
              shift 2
              ;;
            --status=*)
              need_eq "$1"
              status="${1#--status=}"
              shift || true
              ;;
            --type)
              need_value "$@"
              type="$2"
              shift 2
              ;;
            --type=*)
              need_eq "$1"
              type="${1#--type=}"
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
            --onRoadmap | --on-roadmap)
              on_roadmap="1"
              shift || true
              ;;
            --onRoadmap=* | --on-roadmap=*)
              need_eq "$1"
              on_roadmap="${1#*=}"
              shift || true
              ;;
            --internal)
              internal="1"
              shift || true
              ;;
            --internal=*)
              need_eq "$1"
              internal="${1#--internal=}"
              shift || true
              ;;
            --score)
              [ "$#" -ge 2 ] || { echo "spark.sh: $1 attend une valeur" >&2; exit 1; }
              score="$2"
              shift 2
              ;;
            --score=*)
              need_eq "$1"
              score="${1#--score=}"
              shift || true
              ;;
            --unscored)
              unscored="1"
              shift || true
              ;;
            --scoreMode | --score-mode)
              [ "$#" -ge 2 ] || { echo "spark.sh: $1 attend une valeur" >&2; exit 1; }
              score_mode="$2"
              shift 2
              ;;
            --scoreMode=* | --score-mode=*)
              need_eq "$1"
              score_mode="${1#*=}"
              shift || true
              ;;
            --assignee)
              need_value "$@"
              assignee="$2"
              shift 2
              ;;
            --assignee=*)
              need_eq "$1"
              assignee="${1#--assignee=}"
              shift || true
              ;;
            --query | -q)
              need_value "$@"
              query="$2"
              shift 2
              ;;
            --query=* | -q=*)
              need_eq "$1"
              query="${1#*=}"
              shift || true
              ;;
            --limit)
              need_value "$@"
              limit="$2"
              shift 2
              ;;
            --limit=*)
              need_eq "$1"
              limit="${1#--limit=}"
              shift || true
              ;;
            --offset)
              need_value "$@"
              offset="$2"
              shift 2
              ;;
            --offset=*)
              need_eq "$1"
              offset="${1#--offset=}"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -n "$score" ] && [ -n "$unscored" ]; then
          echo "spark.sh tickets search: --score et --unscored sont exclusifs (un ticket non scoré n'a pas de valeur) — choisir l'un ou l'autre." >&2
          exit 1
        fi
        if [ -n "$score" ]; then
          case "$score" in
            *[!0-9,]* | ,* | *, | *,,*)
              echo "spark.sh tickets search: --score attend des entiers séparés par des virgules (ex: 8 ou 34,55) — reçu: $score" >&2
              exit 1
              ;;
          esac
        fi
        if [ -n "$score_mode" ]; then
          case "$score_mode" in
            manual | automatic) ;;
            *)
              echo "spark.sh tickets search: --scoreMode manual|automatic attendu (reçu: $score_mode)" >&2
              exit 1
              ;;
          esac
        fi
        if [ -z "$project" ]; then
          project="$(default_project 2>/dev/null || true)"
        fi
        qs="$(
          CLIENT="$client" PRIORITY="$priority" STATUS="$status" TYPE="$type" \
            PROJECT="$project" ON_ROADMAP="$on_roadmap" INTERNAL="$internal" \
            ASSIGNEE="$assignee" QUERY="$query" LIMIT="$limit" OFFSET="$offset" \
            SCORE="$score" UNSCORED="$unscored" SCORE_MODE="$score_mode" \
            python3 - <<'PY'
import os
from urllib.parse import urlencode

def add(d, k, v):
    v = (v or "").strip()
    if v:
        d[k] = v

params = {"client": os.environ["CLIENT"]}
add(params, "priority", os.environ.get("PRIORITY"))
add(params, "status", os.environ.get("STATUS"))
add(params, "type", os.environ.get("TYPE"))
add(params, "project", os.environ.get("PROJECT"))
add(params, "assignee", os.environ.get("ASSIGNEE"))
add(params, "query", os.environ.get("QUERY"))
add(params, "score", os.environ.get("SCORE"))
add(params, "unscored", os.environ.get("UNSCORED"))
add(params, "scoreMode", os.environ.get("SCORE_MODE"))
# flags booléens : toujours envoyer si set (y compris "0"/"false")
or_ = (os.environ.get("ON_ROADMAP") or "").strip()
if or_ != "":
    params["onRoadmap"] = or_
intr = (os.environ.get("INTERNAL") or "").strip()
if intr != "":
    params["internal"] = intr
limit = (os.environ.get("LIMIT") or "").strip()
if limit != "":
    params["limit"] = limit
offset = (os.environ.get("OFFSET") or "").strip()
if offset != "" and offset != "0":
    params["offset"] = offset
elif offset == "0":
    params["offset"] = "0"
print(urlencode(params))
PY
        )"
        api GET "/api/v1/tickets?${qs}"
        echo
        ;;
      create)
        # strict : "Mon titre" n'est pas un slug → utilise client défaut
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh tickets create [clientSlug] <title> [body] …" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        title="${1:-}"
        shift || true
        case "$title" in
          --help | -h)
            echo "Usage: spark.sh tickets create [clientSlug] <title> [body] [--priority …] [--project …] [--score n] [--public]" >&2
            exit 1
            ;;
          --*)
            echo "spark.sh tickets create: le titre ne peut pas commencer par -- (reçu: $title)" >&2
            exit 1
            ;;
        esac
        body=""
        visibility="" # "" = omit (API staff → internal true) | internal | public
        priority=""   # "" = omit → API default p2
        ticket_type=""
        project=""
        score=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --public)
              visibility="public"
              shift
              ;;
            --internal)
              visibility="internal"
              shift
              ;;
            --internal=*)
              need_eq "$1"
              v="${1#--internal=}"
              case "$v" in
                1|true|yes|on) visibility="internal" ;;
                0|false|no|off) visibility="public" ;;
                *)
                  echo "spark.sh: --internal= true|false attendu" >&2
                  exit 1
                  ;;
              esac
              shift
              ;;
            --priority)
              need_value "$@"
              priority="$2"
              shift 2
              ;;
            --priority=*)
              need_eq "$1"
              priority="${1#--priority=}"
              shift
              ;;
            --type)
              need_value "$@"
              ticket_type="$2"
              shift 2
              ;;
            --type=*)
              need_eq "$1"
              ticket_type="${1#--type=}"
              shift
              ;;
            --project)
              need_value "$@"
              project="$2"
              shift 2
              ;;
            --project=*)
              need_eq "$1"
              project="${1#--project=}"
              shift
              ;;
            --score)
              [ "$#" -ge 2 ] || { echo "spark.sh: $1 attend une valeur" >&2; exit 1; }
              score="$2"
              shift 2
              ;;
            --score=*)
              need_eq "$1"
              score="${1#--score=}"
              shift
              ;;
            --*)
              echo "spark.sh tickets create: option inconnue: $1" >&2
              exit 1
              ;;
            *)
              # premier arg positionnel restant = body
              if [ -z "$body" ]; then
                body="$1"
              else
                body="$body $1"
              fi
              shift
              ;;
          esac
        done
        if [ -z "$client" ] || [ -z "$title" ]; then
          echo "Usage: spark.sh tickets create [clientSlug] <title> [body] [--priority …] [--project …] [--public]" >&2
          echo "  client optionnel si config/spark.yml. Défaut staff = interne ; --public = visible client." >&2
          exit 1
        fi
        if [ -z "$project" ]; then
          project="$(default_project 2>/dev/null || true)"
        fi
        if [ -n "$priority" ]; then
          case "$priority" in
            p0|p1|p2|p3) ;;
            *)
              echo "spark.sh tickets create: --priority p0|p1|p2|p3 attendu (reçu: $priority)" >&2
              exit 1
              ;;
          esac
        fi
        if [ -n "$ticket_type" ]; then
          case "$ticket_type" in
            bug|feature) ;;
            *)
              echo "spark.sh tickets create: --type bug|feature attendu (reçu: $ticket_type)" >&2
              exit 1
              ;;
          esac
        fi
        if [ -n "$score" ]; then
          case "$score" in
            1|2|3|5|8|13|21|34|55) ;;
            *)
              echo "spark.sh tickets create: --score attend une valeur de l'échelle 1|2|3|5|8|13|21 (jouable) ou 34|55 (préscore) — reçu: $score" >&2
              exit 1
              ;;
          esac
        fi
        payload="$(
          TITLE="$title" BODY="$body" CLIENT="$client" VIS="$visibility" \
            PRIORITY="$priority" TTYPE="$ticket_type" PROJECT="$project" \
            SCORE="$score" python3 - <<'PY'
import json, os
payload = {
  "clientSlug": os.environ["CLIENT"],
  "title": os.environ["TITLE"],
  "body": os.environ.get("BODY") or "",
}
vis = (os.environ.get("VIS") or "").strip()
if vis == "public":
  payload["internal"] = False
elif vis == "internal":
  payload["internal"] = True
# omit → API resolveCreateInternal (staff default true)
prio = (os.environ.get("PRIORITY") or "").strip()
if prio:
  payload["priority"] = prio
ttype = (os.environ.get("TTYPE") or "").strip()
if ttype:
  payload["type"] = ttype
sc = (os.environ.get("SCORE") or "").strip()
if sc:
  payload["score"] = int(sc)
proj = (os.environ.get("PROJECT") or "").strip()
if proj:
  # create API : projectId = cuid uniquement (pas le nom).
  payload["projectId"] = proj
print(json.dumps(payload))
PY
        )"
        api POST "/api/v1/tickets" "$payload"
        echo
        ;;
      patch)
        id="${1:-}"
        shift || true
        json=""
        client=""
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
            *)
              if [ -z "$json" ]; then
                json="$1"
              else
                echo "Arg inconnu: $1" >&2
                exit 1
              fi
              shift || true
              ;;
          esac
        done
        if [ -z "$id" ] || [ -z "$json" ]; then
          echo "Usage: spark.sh tickets patch <id|ref> '<json>' [--client slug]" >&2
          echo "  Owner + ref numérique : --client ou config/spark.yml (sinon CUID)." >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        # clientSlug aussi en body pour PATCH (query + body supportés par l'API)
        if [ -n "$client" ]; then
          payload="$(json_with_client_slug "$json" "$client")"
          api PATCH "/api/v1/tickets/${id}?client=${client}" "$payload"
        else
          api PATCH "/api/v1/tickets/${id}" "$json"
        fi
        echo
        ;;
      reject)
        id="${1:-}"
        shift || true
        client=""
        duplicate=""
        comment=""
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
            --duplicate)
              need_value "$@"
              duplicate="$2"
              shift 2
              ;;
            --duplicate=*)
              need_eq "$1"
              duplicate="${1#--duplicate=}"
              shift || true
              ;;
            --comment)
              need_value "$@"
              comment="$2"
              shift 2
              ;;
            --comment=*)
              need_eq "$1"
              comment="${1#--comment=}"
              shift || true
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -z "$id" ]; then
          echo "Usage: spark.sh tickets reject <id|ref> [--client slug] [--duplicate <ref|id>] [--comment \"…\"]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        payload="$(
          CLIENT="$client" DUP="$duplicate" COMMENT="$comment" python3 - <<'PY'
import json, os
body = {}
c = (os.environ.get("CLIENT") or "").strip()
if c:
    body["clientSlug"] = c
d = (os.environ.get("DUP") or "").strip()
if d:
    body["duplicateOf"] = d
cm = (os.environ.get("COMMENT") or "").strip()
if cm:
    body["reason"] = cm
print(json.dumps(body))
PY
        )"
        if [ -n "$client" ]; then
          api POST "/api/v1/tickets/${id}/reject?client=${client}" "$payload"
        else
          api POST "/api/v1/tickets/${id}/reject" "$payload"
        fi
        echo
        ;;
      get)
        id="${1:-}"
        shift || true
        client=""
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
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        if [ -z "$id" ]; then
          echo "Usage: spark.sh tickets get <id|ref> [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        if [ -n "$client" ]; then
          api GET "/api/v1/tickets/${id}?client=${client}"
        else
          api GET "/api/v1/tickets/${id}"
        fi
        echo
        ;;
      comments)
        csub="${1:-}"
        shift || true
        case "$csub" in
          list)
            id="${1:-}"
            shift || true
            client=""
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
                *)
                  echo "Arg inconnu: $1" >&2
                  exit 1
                  ;;
              esac
            done
            if [ -z "$id" ]; then
              echo "Usage: spark.sh tickets comments list <id> [--client slug]" >&2
              exit 1
            fi
            fill_client_if_empty "$client" || true
            client="$PARSED_CLIENT"
            if [ -n "$client" ]; then
              api GET "/api/v1/tickets/${id}/comments?client=${client}"
            else
              api GET "/api/v1/tickets/${id}/comments"
            fi
            echo
            ;;
          add)
            id="${1:-}"
            shift || true
            body_text=""
            parent=""
            internal=""
            client=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --parent)
                  need_value "$@"
                  parent="$2"
                  shift 2
                  ;;
                --parent=*)
                  need_eq "$1"
                  parent="${1#--parent=}"
                  shift || true
                  ;;
                --internal)
                  internal="1"
                  shift || true
                  ;;
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
                --*)
                  echo "Option inconnue: $1" >&2
                  exit 1
                  ;;
                *)
                  if [ -z "$body_text" ]; then
                    body_text="$1"
                  else
                    body_text="$body_text $1"
                  fi
                  shift || true
                  ;;
              esac
            done
            if [ -z "$id" ] || [ -z "$body_text" ]; then
              echo "Usage: spark.sh tickets comments add <id> \"body\" [--parent N] [--internal] [--client slug]" >&2
              exit 1
            fi
            fill_client_if_empty "$client" || true
            client="$PARSED_CLIENT"
            payload="$(
              BODY="$body_text" PARENT="$parent" INTERNAL="$internal" CLIENT="$client" python3 - <<'PY'
import json, os
p = {"body": os.environ.get("BODY") or ""}
parent = (os.environ.get("PARENT") or "").strip()
if parent:
    p["parentId"] = int(parent)
if (os.environ.get("INTERNAL") or "").strip() in ("1", "true", "yes"):
    p["internal"] = True
client = (os.environ.get("CLIENT") or "").strip()
if client:
    p["clientSlug"] = client
print(json.dumps(p))
PY
            )"
            api POST "/api/v1/tickets/${id}/comments" "$payload"
            echo
            ;;
          *)
            echo "Usage: spark.sh tickets comments {list|add} …" >&2
            exit 1
            ;;
        esac
        ;;
      github-list)
        id="${1:-}"
        shift || true
        client=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --client) need_value "$@"; client="$2"; shift 2 ;;
            --client=*) need_eq "$1"; client="${1#--client=}"; shift || true ;;
            *) echo "Arg inconnu: $1" >&2; exit 1 ;;
          esac
        done
        if [ -z "$id" ]; then
          echo "Usage: spark.sh tickets github-list <id|ref> [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        if [ -n "$client" ]; then
          api GET "/api/v1/tickets/${id}/github-issues?client=${client}"
        else
          api GET "/api/v1/tickets/${id}/github-issues"
        fi
        echo
        ;;
      github-create)
        id="${1:-}"
        shift || true
        client=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --client) need_value "$@"; client="$2"; shift 2 ;;
            --client=*) need_eq "$1"; client="${1#--client=}"; shift || true ;;
            *) echo "Arg inconnu: $1" >&2; exit 1 ;;
          esac
        done
        if [ -z "$id" ]; then
          echo "Usage: spark.sh tickets github-create <id|ref> [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        if [ -n "$client" ]; then
          api POST "/api/v1/tickets/${id}/github-issue?client=${client}" "{}"
        else
          api POST "/api/v1/tickets/${id}/github-issue" "{}"
        fi
        echo
        ;;
      github-link)
        id="${1:-}"
        ref="${2:-}"
        shift 2 || true
        client=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --client) need_value "$@"; client="$2"; shift 2 ;;
            --client=*) need_eq "$1"; client="${1#--client=}"; shift || true ;;
            *) echo "Arg inconnu: $1" >&2; exit 1 ;;
          esac
        done
        if [ -z "$id" ] || [ -z "$ref" ]; then
          echo "Usage: spark.sh tickets github-link <id|ref> '<#n|url>' [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        payload="$(
          REF="$ref" python3 - <<'PY'
import json, os
print(json.dumps({"reference": os.environ["REF"]}))
PY
        )"
        if [ -n "$client" ]; then
          api POST "/api/v1/tickets/${id}/github-issues?client=${client}" "$payload"
        else
          api POST "/api/v1/tickets/${id}/github-issues" "$payload"
        fi
        echo
        ;;
      github-unlink)
        id="${1:-}"
        num="${2:-}"
        shift 2 || true
        client=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --client) need_value "$@"; client="$2"; shift 2 ;;
            --client=*) need_eq "$1"; client="${1#--client=}"; shift || true ;;
            *) echo "Arg inconnu: $1" >&2; exit 1 ;;
          esac
        done
        if [ -z "$id" ] || [ -z "$num" ]; then
          echo "Usage: spark.sh tickets github-unlink <id|ref> <issueNumber> [--client slug]" >&2
          exit 1
        fi
        fill_client_if_empty "$client" || true
        client="$PARSED_CLIENT"
        # strip leading #
        num="${num#\#}"
        if [ -n "$client" ]; then
          api DELETE "/api/v1/tickets/${id}/github-issues?issueNumber=${num}&client=${client}"
        else
          api DELETE "/api/v1/tickets/${id}/github-issues?issueNumber=${num}"
        fi
        echo
        ;;
      *)
        echo "Usage: spark.sh tickets {list|search|create|get|patch|reject|comments|github-list|github-create|github-link|github-unlink} …" >&2
        exit 1
        ;;
    esac
    ;;
  links)
    sub="${1:-}"
    shift || true
    case "$sub" in
      list)
        parse_client_positional "${1:-}" || {
          echo "Usage: spark.sh links list [client] [--task <id|ref>] [--kind parent|blocks]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        q="client=${client}"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --task)
              need_value "$@"
              q="${q}&taskId=$2"
              shift 2
              ;;
            --kind)
              need_value "$@"
              q="${q}&kind=$2"
              shift 2
              ;;
            *)
              echo "Arg inconnu: $1" >&2
              exit 1
              ;;
          esac
        done
        api GET "/api/v1/task-links?${q}"
        echo
        ;;
      add)
        client="${1:-}"
        task="${2:-}"
        relation="${3:-}"
        other="${4:-}"
        if [ -z "$client" ] || [ -z "$task" ] || [ -z "$relation" ] || [ -z "$other" ]; then
          echo "Usage: spark.sh links add <client> <task> <relation> <other>" >&2
          echo "  relation: parent | child | blocks | blocked_by" >&2
          echo "  task/other: id cuid ou ref (#42 / 42)" >&2
          exit 1
        fi
        payload="$(
          CLIENT="$client" TASK="$task" REL="$relation" OTHER="$other" python3 - <<'PY'
import json, os
def coerce(v):
    s = str(v).strip().lstrip("#")
    if s.isdigit():
        return int(s)
    return v
print(json.dumps({
  "clientSlug": os.environ["CLIENT"],
  "taskId": coerce(os.environ["TASK"]),
  "relation": os.environ["REL"],
  "otherTaskId": coerce(os.environ["OTHER"]),
}))
PY
        )"
        api POST "/api/v1/task-links" "$payload"
        echo
        ;;
      delete)
        client="${1:-}"
        link_id="${2:-}"
        if [ -z "$client" ] || [ -z "$link_id" ]; then
          echo "Usage: spark.sh links delete <client> <linkId>" >&2
          exit 1
        fi
        api DELETE "/api/v1/task-links/${link_id}?client=${client}"
        echo
        ;;
      *)
        echo "Usage: spark.sh links {list|add|delete} …" >&2
        exit 1
        ;;
    esac
    ;;
  get)
    path="${1:-}"
    [ -n "$path" ] || {
      echo "Usage: spark.sh get <path>" >&2
      exit 1
    }
    api GET "$path"
    echo
    ;;
  post)
    path="${1:-}"
    json="${2:-}"
    [ -n "$path" ] && [ -n "$json" ] || {
      echo "Usage: spark.sh post <path> '<json>'" >&2
      exit 1
    }
    api POST "$path" "$json"
    echo
    ;;
  patch)
    path="${1:-}"
    json="${2:-}"
    [ -n "$path" ] && [ -n "$json" ] || {
      echo "Usage: spark.sh patch <path> '<json>'" >&2
      exit 1
    }
    api PATCH "$path" "$json"
    echo
    ;;
  delete)
    path="${1:-}"
    [ -n "$path" ] || {
      echo "Usage: spark.sh delete <path>" >&2
      exit 1
    }
    api DELETE "$path"
    echo
    ;;
  ideas)
    isub="${1:-}"
    shift || true
    case "$isub" in
      create)
        parse_client_positional "${1:-}" strict || {
          echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2
          client_missing_hint
          exit 1
        }
        client="$PARSED_CLIENT"
        [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
        title="${1:-}"
        shift || true
        case "$title" in
          --help | -h)
            echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2
            echo "  Titre seul. Défaut visible. --internal = masquée au client (staff Silex)." >&2
            exit 1
            ;;
          --*)
            echo "spark.sh ideas create: le titre ne peut pas commencer par -- (reçu: $title)" >&2
            exit 1
            ;;
          "")
            echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2
            exit 1
            ;;
        esac
        internal=0
        while [ $# -gt 0 ]; do
          case "$1" in
            --internal) internal=1; shift ;;
            --*)
              echo "spark.sh ideas create: option inconnue: $1" >&2
              exit 1
              ;;
            *)
              echo "spark.sh ideas create: argument inattendu: $1 (titre seul)" >&2
              exit 1
              ;;
          esac
        done
        payload="$(
          TITLE="$title" CLIENT="$client" INTERNAL="$internal" python3 - <<'PY'
import json, os
print(json.dumps({
  "clientSlug": os.environ["CLIENT"],
  "title": os.environ["TITLE"],
  "internal": os.environ.get("INTERNAL") == "1",
}))
PY
        )"
        api POST "/api/v1/ideas" "$payload"
        echo
        ;;
      *)
        echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2
        exit 1
        ;;
    esac
    ;;
  "" | help | -h | --help)
    cat <<'EOF'
spark.sh — API Spark (PAT spu_)

  spark.sh meta
  spark.sh meta-links
  spark.sh meta-projects
  spark.sh v1
  spark.sh tickets list [client]
  spark.sh tickets search [client] [options]
      --priority p0|p1|p2|p3  --status new|todo|doing|…
      --type bug|feature  --project <id|name>
      --onRoadmap  --internal  --assignee <id>
      --score <csv>  --unscored  --scoreMode manual|automatic
      --query "texte"  --limit N  --offset N
  spark.sh tickets actionable [client] [--json] [--include-internal]
  spark.sh tickets get <id|ref> [--client slug]
  spark.sh tickets comments list|add … [--client slug]
  spark.sh tickets create [client] <title> [body] [--public] [--project …] [--score n]
  spark.sh tickets patch <id|ref> '<json>' [--client slug]
  spark.sh tickets reject <id|ref> [--client slug] [--duplicate <ref>] [--comment "…"]
  spark.sh tickets github-* <id|ref> … [--client slug]
  spark.sh projects list|by-repo|create|patch|delete …
  spark.sh links|resources|journeys|orgchart|accueil|tasks …
  spark.sh ideas create [client] <title> [--internal]
  spark.sh config show|init|set …
  spark.sh get|post|patch|delete <path> [json]

Config secrets: SPARK_URL + SPARK_USER_API_KEY
  ou ~/.config/silex/spark.env | spark-user-api-key | BW gosilex/spark-user-api-key

Config client/project (pas de secret):
  ./config/spark.yml  |  ~/.config/silex/spark.yml  |  SPARK_CLIENT / SPARK_PROJECT
  spark.sh config init --client <slug> [--project X] [--global]
EOF
    ;;
  *)
    echo "Commande inconnue: $cmd — spark.sh help" >&2
    exit 1
    ;;
esac
