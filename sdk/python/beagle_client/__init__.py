"""
BEAGLE Python Client SDK
Unified interface for BEAGLE services
"""

from .client import BeagleClient
from .models import Paper, Draft, Interaction

__version__ = "0.1.0"
__all__ = ["BeagleClient", "Paper", "Draft", "Interaction"]


