from __future__ import annotations

import ast
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Set

_STDLIB_MODULES: Set[str] = {name.lower() for name in getattr(sys, "stdlib_module_names", set())}
_STDLIB_MODULES.update({"typing_extensions"})


@dataclass(slots=True)
class CodeSummary:
    """Resumo estrutural de um repositório analisado."""

    path: Path
    python_imports: Set[str] = field(default_factory=set)
    api_endpoints: List[str] = field(default_factory=list)
    node_dependencies: Dict[str, str] = field(default_factory=dict)


def _safe_read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def _extract_python_imports(file_path: Path, summary: CodeSummary) -> None:
    source = _safe_read_text(file_path)
    if not source:
        return
    try:
        tree = ast.parse(source, filename=str(file_path))
    except SyntaxError:
        return

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                module = alias.name.split(".")[0].lower()
                if not _is_stdlib_module(module):
                    summary.python_imports.add(module)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                module = node.module.split(".")[0].lower()
                if not _is_stdlib_module(module):
                    summary.python_imports.add(module)

        decorator = getattr(node, "decorator_list", None)
        if decorator:
            for deco in decorator:
                endpoint = _fastapi_endpoint_from_decorator(deco)
                if endpoint:
                    summary.api_endpoints.append(f"{endpoint} ({file_path})")


def _fastapi_endpoint_from_decorator(decorator: ast.AST) -> str | None:
    if isinstance(decorator, ast.Call):
        func = decorator.func
        if isinstance(func, ast.Attribute):
            if func.attr in {"get", "post", "put", "delete", "patch"}:
                if decorator.args and isinstance(decorator.args[0], ast.Str):
                    return f"{func.attr.upper()} {decorator.args[0].s}"
    return None


def _extract_fastapi_app(file_path: Path, summary: CodeSummary) -> None:
    source = _safe_read_text(file_path)
    if "FastAPI" not in source:
        return
    for line in source.splitlines():
        line = line.strip()
        if line.startswith("@"):
            continue
        if "FastAPI(" in line:
            summary.api_endpoints.append(f"FastAPI instance ({file_path})")
            break


def _extract_node_dependencies(repo_path: Path, summary: CodeSummary) -> None:
    package_json = repo_path / "package.json"
    if not package_json.is_file():
        return
    data = _safe_read_text(package_json)
    if not data:
        return
    try:
        payload = json.loads(data)
    except json.JSONDecodeError:
        return

    for section in ("dependencies", "devDependencies"):
        dependencies = payload.get(section, {})
        for name, version in dependencies.items():
            summary.node_dependencies[name] = version


def analyze_repository_code(repo_path: Path) -> CodeSummary:
    """Gera um CodeSummary para o repositório especificado."""
    summary = CodeSummary(path=repo_path)
    python_files = list(repo_path.rglob("*.py"))
    for file_path in python_files[:500]:
        _extract_python_imports(file_path, summary)
        _extract_fastapi_app(file_path, summary)

    _extract_node_dependencies(repo_path, summary)
    return summary


def analyze_codebases(paths: Iterable[Path]) -> List[CodeSummary]:
    """Coleta resumos de código para múltiplos diretórios base."""
    summaries: List[CodeSummary] = []
    for path in paths:
        if path.is_dir():
            summaries.append(analyze_repository_code(path))
    return summaries


def _is_stdlib_module(module: str) -> bool:
    if module.lower() in _STDLIB_MODULES:
        return True
    # Alguns módulos stdlib apresentam pontos ou submódulos específicos.
    return module.lower() in {"os", "sys", "json", "re", "pathlib", "subprocess", "logging"}

