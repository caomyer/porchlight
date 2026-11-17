# The build number every signed build of a commit carries, sourced by the scripts that
# sign (deploy-ipad.sh, testflight.sh), so a cable install and a TestFlight build of the
# same commit report the same version.
#
# It is the commit's own time in UTC, as YYYYMMDD.HHMMSS (for example 20261116.230512):
#   - it only depends on the commit, so the same commit always builds the same number, on
#     any Mac, from any branch;
#   - a later commit has a later time, so every upload is higher than the last without
#     editing anything, which App Store Connect requires within a version;
#   - it reads as a date, so a device's build says when its code was written.
# A commit count would also be stable, but it goes backwards between branches (a branch
# with fewer commits than the one uploaded last), and these branches are uploaded from.
# Two components are fine for CFBundleVersion, which allows up to three integers.

# Prints the build number of HEAD, run from the repository.
porchlight_build_number() {
  TZ=UTC git log -1 --date=format-local:'%Y%m%d.%H%M%S' --format=%cd HEAD
}

# Prints the marketing version from project.yml, the one place it is set.
porchlight_marketing_version() {
  sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1
}
