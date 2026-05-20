#!/usr/bin/env python3
"""Read-only diagnostics service for the LibreFS HFS container."""

from __future__ import annotations

import hmac
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


STARTED_AT = time.time()

SAFE_CONFIG_KEYS = [
    "DATA_DIR",
    "LIBREFS_API_ADDR",
    "LIBREFS_CONSOLE_ADDR",
    "NGINX_CONF",
    "MINIO_SERVER_URL",
    "MINIO_BROWSER_REDIRECT_URL",
    "PUBLIC_BASE_URL",
    "SPACE_HOST",
    "LIBREFS_REF",
    "LIBREFS_COMMIT",
    "GO_VERSION",
    "ADMIN_ENABLED",
    "ADMIN_FILES_ENABLED",
    "ADMIN_FILES_WRITE_ENABLED",
]

SECRET_KEYS = [
    "MINIO_ROOT_USER",
    "MINIO_ROOT_PASSWORD",
    "OPS_TOKEN",
    "ADMIN_TOKEN",
]


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


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


def parse_bool(value: str, default: bool = False) -> bool:
    if value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def host_port_from_addr(value: str, default_port: int) -> tuple[str, int]:
    raw = value.strip() or f":{default_port}"
    if raw.startswith(":"):
        return "127.0.0.1", parse_int(raw[1:], default_port, minimum=1, maximum=65535)
    if ":" not in raw:
        return raw, default_port
    host, port = raw.rsplit(":", 1)
    return host or "127.0.0.1", parse_int(port, default_port, minimum=1, maximum=65535)


def http_check(name: str, url: str, expected_status: int = 200, timeout: float = 2.0) -> dict[str, Any]:
    started = time.time()
    try:
        request = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            body = response.read(256)
        ok = status == expected_status
        return {
            "name": name,
            "ok": ok,
            "type": "http",
            "url": url,
            "status": status,
            "expected_status": expected_status,
            "duration_ms": round((time.time() - started) * 1000, 2),
            "body_sample": body.decode("utf-8", errors="replace"),
        }
    except urllib.error.HTTPError as exc:
        ok = exc.code == expected_status
        return {
            "name": name,
            "ok": ok,
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


def tcp_check(name: str, host: str, port: int, timeout: float = 1.0) -> dict[str, Any]:
    started = time.time()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return {
            "name": name,
            "ok": True,
            "type": "tcp",
            "host": host,
            "port": port,
            "duration_ms": round((time.time() - started) * 1000, 2),
        }
    except Exception as exc:  # pragma: no cover - runtime diagnostics
        return {
            "name": name,
            "ok": False,
            "type": "tcp",
            "host": host,
            "port": port,
            "duration_ms": round((time.time() - started) * 1000, 2),
            "error": str(exc),
        }


def health_payload(public: bool = False) -> dict[str, Any]:
    api_host, api_port = host_port_from_addr(env("LIBREFS_API_ADDR", ":9000"), 9000)
    console_host, console_port = host_port_from_addr(env("LIBREFS_CONSOLE_ADDR", ":9001"), 9001)

    checks = [
        http_check("nginx-s3-health", "http://127.0.0.1:7860/minio/health/ready"),
        http_check("librefs-s3-health", f"http://{api_host}:{api_port}/minio/health/ready"),
        tcp_check("console-port", console_host, console_port),
    ]

    payload: dict[str, Any] = {
        "ok": all(check["ok"] for check in checks),
        "checks": checks,
        "ops": {
            "ok": True,
            "uptime_seconds": round(time.time() - STARTED_AT, 2),
        },
    }
    if not public:
        payload["routes"] = {
            "s3": "/",
            "console": "/console/",
            "ops": "/_ops/",
            "admin": "/_admin/",
        }
    return payload


def read_key_value_file(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            parts = line.split()
            if parts:
                result[parts[0].rstrip(":")] = parts[1] if len(parts) > 1 else ""
    except OSError:
        pass
    return result


def memory_payload() -> dict[str, Any]:
    meminfo = read_key_value_file(Path("/proc/meminfo"))
    total_kib = parse_int(meminfo.get("MemTotal", 0), 0)
    available_kib = parse_int(meminfo.get("MemAvailable", 0), 0)
    return {
        "total_bytes": total_kib * 1024 if total_kib else None,
        "available_bytes": available_kib * 1024 if available_kib else None,
    }


def load_payload() -> dict[str, Any]:
    try:
        one, five, fifteen, *_rest = Path("/proc/loadavg").read_text(encoding="utf-8").split()
        return {"load1": float(one), "load5": float(five), "load15": float(fifteen)}
    except (OSError, ValueError):
        return {"load1": None, "load5": None, "load15": None}


def uptime_seconds() -> float | None:
    try:
        return float(Path("/proc/uptime").read_text(encoding="utf-8").split()[0])
    except (OSError, ValueError, IndexError):
        return None


def disk_payload(path: str) -> dict[str, Any]:
    target = Path(path)
    try:
        stats = os.statvfs(target)
        total = stats.f_frsize * stats.f_blocks
        free = stats.f_frsize * stats.f_bavail
        used = total - free
        return {
            "path": str(target),
            "total_bytes": total,
            "used_bytes": used,
            "free_bytes": free,
            "used_percent": round((used / total) * 100, 2) if total else None,
        }
    except OSError as exc:
        return {"path": str(target), "error": str(exc)}


def process_count() -> int | None:
    try:
        return sum(1 for child in Path("/proc").iterdir() if child.name.isdigit())
    except OSError:
        return None


def system_payload() -> dict[str, Any]:
    data_dir = env("DATA_DIR", "/data")
    return {
        "ok": True,
        "time": int(time.time()),
        "ops_uptime_seconds": round(time.time() - STARTED_AT, 2),
        "system_uptime_seconds": uptime_seconds(),
        "load": load_payload(),
        "memory": memory_payload(),
        "data_disk": disk_payload(data_dir),
        "tmp_disk": disk_payload("/tmp"),
        "process_count": process_count(),
    }


def config_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "safe_config": {key: env(key) for key in SAFE_CONFIG_KEYS if env(key) != ""},
        "secret_present": {key: bool(env(key)) for key in SECRET_KEYS},
        "notes": [
            "secret values are intentionally omitted",
            "ADMIN_ENABLED controls /_admin and is independent from OPS_TOKEN",
        ],
    }


def version_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "librefs_ref": env("LIBREFS_REF", "master"),
        "librefs_commit": env("LIBREFS_COMMIT", "HEAD"),
        "go_version": env("GO_VERSION"),
        "ubuntu_version": env("UBUNTU_VERSION"),
        "space_id": env("SPACE_ID"),
        "space_host": env("SPACE_HOST"),
        "container": {
            "python": ".".join(map(str, sys.version_info[:3])),
            "pid": os.getpid(),
        },
    }


def metric_bool(value: Any) -> int:
    return 1 if bool(value) else 0


def metric_escape(value: Any) -> str:
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def metrics_payload() -> str:
    health = health_payload(public=True)
    system = system_payload()
    lines = [
        "# HELP librefs_hfs_ops_up Whether the ops service is running.",
        "# TYPE librefs_hfs_ops_up gauge",
        "librefs_hfs_ops_up 1",
        "# HELP librefs_hfs_health_ok Whether all configured health checks are passing.",
        "# TYPE librefs_hfs_health_ok gauge",
        f"librefs_hfs_health_ok {metric_bool(health.get('ok'))}",
        "# HELP librefs_hfs_check_ok Individual health check status.",
        "# TYPE librefs_hfs_check_ok gauge",
    ]
    for check in health.get("checks", []):
        name = metric_escape(check.get("name", "unknown"))
        lines.append(f'librefs_hfs_check_ok{{check="{name}"}} {metric_bool(check.get("ok"))}')
        if check.get("duration_ms") is not None:
            lines.append(f'librefs_hfs_check_duration_ms{{check="{name}"}} {check["duration_ms"]}')
    memory = system.get("memory", {})
    disk = system.get("data_disk", {})
    if memory.get("available_bytes") is not None:
        lines.append(f'librefs_hfs_memory_available_bytes {memory["available_bytes"]}')
    if disk.get("free_bytes") is not None:
        lines.append(f'librefs_hfs_data_free_bytes {disk["free_bytes"]}')
    lines.append(f'librefs_hfs_ops_uptime_seconds {system["ops_uptime_seconds"]}')
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    server_version = "librefs-hfs-ops/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def normalized_path(self) -> str:
        path = urllib.parse.urlsplit(self.path).path
        if path == "/_ops":
            return "/"
        if path.startswith("/_ops/"):
            return path[len("/_ops") :]
        return path or "/"

    def query(self) -> dict[str, list[str]]:
        return urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_text(self, payload: str, content_type: str = "text/plain; charset=utf-8", status: int = 200) -> None:
        data = payload.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def bearer_token(self) -> str:
        auth = self.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            return auth[7:].strip()
        return ""

    def request_token(self) -> str:
        query_token = self.query().get("token", [""])[0]
        return self.headers.get("X-Ops-Token", "") or self.bearer_token() or query_token

    def authenticated(self) -> bool:
        expected = env("OPS_TOKEN", "librefs_ops_demo_token")
        token = self.request_token()
        return bool(expected) and hmac.compare_digest(token, expected)

    def require_auth(self) -> bool:
        if self.authenticated():
            return True
        self.send_json(
            {
                "ok": False,
                "error": "unauthorized",
                "hint": "send X-Ops-Token, Authorization: Bearer <token>, or ?token=<token>",
            },
            status=401,
        )
        return False

    def do_GET(self) -> None:
        path = self.normalized_path()
        if path == "/healthz":
            self.send_json({"ok": True, "service": "ops", "uptime_seconds": round(time.time() - STARTED_AT, 2)})
            return

        if not self.require_auth():
            return

        if path in {"/", ""}:
            self.send_json(
                {
                    "ok": True,
                    "service": "librefs-hfs-ops",
                    "endpoints": ["/health", "/system", "/config", "/version", "/metrics"],
                }
            )
        elif path == "/health":
            self.send_json(health_payload())
        elif path == "/system":
            self.send_json(system_payload())
        elif path == "/config":
            self.send_json(config_payload())
        elif path == "/version":
            self.send_json(version_payload())
        elif path == "/metrics":
            self.send_text(metrics_payload(), content_type="text/plain; version=0.0.4; charset=utf-8")
        else:
            self.send_json({"ok": False, "error": "not_found", "path": path}, status=404)


def main() -> None:
    host = env("OPS_HOST", "127.0.0.1")
    port = parse_int(env("OPS_PORT", "8081"), 8081, minimum=1, maximum=65535)
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"librefs-hfs ops service listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
