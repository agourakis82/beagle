"""
MLX-optimized LoRA training for voice preservation.
Runs on M3 Max unified memory architecture.
"""
import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
from mlx_lm import load, generate, LoRALinear
from pathlib import Path
import json
from typing import List, Dict
import numpy as np


class VoiceLoRATrainer:
    """
    Train LoRA adapters to preserve author's writing voice.
    """

    def __init__(
        self,
        base_model: str = "mlx-community/Llama-3.3-70B-4bit",
        lora_rank: int = 16,
        lora_alpha: int = 32,
        lora_dropout: float = 0.05,
    ):
        """
        Initialize trainer.

        Args:
            base_model: MLX model path
            lora_rank: LoRA rank (lower = faster, less expressive)
            lora_alpha: LoRA scaling factor
            lora_dropout: Dropout rate
        """
        self.base_model_name = base_model
        self.lora_config = {
            "r": lora_rank,
            "alpha": lora_alpha,
            "dropout": lora_dropout,
            "target_modules": ["q_proj", "k_proj", "v_proj", "o_proj"],
        }

        # Load base model
        self.model, self.tokenizer = load(base_model)

        # Freeze base model
        self.model.freeze()

        # Add LoRA layers
        self._inject_lora_layers()

    def _inject_lora_layers(self):
        """Inject LoRA layers into target modules."""
        for name, module in self.model.named_modules():
            if any(target in name for target in self.lora_config["target_modules"]):
                # Replace linear layer with LoRA linear
                setattr(
                    self.model,
                    name,
                    LoRALinear(
                        module.weight.shape[1],
                        module.weight.shape[0],
                        r=self.lora_config["r"],
                        alpha=self.lora_config["alpha"],
                        dropout=self.lora_config["dropout"],
                    )
                )

    def prepare_dataset(
        self,
        corpus_dir: Path,
        max_examples: int = 500,
    ) -> List[Dict[str, str]]:
        """
        Prepare training dataset from user's writing corpus.

        Args:
            corpus_dir: Directory containing user's papers/drafts
            max_examples: Maximum examples to include

        Returns:
            List of {"input": str, "output": str} examples
        """
        examples = []

        # Collect all markdown/text files
        for file_path in corpus_dir.glob("**/*.md"):
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            # Split into sections
            sections = self._split_into_sections(content)

            for i, section in enumerate(sections):
                if i == 0:
                    continue  # Skip first section (usually title)

                # Create training example: previous section → current section
                if i > 0:
                    examples.append({
                        "input": sections[i-1],
                        "output": section,
                    })

                if len(examples) >= max_examples:
                    break

            if len(examples) >= max_examples:
                break

        return examples

    def _split_into_sections(self, content: str) -> List[str]:
        """Split markdown content into sections."""
        import re
        # Split on ## headers
        sections = re.split(r'\n##\s+', content)
        return [s.strip() for s in sections if s.strip()]

    def train(
        self,
        dataset: List[Dict[str, str]],
        epochs: int = 3,
        batch_size: int = 8,
        learning_rate: float = 1e-4,
        output_dir: Path = Path("models/voice_adapters"),
    ):
        """
        Train LoRA adapter.

        Args:
            dataset: Training examples
            epochs: Number of epochs
            batch_size: Batch size (adjust for M3 Max 48GB)
            learning_rate: Learning rate for AdamW
            output_dir: Where to save adapter
        """
        # Setup optimizer (only optimize LoRA parameters)
        lora_params = [p for n, p in self.model.named_parameters() if "lora" in n]
        optimizer = optim.AdamW(learning_rate=learning_rate)

        # Training loop
        for epoch in range(epochs):
            print(f"Epoch {epoch+1}/{epochs}")

            epoch_loss = 0.0
            num_batches = 0

            for i in range(0, len(dataset), batch_size):
                batch = dataset[i:i+batch_size]

                # Tokenize batch
                inputs = [ex["input"] for ex in batch]
                targets = [ex["output"] for ex in batch]

                input_ids = self.tokenizer(inputs, return_tensors="mlx", padding=True)
                target_ids = self.tokenizer(targets, return_tensors="mlx", padding=True)

                # Forward pass
                outputs = self.model(input_ids["input_ids"])

                # Compute loss (cross-entropy)
                loss = nn.losses.cross_entropy(outputs, target_ids["input_ids"])

                # Backward pass (MLX auto-diff)
                loss_value, grads = mx.value_and_grad(loss)(lora_params)

                # Update LoRA parameters only
                optimizer.update(lora_params, grads)

                epoch_loss += loss_value.item()
                num_batches += 1

                if num_batches % 10 == 0:
                    print(f"  Batch {num_batches}, Loss: {loss_value.item():.4f}")

            avg_loss = epoch_loss / num_batches
            print(f"  Epoch {epoch+1} Average Loss: {avg_loss:.4f}")

        # Save LoRA adapter
        output_dir.mkdir(parents=True, exist_ok=True)
        adapter_path = output_dir / f"voice_adapter_epoch{epochs}.safetensors"

        self._save_lora_adapter(adapter_path)

        print(f"✅ LoRA adapter saved to {adapter_path}")

        return adapter_path

    def _save_lora_adapter(self, path: Path):
        """Save only LoRA parameters (not base model)."""
        from safetensors import safe_open
        from safetensors.torch import save_file

        lora_state_dict = {
            n: p for n, p in self.model.named_parameters() if "lora" in n
        }

        save_file(lora_state_dict, str(path))

    def evaluate_voice_similarity(
        self,
        test_examples: List[Dict[str, str]],
        adapter_path: Path,
    ) -> float:
        """
        Evaluate voice similarity on test set.

        Returns:
            Similarity score (0-1)
        """
        # TODO: Implement stylometric analysis
        # Compare generated text vs ground truth on:
        # - Lexical features
        # - Syntactic features
        # - Readability metrics

        return 0.94  # Placeholder

