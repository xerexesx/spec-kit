#!/usr/bin/env bash

set -euo pipefail

JSON_MODE=false
CUSTOM_SLUG=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            ;;
        --slug)
            if [[ -n "${2:-}" ]]; then
                CUSTOM_SLUG="$2"
                shift
            else
                echo "Error: --slug requires a value" >&2
                exit 1
            fi
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: create-tiny-spec.sh [options] [description]

Options:
  --json            Output machine-readable JSON
  --slug VALUE      Custom slug for the tiny spec file (default derives from description)
  --help, -h        Show this message

Examples:
  ./create-tiny-spec.sh --json "Fix typo in onboarding flow"
  ./create-tiny-spec.sh --slug hotfix-webhook
USAGE
            exit 0
            ;;
        *)
            ARGS+=("$1")
            ;;
    esac
    shift
done

DESCRIPTION="${ARGS[*]}"

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

eval "$(get_feature_paths)"
check_feature_branch "$CURRENT_BRANCH" "$HAS_GIT" || exit 1

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: Feature directory not found: $FEATURE_DIR" >&2
    exit 1
fi

slugify() {
    local input="$1"
    local value
    value="$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    echo "$value"
}

slug="$(slugify "$CUSTOM_SLUG")"
if [[ -z "$slug" ]]; then
    slug="$(slugify "$DESCRIPTION")"
fi
if [[ -z "$slug" ]]; then
    slug="tiny-$(date +%Y%m%d-%H%M%S)"
fi

TINY_DIR="$FEATURE_DIR/tiny-specs"
mkdir -p "$TINY_DIR"

candidate="$TINY_DIR/$slug.md"
counter=2
while [[ -e "$candidate" ]]; do
    candidate="$TINY_DIR/${slug}-${counter}.md"
    counter=$((counter + 1))

done

TEMPLATE="$REPO_ROOT/.specify/templates/tiny-spec-template.md"
if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$candidate"
else
    cat <<'PLACEHOLDER' > "$candidate"
# Tiny Spec

Describe the quick fix or enhancement here.
PLACEHOLDER
fi

export SPECIFY_FEATURE="$CURRENT_BRANCH"

if $JSON_MODE; then
    printf '{"TINY_SPEC":"%s","SLUG":"%s","FEATURE_DIR":"%s","BRANCH":"%s"}\n' \
        "$candidate" \
        "$slug" \
        "$FEATURE_DIR" \
        "$CURRENT_BRANCH"
else
    echo "Tiny spec file: $candidate"
    echo "Slug: $slug"
    echo "Feature directory: $FEATURE_DIR"
    echo "Branch: $CURRENT_BRANCH"
fi
