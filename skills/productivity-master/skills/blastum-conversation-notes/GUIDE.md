---
name: blastum-conversation-notes
description: Save a note summarizing what was learned in the current conversation. Use when the user says "make a note", "note that", "summarize what we learned", or similar.
---
# Conversation Notes

When asked to make a note or record learnings:

1. Infer a descriptive topic slug from the conversation (kebab-case, as many words as needed to be clear)
2. Target file: `docs/notes/<topic-slug>.md` relative to the workspace root
3. Create `docs/notes/` if it does not exist
4. Write the note:

```
# <Descriptive Title That Fully Captures the Topic>

## What We Learned
<Full prose or detailed bullets covering everything discovered: behavior, flow control,
callers, edge cases, decisions made, and why. Do not summarize — explain thoroughly.>

## Context
<What prompted the investigation or conversation.>
```

Write to inform someone who wasn't in the conversation. Include detail on flow control, callers, data shapes, failure modes, or anything else relevant. For code references, cite `file/path.ext:LineN` or method/class names inline.
