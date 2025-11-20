#!/usr/bin/env python3
"""LoRA Training com Unsloth - Script parametrizado e com logging estruturado."""

import argparse
import json
import logging
import os
import sys
from pathlib import Path

try:
    import torch
    from datasets import Dataset
    from transformers import TrainingArguments
    from trl import SFTTrainer
    from unsloth import FastLanguageModel
except ImportError as err:
    print(f"❌ Dependências não instaladas: {err}")
    print("Instale com: pip install unsloth transformers trl datasets")
    sys.exit(1)


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

MODEL_NAME_DEFAULT = "unsloth/Llama-3.2-8B-Instruct-bnb-4bit"


def detect_device() -> str:
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def parse_args():
    parser = argparse.ArgumentParser(description="Treina LoRA com Unsloth (parametrizado)")
    parser.add_argument(
        "--bad-draft",
        default=os.getenv("BAD_DRAFT"),
        help="Caminho ou conteúdo do draft ruim (env: BAD_DRAFT)",
    )
    parser.add_argument(
        "--good-draft",
        default=os.getenv("GOOD_DRAFT"),
        help="Caminho ou conteúdo do draft bom (env: GOOD_DRAFT)",
    )
    parser.add_argument(
        "--output-dir",
        default=os.getenv("OUTPUT_DIR", "lora_adapter"),
        help="Diretório de saída do adapter (env: OUTPUT_DIR)",
    )
    parser.add_argument(
        "--model-name",
        default=os.getenv("MODEL_NAME", MODEL_NAME_DEFAULT),
        help="Modelo base (env: MODEL_NAME)",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=int(os.getenv("EPOCHS", "3")),
        help="Épocas de treinamento (env: EPOCHS)",
    )

    args = parser.parse_args()
    if not args.bad_draft or not args.good_draft:
        parser.error("BAD_DRAFT e GOOD_DRAFT devem ser fornecidos via env vars ou flags")
    return args


def load_draft(value: str, label: str) -> str:
    path = Path(value)
    if path.exists():
        return path.read_text(encoding="utf-8")
    logging.warning("%s não é caminho válido; usando valor literal", label)
    return value


def build_dataset(bad_text: str, good_text: str) -> Dataset:
    prompt = f"### Instruction:\n{bad_text}\n\n### Response:\n{good_text}"
    return Dataset.from_dict({"text": [prompt]})


def main():
    args = parse_args()
    device = detect_device()

    model_name = args.model_name
    logging.info(json.dumps({"event": "training_start", "model": model_name, "device": device}))

    bad_text = load_draft(args.bad_draft, "BAD_DRAFT")
    good_text = load_draft(args.good_draft, "GOOD_DRAFT")

    logging.info(
        json.dumps(
            {
                "event": "drafts_loaded",
                "bad_chars": len(bad_text),
                "good_chars": len(good_text),
                "output_dir": args.output_dir,
            }
        )
    )

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=model_name,
        max_seq_length=4096,
        dtype=None,
        load_in_4bit=True,
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=3407,
    )

    dataset = build_dataset(bad_text, good_text)

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=4096,
        packing=False,
        args=TrainingArguments(
            per_device_train_batch_size=2,
            gradient_accumulation_steps=4,
            warmup_steps=5,
            num_train_epochs=args.epochs,
            learning_rate=2e-4,
            fp16=device == "cuda",
            bf16=device == "cuda",
            logging_steps=1,
            output_dir=args.output_dir,
            optim="adamw_8bit",
            weight_decay=0.01,
            lr_scheduler_type="linear",
            seed=3407,
            report_to=[],
        ),
    )

    trainer.train()

    os.makedirs(args.output_dir, exist_ok=True)
    model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)

    logging.info(
        json.dumps({"event": "training_complete", "model": model_name, "output_dir": args.output_dir})
    )


if __name__ == "__main__":
    main()
