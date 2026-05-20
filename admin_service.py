#!/usr/bin/env python3
"""Default-off admin surface for the LibreFS HFS container."""

from __future__ import annotations

import hmac
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


STARTED_AT = time.time()


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def parse_bool(value: str, default: bool = False) -> bool:
    if value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def parse_int(value: Any, default: int, minimum: int | None = None, maximum: int | None = None) -> int:
    try:
        parsed = int(str(value))
    except (TypeError, ValueError):
        parsed = default
    if minimum is not None:
        parsed = max(parsed, minimum)
    if maximum is not None:
        parsed = min(parsed, maximum)
    return parsed


def admin_enabled() -> bool:
    return parse_bool(env("ADMIN_ENABLED", "false"), default=False)


def admin_token() -> str:
    return env("ADMIN_TOKEN")


def audit_path() -> Path:
    return Path(env("ADMIN_AUDIT_LOG", "/data/logs/admin-audit.jsonl"))


def audit_event(action: str, ok: bool, actor: str, details: dict[str, Any] | None = None) -> None:
    payload = {
        "time": int(time.time()),
        "action": action,
        "ok": ok,
        "actor": actor,
        "details": details or {},
    }
    path = audit_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
    except OSError as exc:
        print(f"failed to write admin audit log: {exc}", flush=True)


def http_check(name: str, url: str, expected_status: int = 200, timeout: float = 2.0) -> dict[str, Any]:
    started = time.time()
    try:
        request = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            response.read(128)
        return {
            "name": name,
            "ok": status == expected_status,
            "type": "http",
            "url": url,
            "status": status,
            "expected_status": expected_status,
            "duration_ms": round((time.time() - started) * 1000, 2),
        }
    except urllib.error.HTTPError as exc:
        return {
            "name": name,
            "ok": exc.code == expected_status,
            "type": "http",
            "url": url,
            "status": exc.code,
            "expected_status": expected_status,
            "duration_ms": round((time.time() - started) * 1000, 2),
            "error": str(exc),
        }
    except Exception as exc:  # pragma: no cover - runtime diagnostics
        return {
            "name": name,
            "ok": False,
            "type": "http",
            "url": url,
            "expected_status": expected_status,
            "duration_ms": round((time.time() - started) * 1000, 2),
            "error": str(exc),
        }


def run_health_checks() -> dict[str, Any]:
    checks = [
        http_check("nginx-s3-health", "http://127.0.0.1:7860/minio/health/ready"),
        http_check("ops-healthz", "http://127.0.0.1:8081/healthz"),
    ]
    return {"ok": all(check["ok"] for check in checks), "checks": checks}


def run_command(args: list[str], timeout: float = 10.0) -> dict[str, Any]:
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout[-4000:],
            "stderr": result.stderr[-4000:],
        }
    except Exception as exc:  # pragma: no cover - runtime diagnostics
        return {"ok": False, "error": str(exc)}


def actions_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "actions": [
            {
                "name": "run-health-checks",
                "method": "POST",
                "path": "/_admin/api/actions/run-health-checks",
                "writes": False,
                "requires_confirm": False,
            },
            {
                "name": "reload-nginx",
                "method": "POST",
                "path": "/_admin/api/actions/reload-nginx",
                "writes": True,
                "requires_confirm": True,
            },
        ],
    }


def status_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "librefs-hfs-admin",
        "enabled": admin_enabled(),
        "uptime_seconds": round(time.time() - STARTED_AT, 2),
        "audit_log": str(audit_path()),
        "admin_files_enabled": parse_bool(env("ADMIN_FILES_ENABLED", "false"), default=False),
        "admin_files_write_enabled": parse_bool(env("ADMIN_FILES_WRITE_ENABLED", "false"), default=False),
        "notes": [
            "admin is independent from OPS_TOKEN",
            "file manager and terminal are intentionally not implemented",
            "restart-service is intentionally omitted because start.sh owns process supervision",
        ],
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "librefs-hfs-admin/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def normalized_path(self) -> str:
        path = urllib.parse.urlsplit(self.path).path
        if path == "/_admin":
            return "/"
        if path.startswith("/_admin/"):
            return path[len("/_admin") :]
        return path or "/"

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self) -> dict[str, Any]:
        length = parse_int(self.headers.get("Content-Length", "0"), 0, minimum=0, maximum=1024 * 1024)
        if length == 0:
            return {}
        data = self.rfile.read(length)
        try:
            payload = json.loads(data.decode("utf-8"))
        except json.JSONDecodeError:
            return {}
        return payload if isinstance(payload, dict) else {}

    def bearer_token(self) -> str:
        auth = self.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            return auth[7:].strip()
        return ""

    def request_token(self) -> str:
        return self.headers.get("X-Admin-Token", "") or self.bearer_token()

    def require_enabled(self) -> bool:
        if admin_enabled():
            return True
        self.send_json({"ok": False, "error": "admin_disabled"}, status=404)
        return False

    def require_auth(self) -> bool:
        expected = admin_token()
        if not expected:
            self.send_json({"ok": False, "error": "ADMIN_TOKEN must be set before enabling admin"}, status=503)
            return False
        token = self.request_token()
        if token and hmac.compare_digest(token, expected):
            return True
        self.send_json(
            {"ok": False, "error": "unauthorized", "hint": "send X-Admin-Token or Authorization: Bearer <token>"},
            status=401,
        )
        return False

    def guard(self) -> bool:
        return self.require_enabled() and self.require_auth()

    def do_GET(self) -> None:
        path = self.normalized_path()
        if path == "/healthz":
            self.send_json({"ok": True, "service": "admin", "enabled": admin_enabled()})
            return
        if not self.guard():
            return

        if path in {"/", ""}:
            self.send_json({"ok": True, "service": "librefs-hfs-admin", "endpoints": ["/api/status", "/api/actions"]})
        elif path == "/api/status":
            self.send_json(status_payload())
        elif path == "/api/actions":
            self.send_json(actions_payload())
        else:
            self.send_json({"ok": False, "error": "not_found", "path": path}, status=404)

    def do_POST(self) -> None:
        path = self.normalized_path()
        if not self.guard():
            return

        actor = "token"
        payload = self.read_json()
        if path == "/api/actions/run-health-checks":
            result = run_health_checks()
            audit_event("run-health-checks", result["ok"], actor)
            self.send_json(result, status=200 if result["ok"] else 503)
            return

        if path == "/api/actions/reload-nginx":
            if payload.get("confirm") is not True:
                self.send_json({"ok": False, "error": "confirm=true is required"}, status=400)
                return
            command = ["nginx", "-s", "reload", "-c", env("NGINX_CONF", "/etc/nginx/nginx.conf")]
            result = run_command(command, timeout=10.0)
            audit_event("reload-nginx", result["ok"], actor, {"returncode": result.get("returncode")})
            self.send_json(result, status=200 if result["ok"] else 500)
            return

        self.send_json({"ok": False, "error": "not_found", "path": path}, status=404)


def main() -> None:
    host = env("ADMIN_HOST", "127.0.0.1")
    port = parse_int(env("ADMIN_PORT", "8082"), 8082, minimum=1, maximum=65535)
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"librefs-hfs admin service listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
