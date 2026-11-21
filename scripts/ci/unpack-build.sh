#!/bin/zsh
# Checks the build a test job downloaded (products.tar, in this folder) against the size and
# SHA-256 the build job recorded, downloads it again up to twice when it does not match, and
# unpacks it into $PRODUCTS.
#
#   zsh scripts/ci/unpack-build.sh <sha256> <bytes>
#
# A download can arrive cut short and still be reported as a success: on November 21, 2026
# a smoke job failed in "Unpack the build" with "Truncated tar archive" while the other jobs
# of the same run unpacked the same build. That is the download's failure, not the tests',
# so it is retried here, and when it cannot be put right the job fails saying so, in words
# nobody can read as a red test run.
#
# Downloading again uses the GitHub CLI (`gh run download`), which needs GH_TOKEN and the
# workflow's `actions: read` permission; GITHUB_RUN_ID and GITHUB_REPOSITORY name the run.
set -euo pipefail

want_sha=$1
want_size=$2
tries=3

# Why the download is not the build, or nothing when it is.
problem() {
  [[ -f products.tar ]] || { print -r -- "there is no products.tar"; return }
  local size=$(stat -f%z products.tar)
  [[ "$size" == "$want_size" ]] || { print -r -- "it is $size bytes and the build is $want_size"; return }
  local sha=$(shasum -a 256 products.tar | cut -d' ' -f1)
  [[ "$sha" == "$want_sha" ]] || { print -r -- "its checksum is $sha and the build's is $want_sha"; return }
}

attempt=1
while true; do
  why=$(problem)
  [[ -z "$why" ]] && break
  if (( attempt >= tries )); then
    echo "::error::The build's download was corrupted $tries times in a row ($why). This is the download failing, not a test: run the job again."
    exit 1
  fi
  echo "The build's download was corrupted ($why): downloading it again, try $(( attempt + 1 )) of $tries"
  rm -f products.tar
  gh run download "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" --name products --dir . || echo "The download itself failed"
  attempt=$(( attempt + 1 ))
done
echo "The build's download is whole: $want_size bytes, sha256 $want_sha"

mkdir -p "$PRODUCTS"
if ! tar -xf products.tar -C "$PRODUCTS"; then
  echo "::error::The build was downloaded whole (its size and checksum match) and could not be unpacked. This is this Mac, most likely its disk, not a test: run the job again."
  df -h "$PRODUCTS" || true
  exit 1
fi
rm products.tar
