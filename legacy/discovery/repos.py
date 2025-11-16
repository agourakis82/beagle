from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass(slots=True)
class RepositoryInfo:
    """Representa um repositório Git descoberto no filesystem."""

    name: str
    path: Path
    current_branch: Optional[str]
    description: Optional[str]


def _is_git_repository(path: Path) -> bool:
    return (path / ".git").is_dir()


def _get_current_branch(path: Path) -> Optional[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--abbrev-ref", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        branch = result.stdout.strip()
        return branch if branch and branch != "HEAD" else None
    except (subprocess.SubprocessError, FileNotFoundError):
        return None


def _get_description(path: Path) -> Optional[str]:
    readme = path / "README.md"
    if not readme.is_file():
        return None

    try:
        with readme.open("r", encoding="utf-8") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped:
                    return stripped
    except OSError:
        return None
    return None


def discover_repositories(root_paths: Iterable[Path]) -> List[RepositoryInfo]:
    """Localiza repositórios Git a partir dos diretórios raiz informados."""
    repositories: List[RepositoryInfo] = []
    for root in root_paths:
        if not root.exists():
            continue
        for candidate in root.rglob(".git"):
            repo_path = candidate.parent
            repositories.append(
                RepositoryInfo(
                    name=repo_path.name,
                    path=repo_path,
                    current_branch=_get_current_branch(repo_path),
                    description=_get_description(repo_path),
                )
            )
    return repositories


