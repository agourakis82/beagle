"""
BEAGLE Data Models
"""

from dataclasses import dataclass
from typing import List, Optional, Dict
from datetime import datetime


@dataclass
class Paper:
    """Paper metadata"""
    id: Optional[str] = None
    title: str = ""
    authors: List[str] = None
    abstract: Optional[str] = None
    doi: Optional[str] = None
    publication_date: Optional[datetime] = None
    journal: Optional[str] = None
    citation_count: int = 0

    def __post_init__(self):
        if self.authors is None:
            self.authors = []


@dataclass
class Draft:
    """Generated draft section"""
    section_type: str
    content: str
    metadata: Dict = None
    version: int = 1

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}


@dataclass
class Interaction:
    """User interaction record"""
    user_prompt: str
    model_response: str
    user_edit: Optional[str] = None
    feedback_score: Optional[int] = None
    context: Dict = None

    def __post_init__(self):
        if self.context is None:
            self.context = {}


