#!/usr/bin/env bash
# Keep the role control flow; replace only URI transport with recorded answers.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
for name in prove-ghcr.yml ghcr-repositories.yml \
	prove-ghcr-repository.yml ghcr-verdict.yml; do
	source="${GHCR_PROBE_SOURCE:-roles/docker/tasks}/$name"
	sed 's/ansible.builtin.uri:/ghcr_recorded_uri:/' "$source" \
		>"$tmp/${source##*/}" || exit 1
done
# Fail closed: a new network module, command, or include must never reach the
# test runner merely because the URI substitution did not recognize it.
python3 -c '
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
files = {path.name for path in root.glob("*.yml")}
actions = {"ghcr_recorded_uri"} | {
    "ansible.builtin." + name
    for name in ("assert", "set_fact", "debug", "fail", "include_tasks")
}
keywords = set("name vars when loop loop_control register no_log failed_when "
               "changed_when check_mode ignore_errors block rescue always".split())

def check(tasks):
    for task in tasks:
        unknown = task.keys() - keywords - actions
        if unknown:
            raise ValueError("unmocked action: " + ", ".join(sorted(unknown)))
        include = task.get("ansible.builtin.include_tasks")
        if include is not None and include not in files:
            raise ValueError("include outside guarded files: " + str(include))
        for key in ("block", "rescue", "always"):
            check(task.get(key, []))

try:
    for path in root.glob("*.yml"):
        check(yaml.safe_load(path.read_text()))
except (ValueError, TypeError, AttributeError, yaml.YAMLError) as error:
    sys.exit("Unsafe probe fixture: " + str(error))
' "$tmp" || exit 1
export ANSIBLE_ACTION_PLUGINS="$PWD/tests/ghcr-verdict/action_plugins"
ansible-playbook -i tests/ghcr-verdict/inventory.yml \
	tests/ghcr-verdict/probe.yml \
	-e "ghcr_probe_tasks=$tmp/prove-ghcr.yml" "$@"
