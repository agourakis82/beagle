from __future__ import annotations

from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

from discovery.code import CodeSummary
from discovery.repos import RepositoryInfo
from discovery.services import KubernetesService, ListeningPort, ServiceInfo
from validation.health import HealthCheckResult

INTERESTING_PREFIXES: Sequence[str] = ("darwin-", "pcs-", "hyperbolic-")


def _render_repository_section(repositories: Iterable[RepositoryInfo]) -> str:
    lines = ["## Repositórios Descobertos"]
    for repo in sorted(repositories, key=lambda r: r.name.lower()):
        description = repo.description or "Sem descrição"
        branch = repo.current_branch or "branch desconhecida"
        lines.append(f"- **{repo.name}** (`{repo.path}`) — {branch}. {description}")
    if len(lines) == 1:
        lines.append("- Nenhum repositório encontrado.")
    return "\n".join(lines)


def _render_services_section(services: Iterable[ServiceInfo]) -> str:
    lines = ["## Serviços Ativos"]
    services = list(services)
    if not services:
        lines.append("- Nenhum serviço detectado.")
        return "\n".join(lines)

    for service in services:
        ports = ", ".join(service.ports) if service.ports else "portas não detectadas"
        notes = f" — {service.notes}" if service.notes else ""
        ns = f"{service.platform}" + (f":{service.namespace}" if service.namespace else "")
        lines.append(f"- **{service.name}** [{ns}] — {service.status} — {ports}{notes}")
    return "\n".join(lines)


def _render_health_section(results: Iterable[HealthCheckResult]) -> str:
    lines = ["## Health Checks"]
    results = list(results)
    if not results:
        lines.append("- Nenhum health check configurado.")
        return "\n".join(lines)

    for result in results:
        icon = "✅" if result.ok else "❌"
        target = result.url or (f"porta {result.port}" if result.port else "–")
        code = result.status_code if result.status_code is not None else "–"
        error = f" — {result.error}" if result.error else ""
        lines.append(f"- {icon} **{result.name}** ({target}) → {code}{error}")
    return "\n".join(lines)


def _render_dependency_graph(
    repositories: Iterable[RepositoryInfo],
    summaries: Iterable[CodeSummary],
) -> str:
    lines = ["## Grafo de Dependências", "```mermaid", "graph TD"]
    repo_list = list(repositories)
    summaries = list(summaries)
    alias_map = _build_repo_alias_map(repo_list)
    nodes: Dict[str, str] = {}
    edges: Set[Tuple[str, str]] = set()

    for summary in summaries:
        source_repo = summary.path.name
        if not _is_interesting_repo(source_repo):
            continue
        source_id = _sanitize_node_id(source_repo)
        nodes[source_repo] = source_id
        for module in summary.python_imports:
            target_repo = alias_map.get(module.lower())
            if not target_repo or target_repo == source_repo:
                continue
            if not _is_interesting_repo(target_repo):
                continue
            target_id = _sanitize_node_id(target_repo)
            nodes[target_repo] = target_id
            edges.add((source_repo, target_repo))

    if not edges:
        lines.append('    Empty["Nenhum dado de dependência inter-repo"]')
        lines.append("```")
        return "\n".join(lines)

    for repo_name, node_id in sorted(nodes.items()):
        lines.append(f'    {node_id}["{repo_name}"]')
    for source, target in sorted(edges):
        lines.append(f"    {_sanitize_node_id(source)} --> {_sanitize_node_id(target)}")

    lines.append("```")
    return "\n".join(lines)


def _render_action_items(
    services: Iterable[ServiceInfo],
    health_results: Iterable[HealthCheckResult],
) -> str:
    lines = ["## Action Items"]
    actions: List[str] = []
    for service in services:
        if "CrashLoopBackOff" in service.status or "ImagePullBackOff" in service.status:
            actions.append(
                f"- {service.name}: {service.status} — verificar build ou imagem container."
            )
        elif "Exit" in service.status or "Exited" in service.status:
            actions.append(
                f"- {service.name}: processo finalizado — avaliar logs e reiniciar."
            )
        for issue in service.issues:
            actions.append(
                f"- {service.name}: {issue} — investigar causa raiz e restaurar workload."
            )
    for result in health_results:
        if not result.ok:
            actions.append(
                f"- {result.name}: health check falhou ({result.error or 'status não-OK'})."
            )
    if not actions:
        actions.append("- Nenhuma ação urgente identificada.")
    lines.extend(actions)
    return "\n".join(lines)


def _render_issues_section(
    services: Iterable[ServiceInfo],
    health_results: Iterable[HealthCheckResult],
    listening_ports: Dict[int, List[ListeningPort]],
) -> str:
    lines = ["## 🔥 Issues"]
    issues: List[str] = []
    open_ports = set(listening_ports.keys())
    seen: Set[str] = set()

    for service in services:
        status_lower = service.status.lower()
        if service.platform == "kubernetes" and any(
            marker in status_lower for marker in ("imagepullbackoff", "crashloop")
        ):
            entry = (
                "🔴 {name} [k8s]: {status}. Ação sugerida: inspecionar logs (`kubectl logs`) e revisar build da imagem.".format(
                    name=service.name,
                    status=service.status,
                )
            )
            if entry not in seen:
                seen.add(entry)
                issues.append(entry)
        elif service.platform == "docker" and status_lower.startswith("exited"):
            entry = (
                "🟡 {name} [docker]: container finalizado ({status}). Ação sugerida: `docker logs {name}` e reinstaurar o serviço.".format(
                    name=service.name,
                    status=service.status,
                )
            )
            if entry not in seen:
                seen.add(entry)
                issues.append(entry)
        elif service.platform == "kubernetes" and status_lower == "pending":
            entry = (
                "🟡 {name} [k8s]: Pending — verificar quota de recursos/affinity no cluster.".format(
                    name=service.name
                )
            )
            if entry not in seen:
                seen.add(entry)
                issues.append(entry)
        for issue in service.issues:
            severity = "🔴" if any(
                token in issue.lower() for token in ("crashloop", "imagepull")
            ) else "🟡"
            namespace = f"{service.namespace} / " if service.namespace else ""
            entry = (
                f"{severity} {namespace}{service.name}: {issue}. Ação sugerida: validar imagem, secrets e Eventos K8s."
            )
            if entry not in seen:
                seen.add(entry)
                issues.append(entry)

    for result in health_results:
        if result.ok:
            continue
        target = result.url or (f"porta {result.port}" if result.port else "alvo")
        severity = "🔴" if result.port is None or result.port not in open_ports else "🟡"
        detail = result.error or "status não-OK"
        remediation = "validar disponibilidade do serviço correspondente e reativar listener."
        if result.port and result.port not in open_ports:
            remediation = (
                f"porta {result.port} não está escutando — subir serviço responsável."
            )
        issues.append(
            f"{severity} {result.name}: {target} indisponível ({detail}). Ação sugerida: {remediation}"
        )

    if not issues:
        lines.append("- Nenhuma issue crítica identificada.")
    else:
        lines.extend(f"- {issue}" for issue in issues)
    return "\n".join(lines)


def generate_markdown_report(
    repositories: Iterable[RepositoryInfo],
    services: Iterable[ServiceInfo],
    code_summaries: Iterable[CodeSummary],
    health_results: Iterable[HealthCheckResult],
    listening_ports: Dict[int, List[ListeningPort]],
    kubernetes_services: Iterable[KubernetesService],
    port_forward_script: Optional[Path],
    port_forward_commands: Iterable[str],
    output_path: Optional[Path] = None,
) -> str:
    repositories = list(repositories)
    services = list(services)
    code_summaries = list(code_summaries)
    health_results = list(health_results)
    kubernetes_services = list(kubernetes_services)
    port_forward_commands = list(port_forward_commands)

    sections = [
        "# Beagle Architecture Report",
        _render_issues_section(services, health_results, listening_ports),
        _render_repository_section(repositories),
        _render_services_section(services),
        _render_dependency_graph(repositories, code_summaries),
        _render_health_section(health_results),
        _render_action_items(services, health_results),
        _render_port_forward_section(
            kubernetes_services,
            port_forward_script,
            port_forward_commands,
        ),
    ]

    report = "\n\n".join(sections) + "\n"

    if output_path:
        try:
            output_path.write_text(report, encoding="utf-8")
        except OSError as exc:
            raise RuntimeError(f"Não foi possível escrever o relatório: {exc}") from exc

    return report


def _build_repo_alias_map(
    repositories: Iterable[RepositoryInfo],
) -> Dict[str, str]:
    alias_map: Dict[str, str] = {}
    for repo in repositories:
        name = repo.name
        aliases = {
            name,
            name.replace("-", "_"),
            name.replace("-", ""),
        }
        for alias in aliases:
            alias_map[alias.lower()] = name
    return alias_map


def _is_interesting_repo(repo_name: str) -> bool:
    return repo_name.startswith(tuple(INTERESTING_PREFIXES))


def _sanitize_node_id(repo_name: str) -> str:
    return repo_name.replace("-", "_").replace(".", "_")


def _render_port_forward_section(
    services: Iterable[KubernetesService],
    script_path: Optional[Path],
    commands: Iterable[str],
) -> str:
    lines = ["## Port Forward Script"]
    if not services:
        lines.append("- Nenhum serviço Kubernetes com portas expostas encontrado.")
        return "\n".join(lines)

    script_reference = f"{script_path}" if script_path else "scripts/port-forward-darwin.sh"
    lines.append(f"- Script gerado: `{script_reference}`")
    if commands:
        lines.append("- Encaminhamentos configurados:")
        for command in commands:
            lines.append(f"  - `{command}`")
    else:
        lines.append("- Não há comandos válidos para encaminhar portas no momento.")
    return "\n".join(lines)

