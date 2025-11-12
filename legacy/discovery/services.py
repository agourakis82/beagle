from __future__ import annotations

import json
import re
import subprocess
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Sequence


_IGNORED_PROCESS_PREFIXES: Sequence[str] = ("systemd", "snapfuse", "pause", "nginx")
_INTERESTING_PROCESS_KEYWORDS: Sequence[str] = ("python", "uvicorn", "gunicorn", "node")


@dataclass(slots=True)
class ListeningPort:
    """Representa uma porta TCP escutando localmente."""

    port: int
    pid: Optional[int]
    process: str


@dataclass(slots=True)
class ServiceInfo:
    """Representa um serviço detectado em Docker, Kubernetes ou processo local."""

    platform: str
    name: str
    status: str
    ports: List[str] = field(default_factory=list)
    notes: Optional[str] = None
    pid: Optional[int] = None
    namespace: Optional[str] = None
    issues: List[str] = field(default_factory=list)


@dataclass(slots=True)
class KubernetesService:
    """Representa um Service Kubernetes com portas expostas."""

    namespace: str
    name: str
    ports: List[int] = field(default_factory=list)
    selector: Optional[Dict[str, str]] = None


@dataclass(slots=True)
class ServiceInventory:
    """Snapshot consolidado dos serviços e portas descobertos."""

    services: List[ServiceInfo]
    listening_ports: Dict[int, List[ListeningPort]]
    kubernetes_services: List[KubernetesService]


def _run_command(command: List[str], timeout: int = 10) -> Optional[str]:
    try:
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _collect_listening_ports() -> List[ListeningPort]:
    """Utiliza `ss -tlnp` (ou `netstat -tlnp`) para obter portas TCP escutando."""
    commands = (["ss", "-tlnp"], ["netstat", "-tlnp"])
    output: Optional[str] = None
    for cmd in commands:
        output = _run_command(cmd, timeout=5)
        if output:
            break
    if not output:
        return []

    listeners: List[ListeningPort] = []
    for line in output.splitlines():
        if "LISTEN" not in line or "users:(" not in line:
            continue
        port_match = re.search(r":(\d+)\s", f"{line} ")
        if not port_match:
            continue
        port = int(port_match.group(1))
        for process_entry in re.findall(r'"([^"]+)",pid=(\d+)', line):
            process_name, pid_str = process_entry
            pid = int(pid_str)
            listeners.append(ListeningPort(port=port, pid=pid, process=process_name))
    return listeners


def _filter_process_name(name: str) -> bool:
    lowered = name.lower()
    if any(lowered.startswith(prefix) for prefix in _IGNORED_PROCESS_PREFIXES):
        return False
    return any(keyword in lowered for keyword in _INTERESTING_PROCESS_KEYWORDS)


def discover_docker_services() -> List[ServiceInfo]:
    """Coleta serviços ativos via `docker ps`."""
    stdout = _run_command(
        [
            "docker",
            "ps",
            "--format",
            "{{json .}}",
        ],
        timeout=15,
    )
    if not stdout:
        return []

    services: List[ServiceInfo] = []
    for line in stdout.splitlines():
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        name = payload.get("Names", "unknown")
        status = payload.get("Status", "unknown")
        ports = payload.get("Ports", "") or ""
        cleaned_ports = [
            port.split("->")[0].strip()
            for port in ports.split(",")
            if port.strip()
        ]
        services.append(
            ServiceInfo(
                platform="docker",
                name=name,
                status=status,
                ports=cleaned_ports,
                notes=payload.get("Image"),
            )
        )
    return services


def discover_kubernetes_pods(namespace: Optional[str] = None) -> List[ServiceInfo]:
    """Coleta pods em execução via `kubectl get pods`."""
    command = ["kubectl", "get", "pods", "-o", "json"]
    if namespace:
        command.extend(["-n", namespace])
    else:
        command.insert(2, "-A")

    stdout = _run_command(command, timeout=20)
    if not stdout:
        return []

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return []

    items = payload.get("items", [])
    services: List[ServiceInfo] = []
    for item in items:
        metadata = item.get("metadata", {})
        status = item.get("status", {})
        spec = item.get("spec", {})
        pod_name = metadata.get("name", "unknown")
        pod_namespace = metadata.get("namespace", "default")
        pod_phase = status.get("phase", "unknown")
        containers = status.get("containerStatuses", []) or []
        notes_parts = []
        issues: List[str] = []
        for container in containers:
            container_state = container.get("state", {})
            notes_parts.append(
                f"{container.get('name')}: {next(iter(container_state.keys()), 'unknown')}"
            )
            waiting = container_state.get("waiting")
            if waiting:
                reason = waiting.get("reason", "")
                if reason:
                    issues.append(f"{container.get('name')}: {reason}")
            last_state = container.get("lastState", {})
            if last_state.get("terminated"):
                reason = last_state["terminated"].get("reason")
                if reason:
                    issues.append(f"{container.get('name')}: terminated ({reason})")
        if pod_phase.lower() == "pending":
            issues.append("Pending: pod aguardando recursos")

        ports: List[str] = []
        for container in spec.get("containers", []) or []:
            for port_def in container.get("ports", []) or []:
                port_value = port_def.get("containerPort")
                if port_value:
                    ports.append(str(port_value))
        services.append(
            ServiceInfo(
                platform="kubernetes",
                name=pod_name,
                status=pod_phase,
                ports=ports,
                notes="; ".join(notes_parts) if notes_parts else None,
                namespace=pod_namespace,
                issues=issues,
            )
        )
    return services


def discover_kubernetes_services(namespace: Optional[str] = None) -> List[KubernetesService]:
    """Coleta serviços Kubernetes e respectivas portas."""
    command = ["kubectl", "get", "svc", "-o", "json"]
    if namespace:
        command.extend(["-n", namespace])
    else:
        command.insert(2, "-A")

    stdout = _run_command(command, timeout=20)
    if not stdout:
        return []

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return []

    services: List[KubernetesService] = []
    for item in payload.get("items", []):
        metadata = item.get("metadata", {})
        spec = item.get("spec", {})
        namespace_name = metadata.get("namespace", "default")
        service_name = metadata.get("name", "unknown")
        ports: List[int] = []
        for port_def in spec.get("ports", []) or []:
            port = port_def.get("port")
            if port:
                ports.append(int(port))
        selector = spec.get("selector")
        services.append(
            KubernetesService(
                namespace=namespace_name,
                name=service_name,
                ports=ports,
                selector=selector if selector else None,
            )
        )
    return services


def discover_local_processes(listeners: Iterable[ListeningPort]) -> List[ServiceInfo]:
    """Retorna apenas processos Python/Node com portas expostas."""
    seen: set[tuple[int, int]] = set()
    services: List[ServiceInfo] = []
    for listener in listeners:
        if listener.pid is None:
            continue
        if not _filter_process_name(listener.process):
            continue
        key = (listener.pid, listener.port)
        if key in seen:
            continue
        seen.add(key)
        services.append(
            ServiceInfo(
                platform="process",
                name=listener.process,
                status="LISTENING",
                ports=[str(listener.port)],
                notes=f"PID {listener.pid}",
                pid=listener.pid,
            )
        )
    return services


def discover_services() -> ServiceInventory:
    """Agrupa todos os serviços detectados e respectivas portas."""
    listeners = _collect_listening_ports()
    inventory = defaultdict(list)  # type: Dict[int, List[ListeningPort]]
    for listener in listeners:
        inventory[listener.port].append(listener)

    services: List[ServiceInfo] = []
    services.extend(discover_docker_services())
    kubernetes_pods = discover_kubernetes_pods()
    services.extend(kubernetes_pods)
    services.extend(discover_local_processes(listeners))

    kubernetes_services = discover_kubernetes_services()

    return ServiceInventory(
        services=services,
        listening_ports=dict(inventory),
        kubernetes_services=kubernetes_services,
    )

