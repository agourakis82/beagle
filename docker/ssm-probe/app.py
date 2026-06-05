import os
import threading
import time
import uuid
from typing import Any

import torch
from fastapi import FastAPI
from pydantic import BaseModel, Field
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

try:
    import pynvml
except Exception:  # pragma: no cover - optional runtime telemetry
    pynvml = None


MODEL_ID = os.environ.get("MODEL_ID", "state-spaces/mamba-130m-hf")
SERVED_MODEL_NAME = os.environ.get("SERVED_MODEL_NAME", "mamba-130m-hf")
MAX_MODEL_TOKENS = int(os.environ.get("MAX_MODEL_TOKENS", "4096"))
MODEL_DTYPE = os.environ.get("MODEL_DTYPE", "auto")
LOAD_IN_4BIT = os.environ.get("LOAD_IN_4BIT", "").lower() in {"1", "true", "yes"}
TRUST_REMOTE_CODE = os.environ.get("TRUST_REMOTE_CODE", "").lower() in {
    "1",
    "true",
    "yes",
}
IGNORE_MISMATCHED_SIZES = os.environ.get("IGNORE_MISMATCHED_SIZES", "").lower() in {
    "1",
    "true",
    "yes",
}

app = FastAPI(title="Sounio SSM Probe")
lock = threading.Lock()
state: dict[str, Any] = {
    "ready": False,
    "model_id": MODEL_ID,
    "served_model_name": SERVED_MODEL_NAME,
    "device": "cuda" if torch.cuda.is_available() else "cpu",
    "last_request": None,
}


class CompletionRequest(BaseModel):
    model: str | None = None
    prompt: str
    max_tokens: int = Field(default=64, ge=1, le=512)
    temperature: float = Field(default=0.0, ge=0.0, le=2.0)
    top_p: float = Field(default=1.0, ge=0.0, le=1.0)
    top_k: int | None = Field(default=None, ge=1)
    repetition_penalty: float = Field(default=1.0, ge=0.1, le=4.0)


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    model: str | None = None
    messages: list[ChatMessage]
    max_tokens: int = Field(default=64, ge=1, le=512)
    temperature: float = Field(default=0.0, ge=0.0, le=2.0)
    top_p: float = Field(default=1.0, ge=0.0, le=1.0)
    top_k: int | None = Field(default=None, ge=1)
    repetition_penalty: float = Field(default=1.0, ge=0.1, le=4.0)


def gpu_memory() -> dict[str, int] | None:
    if pynvml is None or not torch.cuda.is_available():
        return None
    try:
        pynvml.nvmlInit()
        handle = pynvml.nvmlDeviceGetHandleByIndex(0)
        info = pynvml.nvmlDeviceGetMemoryInfo(handle)
        return {
            "used_mib": int(info.used // 1024 // 1024),
            "free_mib": int(info.free // 1024 // 1024),
            "total_mib": int(info.total // 1024 // 1024),
        }
    except Exception:
        return None


def format_chat(tokenizer: Any, messages: list[ChatMessage]) -> str:
    payload = [{"role": msg.role.strip() or "user", "content": msg.content} for msg in messages]
    if hasattr(tokenizer, "apply_chat_template"):
        try:
            return tokenizer.apply_chat_template(
                payload,
                tokenize=False,
                add_generation_prompt=True,
            )
        except Exception as exc:
            state["last_chat_template_error"] = str(exc)

    parts = []
    for msg in payload:
        parts.append(f"{msg['role']}: {msg['content'].strip()}")
    parts.append("assistant:")
    return "\n".join(parts)


def model_dtype() -> Any:
    if not torch.cuda.is_available():
        return torch.float32
    match MODEL_DTYPE.lower():
        case "auto":
            return "auto"
        case "bfloat16" | "bf16":
            return torch.bfloat16
        case "float16" | "fp16":
            return torch.float16
        case "float32" | "fp32":
            return torch.float32
        case _:
            return "auto"


@app.on_event("startup")
def load_model() -> None:
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=TRUST_REMOTE_CODE)
    if tokenizer.pad_token_id is None and tokenizer.eos_token_id is not None:
        tokenizer.pad_token = tokenizer.eos_token

    kwargs: dict[str, Any] = {
        "device_map": "auto" if torch.cuda.is_available() else None,
        "ignore_mismatched_sizes": IGNORE_MISMATCHED_SIZES,
        "trust_remote_code": TRUST_REMOTE_CODE,
    }
    if LOAD_IN_4BIT:
        kwargs["quantization_config"] = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
            bnb_4bit_compute_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        )
    else:
        kwargs["torch_dtype"] = model_dtype()

    model = AutoModelForCausalLM.from_pretrained(MODEL_ID, **kwargs)
    model.eval()

    state["tokenizer"] = tokenizer
    state["model"] = model
    state["ready"] = True
    state["startup_gpu_memory"] = gpu_memory()
    state["load_config"] = {
        "model_dtype": MODEL_DTYPE,
        "load_in_4bit": LOAD_IN_4BIT,
        "trust_remote_code": TRUST_REMOTE_CODE,
        "ignore_mismatched_sizes": IGNORE_MISMATCHED_SIZES,
    }


def generate(
    prompt: str,
    max_tokens: int,
    temperature: float,
    top_p: float,
    top_k: int | None,
    repetition_penalty: float,
) -> tuple[str, dict[str, Any]]:
    tokenizer = state["tokenizer"]
    model = state["model"]
    start_mem = gpu_memory()
    started = time.perf_counter()

    with lock:
        inputs = tokenizer(
            prompt,
            return_tensors="pt",
            truncation=True,
            max_length=MAX_MODEL_TOKENS,
        )
        inputs = {k: v.to(model.device) for k, v in inputs.items()}
        prompt_tokens = int(inputs["input_ids"].shape[-1])
        with torch.inference_mode():
            generate_kwargs: dict[str, Any] = {
                "max_new_tokens": max_tokens,
                "do_sample": temperature > 0,
                "pad_token_id": tokenizer.pad_token_id,
                "eos_token_id": tokenizer.eos_token_id,
                "repetition_penalty": repetition_penalty,
            }
            if temperature > 0:
                generate_kwargs["temperature"] = temperature
                generate_kwargs["top_p"] = top_p
                if top_k is not None:
                    generate_kwargs["top_k"] = top_k
            output = model.generate(
                **inputs,
                **generate_kwargs,
            )

    elapsed_ms = (time.perf_counter() - started) * 1000
    generated_ids = output[0, prompt_tokens:]
    text = tokenizer.decode(generated_ids, skip_special_tokens=True)
    completion_tokens = int(generated_ids.shape[-1])
    metrics = {
        "duration_ms": round(elapsed_ms, 3),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "tokens_per_second": round(completion_tokens / (elapsed_ms / 1000), 3)
        if elapsed_ms > 0
        else 0,
        "gpu_memory_before": start_mem,
        "gpu_memory_after": gpu_memory(),
    }
    state["last_request"] = metrics
    return text, metrics


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "healthy" if state["ready"] else "loading",
        "model": SERVED_MODEL_NAME,
        "device": state["device"],
        "load_config": state.get("load_config"),
        "gpu_memory": gpu_memory(),
    }


@app.get("/metrics")
def metrics() -> dict[str, Any]:
    return {
        "model": SERVED_MODEL_NAME,
        "load_config": state.get("load_config"),
        "startup_gpu_memory": state.get("startup_gpu_memory"),
        "last_request": state.get("last_request"),
        "current_gpu_memory": gpu_memory(),
    }


@app.get("/v1/models")
def models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [
            {
                "id": SERVED_MODEL_NAME,
                "object": "model",
                "owned_by": "sounio-ssm-probe",
            }
        ],
    }


@app.post("/v1/completions")
def completions(req: CompletionRequest) -> dict[str, Any]:
    text, m = generate(
        req.prompt,
        req.max_tokens,
        req.temperature,
        req.top_p,
        req.top_k,
        req.repetition_penalty,
    )
    return {
        "id": f"cmpl-{uuid.uuid4()}",
        "object": "text_completion",
        "model": SERVED_MODEL_NAME,
        "choices": [{"index": 0, "text": text, "finish_reason": "stop"}],
        "usage": {
            "prompt_tokens": m["prompt_tokens"],
            "completion_tokens": m["completion_tokens"],
            "total_tokens": m["prompt_tokens"] + m["completion_tokens"],
        },
        "sounio_probe": m,
    }


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest) -> dict[str, Any]:
    tokenizer = state["tokenizer"]
    text, m = generate(
        format_chat(tokenizer, req.messages),
        req.max_tokens,
        req.temperature,
        req.top_p,
        req.top_k,
        req.repetition_penalty,
    )
    return {
        "id": f"chatcmpl-{uuid.uuid4()}",
        "object": "chat.completion",
        "model": SERVED_MODEL_NAME,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text.strip()},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": m["prompt_tokens"],
            "completion_tokens": m["completion_tokens"],
            "total_tokens": m["prompt_tokens"] + m["completion_tokens"],
        },
        "sounio_probe": m,
    }
