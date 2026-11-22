#!/usr/bin/env bash
# Inject disabled network tasks: the guard must refuse even unreachable calls,
# before Ansible gets a chance to evaluate them or contact any endpoint.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
for action in get_url ansible.builtin.get_url uri ansible.builtin.command \
	ansible.builtin.shell community.general.unmocked_network_action; do
	cp roles/docker/tasks/*.yml "$tmp/" || exit 1
	printf '\n- name: Forbidden transport\n  %s: {}\n  when: false\n' \
		"$action" >>"$tmp/prove-ghcr.yml"
	if out=$(GHCR_PROBE_SOURCE="$tmp" ./scripts/ghcr-probe.sh 2>&1); then
		printf 'FAIL probe guard accepted %s\n' "$action" >&2
		exit 1
	fi
	if [[ $out != *"Unsafe probe fixture: unmocked action: $action"* ]]; then
		printf '%s\nFAIL unexpected probe guard error\n' "$out" >&2
		exit 1
	fi
done
printf 'ok  probe guard refused all 6 unmocked transports\n'
