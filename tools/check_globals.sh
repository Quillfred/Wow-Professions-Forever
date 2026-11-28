#!/bin/sh
# Fails if an addon file writes a global it shouldn't (usually a local used before its
# declaration). Allowed: the saved variables, the slash command and the data table.
set -e
cd "$(dirname "$0")/.."
bad=$(for f in SkillRoute/*.lua; do
  luac5.1 -p -l "$f" | grep -o 'SETGLOBAL.*' | sed 's/.*; //' | sed "s|^|$f: |"
done | grep -v -E ': (SkillRouteDB|SkillRouteData|SkillRouteMapPinMixin|SLASH_SKILLROUTE[0-9])$' || true)
if [ -n "$bad" ]; then echo "Unexpected global writes:"; echo "$bad"; exit 1; fi
# reading a one- or two-letter global is almost always a leftover local (e.g. "d")
short=$(for f in SkillRoute/*.lua; do
  luac5.1 -p -l "$f" | grep -o 'GETGLOBAL.*' | sed 's/.*; //' | grep -E '^[A-Za-z_]{1,2}$' | sed "s|^|$f: |"
done | grep -v -E ': (_G)$' || true)
if [ -n "$short" ]; then echo "Suspicious global reads:"; echo "$short"; exit 1; fi
echo "globals OK"
