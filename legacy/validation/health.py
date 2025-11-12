from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Optional

import requests


@dataclass(slots=True)
class HealthCheck:
    name: str
    url: Optional[str] = None
    host: str = "localhost"
    port: Optional[int] = None
    expect_http: bool = True


@dataclass(slots=True)
class HealthCheckResult:
    name: str
    url: Optional[str]
    status_code: Optional[int]
    ok: bool
    error: Optional[str] = None
    port: Optional[int] = None


def run_health_checks(
    checks: Iterable[HealthCheck],
    timeout: int = 5,
) -> List[HealthCheckResult]:
    """Executa health checks HTTP ou TCP."""
    import socket

    results: List[HealthCheckResult] = []
    for check in checks:
        if check.url:
            try:
                response = requests.get(check.url, timeout=timeout)
                results.append(
                    HealthCheckResult(
                        name=check.name,
                        url=check.url,
                        status_code=response.status_code,
                        ok=response.ok,
                    )
                )
            except requests.RequestException as exc:
                results.append(
                    HealthCheckResult(
                        name=check.name,
                        url=check.url,
                        status_code=None,
                        ok=False,
                        error=str(exc),
                    )
                )
            continue

        if check.port is None:
            results.append(
                HealthCheckResult(
                    name=check.name,
                    url=None,
                    status_code=None,
                    ok=False,
                    error="Health check sem URL ou porta definida.",
                    port=None,
                )
            )
            continue

        address = (check.host, check.port)
        try:
            with socket.create_connection(address, timeout=timeout):
                tcp_ok = True
        except OSError as exc:
            results.append(
                HealthCheckResult(
                    name=check.name,
                    url=None,
                    status_code=None,
                    ok=False,
                    error=str(exc),
                    port=check.port,
                )
            )
            continue

        http_url = f"http://{check.host}:{check.port}/health"
        if check.expect_http:
            try:
                response = requests.get(http_url, timeout=timeout)
                results.append(
                    HealthCheckResult(
                        name=check.name,
                        url=http_url,
                        status_code=response.status_code,
                        ok=response.ok,
                        port=check.port,
                    )
                )
            except requests.RequestException as exc:
                results.append(
                    HealthCheckResult(
                        name=check.name,
                        url=http_url,
                        status_code=None,
                        ok=False,
                        error=str(exc),
                        port=check.port,
                    )
                )
        else:
            results.append(
                HealthCheckResult(
                    name=check.name,
                    url=None,
                    status_code=None,
                    ok=tcp_ok,
                    port=check.port,
                )
            )
    return results

