#!/usr/bin/env bash
# Keep the role control flow; replace only URI transport with recorded answers.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
for source in "${GHCR_PROBE_SOURCE:-roles/docker/tasks}"/*.yml; do
	sed 's/ansible.builtin.uri:/ghcr_recorded_uri:/' "$source" \
		>"$tmp/${source##*/}" || exit 1
done
export ANSIBLE_ACTION_PLUGINS="$PWD/tests/ghcr-verdict/action_plugins"
ansible-playbook -i tests/ghcr-verdict/inventory.yml \
	tests/ghcr-verdict/probe.yml \
	-e "ghcr_probe_tasks=$tmp/prove-ghcr.yml" "$@"
