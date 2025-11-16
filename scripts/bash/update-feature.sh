#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
TARGETS_VALUE=""
CLARIFY_ONLY=false
SKIP_CHECKLISTS=false
NO_BACKUP=false
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            ;;
        --targets)
            if [[ -n "${2:-}" ]]; then
                TARGETS_VALUE="$2"
                shift
            else
                echo "Error: --targets requires a value" >&2
                exit 1
            fi
            ;;
        --clarify-only)
            CLARIFY_ONLY=true
            ;;
        --skip-checklists)
            SKIP_CHECKLISTS=true
            ;;
        --no-backup)
            NO_BACKUP=true
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: update-feature.sh [options]

Options:
  --json               Output machine-readable JSON metadata
  --targets LIST       Comma/space separated list of targets: spec,plan,tasks,all (default: spec)
  --clarify-only       Indicate that this run is only gathering clarifications
  --skip-checklists    Signal that checklist regeneration should be skipped for this iteration
  --no-backup          Skip creation of spec.md/plan.md/tasks.md .bak snapshots
  --help, -h           Show this help message

Examples:
  ./update-feature.sh --json
  ./update-feature.sh --json --targets spec,plan
  ./update-feature.sh --targets tasks --no-backup
USAGE
            exit 0
            ;;
        *)
            ARGS+=("$1")
            ;;
    esac
    shift
done

if [[ -z "$TARGETS_VALUE" ]]; then
    TARGETS_VALUE="spec"
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval "$(get_feature_paths)"
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Feature directory not found: $FEATURE_DIR" >&2
    exit 1
fi

if [[ ! -f "$FEATURE_SPEC" ]]; then
    echo "ERROR: spec.md not found in $FEATURE_DIR" >&2
    echo "Run /speckit.specify first." >&2
    exit 1
fi

declare -A TARGET_MAP
TARGET_MAP[spec]="$FEATURE_SPEC"
TARGET_MAP[plan]="$IMPL_PLAN"
TARGET_MAP[tasks]="$TASKS"

VALID_TARGETS=(spec plan tasks)

contains_target() {
    local lookup="$1"
    for opt in "${VALID_TARGETS[@]}"; do
        if [[ "$opt" == "$lookup" ]]; then
            return 0
        fi
    done
    return 1
}

trim_string() {
    local var="$1"
    echo "$var" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

resolve_targets() {
    local raw="$1"
    local cleaned="${raw//,/ }"
    local token
    declare -A seen=()
    local resolved=()

    for token in $cleaned; do
        local trimmed="$(trim_string "$token")"
        [[ -z "$trimmed" ]] && continue
        local lowered="${trimmed,,}"
        if [[ "$lowered" == "all" ]]; then
            resolved=("spec" "plan" "tasks")
            printf '%s\n' "${resolved[@]}"
            return
        fi
        if contains_target "$lowered"; then
            if [[ -z "${seen[$lowered]:-}" ]]; then
                seen[$lowered]=1
                resolved+=("$lowered")
            fi
        else
            echo "ERROR: Unknown target '$trimmed'. Allowed: spec, plan, tasks, all." >&2
            exit 1
        fi
    done

    if [[ ${#resolved[@]} -eq 0 ]]; then
        resolved=("spec")
    fi

    printf '%s\n' "${resolved[@]}"
}

mapfile -t TARGETS < <(resolve_targets "$TARGETS_VALUE")

missing_files=()
for target in "${TARGETS[@]}"; do
    file="${TARGET_MAP[$target]}"
    if [[ ! -f "$file" ]]; then
        missing_files+=("$target")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    for miss in "${missing_files[@]}"; do
        case "$miss" in
            spec)
                echo "ERROR: spec.md missing; run /speckit.specify first." >&2
                ;;
            plan)
                echo "ERROR: plan.md missing; run /speckit.plan before targeting plan updates." >&2
                ;;
            tasks)
                echo "ERROR: tasks.md missing; run /speckit.tasks before targeting tasks." >&2
                ;;
        esac
    done
    exit 1
fi

BACKUPS=()
if ! $NO_BACKUP; then
    timestamp="$(date +%Y%m%d-%H%M%S)"
    for target in "${TARGETS[@]}"; do
        file="${TARGET_MAP[$target]}"
        if [[ -f "$file" ]]; then
            backup="${file}.bak.${timestamp}"
            cp "$file" "$backup"
            BACKUPS+=("$backup")
        fi
    done
fi

export SPECIFY_FEATURE="$CURRENT_BRANCH"

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

to_json_array() {
    if [[ $# -eq 0 ]]; then
        echo "[]"
        return
    fi
    local out="["
    local value
    for value in "$@"; do
        local esc="$(json_escape "$value")"
        out+="\"$esc\"," 
    done
    out="${out%,}]"
    echo "$out"
}

files_json="{"
for target in "${TARGETS[@]}"; do
    file="${TARGET_MAP[$target]}"
    esc_target="$(json_escape "$target")"
    esc_file="$(json_escape "$file")"
    files_json+="\"$esc_target\":\"$esc_file\"," 
done
files_json="${files_json%,}}"

backups_json="$(to_json_array "${BACKUPS[@]}")"
targets_json="$(to_json_array "${TARGETS[@]}")"

if $JSON_MODE; then
    printf '{"FEATURE_DIR":"%s","BRANCH":"%s","TARGETS":%s,"FILES":%s,"BACKUPS":%s,"CLARIFY_ONLY":%s,"SKIP_CHECKLISTS":%s}\n' \
        "$(json_escape "$FEATURE_DIR")" \
        "$(json_escape "$CURRENT_BRANCH")" \
        "$targets_json" \
        "$files_json" \
        "$backups_json" \
        "$([[ $CLARIFY_ONLY == true ]] && echo true || echo false)" \
        "$([[ $SKIP_CHECKLISTS == true ]] && echo true || echo false)"
else
    echo "Feature directory: $FEATURE_DIR"
    echo "Branch: $CURRENT_BRANCH"
    echo "Targets: ${TARGETS[*]}"
    echo "Clarify only: $CLARIFY_ONLY"
    echo "Skip checklists: $SKIP_CHECKLISTS"
    if $NO_BACKUP; then
        echo "Backups: skipped (--no-backup)"
    elif [[ ${#BACKUPS[@]} -eq 0 ]]; then
        echo "Backups: none created"
    else
        echo "Backups:"
        for backup in "${BACKUPS[@]}"; do
            echo "  - $backup"
        done
    fi
fi
