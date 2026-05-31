# Python SDK (apple-fm-sdk)

Python bindings for evaluating Swift app's Foundation Models features. Runs Swift framework under the hood — evaluations reflect real on-device performance.

## Requirements

- macOS 26.0+
- Xcode 26.0+ and SDK agreement
- Python 3.10+
- Apple Intelligence enabled

## Installation

```bash
pip install apple-fm-sdk
```

## Basic usage

```python
import apple_fm_sdk as fm

model = fm.SystemLanguageModel()
is_available, reason = model.is_available()

if is_available:
    session = fm.LanguageModelSession(model=model)
    response = await session.respond(prompt="Hello, how are you?")
    print(f"Model response: {response}")
else:
    print(f"Foundation Models not available: {reason}")
```

## Guided generation

- `@fm.generable` decorator
- `fm.guide()`, `anyOf`, `range`, `count`, `regex`, etc.
- Schema compatibility with Swift `@Generable`

## Tools

- Create tool class, use with sessions
- Same pattern as Swift: name, description, arguments, call

## Evaluation workflows

- Batch evaluation
- Export transcripts from Swift, process in Python
- [Evaluation docs](https://apple.github.io/python-apple-fm-sdk/evaluation.html)

## Docs

- [Getting started](https://apple.github.io/python-apple-fm-sdk/)
- [Guided generation](https://apple.github.io/python-apple-fm-sdk/guided_generation.html)
- [Tools](https://apple.github.io/python-apple-fm-sdk/tools.html)
- [GitHub](https://github.com/apple/python-apple-fm-sdk)
