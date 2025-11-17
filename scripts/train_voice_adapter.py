#!/usr/bin/env python3
"""
Train voice preservation LoRA adapter.

Usage: python scripts/train_voice_adapter.py --corpus ~/papers
"""
import argparse
from pathlib import Path
import sys

# Add python/hermes to path
sys.path.insert(0, str(Path(__file__).parent.parent / "python"))

from hermes.mlx_lora_trainer import VoiceLoRATrainer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True, help="Path to writing corpus")
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--output", type=Path, default=Path("models/voice_adapters"))
    args = parser.parse_args()

    print("🚀 Starting voice preservation LoRA training")
    print(f"📁 Corpus: {args.corpus}")
    print(f"🔁 Epochs: {args.epochs}")
    print(f"📦 Batch size: {args.batch_size}")

    # Initialize trainer
    trainer = VoiceLoRATrainer(
        base_model="mlx-community/Llama-3.3-70B-4bit",
        lora_rank=16,
        lora_alpha=32,
    )

    # Prepare dataset
    print("\n📚 Preparing dataset...")
    dataset = trainer.prepare_dataset(args.corpus, max_examples=500)
    print(f"   Loaded {len(dataset)} training examples")

    # Split train/test
    split_idx = int(len(dataset) * 0.9)
    train_data = dataset[:split_idx]
    test_data = dataset[split_idx:]

    # Train
    print("\n🏋️ Training...")
    adapter_path = trainer.train(
        dataset=train_data,
        epochs=args.epochs,
        batch_size=args.batch_size,
        output_dir=args.output,
    )

    # Evaluate
    print("\n📊 Evaluating voice similarity...")
    similarity = trainer.evaluate_voice_similarity(test_data, adapter_path)
    print(f"   Voice similarity: {similarity*100:.1f}%")

    if similarity >= 0.95:
        print("\n✅ SUCCESS: Voice similarity ≥95% - adapter ready for production")
    else:
        print(f"\n⚠️  WARNING: Voice similarity {similarity*100:.1f}% < 95% - may need more training")


if __name__ == "__main__":
    main()

