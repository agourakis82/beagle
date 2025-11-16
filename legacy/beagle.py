from __future__ import annotations

import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Set, Tuple

import typer
import yaml

from discovery.code import CodeSummary, analyze_repository_code
from discovery.repos import RepositoryInfo, discover_repositories
from discovery.services import ServiceInventory, discover_services
from output.report_generator import generate_markdown_report
from output.scripts import generate_port_forward_script
from validation.health import HealthCheck, HealthCheckResult, run_health_checks

app = typer.Typer(help="Beagle — mapeamento automático do ecossistema Darwin.")

DEFAULT_PORT_CHECKS: List[int] = [8090, 8091, 8093, 6333, 11434]


def _default_config_path() -> Path:
    return Path(__file__).resolve().parent / "config.yaml"


def load_config(path: Path | None = None) -> Dict[str, Any]:
    config_path = path or _default_config_path()
    if not config_path.is_file():
        raise FileNotFoundError(f"Arquivo de configuração não encontrado: {config_path}")
    with config_path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def _get_root_paths(config: Dict[str, Any]) -> List[Path]:
    raw_paths = config.get("paths", [])
    return [Path(p).expanduser().resolve() for p in raw_paths]


def _scan_repositories(root_paths: Iterable[Path]) -> List[RepositoryInfo]:
    typer.echo("→ Descobrindo repositórios Git...")
    repos = discover_repositories(root_paths)
    typer.echo(f"   {len(repos)} repositórios encontrados.")
    return repos


def _scan_services() -> ServiceInventory:
    typer.echo("→ Inspecionando serviços (Docker/Kubernetes/processos)...")
    inventory = discover_services()
    typer.echo(f"   {len(inventory.services)} serviços detectados.")
    return inventory


def _scan_code(repositories: Iterable[RepositoryInfo]) -> List[CodeSummary]:
    typer.echo("→ Analisando dependências de código...")
    summaries: List[CodeSummary] = []
    for repo in repositories:
        summaries.append(analyze_repository_code(repo.path))
    typer.echo("   Análise concluída.")
    return summaries


def _assemble_health_checks(config: Dict[str, Any]) -> List[HealthCheck]:
    checks_config = config.get("health_checks", [])
    checks: List[HealthCheck] = []
    registered_ports: Set[int] = set()

    for entry in checks_config:
        name = entry.get("name")
        url = entry.get("url")
        port = entry.get("port")
        host = entry.get("host", "localhost")
        expect_http = entry.get("expect_http", True)

        if not name:
            continue

        if url:
            checks.append(HealthCheck(name=name, url=url))
            continue

        if port is not None:
            try:
                port_value = int(port)
            except ValueError:
                continue
            registered_ports.add(port_value)
            checks.append(
                HealthCheck(
                    name=name,
                    host=host,
                    port=port_value,
                    expect_http=expect_http,
                )
            )

    for port in DEFAULT_PORT_CHECKS:
        if port in registered_ports:
            continue
        checks.append(
            HealthCheck(
                name=f"Porta {port}",
                host="localhost",
                port=port,
                expect_http=True,
            )
        )

    return checks


def _run_health_checks(config: Dict[str, Any]) -> List[HealthCheckResult]:
    checks = _assemble_health_checks(config)
    if not checks:
        typer.echo("→ Nenhum health check configurado.")
        return []
    typer.echo(f"→ Executando {len(checks)} health checks...")
    results = run_health_checks(checks)
    for result in results:
        status = "OK" if result.ok else "FALHA"
        typer.echo(f"   {result.name}: {status}")
    return results


def _ensure_port_forward_script(
    kubernetes_services: Iterable,
) -> Tuple[Path, Set[int], List[str]]:
    script_path = Path(__file__).resolve().parent / "scripts" / "port-forward-darwin.sh"
    forwarded_ports, commands = generate_port_forward_script(kubernetes_services, script_path)
    return script_path, forwarded_ports, commands


@app.command()
def scan(config: Path = typer.Option(None, "--config", "-c", help="Caminho para config.yaml")) -> None:
    """Executa descoberta completa e imprime um sumário."""
    try:
        config_data = load_config(config)
    except FileNotFoundError as exc:
        typer.secho(str(exc), fg=typer.colors.RED)
        raise typer.Exit(code=1) from exc

    root_paths = _get_root_paths(config_data)
    repositories = _scan_repositories(root_paths)
    inventory = _scan_services()
    code_summaries = _scan_code(repositories)
    health_results = _run_health_checks(config_data)
    script_path, forwarded_ports, commands = _ensure_port_forward_script(
        inventory.kubernetes_services
    )

    typer.echo("\nResumo Beagle:")
    typer.echo(f"- Repositórios: {len(repositories)}")
    typer.echo(f"- Serviços monitorados: {len(inventory.services)}")
    typer.echo(f"- Health checks executados: {len(health_results)}")
    typer.echo(f"- Resumos de código: {len(code_summaries)}")
    if forwarded_ports:
        typer.echo(
            f"- Port-forward sugerido ({len(forwarded_ports)} portas): {script_path}"
        )
        typer.echo(f"  Comandos gerados: {len(commands)}")


@app.command()
def check(config: Path = typer.Option(None, "--config", "-c", help="Caminho para config.yaml")) -> None:
    """Executa apenas validações de runtime (health checks HTTP/TCP)."""
    try:
        config_data = load_config(config)
    except FileNotFoundError as exc:
        typer.secho(str(exc), fg=typer.colors.RED)
        raise typer.Exit(code=1) from exc

    results = _run_health_checks(config_data)
    if any(result.ok is False for result in results):
        raise typer.Exit(code=2)


@app.command()
def report(
    config: Path = typer.Option(None, "--config", "-c", help="Caminho para config.yaml"),
    output: Path = typer.Option(None, "--output", "-o", help="Destino do relatório"),
) -> None:
    """Gera o relatório ARCHITECTURE.md consolidando a descoberta."""
    try:
        config_data = load_config(config)
    except FileNotFoundError as exc:
        typer.secho(str(exc), fg=typer.colors.RED)
        raise typer.Exit(code=1) from exc

    root_paths = _get_root_paths(config_data)
    repositories = _scan_repositories(root_paths)
    inventory = _scan_services()
    code_summaries = _scan_code(repositories)
    health_results = _run_health_checks(config_data)
    script_path, forwarded_ports, commands = _ensure_port_forward_script(
        inventory.kubernetes_services
    )

    output_path = output or Path(config_data.get("report", {}).get("output_path", "ARCHITECTURE.md"))
    output_path = output_path if output_path.is_absolute() else Path.cwd() / output_path
    typer.echo(f"→ Gerando relatório em {output_path}...")
    generate_markdown_report(
        repositories=repositories,
        services=inventory.services,
        code_summaries=code_summaries,
        health_results=health_results,
        listening_ports=inventory.listening_ports,
        kubernetes_services=inventory.kubernetes_services,
        port_forward_script=script_path,
        port_forward_commands=commands,
        output_path=output_path,
    )
    typer.secho("Relatório gerado com sucesso.", fg=typer.colors.GREEN)


@app.command()
def fix(
    config: Path = typer.Option(None, "--config", "-c", help="Caminho para config.yaml"),
) -> None:
    """
    Executa o script de port-forward gerado, espera estabilização, revalida health checks
    e informa sucesso ou falha.
    """
    try:
        config_data = load_config(config)
    except FileNotFoundError as exc:
        typer.secho(str(exc), fg=typer.colors.RED)
        raise typer.Exit(code=1) from exc

    inventory = _scan_services()
    script_path, forwarded_ports, commands = _ensure_port_forward_script(
        inventory.kubernetes_services
    )

    if not forwarded_ports:
        typer.echo("Nenhum serviço Kubernetes relevante para encaminhar portas.")
        raise typer.Exit(code=0)

    typer.echo(f"→ {len(commands)} comandos de port-forward identificados.")
    typer.echo(f"→ Executando port-forward script: {script_path}")
    success = False
    try:
        process = subprocess.Popen(
            [str(script_path)],
            cwd=script_path.parent,
        )
    except OSError as exc:
        typer.secho(f"Falha ao executar script: {exc}", fg=typer.colors.RED)
        raise typer.Exit(code=2) from exc

    try:
        time.sleep(5)
        typer.echo("→ Validando portas encaminhadas...")
        refreshed_inventory = discover_services()
        open_ports = set(refreshed_inventory.listening_ports.keys())
        missing_ports = sorted(port for port in forwarded_ports if port not in open_ports)

        health_results = _run_health_checks(config_data)
        success_health = all(result.ok for result in health_results)

        if missing_ports:
            typer.secho(
                f"Portas ausentes após port-forward: {', '.join(map(str, missing_ports))}",
                fg=typer.colors.RED,
            )
        else:
            typer.echo("   Todas as portas esperadas estão ouvindo localmente.")

        if success_health and not missing_ports:
            typer.secho(
                "🎯 Port-forward estabelecido e health checks OK.",
                fg=typer.colors.GREEN,
            )
            typer.echo("Os túneis permanecerão ativos; use Ctrl+C para encerrar.")
            success = True
        else:
            typer.secho("⚠️ Port-forward não estabilizou completamente.", fg=typer.colors.YELLOW)
            raise typer.Exit(code=3)
    except KeyboardInterrupt:
        typer.echo("Interrompido pelo usuário; finalizando port-forward.")
        raise typer.Exit(code=130)
    finally:
        if not success and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def main() -> None:
    app()


if __name__ == "__main__":
    main()

