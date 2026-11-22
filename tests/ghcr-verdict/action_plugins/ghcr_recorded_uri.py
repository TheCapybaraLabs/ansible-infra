"""Recorded registry answers; never opens a network connection."""

from urllib.parse import parse_qs, urlparse

from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        task_vars = task_vars or {}
        url = self._task.args["url"]
        parsed = urlparse(url)
        scope = parse_qs(parsed.query).get("scope", [""])[0]
        repository = scope.removeprefix("repository:").removesuffix(":pull")
        if parsed.path.startswith("/v2/"):
            repository = parsed.path[4:].removesuffix("/tags/list")
        requests = task_vars.get("ansible_facts", {}).get("ghcr_test_requests", []) + [url]
        status = self._templar.template(task_vars.get("ghcr_test_auth", 200))
        if repository and status == 200:
            status = 403 if repository == "example-owner/denied" else 200
            if repository == "example-owner/tags-denied" and parsed.path.startswith("/v2/"):
                status = 404
        return {
            "changed": False,
            "status": status,
            "json": {"token": "test-only-not-a-credential"},
            "ansible_facts": {"ghcr_test_requests": requests},
        }
