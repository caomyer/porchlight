#!/bin/zsh
# Checks scripts/ci/unpack-build.sh without GitHub: a whole download unpacks; a download cut
# short is fetched again and then unpacks; one that stays corrupted fails saying the
# download was corrupted. `gh` is a stand-in on the PATH. Runs anywhere in a second.
#
#   zsh scripts/ci/check-unpack-build.sh
set -euo pipefail
script="${0:A:h}/unpack-build.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A small build, and what the build job would record about it.
mkdir -p "$work/build/Debug" "$work/bin"
print -r -- "the app" > "$work/build/Debug/App.o"
head -c 200000 /dev/urandom > "$work/build/Debug/SwiftSyntax.o"
tar -cf "$work/good.tar" -C "$work/build" .
sha=$(shasum -a 256 "$work/good.tar" | cut -d' ' -f1)
size=$(stat -f%z "$work/good.tar")

# The stand-in `gh run download`: gives whatever $work/served.tar is, and counts its calls.
cat > "$work/bin/gh" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "$GH_CALLS"
cp "$GH_SERVES" products.tar
EOF
chmod +x "$work/bin/gh"
export GH_CALLS="$work/calls" GH_SERVES="$work/served.tar" GITHUB_RUN_ID=1 GITHUB_REPOSITORY=someone/something
PATH="$work/bin:$PATH"

failures=0
expect() {
  if [[ "$2" == "$3" ]]; then echo "ok: $1"; else echo "FAILED: $1 (expected $3, got $2)"; failures=$(( failures + 1 )); fi
}
run() {
  rm -rf "$work/job" "$GH_CALLS"
  mkdir -p "$work/job"
  export PRODUCTS="$work/job/products"
  ( cd "$work/job" && cp "$1" products.tar && zsh "$script" "$sha" "$size" ) > "$work/out" 2>&1 && print 0 || print $?
}
calls() { [[ -f "$GH_CALLS" ]] && wc -l < "$GH_CALLS" | tr -d ' ' || print 0 }

# 1. A whole download.
expect "a whole download unpacks" "$(run "$work/good.tar")" 0
expect "without downloading again" "$(calls)" 0
expect "and the build is there" "$(cat "$work/job/products/Debug/App.o")" "the app"

# 2. A download cut short, as on November 21: fetched again, then unpacked.
head -c 100000 "$work/good.tar" > "$work/short.tar"
cp "$work/good.tar" "$work/served.tar"
expect "a download cut short is put right" "$(run "$work/short.tar")" 0
expect "by downloading once more" "$(calls)" 1
expect "and the whole build is there" "$(stat -f%z "$work/job/products/Debug/SwiftSyntax.o")" 200000

# 3. Same size, wrong bytes: the checksum catches what the size cannot.
cp "$work/good.tar" "$work/flipped.tar"
printf 'X' | dd of="$work/flipped.tar" bs=1 seek=150000 conv=notrunc 2>/dev/null
expect "a download of the right size and wrong bytes is put right" "$(run "$work/flipped.tar")" 0
expect "by downloading once more" "$(calls)" 1

# 4. A download that stays corrupted: the job fails, saying it is the download.
cp "$work/short.tar" "$work/served.tar"
expect "a download corrupted every time fails the job" "$(run "$work/short.tar")" 1
expect "after two more downloads" "$(calls)" 2
grep -q "The build's download was corrupted 3 times in a row" "$work/out" && grep -q "not a test" "$work/out" \
  && echo "ok: and says the download was corrupted, not a test" \
  || { echo "FAILED: the message: $(cat "$work/out")"; failures=$(( failures + 1 )); }
expect "and nothing is unpacked" "$([[ -e "$work/job/products" ]] && print yes || print no)" no

(( failures == 0 )) || { echo "$failures checks of the build's download failed"; exit 1; }
echo "The build's download is checked and retried as it should be."
