#!/bin/sh
# Test build: zip of SkillRoute/ with the version stamped "<next>-dev.<changes since the
# last release tag>", so each test build has its own number (in the zip name, the TOC
# and /sr check). The repository's TOC keeps the plain release version.
# Usage: tools/devzip.sh <output dir>
set -e
out=$(cd "${1:?output dir}" && pwd)
cd "$(dirname "$0")/.."
git fetch -q --tags origin 2>/dev/null || true
ver=$(sed -n 's/^## Version: *//p' SkillRoute/SkillRoute.toc | tr -d '\r')
last=$(git describe --tags --abbrev=0 2>/dev/null || true)
n=$(git rev-list --count ${last:+$last..}HEAD)
dev="$ver-dev.$n"
tmp=$(mktemp -d)
cp -r SkillRoute "$tmp/"
sed -i "s/^## Version: .*/## Version: $dev/" "$tmp/SkillRoute/SkillRoute.toc"
rm -f "$out/SkillRoute-$dev.zip"
(cd "$tmp" && zip -qr "$out/SkillRoute-$dev.zip" SkillRoute)
rm -rf "$tmp"
echo "$out/SkillRoute-$dev.zip"
