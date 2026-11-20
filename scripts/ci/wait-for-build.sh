#!/bin/zsh
# Waits until this run's build job has handed over its build (the "products" artifact),
# and fails as soon as that job ends without one.
set -euo pipefail

api="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
step=$SECONDS
until gh api "$api/artifacts" --jq '.artifacts[].name' | grep -qx products; do
  build=$(gh api "$api/jobs" --jq '.jobs[] | select(.name | startswith("Build")) | .status')
  if [[ "$build" == completed ]]; then
    # It may have uploaded just after the look above.
    gh api "$api/artifacts" --jq '.artifacts[].name' | grep -qx products && break
    echo "The build job ended without a build" >&2
    exit 1
  fi
  sleep 15
done
echo "Waited $(( SECONDS - step ))s for the build"
