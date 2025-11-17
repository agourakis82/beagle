"""
Concept Extraction Pipeline using spaCy + Transformers
Extracts named entities, key phrases, and domain-specific concepts
"""

import spacy
from typing import List, Dict, Any
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
import numpy as np

class Concept(BaseModel):
    """Extracted concept with metadata"""
    text: str
    type: str  # ENTITY, KEYPHRASE, TECHNICAL_TERM
    confidence: float
    embedding: List[float]

class ConceptExtractor:
    def __init__(self, model_name: str = "en_core_web_sm"):
        """Initialize spaCy + sentence-transformers"""
        self.nlp = spacy.load(model_name)
        self.embedding_model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
        
        # Domain-specific patterns for biomaterials, PBPK, neuroscience
        self.domain_patterns = [
            {"label": "BIOMATERIAL", "pattern": [{"LOWER": {"IN": ["collagen", "chitosan", "hydrogel", "scaffold"]}}]},
            {"label": "PBPK_TERM", "pattern": [{"LOWER": {"IN": ["clearance", "auc", "cmax", "vd", "ke"]}}]},
            {"label": "NEURO_TERM", "pattern": [{"LOWER": {"IN": ["synapse", "neurotransmitter", "amygdala", "cortex"]}}]},
        ]
        
        ruler = self.nlp.add_pipe("entity_ruler", before="ner")
        ruler.add_patterns(self.domain_patterns)
    
    def extract_concepts(self, text: str) -> List[Concept]:
        """Extract concepts from text"""
        doc = self.nlp(text)
        concepts = []
        
        # 1. Named Entities
        for ent in doc.ents:
            embedding = self.embedding_model.encode(ent.text).tolist()
            concepts.append(Concept(
                text=ent.text,
                type=f"ENTITY_{ent.label_}",
                confidence=0.9,  # spaCy entities are high confidence
                embedding=embedding,
            ))
        
        # 2. Noun Chunks (key phrases)
        for chunk in doc.noun_chunks:
            if len(chunk.text.split()) >= 2:  # Multi-word phrases only
                embedding = self.embedding_model.encode(chunk.text).tolist()
                concepts.append(Concept(
                    text=chunk.text,
                    type="KEYPHRASE",
                    confidence=0.7,
                    embedding=embedding,
                ))
        
        # 3. Technical terms (capitalized multi-word)
        for token in doc:
            if token.is_alpha and token.is_title and not token.is_stop:
                # Check if part of multi-word technical term
                if token.i + 1 < len(doc) and doc[token.i + 1].is_title:
                    term = doc[token.i:token.i + 2].text
                    embedding = self.embedding_model.encode(term).tolist()
                    concepts.append(Concept(
                        text=term,
                        type="TECHNICAL_TERM",
                        confidence=0.8,
                        embedding=embedding,
                    ))
        
        # Deduplicate by text (keep highest confidence)
        unique_concepts = {}
        for concept in concepts:
            key = concept.text.lower()
            if key not in unique_concepts or concept.confidence > unique_concepts[key].confidence:
                unique_concepts[key] = concept
        
        return list(unique_concepts.values())

def extract_concepts_json(text: str) -> str:
    """Python entry point for Rust FFI"""
    extractor = ConceptExtractor()
    concepts = extractor.extract_concepts(text)
    return [c.model_dump() for c in concepts]

# CLI for testing
if __name__ == "__main__":
    import sys
    text = sys.argv[1] if len(sys.argv) > 1 else "KEC entropy affects collagen scaffold degradation in neural tissue engineering."
    
    extractor = ConceptExtractor()
    concepts = extractor.extract_concepts(text)
    
    print(f"\n🧠 Extracted {len(concepts)} concepts:\n")
    for c in concepts:
        print(f"  • {c.text} ({c.type}, confidence: {c.confidence:.2f})")
