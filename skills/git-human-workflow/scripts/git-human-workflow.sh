#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: git-human-workflow.sh <command> [arguments...]

Commands:
  check                 Verify Git identity and the active GitHub CLI account.
  sanitize-text         Remove whole lines containing prohibited public markers from stdin.
  install-repo-hooks    Install pre-commit and commit-msg guards in this repository.
  git <git arguments>   Run a checked Git command; commits use the resolved identity.
  gh <gh arguments>     Run a checked GitHub CLI command.
USAGE
}

die() {
  printf 'git-human-workflow: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 'run this command from inside a Git repository'
}

first_line() {
  sed -n '1p'
}

contains_marker() {
  local value=${1,,}
  [[ $value =~ (^|[^[:alnum:]])ai([^[:alnum:]]|$) ]] ||
    [[ $value == *codex* ]] ||
    [[ $value == *openai* ]] ||
    [[ $value == *chatgpt* ]] ||
    [[ $value == *copilot* ]] ||
    [[ $value =~ artificial[[:space:]-]+intelligence ]] ||
    [[ $value =~ co-authored-by:.*(codex|openai|chatgpt|copilot) ]]
}

require_clean_text() {
  local value=$1
  local label=$2
  if contains_marker "$value"; then
    die "$label contains a prohibited public marker"
  fi
  return 0
}

scan_file() {
  local path=$1
  local label=${2:-file}
  [[ -f $path ]] || die "$label does not exist: $path"

  local line line_number=0
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    if contains_marker "$line"; then
      die "$label contains a prohibited public marker at line $line_number"
    fi
  done <"$path"
}

read_stdin_to_file() {
  local target=$1
  cat >"$target"
  scan_file "$target" 'stdin payload'
}

git_config_value() {
  local scope=$1
  local key=$2
  case "$scope" in
    local)
      require_repo
      git config --local --get "$key" 2>/dev/null | first_line
      ;;
    global)
      git config --global --get "$key" 2>/dev/null | first_line
      ;;
    *)
      return 1
      ;;
  esac
}

valid_identity_value() {
  [[ -n ${1:-} ]] && ! contains_marker "$1"
}

resolve_git_value() {
  local key=$1
  local scope value
  for scope in local global; do
    value=$(git_config_value "$scope" "$key" || true)
    if valid_identity_value "$value"; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

gh_user_field() {
  local query=$1
  command_exists gh || return 1
  gh api user --jq "$query" 2>/dev/null | first_line
}

resolve_gh_name() {
  local value
  value=$(gh_user_field '.name // .login // empty' || true)
  valid_identity_value "$value" || return 1
  printf '%s\n' "$value"
}

resolve_gh_email() {
  local value login user_id
  value=$(gh_user_field '.email // empty' || true)
  if valid_identity_value "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  value=$(gh api user/emails --jq '.[] | select(.primary == true and .verified == true) | .email' 2>/dev/null | first_line || true)
  if valid_identity_value "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  login=$(gh_user_field '.login // empty' || true)
  user_id=$(gh_user_field '.id // empty' || true)
  if valid_identity_value "$login" && [[ -n $user_id ]]; then
    printf '%s+%s@users.noreply.github.com\n' "$user_id" "$login"
    return 0
  fi
  return 1
}

resolve_identity() {
  AUTHOR_NAME=$(resolve_git_value user.name || resolve_gh_name || true)
  AUTHOR_EMAIL=$(resolve_git_value user.email || resolve_gh_email || true)
  valid_identity_value "$AUTHOR_NAME" || die 'could not resolve a valid author name'
  valid_identity_value "$AUTHOR_EMAIL" || die 'could not resolve a valid author email'
}

ensure_local_identity() {
  require_repo
  resolve_identity
  git config user.name "$AUTHOR_NAME"
  git config user.email "$AUTHOR_EMAIL"
}

check_git_identity() {
  require_repo
  resolve_identity
  local value
  while IFS= read -r value; do
    valid_identity_value "$value" || die 'effective Git identity contains a prohibited marker'
  done < <(git var GIT_AUTHOR_IDENT; git var GIT_COMMITTER_IDENT)
  printf 'Git identity: %s <%s>\n' "$AUTHOR_NAME" "$AUTHOR_EMAIL"
}

check_gh_account() {
  command_exists gh || die 'GitHub CLI is required for hosted operations'
  local auth_help login
  auth_help=$(gh auth status --help 2>&1 || true)
  if [[ $auth_help == *--active* ]]; then
    gh auth status --active --hostname github.com >/dev/null 2>&1 || die 'no active GitHub CLI account for github.com'
  else
    gh auth status --hostname github.com >/dev/null 2>&1 || die 'no active GitHub CLI account for github.com'
  fi
  login=$(gh_user_field '.login // empty' || true)
  valid_identity_value "$login" || die 'active GitHub CLI account is missing or contains a prohibited marker'
  printf 'GitHub account: %s\n' "$login"
}

reject_author_argument() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --author|--author=*) die 'do not pass --author; the resolved identity is enforced' ;;
    esac
  done
}

reject_uninspectable_git_flags() {
  local subcommand=$1
  shift
  [[ $subcommand == commit ]] || return 0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --edit|--no-edit|-e|--reuse-message=*|--reedit-message=*|--fixup=*|--squash=*|-C|-c)
        die "cannot inspect public text supplied by $arg; pass explicit checked text instead"
        ;;
    esac
  done
}

scan_git_file_arguments() {
  local args=("$@")
  local index arg path
  for ((index = 0; index < ${#args[@]}; index++)); do
    arg=${args[index]}
    case "$arg" in
      -F|--file|--message-file)
        index=$((index + 1))
        path=${args[index]:-}
        [[ -n $path && $path != '-' ]] || die "$arg requires a readable message file"
        scan_file "$path" 'Git message file'
        ;;
      -F=*|--file=*|--message-file=*)
        path=${arg#*=}
        [[ $path != '-' ]] || die "$arg requires a readable message file"
        scan_file "$path" 'Git message file'
        ;;
    esac
  done
}

run_git() {
  shift
  [[ $# -gt 0 ]] || die 'git requires a Git command'
  require_repo
  local arg
  for arg in "$@"; do
    require_clean_text "$arg" 'Git argument'
  done
  scan_git_file_arguments "$@"

  local subcommand=$1
  reject_uninspectable_git_flags "$subcommand" "$@"
  if [[ $subcommand == commit ]]; then
    reject_author_argument "$@"
    resolve_identity
    GIT_AUTHOR_NAME=$AUTHOR_NAME \
      GIT_AUTHOR_EMAIL=$AUTHOR_EMAIL \
      GIT_COMMITTER_NAME=$AUTHOR_NAME \
      GIT_COMMITTER_EMAIL=$AUTHOR_EMAIL \
      git "$@" --author="$AUTHOR_NAME <$AUTHOR_EMAIL>"
    return
  fi

  git "$@"
}

TEMP_INPUT=''
cleanup_temp_input() {
  if [[ -n $TEMP_INPUT ]]; then
    rm -f -- "$TEMP_INPUT"
  fi
  return 0
}

prepare_gh_arguments() {
  local args=("$@")
  GH_ARGS=()
  local index=0 arg value
  while ((index < ${#args[@]})); do
    arg=${args[index]}
    require_clean_text "$arg" 'GitHub CLI argument'
    case "$arg" in
      --web|--editor|-e|--fill|--fill-first|--fill-verbose|--generate-notes)
        die "cannot inspect public text supplied by $arg; pass explicit checked text instead"
        ;;
      --input|--body-file|--notes-file|--message-file|--file)
        index=$((index + 1))
        value=${args[index]:-}
        [[ -n $value ]] || die "$arg requires a value"
        GH_ARGS+=("$arg")
        if [[ $value == '-' ]]; then
          [[ -z $TEMP_INPUT ]] || die 'only one stdin payload is supported'
          TEMP_INPUT=$(mktemp)
          read_stdin_to_file "$TEMP_INPUT"
          GH_ARGS+=("$TEMP_INPUT")
        else
          scan_file "$value" "GitHub CLI input for $arg"
          GH_ARGS+=("$value")
        fi
        ;;
      --input=*|--body-file=*|--notes-file=*|--message-file=*|--file=*)
        value=${arg#*=}
        [[ $value != '-' ]] || die "$arg must use the separate flag form for stdin"
        scan_file "$value" "GitHub CLI input for ${arg%%=*}"
        GH_ARGS+=("$arg")
        ;;
      --template)
        index=$((index + 1))
        value=${args[index]:-}
        [[ -f $value ]] || die 'remote templates are not inspectable; pass an explicit checked body instead'
        scan_file "$value" 'GitHub CLI template'
        GH_ARGS+=("$arg" "$value")
        ;;
      --template=*)
        value=${arg#*=}
        [[ -f $value ]] || die 'remote templates are not inspectable; pass an explicit checked body instead'
        scan_file "$value" 'GitHub CLI template'
        GH_ARGS+=("$arg")
        ;;
      *)
        GH_ARGS+=("$arg")
        ;;
    esac
    index=$((index + 1))
  done
}

require_noninteractive_content() {
  local primary=${1:-}
  local secondary=${2:-}
  local arg has_title=0 has_body=0
  for arg in "${GH_ARGS[@]}"; do
    case "$arg" in
      --title|--title=*|-t|--title=*) has_title=1 ;;
      --body|--body=*|--body-file|--body-file=*|--notes|--notes=*|--notes-file|--notes-file=*) has_body=1 ;;
    esac
  done
  case "$primary:$secondary" in
    issue:create|pr:create)
      [[ $has_title -eq 1 && $has_body -eq 1 ]] || die "$primary $secondary requires explicit checked title and body"
      ;;
    issue:comment|pr:comment|pr:review)
      [[ $has_body -eq 1 ]] || die "$primary $secondary requires an explicit checked body"
      ;;
    release:create)
      [[ $has_body -eq 1 ]] || die 'release create requires explicit checked notes'
      ;;
  esac
}

run_gh() {
  shift
  [[ $# -gt 0 ]] || die 'gh requires a GitHub CLI command'
  check_gh_account >/dev/null
  trap cleanup_temp_input RETURN
  prepare_gh_arguments "$@"
  require_noninteractive_content "${GH_ARGS[0]:-}" "${GH_ARGS[1]:-}"
  gh "${GH_ARGS[@]}"
}

sanitize_text() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    contains_marker "$line" || printf '%s\n' "$line"
  done
}

script_path() {
  local source=${BASH_SOURCE[0]}
  cd "$(dirname "$source")" && printf '%s/%s\n' "$PWD" "$(basename "$source")"
}

write_hook() {
  local hook_path=$1
  local helper_path=$2
  local command_name=$3
  local previous_hook=${4:-}
  mkdir -p "$(dirname "$hook_path")"
  cat >"$hook_path" <<HOOK
#!/usr/bin/env bash
set -euo pipefail
# git-human-workflow managed hook
HELPER=$(printf '%q' "$helper_path")
PREVIOUS_HOOK=$(printf '%q' "$previous_hook")
"\$HELPER" $command_name "\$@"
if [[ -n "\$PREVIOUS_HOOK" && -x "\$PREVIOUS_HOOK" ]]; then
  exec "\$PREVIOUS_HOOK" "\$@"
fi
HOOK
  chmod +x "$hook_path"
}

install_hook() {
  local name=$1 command_name=$2
  local git_dir hook_path backup_path helper_path timestamp
  git_dir=$(git rev-parse --git-dir)
  hook_path=$(git rev-parse --git-path "hooks/$name")
  helper_path=$(script_path)
  backup_path=''
  if [[ -f $hook_path ]] && ! grep -q 'git-human-workflow managed hook' "$hook_path"; then
    timestamp=$(date -u +%Y%m%d%H%M%S)
    backup_path="$git_dir/hooks/$name.git-human-workflow-backup.$timestamp"
    mv "$hook_path" "$backup_path"
  fi
  write_hook "$hook_path" "$helper_path" "$command_name" "$backup_path"
}

install_repo_hooks() {
  require_repo
  ensure_local_identity
  install_hook pre-commit hook-pre-commit
  install_hook commit-msg hook-commit-msg
  printf 'installed repository identity and message guards\n'
}

hook_pre_commit() {
  check_git_identity >/dev/null
}

hook_commit_msg() {
  [[ $# -eq 1 ]] || die 'commit-msg hook requires the commit message path'
  scan_file "$1" 'commit message'
}

command_name=${1:-help}
case "$command_name" in
  help|-h|--help)
    usage
    ;;
  check)
    check_git_identity
    check_gh_account
    ;;
  sanitize-text)
    sanitize_text
    ;;
  install-repo-hooks)
    install_repo_hooks
    ;;
  hook-pre-commit)
    hook_pre_commit
    ;;
  hook-commit-msg)
    shift
    hook_commit_msg "$@"
    ;;
  git)
    run_git "$@"
    ;;
  gh)
    run_gh "$@"
    ;;
  *)
    usage >&2
    die "unknown command: $command_name"
    ;;
esac
