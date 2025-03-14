#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.7.0

show_help() {
  cat <<EOF
Usage: $(basename "$0") <options>

    -h, --help                    Display help
    -v, --version                 The chart-releaser version to use (default: $DEFAULT_CHART_RELEASER_VERSION)
        --config                  The path to the chart-releaser config file
    -d, --charts-dir              The charts directory (default: charts)
    -o, --owner                   The repo owner
    -r, --repo                    The repo name
        --pages-branch            The repo pages branch
    -n, --install-dir             The Path to install the cr tool
    -i, --install-only            Just install the cr tool
    -s, --skip-packaging          Skip the packaging step
        --skip-existing           Skip package upload if release exists
        --skip-upload             Skip package upload, just create the release
    -l, --mark-as-latest          Mark the created GitHub release as 'latest' (default: true)
        --packages-with-index     Upload chart packages directly into publishing branch
        --use-arm                 Use ARM64 binary (default: false)
        --release-name-template   Template for release names
EOF
}

main() {
  local version="$DEFAULT_CHART_RELEASER_VERSION"
  local config=
  local charts_dir=charts
  local owner=
  local repo=
  local install_dir=
  local install_only=
  local skip_packaging=
  local skip_existing=
  local skip_upload=
  local mark_as_latest=true
  local packages_with_index=false
  local pages_branch=
  local use_arm=false
  local release_name_template="v{{ .Version }}"

  parse_command_line "$@"

  : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

  local repo_root
  repo_root=$(git rev-parse --show-toplevel)
  pushd "$repo_root" >/dev/null

  if [[ -z "$skip_packaging" ]]; then
    echo 'Looking up latest tag...'
    local latest_tag
    latest_tag=$(lookup_latest_tag)

    echo "Discovering changed charts since '$latest_tag'..."
    local changed_charts=()
    readarray -t changed_charts <<<"$(lookup_changed_charts "$latest_tag")"

    if [[ -n "${changed_charts[*]}" ]]; then
      install_chart_releaser

      rm -rf .cr-release-packages .cr-index
      mkdir -p .cr-release-packages .cr-index

      for chart in "${changed_charts[@]}"; do
        [[ -d "$chart" ]] && package_chart "$chart"
      done

      release_charts
      update_index
    else
      echo "Nothing to do. No chart changes detected."
    fi
  else
    install_chart_releaser
    rm -rf .cr-index
    mkdir -p .cr-index
    release_charts
    update_index
  fi

  popd >/dev/null
}

parse_command_line() {
  while :; do
    case "${1:-}" in
    -h|--help) show_help; exit ;;
    --config) config="$2"; shift ;;
    -v|--version) version="$2"; shift ;;
    -d|--charts-dir) charts_dir="$2"; shift ;;
    -o|--owner) owner="$2"; shift ;;
    -r|--repo) repo="$2"; shift ;;
    --pages-branch) pages_branch="$2"; shift ;;
    -n|--install-dir) install_dir="$2"; shift ;;
    -i|--install-only) install_only=true ;;
    -s|--skip-packaging) skip_packaging=true ;;
    --skip-existing) skip_existing=true ;;
    --skip-upload) skip_upload=true ;;
    -l|--mark-as-latest) mark_as_latest="$2"; shift ;;
    --packages-with-index) packages_with_index=true ;;
    --use-arm) use_arm=true ;;
    --release-name-template) release_name_template="$2"; shift ;;
    *) break ;;
    esac
    shift
  done

  [[ -z "$owner" ]] && { echo "ERROR: '-o|--owner' is required."; exit 1; }
  [[ -z "$repo" ]] && { echo "ERROR: '-r|--repo' is required."; exit 1; }
}

release_charts() {
  local args=(-o "$owner" -r "$repo" -c "$(git rev-parse HEAD)")
  [[ -n "$config" ]] && args+=(--config "$config")
  [[ "$packages_with_index" = true ]] && args+=(--packages-with-index --push --skip-existing)
  [[ -n "$skip_existing" ]] && args+=(--skip-existing)
  [[ "$mark_as_latest" = false ]] && args+=(--make-release-latest=false)
  [[ -n "$pages_branch" ]] && args+=(--pages-branch "$pages_branch")
  [[ -n "$release_name_template" ]] && args+=(--release-name-template "$release_name_template")

  echo 'Releasing charts...'
  cr upload "${args[@]}"
}

update_index() {
  local args=(-o "$owner" -r "$repo" --push)
  [[ -n "$config" ]] && args+=(--config "$config")
  [[ "$packages_with_index" = true ]] && args+=(--packages-with-index --index-path .)
  [[ -n "$pages_branch" ]] && args+=(--pages-branch "$pages_branch")

  echo 'Updating charts repo index...'
  cr index "${args[@]}"
}

main "$@"

