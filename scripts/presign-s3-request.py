#!/usr/bin/env python3
"""Create a short-lived SigV4 query URL for one S3 request."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import os
import urllib.parse


def _sign(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode(), hashlib.sha256).digest()


def _encode(value: str) -> str:
    return urllib.parse.quote(value, safe="-_.~")


def presign(method: str, url: str, region: str, expires: int, now: dt.datetime) -> str:
    access_key = os.environ.get("AWS_ACCESS_KEY_ID", "")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
    if not access_key or not secret_key:
        raise ValueError("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required")

    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("URL must be a credential-free HTTPS endpoint")
    if parsed.fragment:
        raise ValueError("URL must not contain a fragment")

    timestamp = now.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    datestamp = timestamp[:8]
    scope = f"{datestamp}/{region}/s3/aws4_request"
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    query.extend(
        [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", f"{access_key}/{scope}"),
            ("X-Amz-Date", timestamp),
            ("X-Amz-Expires", str(expires)),
            ("X-Amz-SignedHeaders", "host"),
        ]
    )
    canonical_query = "&".join(
        f"{_encode(key)}={_encode(value)}" for key, value in sorted(query)
    )
    canonical_uri = urllib.parse.quote(parsed.path or "/", safe="/-_.~")
    canonical_request = "\n".join(
        [
            method.upper(),
            canonical_uri,
            canonical_query,
            f"host:{parsed.netloc.lower()}\n",
            "host",
            "UNSIGNED-PAYLOAD",
        ]
    )
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            timestamp,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    date_key = _sign(("AWS4" + secret_key).encode(), datestamp)
    region_key = _sign(date_key, region)
    service_key = _sign(region_key, "s3")
    signing_key = _sign(service_key, "aws4_request")
    signature = hmac.new(signing_key, string_to_sign.encode(), hashlib.sha256).hexdigest()
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, canonical_uri, f"{canonical_query}&X-Amz-Signature={signature}", "")
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--method", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--expires", type=int, default=300)
    args = parser.parse_args()
    if not 1 <= args.expires <= 900:
        parser.error("--expires must be between 1 and 900 seconds")
    try:
        print(
            presign(
                args.method,
                args.url,
                args.region,
                args.expires,
                dt.datetime.now(dt.timezone.utc),
            )
        )
    except ValueError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
