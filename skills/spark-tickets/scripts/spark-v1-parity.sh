#!/usr/bin/env bash
# v1 parity command handlers sourced by spark.sh.

spark_parity_url_component() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

spark_parity_path_id() {
  case "$1" in
    .|..) echo "Identifiant invalide : segment de traversée." >&2; return 1 ;;
  esac
  spark_parity_url_component "$1"
}


spark_parity_tasks() {
  local sub="$1" id client reason duplicate patch payload
  shift || true
  case "$sub" in
    demote-preview)
      id="${1:-}"; shift || true
      parse_client_args "$@"; client="$PARSED_CLIENT"
      is_task_cuid "$id" || { echo "Usage: spark.sh tasks demote-preview <cuid> [clientSlug|--client slug]" >&2; return 1; }
      if [ -n "$client" ]; then
        api GET "/api/v1/tasks/${id}/demote?client=$(spark_parity_url_component "$client")"
      else
        api GET "/api/v1/tasks/${id}/demote"
      fi
      echo
      ;;
    demote)
      id="${1:-}"; shift || true
      [ "${1:-}" = "--apply" ] || { echo "Usage: spark.sh tasks demote <cuid> --apply [clientSlug|--client slug]" >&2; echo "  Lire d'abord: spark.sh tasks demote-preview <cuid> …" >&2; return 1; }
      shift
      parse_client_args "$@"; client="$PARSED_CLIENT"
      is_task_cuid "$id" || { echo "Usage: spark.sh tasks demote <cuid> --apply [clientSlug|--client slug]" >&2; return 1; }
      if [ -n "$client" ]; then
        api POST "/api/v1/tasks/${id}/demote?client=$(spark_parity_url_component "$client")" "{}"
      else
        api POST "/api/v1/tasks/${id}/demote" "{}"
      fi
      echo
      ;;
    reject)
      id="${1:-}"; shift || true
      client=""; reason=""; duplicate=""; patch=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --client) need_value "$@"; client="$2"; shift 2 ;;
          --client=*) need_eq "$1"; client="${1#--client=}"; shift ;;
          --reason|--comment) need_value "$@"; reason="$2"; shift 2 ;;
          --reason=*|--comment=*) need_eq "$1"; reason="${1#*=}"; shift ;;
          --duplicate|--duplicate-of-task-id) need_value "$@"; duplicate="$2"; shift 2 ;;
          --duplicate=*|--duplicate-of-task-id=*) need_eq "$1"; duplicate="${1#*=}"; shift ;;
          --patch) need_value "$@"; patch="$2"; shift 2 ;;
          --patch=*) need_eq "$1"; patch="${1#--patch=}"; shift ;;
          *) echo "Arg inconnu: $1" >&2; return 1 ;;
        esac
      done
      is_task_cuid "$id" || { echo "Usage: spark.sh tasks reject <cuid> [--reason text] [--duplicate <cuid|ref>] [--patch '<json>'] [--client slug]" >&2; return 1; }
      payload="$(REASON="$reason" DUPLICATE="$duplicate" PATCH="$patch" CLIENT="$client" python3 - <<'PY'
import json, os
body = {}
for source, target in (("REASON", "reason"), ("DUPLICATE", "duplicateOf"), ("CLIENT", "clientSlug")):
    value = (os.environ.get(source) or "").strip()
    if value:
        body[target] = value
raw = (os.environ.get("PATCH") or "").strip()
if raw:
    try:
        patch = json.loads(raw)
    except json.JSONDecodeError as error:
        raise SystemExit(f"--patch doit être un objet JSON: {error.msg}")
    if not isinstance(patch, dict):
        raise SystemExit("--patch doit être un objet JSON")
    body["patch"] = patch
print(json.dumps(body))
PY
)"
      if [ -n "$client" ]; then
        api POST "/api/v1/tasks/${id}/reject?client=$(spark_parity_url_component "$client")" "$payload"
      else
        api POST "/api/v1/tasks/${id}/reject" "$payload"
      fi
      echo
      ;;
    *) return 2 ;;
  esac
}

spark_parity_tickets() {
  local sub="$1" id client endpoint
  shift || true
  case "$sub" in
    delete|demote-preview|demote)
      id="${1:-}"; shift || true
      [ -n "$id" ] || { echo "Usage: spark.sh tickets ${sub} <id|ref> [--client slug]" >&2; return 1; }
      if [ "$sub" = "demote" ]; then
        [ "${1:-}" = "--apply" ] || { echo "Usage: spark.sh tickets demote <id|ref> --apply [--client slug]" >&2; echo "  Lire d'abord: spark.sh tickets demote-preview <id|ref> …" >&2; return 1; }
        shift
      fi
      client=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --client) need_value "$@"; client="$2"; shift 2 ;;
          --client=*) need_eq "$1"; client="${1#--client=}"; shift ;;
          *) echo "Arg inconnu: $1" >&2; return 1 ;;
        esac
      done
      fill_client_if_empty "$client" || true
      client="$PARSED_CLIENT"
      if [[ "$id" =~ ^#[0-9]+$ ]]; then id="${id#\#}"; fi
      id="$(spark_parity_path_id "$id")" || return $?
      endpoint="/api/v1/tickets/${id}"
      if [ "$sub" != "delete" ]; then endpoint="${endpoint}/demote"; fi
      if [ -n "$client" ]; then endpoint="${endpoint}?client=$(spark_parity_url_component "$client")"; fi
      case "$sub" in
        delete)
          api DELETE "$endpoint" || return $?
          ;;
        demote-preview)
          api GET "$endpoint" || return $?
          ;;
        demote)
          api POST "$endpoint" "{}" || return $?
          ;;
      esac
      echo
      ;;
    *) return 2 ;;
  esac
}

spark_parity_ideas() {
  local sub="${1:-}" id client json title internal endpoint arg
  shift || true
  case "$sub" in
    list)
      parse_client_positional "${1:-}" || { echo "Usage: spark.sh ideas list [clientSlug]" >&2; client_missing_hint; return 1; }
      client="$PARSED_CLIENT"; [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
      [ "$#" -eq 0 ] || { echo "Arg inconnu: $1" >&2; return 1; }
      api GET "/api/v1/ideas?client=$(spark_parity_url_component "$client")"
      echo
      ;;
    create)
      for arg in "$@"; do
        case "$arg" in
          -h|--help)
            echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]"
            return 0
            ;;
        esac
      done
      parse_client_positional "${1:-}" strict || { echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2; client_missing_hint; return 1; }
      client="$PARSED_CLIENT"; [ "${NEED_SHIFT:-0}" = 1 ] && shift || true
      title="${1:-}"; shift || true
      [ -n "$title" ] && [[ "$title" != --* ]] || { echo "Usage: spark.sh ideas create [clientSlug] <title> [--internal]" >&2; return 1; }
      internal=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --internal) internal=1; shift ;;
          *) echo "Arg inconnu: $1" >&2; return 1 ;;
        esac
      done
      json="$(TITLE="$title" CLIENT="$client" INTERNAL="$internal" python3 - <<'PY'
import json, os
print(json.dumps({"clientSlug": os.environ["CLIENT"], "title": os.environ["TITLE"], "internal": os.environ["INTERNAL"] == "1"}))
PY
)"
      api POST "/api/v1/ideas" "$json"
      echo
      ;;
    get|delete|promote)
      id="${1:-}"; shift || true
      parse_client_args "$@"; client="$PARSED_CLIENT"
      is_task_cuid "$id" || { echo "Usage: spark.sh ideas ${sub} <cuid> [clientSlug|--client slug]" >&2; return 1; }
      endpoint="/api/v1/ideas/${id}"
      if [ "$sub" = "promote" ]; then endpoint="${endpoint}/promote"; fi
      if [ -n "$client" ]; then endpoint="${endpoint}?client=$(spark_parity_url_component "$client")"; fi
      case "$sub" in
        get)
          api GET "$endpoint" || return $?
          ;;
        delete)
          api DELETE "$endpoint" || return $?
          ;;
        promote)
          api POST "$endpoint" "{}" || return $?
          ;;
      esac
      echo
      ;;
    patch)
      id="${1:-}"; shift || true; json=""; client=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --client) need_value "$@"; client="$2"; shift 2 ;;
          --client=*) need_eq "$1"; client="${1#--client=}"; shift ;;
          --*) echo "Arg inconnu: $1" >&2; return 1 ;;
          *) [ -z "$json" ] || { echo "Arg inconnu: $1" >&2; return 1; }; json="$1"; shift ;;
        esac
      done
      is_task_cuid "$id" && [ -n "$json" ] || { echo "Usage: spark.sh ideas patch <cuid> '<json>' [--client slug]" >&2; return 1; }
      if [ -n "$client" ]; then
        api PATCH "/api/v1/ideas/${id}?client=$(spark_parity_url_component "$client")" "$(json_with_client_slug "$json" "$client")"
      else
        api PATCH "/api/v1/ideas/${id}" "$json"
      fi
      echo
      ;;
    *) echo "Usage: spark.sh ideas {list|create|get|patch|delete|promote} …" >&2; return 1 ;;
  esac
}

spark_parity_comments() {
  local sub="${1:-}" client section target_type target_id body parent internal id json
  shift || true
  case "$sub" in
    list)
      client="${1:-}"; section="${2:-}"; shift 2 || true
      [ -n "$client" ] && [ -n "$section" ] || { echo "Usage: spark.sh comments list <clientSlug> <section> [--target-type type] [--target-id id]" >&2; return 1; }
      local query="client=$(spark_parity_url_component "$client")&section=$(spark_parity_url_component "$section")"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --target-type) need_value "$@"; query="${query}&targetType=$(spark_parity_url_component "$2")"; shift 2 ;;
          --target-id) need_value "$@"; query="${query}&targetId=$(spark_parity_url_component "$2")"; shift 2 ;;
          *) echo "Arg inconnu: $1" >&2; return 1 ;;
        esac
      done
      api GET "/api/v1/comments?${query}"
      echo
      ;;
    add)
      local -a comment_args=()
      local value
      body=""; parent=""; internal=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --parent) need_value "$@"; parent="$2"; shift 2 ;;
          --parent=*) need_eq "$1"; parent="${1#--parent=}"; shift ;;
          --internal) internal=1; shift ;;
          --*) echo "Option inconnue: $1" >&2; return 1 ;;
          *) comment_args+=("$1"); shift ;;
        esac
      done
      client="${comment_args[0]:-}"; section="${comment_args[1]:-}"; target_type="${comment_args[2]:-}"; target_id="${comment_args[3]:-}"
      for value in "${comment_args[@]:4}"; do body="${body:+$body }$value"; done
      [ -n "$client" ] && [ -n "$section" ] && [ -n "$target_type" ] && { [ "$target_type" = "page" ] || [ -n "$target_id" ]; } && [ -n "$body" ] || { echo "Usage: spark.sh comments add <clientSlug> <section> <targetType> <targetId> <body> [--parent N] [--internal]" >&2; return 1; }
      json="$(CLIENT="$client" SECTION="$section" TYPE="$target_type" TARGET="$target_id" BODY="$body" PARENT="$parent" INTERNAL="$internal" python3 - <<'PY'
import json, os
payload = {"clientSlug": os.environ["CLIENT"], "sectionKey": os.environ["SECTION"], "targetType": os.environ["TYPE"], "targetId": os.environ["TARGET"] or None, "body": os.environ["BODY"]}
if os.environ.get("PARENT"):
    payload["parentId"] = int(os.environ["PARENT"])
if os.environ.get("INTERNAL") == "1":
    payload["internal"] = True
print(json.dumps(payload))
PY
)"
      api POST "/api/v1/comments" "$json"
      echo
      ;;
    edit)
      id="${1:-}"; body="${2:-}"; shift 2 || true
      [ -n "$id" ] && [ -n "$body" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh comments edit <id> <body>" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      api PATCH "/api/v1/comments/${id}" "$(BODY="$body" python3 -c 'import json,os; print(json.dumps({"body": os.environ["BODY"]}))')"
      echo
      ;;
    delete)
      id="${1:-}"; shift || true
      [ -n "$id" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh comments delete <id>" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      api DELETE "/api/v1/comments/${id}"
      echo
      ;;
    *) echo "Usage: spark.sh comments {list|add|edit|delete} …" >&2; return 1 ;;
  esac
}

spark_parity_activity() {
  local client="${1:-}" id="${2:-}"
  shift 2 || true
  [ -n "$client" ] && is_task_cuid "$id" && [ "$#" -eq 0 ] || { echo "Usage: spark.sh activity <clientSlug> <taskCuid>" >&2; return 1; }
  api GET "/api/v1/task-activity?client=$(spark_parity_url_component "$client")&taskId=${id}"
  echo
}

spark_parity_users() {
  local sub="${1:-}" id json credential credential_field client role query
  credential_field="pass""word"
  shift || true
  case "$sub" in
    list)
      client=""; role=""; query=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --client) need_value "$@"; client="$2"; shift 2 ;;
          --client=*) need_eq "$1"; client="${1#--client=}"; shift ;;
          --role) need_value "$@"; role="$2"; shift 2 ;;
          --role=*) need_eq "$1"; role="${1#--role=}"; shift ;;
          --query|-q) need_value "$@"; query="$2"; shift 2 ;;
          --query=*|--q=*) need_eq "$1"; query="${1#*=}"; shift ;;
          *) echo "Arg inconnu: $1" >&2; return 1 ;;
        esac
      done
      local list_query=""
      [ -n "$client" ] && list_query="${list_query}${list_query:+&}client=$(spark_parity_url_component "$client")"
      [ -n "$role" ] && list_query="${list_query}${list_query:+&}role=$(spark_parity_url_component "$role")"
      [ -n "$query" ] && list_query="${list_query}${list_query:+&}q=$(spark_parity_url_component "$query")"
      api GET "/api/v1/users${list_query:+?${list_query}}"
      echo
      ;;
    create)
      json="${1:-}"; shift || true
      [ -n "$json" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh users create '<json>'" >&2; return 1; }
      api POST "/api/v1/users" "$json"
      echo
      ;;
    get)
      id="${1:-}"; shift || true
      [ -n "$id" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh users get <id>" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      api GET "/api/v1/users/${id}"
      echo
      ;;
    patch)
      id="${1:-}"; json="${2:-}"; shift 2 || true
      [ -n "$id" ] && [ -n "$json" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh users patch <id> '<json>'" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      api PATCH "/api/v1/users/${id}" "$json"
      echo
      ;;
    delete)
      id="${1:-}"; shift || true
      [ -n "$id" ] && [ "$#" -eq 0 ] || { echo "Usage: spark.sh users delete <id>" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      api DELETE "/api/v1/users/${id}"
      echo
      ;;
    *)
      [ "$sub" = "reset-${credential_field}" ] || { echo "Usage: spark.sh users {list|create|get|patch|delete|reset-${credential_field}} …" >&2; return 1; }
      id="${1:-}"; shift || true; credential=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--${credential_field}" ]; then
          need_value "$@"; credential="$2"; shift 2
        elif [ "${1%%=*}" = "--${credential_field}" ]; then
          need_eq "$1"; credential="${1#*=}"; shift
        else
          echo "Arg inconnu: $1" >&2; return 1
        fi
      done
      [ -n "$id" ] || { echo "Usage: spark.sh users reset-${credential_field} <id> [--${credential_field} value]" >&2; return 1; }
      id="$(spark_parity_path_id "$id")" || return $?
      json="$(VALUE="$credential" python3 -c 'import json,os; value=os.environ.get("VALUE") or ""; key="pass"+"word"; print(json.dumps({key: value}) if value else "{}")')"
      api POST "/api/v1/users/${id}/${credential_field}" "$json"
      echo
      ;;
  esac
}
