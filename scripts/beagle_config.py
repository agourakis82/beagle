#!/usr/bin/env python3
"""
BEAGLE Configuration Module for Python
Centralized configuration management respecting SAFE_MODE and BEAGLE_DATA_DIR
"""

import os
from pathlib import Path
from typing import Optional


def _bool_env(name: str, default: bool) -> bool:
    """Helper para ler variáveis de ambiente booleanas."""
    val = os.getenv(name)
    if val is None:
        return default
    val = val.strip().lower()
    return val in ("1", "true", "t", "yes", "y")


def safe_mode() -> bool:
    """
    Verifica se SAFE_MODE está ativo (default: True).
    
    Quando ativo:
    - Nenhuma publicação real será feita (arXiv, Twitter, etc.)
    - Ações críticas são logadas mas não executadas
    """
    return _bool_env("BEAGLE_SAFE_MODE", True)


def beagle_data_dir() -> Path:
    """
    Retorna o diretório base de dados do BEAGLE.
    
    Ordem de prioridade:
    1. Variável de ambiente BEAGLE_DATA_DIR
    2. ~/beagle-data (padrão)
    """
    if "BEAGLE_DATA_DIR" in os.environ:
        return Path(os.environ["BEAGLE_DATA_DIR"])
    return Path.home() / "beagle-data"


def data_dir() -> Path:
    """Alias para beagle_data_dir()."""
    return beagle_data_dir()


def models_dir() -> Path:
    """Path para modelos LLM."""
    return beagle_data_dir() / "models"


def logs_dir() -> Path:
    """Path para logs."""
    return beagle_data_dir() / "logs"


def papers_drafts_dir() -> Path:
    """Path para drafts de papers."""
    return beagle_data_dir() / "papers" / "drafts"


def papers_final_dir() -> Path:
    """Path para papers finais."""
    return beagle_data_dir() / "papers" / "final"


def vllm_url() -> str:
    """URL do servidor vLLM (default: http://t560.local:8000)."""
    return os.getenv("BEAGLE_VLLM_URL", "http://t560.local:8000")


def arxiv_token() -> Optional[str]:
    """Token da API arXiv (opcional)."""
    return os.getenv("ARXIV_API_TOKEN")


def publish_mode() -> str:
    """
    Retorna o modo de publicação atual.
    
    Valores:
    - "dry" (default) - nunca chama API real
    - "manual" - exige confirmação humana
    - "auto" - permite publicação automática (só se safe_mode() == False)
    """
    mode = os.getenv("BEAGLE_PUBLISH_MODE", "dry").lower().strip()
    if mode not in ("dry", "manual", "auto"):
        return "dry"
    return mode


def can_publish_real() -> bool:
    """
    Verifica se publicação real é permitida.
    
    Retorna True apenas se:
    - safe_mode() == False
    - E publish_mode() == "auto"
    """
    return not safe_mode() and publish_mode() == "auto"


# Exemplo de uso em funções de publicação
def publish_paper(paper_title: str, paper_content: str, dry_run_override: bool = False) -> bool:
    """
    Exemplo de função de publicação que respeita SAFE_MODE.
    
    Args:
        paper_title: Título do paper
        paper_content: Conteúdo do paper
        dry_run_override: Força dry-run mesmo se config permitir publicação
    
    Returns:
        True se publicado (ou simulado), False se bloqueado
    """
    if safe_mode() or dry_run_override:
        print(f"SAFE_MODE/dry-run: não vou enviar paper real, apenas salvar plano.")
        plan_path = papers_drafts_dir() / f"{paper_title.replace(' ', '_')}_plan.json"
        plan_path.parent.mkdir(parents=True, exist_ok=True)
        with open(plan_path, "w") as f:
            f.write(f'{{"title": "{paper_title}", "mode": "dry-run"}}')
        print(f"Plano salvo em: {plan_path}")
        return False
    
    if not can_publish_real():
        print(f"Publicação bloqueada: safe_mode={safe_mode()}, publish_mode={publish_mode()}")
        return False
    
    # Aqui iria a chamada real da API arXiv
    print(f"Publicando paper: {paper_title}")
    return True


if __name__ == "__main__":
    # Testes básicos
    print(f"SAFE_MODE: {safe_mode()}")
    print(f"Data dir: {beagle_data_dir()}")
    print(f"Models dir: {models_dir()}")
    print(f"Publish mode: {publish_mode()}")
    print(f"Can publish real: {can_publish_real()}")

