# Adapter Training

Teach the on-device model new skills with a custom adapter. Use after prompt engineering and tool calling.

## When to consider

- Dataset suitable for LLM
- Replicating server fine-tuned LLM on-device
- Need lower latency (minimal prompting)
- Prompt engineering insufficient accuracy
- Need specific style/format/policy
- Subject-matter expertise

**Need**: process to load adapters from server; evaluation process; dataset of prompt/response pairs.

## Size & distribution

- ~160 MB per adapter
- Host on server, download via Background Assets

## Entitlement

**Foundation Models Framework Adapter Entitlement** required for deployment (not for training or local testing). Account Holder must request.

## Requirements

- Python 3.11+
- Mac Apple silicon 32GB+ or Linux GPU
- Apple Developer Program member; agree to terms
- New toolkit per system model update (e.g. 26.0.0 for macOS/iOS/iPadOS/visionOS 26)

## Dataset

- Format: jsonl with `role` (user/assistant), `content`
- 5,000+ samples for complex tasks; 100–1,000 for basic
- Schema.md in toolkit; examples/data.py
- Train/eval split

## Training steps

1. Virtual env (conda/venv), `pip install -r requirements.txt`
2. Jupyter: `examples/end_to_end_example.ipynb`
3. Test generation: `examples/generate.py --prompt "Prompt here"`
4. Prepare dataset (jsonl, Schema.md)
5. Train: LoRA (PEFT); only adapter weights updated
   ```bash
   examples/train_adapter.py --train-data ... --eval-data ... --epochs ... --learning-rate ... --batch-size ... --checkpoint-dir ...
   ```
6. Optionally train draft model for speculative decoding: `examples/train_draft_model.py`
7. Evaluate adapter quality (custom process; safety evaluation)
8. Export: `export.export_fmadapter --adapter-name ... --checkpoint ... --draft-checkpoint (optional) --output-dir` → `.fmadapter`
   - Do not modify export folder code

## Download toolkit

Apple Developer Program member; agree to terms. Multiple toolkit versions for different OS version ranges.

## Source

[Foundation Models adapter](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)
