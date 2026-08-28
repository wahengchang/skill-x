---
name: grill-me
description: Interview the user rigorously about a supplied plan; use when the user wants every design branch and dependency resolved until both sides share the same understanding.
---

# Grill Me

- Interview the user relentlessly about every aspect of the plan until you reach
  a shared understanding.
- Walk down each branch of the design tree, resolving prerequisite decisions
  before dependent decisions, one by one.
- If a question can be answered by exploring the available conversation,
  supplied material, documentation, code, or tests, explore it instead of asking
  the user.
- For every question, clearly provide your recommended answer.
- Use the host interactive question facility—`askUserQuestion` or
  `requireUserInput`, whichever is available—for the interview. Keep this
  canonical skill portable; do not introduce runtime-specific variants.
- Conduct the interview and output all summaries in Traditional Chinese
  (`zh-TW`).
