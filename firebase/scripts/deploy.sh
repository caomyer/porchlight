#!/bin/zsh
# Deploys the character relay: its two functions and the Firestore rules.
#
#   zsh firebase/scripts/deploy.sh <firebase-project-id>
#
# The project id is never committed (the repository is public). Give it as the argument,
# or keep it in firebase/.firebaserc, which is git-ignored (see .firebaserc.example).
# Lint and every test run first, and a failure stops the deploy.
#
# It never asks a question: every parameter the functions take has its value in
# functions/.env, which is committed and holds nothing secret.
set -euo pipefail

here=${0:A:h}
source_dir=${here:h}

# Everything runs in a copy outside the repository. The repository may sit in a folder a
# file-syncing service watches (iCloud Drive), and thousands of installed package files
# there are slow to sync and come back as duplicates; nothing is installed or built in it.
work=$(mktemp -d -t porchlight-relay)
trap 'rm -rf "$work"' EXIT
rsync -a --exclude node_modules --exclude lib --exclude '*.log' --exclude '.secret*' "$source_dir/" "$work/"
cd "$work"

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

# The deploy's own output is kept and read: the CLI has been seen to print "Error:" and
# still leave a wrapper thinking all was well, so both its exit status and its words are
# checked. The words decide: a deploy that says "Error:" has failed whatever it exits with.
log=$(mktemp -t porchlight-relay-deploy)
set +e
npx --prefix functions firebase deploy --only functions:characters,firestore:rules --project "$project" --non-interactive 2>&1 | tee "$log"
deploy_status=${pipestatus[1]}
set -e

# The functions can go out and the CLI still end unhappy, because the project has no
# cleanup policy for old build images. That is one command to put right, and nothing
# needs deploying again; it is told apart from a deploy that failed.
if grep -qi "cleanup policy" "$log" && ! grep -q "Deploy complete" "$log"; then
  echo "DEPLOYED, BUT the project has no cleanup policy for old build images, so firebase did not report itself complete. Set it once:" >&2
  echo "  npx --prefix firebase/functions firebase functions:artifacts:setpolicy --project $project" >&2
  exit 3
fi
if (( deploy_status != 0 )); then
  echo "DEPLOY FAILED: firebase deploy exited with status $deploy_status. Nothing above should be trusted as deployed." >&2
  exit $deploy_status
fi
if grep -q "Error:" "$log"; then
  echo "DEPLOY FAILED: firebase deploy printed an error (above) although it exited with status 0." >&2
  exit 1
fi
rm -f "$log"
echo "DEPLOY SUCCEEDED: drawCharacter, characterAllowance and the Firestore rules are live in $project."
