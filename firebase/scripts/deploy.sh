#!/bin/zsh
# Deploys the character relay: its two functions and the Firestore rules.
#
#   zsh firebase/scripts/deploy.sh <firebase-project-id>
#
# The project id is never committed (the repository is public). Give it as the argument,
# or keep it in firebase/.firebaserc, which is git-ignored (see .firebaserc.example).
# Lint and every test run first, and a failure stops the deploy.
set -euo pipefail

here=${0:A:h}
cd "$here/.."

project=${1:-}
if [[ -z "$project" && -f .firebaserc ]]; then
  project=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(".firebaserc","utf8")).projects.default ?? "")')
fi
if [[ -z "$project" || "$project" == "your-firebase-project-id" ]]; then
  echo "Give the Firebase project id: zsh firebase/scripts/deploy.sh <project-id>" >&2
  exit 2
fi

npm --prefix functions ci --no-audit --no-fund
npm --prefix functions run lint
npm --prefix functions test

# The key must already be in Secret Manager; this only checks that it is there, and never
# reads its value.
if ! npx --prefix functions firebase functions:secrets:describe OPENAI_API_KEY --project "$project" >/dev/null 2>&1; then
  echo "The OPENAI_API_KEY secret is not set in $project. Its owner sets it once:" >&2
  echo "  npx --prefix firebase/functions firebase functions:secrets:set OPENAI_API_KEY --project $project" >&2
  exit 1
fi

npx --prefix functions firebase deploy --only functions:characters,firestore:rules --project "$project"
