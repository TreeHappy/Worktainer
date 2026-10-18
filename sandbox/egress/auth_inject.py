"""mitmproxy addon: put auth headers on the devbox's outbound requests.

The devbox's agent talks to an LLM provider it has no key for: the key lives
in OpenBao (see ../openbao/), and this addon fetches it and sets the header on
the way out. The agent never holds the key — it cannot read one out of a
request it made, and anything it puts in these headers is overwritten, so it
cannot forge or smuggle one either.

Wiring: the egress entrypoint starts mitmdump with this file as its only
script addon and redirects the devbox's outbound 443 to it. Secrets are read in
a background thread, never on the request path: a slow or unanswering OpenBao
must not add latency to (or fail) requests.

Environment (defaults mirror compose.yaml):

  BAO_ADDR      OpenBao's address on the data network
  BAO_TOKEN     dev-mode root token
  HEADER_JOBS   one job per line, "<host> bao:<mount>/<path>"
                  api.anthropic.com bao:secret/egress/anthropic
                `<host>` matches that host and anything under it. The secret is
                a KV v2 entry whose FIELD NAMES ARE HEADER NAMES:
                  secret/egress/anthropic = {"x-api-key": "sk-ant-..."}
  BAO_RESYNC    seconds between re-reads of the secrets (300, 0 = read once at
                boot)

Secrets that have not been read yet are simply not injected — the request goes
out unauthenticated and the provider answers 401, which is the honest failure.
"""

import json
import logging
import os
import re
import threading
import time
import urllib.error
import urllib.request

log = logging.getLogger("auth_inject")

BAO_ADDR = "http://10.89.1.20:8200"
BAO_TOKEN = "sandbox-root-token"
BAO_RESYNC = 300
FETCH_TIMEOUT = 5


def matches(host, pattern):
    """True when `host` is `pattern` or a name under it (not `notexample.com`)."""
    host = (host or "").lower().rstrip(".")
    pattern = pattern.lower().rstrip(".")
    return host == pattern or host.endswith("." + pattern)


def parse_jobs(spec):
    """`HEADER_JOBS` -> [(host pattern, API path)], most specific pattern first.

    Jobs are separated by a newline *or* a semicolon. The semicolon exists
    because a systemd env file cannot hold a multi-line value, and the move off
    compose needed one job per secret. Both separators work, so the same value
    reads correctly whether it came from an env file or from a shell.

    A malformed job is dropped with a loud warning rather than raised: this runs
    inside the egress controller, and one typo must not take DNS and
    masquerading down with it.
    """
    jobs = []
    for lineno, line in enumerate(re.split(r"[\n;]", spec), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2 or not parts[1].startswith("bao:"):
            log.warning(
                "HEADER_JOBS entry %d ignored: want '<host> bao:<mount>/<path>', got %r",
                lineno, line,
            )
            continue
        mount, _, path = parts[1][len("bao:"):].strip("/").partition("/")
        if not mount or not path:
            log.warning("HEADER_JOBS line %d ignored: no secret path in %r", lineno, line)
            continue
        jobs.append((parts[0], "/v1/{}/data/{}".format(mount, path)))
    # Longest pattern first, so api.example.com beats example.com.
    jobs.sort(key=lambda job: len(job[0]), reverse=True)
    return jobs


def secret_url(addr, api_path):
    return addr.rstrip("/") + api_path


def fetch_fields(addr, token, api_path):
    """Read one KV v2 entry -> {header name: value}."""
    request = urllib.request.Request(
        secret_url(addr, api_path), headers={"X-Vault-Token": token}
    )
    with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:
        payload = json.load(response)
    # KV v2 nests the entry twice: the outer "data" is the version envelope.
    fields = (payload.get("data") or {}).get("data") or {}
    return {
        header: value
        for header, value in fields.items()
        if isinstance(value, str) and value
    }


class AuthInject:
    def __init__(self):
        self.addr = os.environ.get("BAO_ADDR") or BAO_ADDR
        self.token = os.environ.get("BAO_TOKEN") or BAO_TOKEN
        try:
            self.resync = int(os.environ.get("BAO_RESYNC") or BAO_RESYNC)
        except ValueError:
            log.warning("BAO_RESYNC is not a number; falling back to %s", BAO_RESYNC)
            self.resync = BAO_RESYNC
        self.jobs = parse_jobs(os.environ.get("HEADER_JOBS", ""))
        # host pattern -> {header: value}. Replaced wholesale, never mutated in
        # place, so the request hook can read it while this thread rewrites it.
        self._table = {}
        # host pattern -> header names seen in the last good read. Used to strip
        # those headers when a secret goes away, so an agent cannot fall back to
        # its own forged value.
        self._headers = {}
        self._warned_empty = False

    # -- mitmproxy hooks ----------------------------------------------------

    def load(self, loader):
        log.info(
            "%d job(s), resync=%ds, secrets at %s",
            len(self.jobs), self.resync, self.addr,
        )
        threading.Thread(target=self._refresh_loop, name="auth-inject", daemon=True).start()

    def request(self, flow):
        if not self.jobs:
            return
        host = (flow.request.pretty_host or "").lower()
        for pattern, _api in self.jobs:
            if not matches(host, pattern):
                continue
            fields = self._table.get(pattern)
            if fields:
                # Assign, never append: whatever the agent sent in this header
                # is replaced, so it can neither read nor invent a key.
                for header, value in fields.items():
                    flow.request.headers[header] = value
            else:
                # No value to send — drop the headers instead, or the agent's
                # own attempt at them would go out untouched. (Headers is a
                # case-insensitive MultiDict: `in` plus `del`, not pop.)
                for header in self._headers.get(pattern, ()):
                    if header in flow.request.headers:
                        del flow.request.headers[header]
                if not self._warned_empty:
                    self._warned_empty = True
                    log.warning(
                        "%s matches %s but no headers are loaded yet "
                        "(is secret read yet? see `bin/sandbox logs egress`)",
                        host, pattern,
                    )
            return

    # -- secrets ------------------------------------------------------------

    def _refresh_loop(self):
        while True:
            self._refresh_once()
            if self.resync <= 0:
                return
            time.sleep(self.resync)

    def _refresh_once(self):
        for pattern, api_path in self.jobs:
            try:
                fields = fetch_fields(self.addr, self.token, api_path)
            except (urllib.error.URLError, OSError, ValueError) as exc:
                # Keep whatever we had: a secret server blip must not turn into
                # an outage for the header it was providing.
                log.warning("read %s for %s failed: %s", api_path, pattern, exc)
                continue
            table = dict(self._table)
            table[pattern] = fields
            self._table = table
            if fields:
                # Remember the header names even if a later read comes back
                # empty: that is what lets an emptied secret strip the header
                # instead of leaving the agent's own value in place.
                names = dict(self._headers)
                names[pattern] = set(fields)
                self._headers = names
                log.info(
                    "%s: %s from %s",
                    pattern, ", ".join(sorted(fields)), api_path,
                )
            else:
                log.warning(
                    "%s: %s has no usable fields, requests will go out unauthenticated",
                    pattern, api_path,
                )


addons = [AuthInject()]