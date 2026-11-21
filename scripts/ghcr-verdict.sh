#!/usr/bin/env bash
# GHCR verdict cases. Run from repo root:
#   ./scripts/ghcr-verdict.sh            # the cases against the role
#   ./scripts/ghcr-verdict.sh --mutants  # also break each guard, expect a FAIL
#
# Runs roles/docker/tasks/ghcr-verdict.yml on localhost against recorded
# ghcr.io answers (tests/ghcr-verdict/). It decides whether one rejected token
# stops a converge, which no static check and no golden render can see.
#
# No errexit: each step is checked where it can actually fail.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

mutants=0
case ${1-} in
	--mutants) mutants=1 ;;
	'') ;;
	*)
		printf 'usage: %s [--mutants]\n' "$0" >&2
		exit 2
		;;
esac

red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

play='tests/ghcr-verdict/run.yml'
tasks='roles/docker/tasks/ghcr-verdict.yml'

bold '==> ghcr verdict'
if ! out=$(ansible-playbook "$play" 2>&1); then
	printf '%s\n' "$out"
	red '  FAIL ghcr verdict cases'
	exit 1
fi
green '  ok  ghcr verdict cases'
((mutants)) || exit 0

# Each mutant (tests/ghcr-verdict/mutants.txt) removes one guard. A mutant the
# cases do not catch is a guard no case pins, so the suite fails for it. Caught
# means a case's own check failed ("want"), not that the mutant broke the
# template.
list='tests/ghcr-verdict/mutants.txt'
[[ -r $list ]] || {
	red "  FAIL cannot read $list"
	exit 1
}
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0
ran=0
while IFS= read -r m; do
	[[ -z $m || $m == '#'* ]] && continue
	ran=$((ran + 1))
	from=${m%%@@*}
	to=${m#*@@}
	mutant="$tmp/ghcr-verdict.yml"
	if ! FROM=$from TO=$to python3 -c '
import os, sys
s = open(sys.argv[1]).read()
if os.environ["FROM"] not in s:
    sys.exit(1)
open(sys.argv[2], "w").write(s.replace(os.environ["FROM"], os.environ["TO"], 1))
' "$tasks" "$mutant"; then
		red "  FAIL mutation no longer applies: $from"
		fail=$((fail + 1))
		continue
	fi
	# </dev/null: the loop's stdin is the mutants file.
	out=$(ansible-playbook "$play" -e "ghcr_verdict_tasks=$mutant" \
		</dev/null 2>&1)
	rc=$?
	if ((rc != 0)) && [[ $out == *'(want '* ]]; then
		green "  ok  caught: $from"
	else
		red "  FAIL survived: $from"
		fail=$((fail + 1))
	fi
done <"$list"
# An emptied list must not read as every guard pinned.
if ((ran == 0)); then
	red "  FAIL no mutant in $list"
	exit 1
fi
((fail == 0))
