"""
LoRA Training using HuggingFace PEFT
Called from Rust via PyO3
"""

import json
import time
from pathlib import Path
from typing import List, Dict, Any
from pydantic import BaseModel

try:
    from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments, Trainer
    from peft import LoraConfig, get_peft_model, TaskType
    from datasets import Dataset
    HAS_TRANSFORMERS = True
except ImportError:
    HAS_TRANSFORMERS = False
    print("Warning: transformers/peft not installed. LoRA training will not work.")


class TrainingResult(BaseModel):
    adapter_path: str
    loss_history: List[float]
    final_loss: float
    training_time_seconds: float


def train_lora_json(
    base_model: str,
    training_data_json: str,
    output_path: str,
    rank: int = 8,
    alpha: int = 16,
    dropout: float = 0.1,
    learning_rate: float = 2e-4,
    batch_size: int = 4,
    num_epochs: int = 3,
) -> Dict[str, Any]:
    """
    Train LoRA adapter on personal corpus
    
    Args:
        base_model: HuggingFace model ID (e.g., "microsoft/DialoGPT-small")
        training_data_json: JSON array of training texts
        output_path: Where to save the adapter
        rank: LoRA rank
        alpha: LoRA alpha
        dropout: Dropout rate
        learning_rate: Learning rate
        batch_size: Batch size
        num_epochs: Number of training epochs
    
    Returns:
        TrainingResult as dict
    """
    if not HAS_TRANSFORMERS:
        raise ValueError("transformers/peft not installed. Install with: pip install transformers peft datasets")
    
    start_time = time.time()
    
    # Parse training data
    training_texts = json.loads(training_data_json)
    
    # Load model and tokenizer
    print(f"Loading model: {base_model}")
    tokenizer = AutoTokenizer.from_pretrained(base_model)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    
    model = AutoModelForCausalLM.from_pretrained(base_model)
    
    # Configure LoRA
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=rank,
        lora_alpha=alpha,
        lora_dropout=dropout,
        target_modules=["q_proj", "v_proj"],  # Common for GPT models
    )
    
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()
    
    # Prepare dataset
    def tokenize_function(examples):
        return tokenizer(
            examples["text"],
            truncation=True,
            padding="max_length",
            max_length=512,
        )
    
    dataset = Dataset.from_dict({"text": training_texts})
    tokenized_dataset = dataset.map(tokenize_function, batched=True)
    
    # Training arguments
    training_args = TrainingArguments(
        output_dir=str(output_path),
        num_train_epochs=num_epochs,
        per_device_train_batch_size=batch_size,
        learning_rate=learning_rate,
        logging_steps=10,
        save_strategy="epoch",
    )
    
    # Trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=tokenized_dataset,
    )
    
    # Train
    print("Starting training...")
    train_result = trainer.train()
    
    # Save adapter
    adapter_path = Path(output_path) / "adapter"
    model.save_pretrained(str(adapter_path))
    tokenizer.save_pretrained(str(adapter_path))
    
    training_time = time.time() - start_time
    
    # Extract loss history (simplified - would need to parse logs)
    loss_history = [float(train_result.training_loss)] if hasattr(train_result, 'training_loss') else [0.0]
    
    result = TrainingResult(
        adapter_path=str(adapter_path),
        loss_history=loss_history,
        final_loss=loss_history[-1] if loss_history else 0.0,
        training_time_seconds=training_time,
    )
    
    return result.model_dump()


if __name__ == "__main__":
    # CLI for testing
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python lora_trainer.py <base_model> <training_data.json>")
        sys.exit(1)
    
    base_model = sys.argv[1]
    with open(sys.argv[2]) as f:
        training_data = json.load(f)
    
    result = train_lora_json(
        base_model=base_model,
        training_data_json=json.dumps(training_data),
        output_path="output/lora_adapter",
    )
    
    print(f"\n✅ Training complete!")
    print(f"   Adapter: {result['adapter_path']}")
    print(f"   Final loss: {result['final_loss']:.4f}")
    print(f"   Time: {result['training_time_seconds']:.1f}s")

