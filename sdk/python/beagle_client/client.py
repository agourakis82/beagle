"""
BEAGLE Client - Main interface
"""

import requests
from typing import List, Optional, Dict
from .models import Paper, Draft


class BeagleClient:
    """Main BEAGLE client"""

    def __init__(
        self,
        vllm_url: str = "http://localhost:8000",
        postgres_dsn: str = "postgresql://beagle:beagle_secure_2025@localhost:5432/beagle",
        qdrant_url: str = "http://localhost:6333",
    ):
        self.vllm_url = vllm_url
        self.postgres_dsn = postgres_dsn
        self.qdrant_url = qdrant_url

    def generate_text(
        self,
        prompt: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
        model: Optional[str] = None,
    ) -> str:
        """Generate text using vLLM"""
        # Usar modelo padrão estável se não for passado explicitamente
        if model is None:
            model = "mistralai/Mistral-7B-Instruct-v0.2"
        payload = {
            "model": model,
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        response = requests.post(
            f"{self.vllm_url}/v1/completions",
            json=payload,
            timeout=60,
        )
        response.raise_for_status()
        return response.json()["choices"][0]["text"]

    def generate_draft(
        self,
        section_type: str,
        context: str,
        max_tokens: int = 1024,
    ) -> Draft:
        """Generate manuscript section draft"""
        prompt = f"""Write a {section_type} section for a scientific paper.

Context:
{context}

{section_type.upper()}:"""
        content = self.generate_text(prompt, max_tokens=max_tokens)
        return Draft(
            section_type=section_type,
            content=content.strip(),
            metadata={"context": context},
        )

    def search_papers(
        self,
        query: str,
        limit: int = 10,
    ) -> List[Dict]:
        """Search papers in Qdrant (future implementation)"""
        # TODO: Implement vector search
        return []

    def health_check(self) -> Dict[str, bool]:
        """Check health of all services"""
        health: Dict[str, bool] = {}
        # vLLM: alguns builds não expõem /health ou /v1/models de forma estável.
        # Consideramos UP se a raiz responde (mesmo 404).
        try:
            resp = requests.get(self.vllm_url.rstrip("/") + "/", timeout=5)
            health["vllm"] = resp.status_code < 500
        except Exception:
            health["vllm"] = False
        # Qdrant
        try:
            resp = requests.get(f"{self.qdrant_url}/healthz", timeout=5)
            health["qdrant"] = resp.status_code == 200
        except Exception:
            health["qdrant"] = False
        # PostgreSQL
        try:
            import psycopg2

            conn = psycopg2.connect(self.postgres_dsn)
            conn.close()
            health["postgres"] = True
        except Exception:
            health["postgres"] = False
        return health


