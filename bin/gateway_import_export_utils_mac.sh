#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "${SCRIPT_DIR}/common.lib"

url="http://localhost:5555"
username="Administrator"
password="manage"
api=""
shldDoImport=""

usage() {
  echo "Usage: $0 --import|--export --api_name <name> [--apigateway_url <url>] [--username <user>] [--password <pass>]"
  echo ""
  echo "args:"
  echo "--import (or) --export   *To import or export from the flat file"
  echo "--api_name               *The API project name"
  echo "--apigateway_url          APIGateway url. Default: http://localhost:5555"
  echo "--username                Default: Administrator"
  echo "--password                Default: manage"
  exit 1
}

parseArgs() {
  while (( $# >= 1 )); do
    local arg="$1"
    shift
    case "$arg" in
      --apigateway_url)
        [[ $# -ge 1 ]] || usage
        url="$1"; shift
        ;;
      --api_name)
        [[ $# -ge 1 ]] || usage
        api="$1"; shift
        ;;
      --username)
        [[ $# -ge 1 ]] || usage
        username="$1"; shift
        ;;
      --password)
        [[ $# -ge 1 ]] || usage
        password="$1"; shift
        ;;
      --import)
        shldDoImport="true"
        ;;
      --export)
        shldDoImport="false"
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Unknown argument: $arg"
        usage
        ;;
    esac
  done
}

main() {
  parseArgs "$@"

  if [[ -z "$api" ]]; then
    echo "API name is missing"
    usage
  fi

  if [[ -z "$shldDoImport" ]]; then
    echo "Missing what operation to do (--import or --export)"
    usage
  fi

  if [[ "$shldDoImport" == "true" ]]; then
    echo "Importing the API: $api"
    import_api "$api" "$url" "$username" "$password"
  else
    echo "Exporting the API: $api"
    export_api "$api" "$url" "$username" "$password"
  fi
}

main "$@"
