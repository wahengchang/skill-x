---
name: grill-me
description: Rigorously interview the user about a supplied plan, resolving its material design decisions in dependency order; use when the user asks to be grilled, challenged, or interviewed until the plan and its consequences are mutually understood.
---

# Grill Me

Turn a supplied plan into a shared, decision-complete design. Explore first,
then interview the user only about choices that the available evidence cannot
settle.

## Invariants

- Treat the conversation, the plan and its attachments, repository instructions,
  documentation, implementation, tests, configuration, history, and other
  available evidence as inputs. Inspect the relevant inputs before asking the
  first question and whenever a later question may be answerable by further
  exploration.
- Never ask the user to repeat a discoverable fact. Explore it and record the
  evidence instead. Do not turn ordinary engineering work into an interview.
- Model material decisions and their dependencies explicitly. Resolve
  prerequisites before decisions that depend on them, and finish one coherent
  branch before moving to the next.
- Ask persistently until every material branch is resolved or has a genuine,
  explicitly recorded blocker, and both parties share the same understanding.
- Do not invent facts, decisions, agreement, or certainty. Distinguish evidence,
  inferences, user decisions, recommendations, assumptions, and blockers.

## 1. Explore the plan

Restate the plan's objective, constraints, success criteria, actors, boundaries,
and known decisions. Then inspect all relevant sources available through the
host. Follow references far enough to answer questions they settle: trace code
paths and data flow, read tests and schemas, inspect repository conventions, and
check prior decisions where available.

For each apparent unknown, ask: **Can the existing evidence answer this, or can
another safe exploration step answer it?** If yes, explore and resolve it without
questioning the user. If evidence conflicts, report the conflict rather than
silently choosing a side.

## 2. Build the decision tree

Maintain a working decision tree containing every material design branch. For
each node, track:

- the decision or question;
- why it is material;
- prerequisite and dependent node IDs;
- evidence and current constraints;
- viable alternatives and their consequences;
- status: `resolved-evidence`, `resolved-user`, `blocked`, or `open`;
- the chosen answer, rationale, and any assumptions.

Start with high-leverage roots such as goals, scope, users, constraints, and
success measures. Add dependent branches for architecture, interfaces, data,
failure behavior, security, operations, migration, testing, rollout, and other
domains only where they are material to this plan. Do not force irrelevant
categories into the tree.

Recompute the tree when an answer changes prerequisites, eliminates an option,
or reveals a new material branch. A node is ready for interview only when its
prerequisites are resolved and exploration cannot settle it.

## 3. Interview in dependency order

Choose the highest-priority ready node on one branch. Ask focused questions in
small rounds so answers can affect what is asked next; do not dump the entire
tree as a static questionnaire.

Use the host-provided interactive question facility for every interview
question when one is available: call `askUserQuestion`, or call
`requireUserInput` where that is the host's name. This requirement describes a
host capability, not a runtime-specific skill variant. If neither facility is
exposed, ask the same focused question in conversation and state that the host
does not provide an interactive question facility; never pretend a tool call
occurred.

Every user-facing interview question must include:

1. the decision being made and the dependency it unlocks;
2. concise, genuinely viable options and important consequences;
3. a clearly labeled **Recommended answer**, with evidence-based reasoning;
4. a way to accept the recommendation or provide a different answer.

Do not use an interactive question to ask permission for routine exploration.
When an answer is ambiguous, reflect the interpretation and use the interactive
facility to resolve only the material ambiguity. Challenge contradictions and
unstated consequences respectfully; do not accept an answer that leaves its
prerequisite or meaning unclear.

After the user answers, record the decision, rationale, consequences, and newly
resolved or exposed dependencies. Walk that branch to a stable leaf before
selecting the next ready branch, unless the answer makes another prerequisite
urgent.

## 4. Checkpoint shared understanding

At natural branch boundaries, and whenever the tree changes substantially,
show a concise checkpoint with:

- resolved decisions and whether evidence or the user resolved them;
- consequences, constraints, and assumptions now implied;
- remaining branches in dependency order;
- genuine blockers and exactly what would unblock them.

Invite correction of the checkpoint using the host's interactive question
facility when a response is required. Any correction reopens affected nodes and
their dependents. A lack of evidence is not permission to manufacture an answer;
record a blocker only after available exploration and ready user decisions
cannot resolve it.

## 5. Completion gate

Continue until all material nodes are resolved or explicitly blocked. Before
stopping, verify that:

- no open material node is hidden behind a resolved parent;
- dependent decisions remain consistent with their prerequisites;
- every user decision matches the recorded interpretation;
- every blocker is genuine, scoped, and paired with an owner or next evidence
  needed; and
- the plan's intended behavior, consequences, and remaining uncertainty are
  mutually understood.

Finish with a decision record containing the final objective and scope, resolved
decisions in dependency order, their rationale and consequences, assumptions,
remaining blockers, and next actions. Explicitly ask for confirmation through
`askUserQuestion` or `requireUserInput` when available. Do not claim shared
understanding until the user confirms it; if confirmation reveals disagreement,
reopen the affected branch and continue the interview.
