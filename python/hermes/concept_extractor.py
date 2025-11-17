"""
Concept extraction using MLX-optimized models on M3 Max
"""
import mlx.core as mx
from mlx_lm import load, generate
from sentence_transformers import SentenceTransformer
import spacy
import re


# Load models globally (lazy initialization)
_llm = None
_tokenizer = None
_embedder = None
_nlp = None


def _ensure_models():
    global _llm, _tokenizer, _embedder, _nlp

    if _llm is None:
        # Load MLX-optimized LLM (Llama 3.3 70B 4-bit)
        _llm, _tokenizer = load("mlx-community/Llama-3.3-70B-4bit")

    if _embedder is None:
        # Load embedder (E5-base-v2)
        _embedder = SentenceTransformer("intfloat/e5-base-v2")

    if _nlp is None:
        # Load spaCy for NER
        try:
            _nlp = spacy.load("en_core_sci_md")  # SciSpacy model
        except OSError:
            # Fallback to standard English model
            _nlp = spacy.load("en_core_web_sm")


def extract_concepts(text: str) -> dict:
    """
    Extract concepts and entities from text.

    Returns:
        {"concepts": list[str], "entities": list[tuple[str, str, float]]}
    """
    _ensure_models()

    # 1. Use LLM to extract high-level concepts
    prompt = f"""Extract key scientific concepts from this text.
Return ONLY a Python list of concept names (3-5 words max each).

Text: {text}

Concepts (list format):"""

    response = generate(_llm, _tokenizer, prompt=prompt, max_tokens=100, temp=0.3)
    concepts = _parse_concept_list(response)

    # 2. Use spaCy NER for entities
    doc = _nlp(text)
    entities = [
        (ent.text, ent.label_, 1.0)  # text, type, confidence
        for ent in doc.ents
    ]

    return {
        "concepts": concepts,
        "entities": entities,
    }


def generate_embeddings(text: str) -> list[float]:
    """Generate semantic embeddings for text."""
    _ensure_models()

    # E5 requires "query: " prefix for queries
    embedding = _embedder.encode(f"query: {text}", normalize_embeddings=True)

    return embedding.tolist()


def _parse_concept_list(response: str) -> list[str]:
    """Parse LLM response to extract concept list."""
    # Try to find Python list notation
    match = re.search(r'\[([^\]]+)\]', response)
    if match:
        items_str = match.group(1)
        # Split by comma, strip quotes/whitespace
        concepts = [
            item.strip().strip('"').strip("'")
            for item in items_str.split(',')
        ]
        return concepts[:10]  # Max 10 concepts

    # Fallback: split by newlines
    lines = [line.strip() for line in response.split('\n') if line.strip()]
    return lines[:10]

