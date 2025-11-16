from __future__ import annotations

from pathlib import Path
from typing import Iterable, List, Sequence, Set, Tuple

from discovery.services import KubernetesService

INTERESTING_NAMESPACES: Sequence[str] = ("darwin", "pcs", "hyperbolic")
INTERESTING_PREFIXES: Sequence[str] = ("darwin", "pcs", "hyperbolic")


def _is_interesting_service(service: KubernetesService) -> bool:
    namespace = service.namespace.lower()
    name = service.name.lower()
    if any(namespace.startswith(ns) for ns in INTERESTING_NAMESPACES):
        return True
    return any(name.startswith(prefix) for prefix in INTERESTING_PREFIXES)


def generate_port_forward_script(
    services: Iterable[KubernetesService],
    output_path: Path,
) -> Tuple[Set[int], List[str]]:
    """
    Gera um script de port-forward para serviços relevantes e retorna
    o conjunto de portas encaminhadas e a representação textual dos comandos.
    """
    services = [svc for svc in services if svc.ports and _is_interesting_service(svc)]
    commands: List[str] = []
    forwarded_ports: Set[int] = set()

    for service in services:
        for port in service.ports:
            forwarded_ports.add(port)
            commands.append(
                f"kubectl port-forward -n {service.namespace} svc/{service.name} {port}:{port} &"
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "#!/bin/bash",
        "",
        "# Script gerado automaticamente pelo Beagle para encaminhar serviços Darwin.",
        "set -euo pipefail",
        "",
    ]

    if commands:
        lines.extend(commands)
        lines.append("")
        lines.append("# Mantém os encaminhamentos ativos até interrupção manual (Ctrl+C).")
        lines.append("wait")
    else:
        lines.append(
            "# Nenhum serviço Kubernetes relevante foi identificado para port-forward."
        )

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    output_path.chmod(0o755)

    return forwarded_ports, commands


