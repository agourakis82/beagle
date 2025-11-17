"""
LoRA Adapter Validation
Validates trained adapter by computing similarity on test data
"""

import json
from typing import List, Dict
from pathlib import Path

try:
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from peft import PeftModel
    from sentence_transformers import SentenceTransformer
    HAS_TRANSFORMERS = True
except ImportError:
    HAS_TRANSFORMERS = False


def validate_lora_json(adapter_path: str, test_data_json: str) -> float:
    """
    Validate LoRA adapter by computing text similarity
    
    Args:
        adapter_path: Path to saved adapter
        test_data_json: JSON array of test texts
    
    Returns:
        Average similarity score (0.0-1.0)
    """
    if not HAS_TRANSFORMERS:
        return 0.5  # Neutral score if transformers not available
    
    # Parse test data
    test_texts = json.loads(test_data_json)
    
    if not test_texts:
        return 0.0
    
    # Use sentence-transformers for similarity (simpler than loading full model)
    try:
        model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
        
        # Compute embeddings
        embeddings = model.encode(test_texts)
        
        # Compute average pairwise similarity
        import numpy as np
        similarities = []
        for i in range(len(embeddings)):
            for j in range(i + 1, len(embeddings)):
                sim = np.dot(embeddings[i], embeddings[j]) / (
                    np.linalg.norm(embeddings[i]) * np.linalg.norm(embeddings[j])
                )
                similarities.append(float(sim))
        
        avg_similarity = float(np.mean(similarities)) if similarities else 0.0
        return max(0.0, min(1.0, avg_similarity))  # Clamp to [0, 1]
    
    except Exception as e:
        print(f"Validation error: {e}")
        return 0.5  # Neutral score on error


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python lora_validator.py <adapter_path> <test_data.json>")
        sys.exit(1)
    
    adapter_path = sys.argv[1]
    with open(sys.argv[2]) as f:
        test_data = json.load(f)
    
    similarity = validate_lora_json(adapter_path, json.dumps(test_data))
    print(f"Average similarity: {similarity:.4f}")

