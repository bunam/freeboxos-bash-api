#!/bin/bash

set -u

FREEBOX_URL="http://mafreebox.freebox.fr"
_API_VERSION=
_API_BASE_URL=
_SESSION_TOKEN=

case "$OSTYPE" in
    darwin*) SED_REX='-E' ;;
    *) SED_REX='-r' ;;
esac

######## FUNCTIONS ########
function get_json_value_for_key {
    local value=$(echo "$1" | \
     sed -n $SED_REX 's/\\\//\//g;s/^ *\{//;s/\} *$//;s/.*"?'$2'"?:(.*)/\1/p')
    case "$value" in
        # new json { } block
        {*) echo "$value"
            ;;
        # string with double quotes
        \"*)
             echo "$value" | \
              sed $SED_REX 's/\\"/@ESCAPE_DOUBLE_QUOTE@/pg;s/^"([^"]*)".*/\1/;s/@ESCAPE_DOUBLE_QUOTE@/"/pg'
             ;;
        # all other use , as field separator
        *)
           echo "${value%%,*}"
           ;;
    esac
}

function _check_success {
    local value=$(get_json_value_for_key "$1" success)
    if [[ "$value" != true ]]; then
        echo "$(get_json_value_for_key "$answer" msg): $(get_json_value_for_key "$answer" error_code)" >&2
        exit 1
    fi
    return 0
}

function _check_freebox_api {
    local answer=$(curl -s "$FREEBOX_URL/api_version")
    _API_VERSION=$(get_json_value_for_key "$answer" api_version | sed 's/\..*//')
    _API_BASE_URL=$(get_json_value_for_key "$answer" api_base_url)
}

function call_freebox_api {
    local api_url="$1"
    local data="${2-}"
    local options=("")
    local url="$FREEBOX_URL"$( echo "/$_API_BASE_URL/v$_API_VERSION/$api_url" | sed 's@//@/@g')
    [[ -n "$_SESSION_TOKEN" ]] && options+=(-H "X-Fbx-App-Auth: $_SESSION_TOKEN")
    [[ -n "$data" ]] && options+=(-d "$data")
    answer=$(curl -s "$url" "${options[@]}")
    _check_success "$answer"
    echo "$answer"
}

function login_freebox {
    local APP_ID="$1"
    local APP_TOKEN="$2"
    local answer=

    _check_freebox_api
    answer=$(call_freebox_api 'login')
    _check_success "$answer"
    local challenge=$(get_json_value_for_key "$answer" challenge)
    local password=$(echo -n "$challenge" | openssl dgst -sha1 -hmac "$APP_TOKEN" | sed  's/^(stdin)= //')
    answer=$(call_freebox_api '/login/session/' "{\"app_id\":\"${APP_ID}\", \"password\":\"${password}\" }")
    _SESSION_TOKEN=$(get_json_value_for_key "$answer" session_token)
}
