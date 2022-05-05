#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

RELEASE_TYPE=${1:-}

echo_help() {
  cat << EOF
USAGE:
    ./scripts/publish <release_type>
ARGS:
    <release_type>
            A Semantic Versioning release type used to bump the version number. Either "patch", "minor", or "major".
EOF
}

create_github_release() {
  if which hub | grep -q "not found"; then
    create_github_release_fallback
    return
  fi

  # Get the last two releases. For example, `("v1.3.1" "v1.3.2")`
  local versions=($(git tag --sort version:refname | grep '^v' | tail -n 2))

  # If we didn't find exactly two previous version versions, give up
  if [ ${#versions[@]} -ne 2 ]; then
    create_github_release_fallback
    return
  fi

  local previous_version="${versions[0]}"
  local current_version="${versions[1]}"
  local commit_titles=$(git log --pretty=format:"- %s" "$previous_version".."$current_version"^)
  local release_notes="$(cat << EOF
$current_version
<!-- Please group the following commits into one of the sections below. -->
<!-- Remove empty sections when done. -->
$commit_titles
### New features
### Fixes
### Changed
EOF
)"

  echo "Creating GitHub release"
  echo ""
  echo -n "    "
  hub release create -em "$release_notes" "$current_version"
}

create_github_release_fallback() {
  cat << EOF
Remember to create a release on GitHub with a changelog notes:
    https://github.com/stripe/stripe-react-native/releases/new
EOF
}

# Show help if no arguments passed
if [ $# -eq 0 ]; then
  echo "Error! Missing release type argument"
  echo ""
  echo_help
  exit 1
fi

# Show help message if -h, --help, or help passed
case $1 in
  -h | --help | help)
    echo_help
    exit 0
    ;;
esac

# Validate passed release type
case $RELEASE_TYPE in
  patch | minor | major)
    ;;

  *)
    echo "Error! Invalid release type supplied"
    echo ""
    echo_help
    exit 1
    ;;
esac

# Make sure our working dir is the repo root directory
cd "$(git rev-parse --show-toplevel)"

echo "Fetching git remotes"
git fetch

GIT_STATUS=$(git status)

if ! grep -q 'On branch main' <<< "$GIT_STATUS"; then
  echo "Error! Must be on main branch to publish"
  exit 1
fi

if ! grep -q "Your branch is up to date with 'origin/main'." <<< "$GIT_STATUS"; then
  echo "Error! Must be up to date with origin/main to publish"
  exit 1
fi

if ! grep -q 'working tree clean' <<< "$GIT_STATUS"; then
  echo "Error! Cannot publish with dirty working tree"
  exit 1
fi

echo "Installing dependencies according to lockfile"
yarn -s install --frozen-lockfile

echo "Running tests"
yarn -s run unit-test:android

echo "Linting"
yarn -s run lint

echo "Bumping package.json $RELEASE_TYPE version and tagging commit"
yarn -s version --$RELEASE_TYPE

echo "Publishing release"
yarn -s --ignore-scripts publish --non-interactive --access=public

echo "Pushing git commit and tag"
git push --follow-tags

echo "Publish successful!"
echo ""

create_github_release
