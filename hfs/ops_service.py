#!/usr/bin/env python3
"""Read-only diagnostics service for the LibreFS HFS container."""

from __future__ import annotations

import hmac
import html
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


STARTED_AT = time.time()
SUPPORTED_LANGUAGES = ("zh-CN", "en")
DEFAULT_LANGUAGE = "en"
OPS_COOKIE_NAME = "librefs_hfs_ops_token"

MESSAGES = {
    "root_description": {
        "en": "Read-only diagnostics for LibreFS HFS.",
        "zh-CN": "LibreFS HFS 只读诊断入口。",
    },
    "auth_required": {
        "en": "Authentication is required.",
        "zh-CN": "需要认证。",
    },
    "auth_hint": {
        "en": "Send X-Ops-Token or Authorization: Bearer <token>. Browser login may bootstrap at /_ops/?token=<token>.",
        "zh-CN": "请发送 X-Ops-Token 或 Authorization: Bearer <token>。浏览器登录可临时使用 /_ops/?token=<token> 引导。",
    },
    "not_found": {
        "en": "The requested ops endpoint was not found.",
        "zh-CN": "请求的 ops 端点不存在。",
    },
    "secret_omitted": {
        "en": "secret values are intentionally omitted",
        "zh-CN": "Secret 原文已刻意省略。",
    },
    "admin_independent": {
        "en": "ADMIN_ENABLED controls /_admin and is independent from OPS_TOKEN.",
        "zh-CN": "ADMIN_ENABLED 控制 /_admin，并且与 OPS_TOKEN 相互独立。",
    },
}

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


def normalize_language(value: str) -> str:
    lang = value.strip().lower().replace("_", "-")
    if not lang:
        return ""
    if lang in {"zh", "zh-cn", "zh-hans", "cn"} or lang.startswith("zh-"):
        return "zh-CN"
    if lang == "en" or lang.startswith("en-"):
        return "en"
    return ""


def text(message_key: str, language: str) -> str:
    choices = MESSAGES.get(message_key, {})
    return choices.get(language) or choices.get(DEFAULT_LANGUAGE) or message_key


def localized_notes(message_keys: list[str], language: str) -> list[str]:
    return [text(key, language) for key in message_keys]


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


def config_payload(language: str = DEFAULT_LANGUAGE) -> dict[str, Any]:
    return {
        "ok": True,
        "language": language,
        "supported_languages": list(SUPPORTED_LANGUAGES),
        "safe_config": {key: env(key) for key in SAFE_CONFIG_KEYS if env(key) != ""},
        "secret_present": {key: bool(env(key)) for key in SECRET_KEYS},
        "notes": localized_notes(["secret_omitted", "admin_independent"], language),
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


def format_bytes(value: Any) -> str:
    if not isinstance(value, (int, float)):
        return "n/a"
    size = float(value)
    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if abs(size) < 1024 or unit == "TiB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} {unit}"
        size /= 1024
    return f"{size:.1f} TiB"


def format_seconds(value: Any) -> str:
    if not isinstance(value, (int, float)):
        return "n/a"
    seconds = int(value)
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours or parts:
        parts.append(f"{hours}h")
    if minutes or parts:
        parts.append(f"{minutes}m")
    parts.append(f"{seconds}s")
    return " ".join(parts)


def json_block(payload: Any) -> str:
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2)
    return html.escape(data)


def table_rows(rows: list[tuple[str, Any]]) -> str:
    body = []
    for key, value in rows:
        body.append(
            "<tr>"
            f"<th scope=\"row\">{html.escape(str(key))}</th>"
            f"<td>{html.escape(str(value))}</td>"
            "</tr>"
        )
    return "\n".join(body)


def badge(ok: Any, true_label: str, false_label: str) -> str:
    label = true_label if ok else false_label
    tone = "ok" if ok else "bad"
    return f"<span class=\"badge {tone}\">{html.escape(label)}</span>"


def render_ops_dashboard(language: str) -> str:
    labels = {
        "zh-CN": {
            "title": "LibreFS HFS 只读诊断面板",
            "subtitle": "一次性聚合 health、system、config、version 和 metrics；Secret 原文不会显示。",
            "healthy": "健康状态",
            "checks": "检查项",
            "ops_uptime": "Ops 运行时间",
            "system_uptime": "系统运行时间",
            "data_disk": "数据盘使用",
            "routes": "路由",
            "health_checks": "健康检查",
            "system": "系统资源",
            "config": "配置摘要",
            "secrets": "Secret 状态",
            "version": "版本与运行时",
            "metrics": "Prometheus Metrics",
            "api_endpoints": "API 端点",
            "raw": "原始 JSON",
            "ok": "正常",
            "bad": "异常",
            "present": "已配置",
            "missing": "未配置",
            "open_console": "打开 Console",
            "open_admin": "打开 Admin API",
            "logout": "退出 Ops 登录",
            "refresh": "刷新页面",
        },
        "en": {
            "title": "LibreFS HFS read-only diagnostics",
            "subtitle": "A single view for health, system, config, version, and metrics. Secret values are omitted.",
            "healthy": "Health",
            "checks": "Checks",
            "ops_uptime": "Ops uptime",
            "system_uptime": "System uptime",
            "data_disk": "Data disk used",
            "routes": "Routes",
            "health_checks": "Health checks",
            "system": "System resources",
            "config": "Config summary",
            "secrets": "Secret status",
            "version": "Version and runtime",
            "metrics": "Prometheus metrics",
            "api_endpoints": "API endpoints",
            "raw": "Raw JSON",
            "ok": "OK",
            "bad": "Failed",
            "present": "Present",
            "missing": "Missing",
            "open_console": "Open Console",
            "open_admin": "Open Admin API",
            "logout": "Log out of Ops",
            "refresh": "Refresh",
        },
    }.get(language, {})

    health = health_payload()
    system = system_payload()
    config = config_payload(language)
    version = version_payload()
    metrics = metrics_payload()

    checks = health.get("checks", [])
    passed_checks = sum(1 for check in checks if check.get("ok"))
    data_disk = system.get("data_disk", {})
    data_disk_used = data_disk.get("used_percent")
    data_disk_label = f"{data_disk_used}%" if data_disk_used is not None else "n/a"
    query = "?format=json"
    api_endpoints = ["/_ops/health", "/_ops/system", "/_ops/config", "/_ops/version", "/_ops/metrics"]

    check_rows = []
    for check in checks:
        target = check.get("url") or f"{check.get('host', '')}:{check.get('port', '')}"
        detail = check.get("status") or check.get("error") or ""
        check_rows.append(
            "<tr>"
            f"<th scope=\"row\">{html.escape(str(check.get('name', 'unknown')))}</th>"
            f"<td>{html.escape(str(check.get('type', '')))}</td>"
            f"<td>{html.escape(str(target))}</td>"
            f"<td>{badge(check.get('ok'), labels['ok'], labels['bad'])}</td>"
            f"<td>{html.escape(str(check.get('duration_ms', 'n/a')))} ms</td>"
            f"<td>{html.escape(str(detail))}</td>"
            "</tr>"
        )

    safe_config_rows = [(key, value) for key, value in config.get("safe_config", {}).items()]
    if not safe_config_rows:
        safe_config_rows = [("safe_config", "empty")]

    secret_rows = [
        (key, labels["present"] if present else labels["missing"])
        for key, present in config.get("secret_present", {}).items()
    ]

    memory = system.get("memory", {})
    tmp_disk = system.get("tmp_disk", {})
    version_container = version.get("container", {})
    version_rows = [
        ("librefs_ref", version.get("librefs_ref")),
        ("librefs_commit", version.get("librefs_commit")),
        ("go_version", version.get("go_version")),
        ("ubuntu_version", version.get("ubuntu_version")),
        ("space_id", version.get("space_id")),
        ("space_host", version.get("space_host")),
        ("python", version_container.get("python")),
        ("pid", version_container.get("pid")),
    ]

    return f"""<!doctype html>
<html lang="{html.escape(language)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(labels["title"])}</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f2efe7;
      --ink: #17211b;
      --muted: #68746d;
      --panel: rgba(255, 252, 244, 0.88);
      --line: #d8d0bf;
      --ok: #127a4a;
      --bad: #b42318;
      --accent: #a95b1b;
      --shadow: 0 24px 70px rgba(44, 35, 21, 0.16);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      background:
        radial-gradient(circle at 8% 8%, rgba(169, 91, 27, 0.22), transparent 28rem),
        radial-gradient(circle at 92% 10%, rgba(18, 122, 74, 0.16), transparent 26rem),
        linear-gradient(135deg, #f8f1df 0%, var(--bg) 44%, #e8eadf 100%);
      font-family: "Avenir Next", "Gill Sans", "Trebuchet MS", sans-serif;
    }}
    main {{
      width: min(1180px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 32px 0 54px;
    }}
    header.hero {{
      display: grid;
      grid-template-columns: 1.4fr auto;
      gap: 20px;
      align-items: end;
      padding: 28px;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }}
    h1 {{
      margin: 0;
      max-width: 780px;
      font-size: clamp(2rem, 4vw, 4.5rem);
      line-height: 0.95;
      letter-spacing: -0.055em;
    }}
    .subtitle {{
      margin: 16px 0 0;
      max-width: 720px;
      color: var(--muted);
      font-size: 1.02rem;
      line-height: 1.55;
    }}
    .actions {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      justify-content: flex-end;
    }}
    .button {{
      display: inline-flex;
      align-items: center;
      min-height: 42px;
      padding: 0 14px;
      border: 1px solid var(--line);
      border-radius: 999px;
      color: var(--ink);
      background: rgba(255,255,255,0.58);
      text-decoration: none;
      font-weight: 700;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 14px;
      margin: 18px 0;
    }}
    .card, section {{
      border: 1px solid var(--line);
      border-radius: 22px;
      background: var(--panel);
      box-shadow: 0 12px 30px rgba(44, 35, 21, 0.08);
    }}
    .card {{
      padding: 18px;
    }}
    .kicker {{
      color: var(--muted);
      font-size: 0.78rem;
      font-weight: 800;
      letter-spacing: 0.11em;
      text-transform: uppercase;
    }}
    .value {{
      margin-top: 10px;
      font-size: clamp(1.3rem, 2.1vw, 2.1rem);
      font-weight: 850;
      letter-spacing: -0.035em;
    }}
    section {{
      margin-top: 16px;
      overflow: hidden;
    }}
    section h2 {{
      margin: 0;
      padding: 18px 20px;
      border-bottom: 1px solid var(--line);
      font-size: 1rem;
      letter-spacing: 0.01em;
    }}
    .section-body {{
      padding: 18px 20px;
      overflow-x: auto;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      min-width: 620px;
    }}
    th, td {{
      padding: 11px 10px;
      border-bottom: 1px solid rgba(216, 208, 191, 0.72);
      text-align: left;
      vertical-align: top;
      font-size: 0.94rem;
    }}
    th {{
      width: 210px;
      font-weight: 800;
    }}
    tr:last-child th, tr:last-child td {{ border-bottom: 0; }}
    .badge {{
      display: inline-flex;
      align-items: center;
      padding: 4px 9px;
      border-radius: 999px;
      color: #fff;
      font-size: 0.76rem;
      font-weight: 850;
    }}
    .badge.ok {{ background: var(--ok); }}
    .badge.bad {{ background: var(--bad); }}
    pre {{
      margin: 0;
      padding: 16px;
      border-radius: 16px;
      background: #17211b;
      color: #f7efd8;
      overflow: auto;
      font: 0.86rem/1.55 "Menlo", "Monaco", "Consolas", monospace;
    }}
    details {{
      margin-top: 12px;
    }}
    summary {{
      cursor: pointer;
      color: var(--accent);
      font-weight: 850;
    }}
    @media (max-width: 850px) {{
      header.hero {{ grid-template-columns: 1fr; }}
      .actions {{ justify-content: flex-start; }}
      .grid {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
    }}
    @media (max-width: 560px) {{
      main {{ width: min(100vw - 20px, 1180px); padding-top: 10px; }}
      header.hero {{ padding: 20px; border-radius: 20px; }}
      .grid {{ grid-template-columns: 1fr; }}
      table {{ min-width: 520px; }}
    }}
  </style>
</head>
<body>
  <main>
    <header class="hero">
      <div>
        <h1>{html.escape(labels["title"])}</h1>
        <p class="subtitle">{html.escape(labels["subtitle"])}</p>
      </div>
      <nav class="actions" aria-label="Ops links">
        <a class="button" href="/console/">{html.escape(labels["open_console"])}</a>
        <a class="button" href="/_admin/">{html.escape(labels["open_admin"])}</a>
        <a class="button" href="">{html.escape(labels["refresh"])}</a>
        <a class="button" href="{query}">JSON</a>
        <a class="button" href="/_ops/logout">{html.escape(labels["logout"])}</a>
      </nav>
    </header>

    <div class="grid" aria-label="Summary">
      <article class="card">
        <div class="kicker">{html.escape(labels["healthy"])}</div>
        <div class="value">{badge(health.get("ok"), labels["ok"], labels["bad"])}</div>
      </article>
      <article class="card">
        <div class="kicker">{html.escape(labels["checks"])}</div>
        <div class="value">{passed_checks}/{len(checks)}</div>
      </article>
      <article class="card">
        <div class="kicker">{html.escape(labels["ops_uptime"])}</div>
        <div class="value">{html.escape(format_seconds(health.get("ops", {}).get("uptime_seconds")))}</div>
      </article>
      <article class="card">
        <div class="kicker">{html.escape(labels["data_disk"])}</div>
        <div class="value">{html.escape(data_disk_label)}</div>
      </article>
    </div>

    <section>
      <h2>{html.escape(labels["api_endpoints"])}</h2>
      <div class="section-body">
        <table><tbody>{table_rows([(endpoint, endpoint) for endpoint in api_endpoints])}</tbody></table>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["health_checks"])}</h2>
      <div class="section-body">
        <table>
          <thead><tr><th>Name</th><th>Type</th><th>Target</th><th>Status</th><th>Latency</th><th>Detail</th></tr></thead>
          <tbody>{"".join(check_rows)}</tbody>
        </table>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["system"])}</h2>
      <div class="section-body">
        <table><tbody>{table_rows([
            ("time", system.get("time")),
            ("ops_uptime", format_seconds(system.get("ops_uptime_seconds"))),
            ("system_uptime", format_seconds(system.get("system_uptime_seconds"))),
            ("load", system.get("load")),
            ("memory_total", format_bytes(memory.get("total_bytes"))),
            ("memory_available", format_bytes(memory.get("available_bytes"))),
            ("data_disk", f"{format_bytes(data_disk.get('used_bytes'))} used / {format_bytes(data_disk.get('total_bytes'))} total"),
            ("tmp_disk", f"{format_bytes(tmp_disk.get('used_bytes'))} used / {format_bytes(tmp_disk.get('total_bytes'))} total"),
            ("process_count", system.get("process_count")),
        ])}</tbody></table>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["config"])}</h2>
      <div class="section-body">
        <table><tbody>{table_rows(safe_config_rows)}</tbody></table>
        <h2>{html.escape(labels["secrets"])}</h2>
        <table><tbody>{table_rows(secret_rows)}</tbody></table>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["version"])}</h2>
      <div class="section-body">
        <table><tbody>{table_rows(version_rows)}</tbody></table>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["metrics"])}</h2>
      <div class="section-body">
        <pre>{html.escape(metrics)}</pre>
      </div>
    </section>

    <section>
      <h2>{html.escape(labels["raw"])}</h2>
      <div class="section-body">
        <details><summary>health</summary><pre>{json_block(health)}</pre></details>
        <details><summary>system</summary><pre>{json_block(system)}</pre></details>
        <details><summary>config</summary><pre>{json_block(config)}</pre></details>
        <details><summary>version</summary><pre>{json_block(version)}</pre></details>
      </div>
    </section>
  </main>
</body>
</html>"""


def render_login_page(language: str, error: str = "") -> str:
    labels = {
        "zh-CN": {
            "title": "Ops 登录",
            "heading": "进入 LibreFS HFS Ops",
            "intro": "输入 OPS_TOKEN 后会保存为浏览器 HttpOnly cookie，后续访问不需要把 token 放在 URL 里。",
            "token": "OPS_TOKEN",
            "submit": "登录",
            "error": "Token 不正确。",
            "hint": "浏览器登录仍然兼容临时 URL：/_ops/?token=<ops-token>。",
        },
        "en": {
            "title": "Ops login",
            "heading": "Enter LibreFS HFS Ops",
            "intro": "After OPS_TOKEN is accepted, the browser stores it as an HttpOnly cookie so later visits do not need token in the URL.",
            "token": "OPS_TOKEN",
            "submit": "Log in",
            "error": "The token is not correct.",
            "hint": "Temporary browser login is still supported: /_ops/?token=<ops-token>.",
        },
    }.get(language, {})
    error_html = f"<p class=\"error\">{html.escape(labels['error'])}</p>" if error else ""
    return f"""<!doctype html>
<html lang="{html.escape(language)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(labels["title"])}</title>
  <style>
    :root {{
      --bg: #f2efe7;
      --ink: #17211b;
      --muted: #68746d;
      --panel: rgba(255, 252, 244, 0.92);
      --line: #d8d0bf;
      --accent: #a95b1b;
      --bad: #b42318;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      color: var(--ink);
      background:
        radial-gradient(circle at 12% 8%, rgba(169, 91, 27, 0.24), transparent 28rem),
        radial-gradient(circle at 88% 18%, rgba(18, 122, 74, 0.16), transparent 24rem),
        linear-gradient(135deg, #f8f1df 0%, var(--bg) 48%, #e8eadf 100%);
      font-family: "Avenir Next", "Gill Sans", "Trebuchet MS", sans-serif;
    }}
    main {{
      width: min(520px, 100%);
      padding: 28px;
      border: 1px solid var(--line);
      border-radius: 28px;
      background: var(--panel);
      box-shadow: 0 24px 70px rgba(44, 35, 21, 0.16);
    }}
    h1 {{
      margin: 0;
      font-size: clamp(2rem, 6vw, 3.8rem);
      line-height: 0.95;
      letter-spacing: -0.055em;
    }}
    p {{
      color: var(--muted);
      line-height: 1.55;
    }}
    label {{
      display: block;
      margin: 18px 0 8px;
      font-weight: 850;
    }}
    input {{
      width: 100%;
      min-height: 46px;
      padding: 10px 12px;
      border: 1px solid var(--line);
      border-radius: 14px;
      font: inherit;
      background: #fffdf6;
    }}
    button {{
      width: 100%;
      min-height: 48px;
      margin-top: 14px;
      border: 0;
      border-radius: 999px;
      color: #fff;
      background: var(--accent);
      font: inherit;
      font-weight: 850;
      cursor: pointer;
    }}
    .error {{
      color: var(--bad);
      font-weight: 850;
    }}
    .hint {{
      margin-bottom: 0;
      font-size: 0.92rem;
    }}
  </style>
</head>
<body>
  <main>
    <h1>{html.escape(labels["heading"])}</h1>
    <p>{html.escape(labels["intro"])}</p>
    {error_html}
    <form method="post" action="/_ops/login">
      <label for="token">{html.escape(labels["token"])}</label>
      <input id="token" name="token" type="password" autocomplete="current-password" autofocus required>
      <button type="submit">{html.escape(labels["submit"])}</button>
    </form>
    <p class="hint">{html.escape(labels["hint"])}</p>
  </main>
</body>
</html>"""


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

    def language(self) -> str:
        query_lang = self.query().get("lang", [""])[0]
        header_lang = self.headers.get("X-Control-Language", "")
        for candidate in [query_lang, header_lang]:
            selected = normalize_language(candidate)
            if selected:
                return selected
        for candidate in self.headers.get("Accept-Language", "").split(","):
            selected = normalize_language(candidate.split(";", 1)[0])
            if selected:
                return selected
        return normalize_language(env("CONTROL_PLANE_DEFAULT_LANG", "")) or DEFAULT_LANGUAGE

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        payload.setdefault("language", self.language())
        payload.setdefault("supported_languages", list(SUPPORTED_LANGUAGES))
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

    def send_ops_cookie(self, token: str) -> None:
        jar = cookies.SimpleCookie()
        jar[OPS_COOKIE_NAME] = token
        jar[OPS_COOKIE_NAME]["path"] = "/_ops"
        jar[OPS_COOKIE_NAME]["secure"] = True
        jar[OPS_COOKIE_NAME]["httponly"] = True
        jar[OPS_COOKIE_NAME]["samesite"] = "Lax"
        self.send_header("Set-Cookie", jar[OPS_COOKIE_NAME].OutputString())

    def send_clear_ops_cookie(self) -> None:
        jar = cookies.SimpleCookie()
        jar[OPS_COOKIE_NAME] = ""
        jar[OPS_COOKIE_NAME]["path"] = "/_ops"
        jar[OPS_COOKIE_NAME]["secure"] = True
        jar[OPS_COOKIE_NAME]["httponly"] = True
        jar[OPS_COOKIE_NAME]["samesite"] = "Lax"
        jar[OPS_COOKIE_NAME]["max-age"] = 0
        self.send_header("Set-Cookie", jar[OPS_COOKIE_NAME].OutputString())

    def send_redirect(self, location: str, token: str = "", clear_cookie: bool = False) -> None:
        self.send_response(303)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        if token:
            self.send_ops_cookie(token)
        if clear_cookie:
            self.send_clear_ops_cookie()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def wants_html(self) -> bool:
        fmt = self.query().get("format", [""])[0].strip().lower()
        if fmt in {"json", "api"}:
            return False
        if fmt in {"html", "dashboard"}:
            return True
        return "text/html" in self.headers.get("Accept", "")

    def external_path_without_token(self) -> str:
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path in {"", "/"}:
            path = "/_ops/"
        elif parsed.path.startswith("/_ops"):
            path = parsed.path
        else:
            path = f"/_ops{parsed.path}"
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        query.pop("token", None)
        encoded = urllib.parse.urlencode(query, doseq=True)
        return path + (f"?{encoded}" if encoded else "")

    def bearer_token(self) -> str:
        auth = self.headers.get("Authorization", "")
        if auth.lower().startswith("bearer "):
            return auth[7:].strip()
        return ""

    def query_token(self) -> str:
        return self.query().get("token", [""])[0]

    def cookie_token(self) -> str:
        raw_cookie = self.headers.get("Cookie", "")
        if not raw_cookie:
            return ""
        jar = cookies.SimpleCookie()
        try:
            jar.load(raw_cookie)
        except cookies.CookieError:
            return ""
        morsel = jar.get(OPS_COOKIE_NAME)
        return morsel.value if morsel else ""

    def request_tokens(self) -> list[str]:
        return [
            self.headers.get("X-Ops-Token", ""),
            self.bearer_token(),
            self.cookie_token(),
        ]

    def request_token(self) -> str:
        for token in self.request_tokens():
            if token:
                return token
        return ""

    def token_valid(self, token: str) -> bool:
        expected = env("OPS_TOKEN", "librefs_ops_demo_token")
        return bool(expected) and bool(token) and hmac.compare_digest(token, expected)

    def authenticated(self) -> bool:
        return any(self.token_valid(token) for token in self.request_tokens())

    def require_auth(self) -> bool:
        if self.authenticated():
            return True
        language = self.language()
        if self.wants_html():
            self.send_text(render_login_page(language), content_type="text/html; charset=utf-8", status=401)
            return False
        self.send_json(
            {
                "ok": False,
                "error": "unauthorized",
                "message": text("auth_required", language),
                "hint": text("auth_hint", language),
            },
            status=401,
        )
        return False

    def do_POST(self) -> None:
        path = self.normalized_path()
        if path != "/login":
            self.send_json(
                {"ok": False, "error": "not_found", "message": text("not_found", self.language()), "path": path},
                status=404,
            )
            return

        length = parse_int(self.headers.get("Content-Length", "0"), 0, minimum=0, maximum=4096)
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        token = urllib.parse.parse_qs(body).get("token", [""])[0]
        if self.token_valid(token):
            self.send_redirect("/_ops/", token=token)
            return
        self.send_text(render_login_page(self.language(), error="invalid_token"), content_type="text/html; charset=utf-8", status=401)

    def do_GET(self) -> None:
        path = self.normalized_path()
        if path == "/healthz":
            self.send_json({"ok": True, "service": "ops", "uptime_seconds": round(time.time() - STARTED_AT, 2)})
            return

        if path == "/logout":
            self.send_redirect("/_ops/", clear_cookie=True)
            return

        query_token = self.query_token()
        if path in {"/", ""} and query_token and self.token_valid(query_token) and self.wants_html():
            self.send_redirect(self.external_path_without_token(), token=query_token)
            return

        if not self.require_auth():
            return

        if path in {"/", ""}:
            language = self.language()
            if self.wants_html():
                self.send_text(render_ops_dashboard(language), content_type="text/html; charset=utf-8")
                return
            self.send_json(
                {
                    "ok": True,
                    "service": "librefs-hfs-ops",
                    "description": text("root_description", language),
                    "endpoints": ["/_ops/health", "/_ops/system", "/_ops/config", "/_ops/version", "/_ops/metrics"],
                }
            )
        elif path == "/health":
            self.send_json(health_payload())
        elif path == "/system":
            self.send_json(system_payload())
        elif path == "/config":
            self.send_json(config_payload(self.language()))
        elif path == "/version":
            self.send_json(version_payload())
        elif path == "/metrics":
            self.send_text(metrics_payload(), content_type="text/plain; version=0.0.4; charset=utf-8")
        else:
            self.send_json(
                {"ok": False, "error": "not_found", "message": text("not_found", self.language()), "path": path},
                status=404,
            )


def main() -> None:
    host = env("OPS_HOST", "127.0.0.1")
    port = parse_int(env("OPS_PORT", "8081"), 8081, minimum=1, maximum=65535)
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"librefs-hfs ops service listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
