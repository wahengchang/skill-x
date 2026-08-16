---
name: ai-x
description: Complete a task independently as the primary AI, then invoke a separate AI agent as an independent reviewer/challenger and run an evidence-backed consensus loop (verdicts ACCEPT / NEEDS_REVISION / BLOCKED, adjudication AGREE / PARTIAL / DISAGREE) until CONSENSUS_ACCEPTED or a genuine user decision; use when you want a second AI opinion or an independent cross-model review of research, analysis, code, plans, or any deliverable.
---

# ai-x — Cross-AI Consensus Review Protocol

使用 `ai-x` 讓主要 AI 與另一個獨立 AI Agent 對同一項工作進行交叉審查、反駁與改進。

核心原則：

* Primary AI 先獨立完成原始任務。
* Supporting AI 是 reviewer / challenger / consultant，不是主要執行者。
* 必須實際使用第二個模型或 AI Agent，不得由 Primary AI 模擬第二意見。
* Reviewer 提供獨立審查。
* Primary AI 不得直接接受 Reviewer 結論，必須自行驗證。
* 對實質分歧持續進行 evidence-backed review。
* 直到雙方形成技術共識，或確認存在必須由使用者裁決的真正分歧。

整體流程：

**Primary execution → reviewer selection → independent review → primary adjudication → focused consensus loop → CONSENSUS_ACCEPTED / user decision**

---

## 1. Purpose & Roles

### Primary AI

Primary AI 對原始任務與最終成果負責。

Primary AI 必須：

* 先獨立理解並完成使用者任務。
* 對最終內容、技術判斷與品質負責。
* 自行驗證 Reviewer 提出的 findings。
* 整合經驗證後確實有價值的修改。
* 在存在真正無法由證據解決的取捨時，交由使用者決定。

Primary AI 不得把最終決策責任轉交給 Reviewer。

### Supporting AI / Reviewer

Supporting AI 是獨立的：

* reviewer
* challenger
* consultant

Reviewer 的責任是：

* 獨立檢查 Primary AI 的成果。
* 找出 correctness、assumption、risk、gap 或 implementation 問題。
* 提供 evidence-backed findings。
* 挑戰 Primary AI 的判斷。
* 在後續輪次重新驗證 Primary AI 的回覆。

Reviewer 不是主要執行者。

除非 review 本身必須進行非破壞性驗證，Reviewer 不應實作原始任務、修改產品檔案或接管 Primary AI 的工作。

---

## 2. Primary Execution

在呼叫 Reviewer 前，Primary AI 必須先獨立完成使用者原始任務。

適用任務包括但不限於：

* research
* analysis
* report
* writing
* development
* debugging
* planning
* architecture
* review
* design
* technical specification

Primary AI 不應先詢問 Reviewer「應該怎麼做」，再把 Reviewer 的答案當作自己的主要方案。

Cross-AI 的基本順序必須是：

**Primary independent work → independent review**

而不是：

**Reviewer proposes → Primary follows**

完成 Primary result 後，再建立 Review Request。

---

## 3. Reviewer Selection

選擇適合目前任務的第二 AI Agent。

例如：

* Codex
* Claude Code
* OpenCode
* 其他可用 AI Agent
* CLI agent
* SDK / API
* MCP tool
* sub-agent
* delegated-agent interface

不要假設任何單一 Agent 是固定或唯一選項。

選擇 Reviewer 時考慮：

* 任務能力
* domain suitability
* repository access
* context access
* available tools
* permissions
* structured output capability
* model diversity
* reasoning diversity
* latency / cost
* environment compatibility

在其他條件相近時，優先使用能提供不同模型、工具鏈或推理路徑的 Reviewer。

若目的是取得獨立第二意見，應使用新的 session。

只有在後續需要追問、反駁或延續同一 Reviewer context 時，才 reuse / resume 原 session。

---

## 4. Review Context

呼叫 Reviewer 前，Primary AI 建立一份聚焦的 Review Request。

提供足以讓 Reviewer 獨立判斷的必要資訊，包括：

* 原始任務或問題
* Primary AI 已完成的結果
* 被審查的 artifacts / files / content
* 必要 repository context
* 使用者限制與 acceptance criteria
* Reviewer 的角色
* 本次 review 的檢查重點
* 預期的 output format

避免傳入與 review 無關的大量 conversation 或 repository context。

但不得為了縮短 context，而省略 Reviewer 驗證 finding 所必須的原始資料。

Reviewer 必須能直接檢查必要的 source、artifact、repository files、documents 或其他 evidence，而不是只能依賴 Primary AI 的摘要。

若需要提高獨立性，可分兩階段：

1. Reviewer 先根據原始 task、target 與 evidence 獨立判斷。
2. 再檢查 Primary AI 的結果並提出 critique。

---

## 5. Invocation

在相關 project / work directory 中執行 Reviewer。

在可行時：

* 優先使用 non-interactive invocation。
* 優先使用 structured / machine-readable output。
* 使用最低必要權限。
* review-only 任務優先 read-only。
* 不授予不必要的 filesystem write、network、deployment 或 destructive permissions。
* 不修改被 review 的產品檔案。

Reviewer 可以使用非破壞性檢查驗證事實，例如：

* 讀取 source files
* repository search
* static inspection
* existing tests
* typecheck
* lint
* dry-run
* read-only commands
* temporary isolated verification

不得因 review 而進行：

* destructive operations
* deployment
* publishing
* irreversible migration
* 修改 tracked product files

除非使用者明確授權。

---

## 6. First Review Verdict

Reviewer 第一輪必須先進行獨立審查，再給出整體 verdict。

允許的 verdict：

### `ACCEPT`

沒有發現需要修改的實質問題。

可以存在非阻擋性的 minor suggestion，但不得存在未解決的重大 correctness 或 implementation 問題。

### `NEEDS_REVISION`

存在需要修改的 finding，但已有合理且可實作的修正方向。

### `BLOCKED`

存在阻擋級問題，例如：

* 基本需求矛盾
* 缺少必要資訊
* ownership 無法確定
* interface 無法定義
* compatibility 衝突
* 不可安全實作
* 關鍵事實無法驗證
* 必須由使用者做產品或風險取捨

Reviewer 不得只輸出 verdict；若不是 `ACCEPT`，必須列出對應 findings。

---

## 7. Finding Schema

每個實質 finding 必須有穩定 ID，例如：

* `F-001`
* `F-002`
* `F-003`

後續輪次持續使用同一 ID，不得任意重新編號。

每項 finding 至少包含：

| Field            | Requirement                                                  |
| ---------------- | ------------------------------------------------------------ |
| ID               | 穩定且唯一                                                        |
| Severity         | BLOCKER / HIGH / MEDIUM / LOW                                |
| Claim            | 明確指出問題                                                       |
| Evidence         | 程式碼、文件、資料、行為或可驗證推理                                           |
| Failure Scenario | 問題在什麼情況下實際失效                                                 |
| Impact           | 對 correctness、compatibility、security、UX 或 implementation 的影響 |
| Recommendation   | 精確且可實作的修改建議                                                  |
| Verification     | 如何驗證修改後問題已解決                                                 |

Findings 應優先檢查：

* correctness
* contradictions
* ownership
* responsibility overlap
* state transitions
* data flow
* failure modes
* atomicity
* idempotency
* concurrency
* compatibility
* interfaces
* assumptions
* security
* implementation feasibility
* test gaps

不同任務可以使用不同 review rubric。

例如 writing / research 任務可改為檢查：

* factual accuracy
* unsupported claims
* missing evidence
* structure
* clarity
* audience fit
* contradictory reasoning
* omitted alternatives

---

## 8. Primary Adjudication

收到 Reviewer findings 後，Primary AI 必須逐項獨立判斷。

每項 finding 使用：

* `AGREE`
* `PARTIAL`
* `DISAGREE`

### `AGREE`

Primary AI 確認 finding 成立。

必須說明：

* 為什麼成立
* 採取什麼修改
* 修改後如何滿足 requirement

### `PARTIAL`

Primary AI 只接受 finding 的部分內容。

必須指出：

* 同意的部分
* 不同意的部分
* 原建議的問題
* Primary AI 採用的精確替代方案

### `DISAGREE`

Primary AI 判斷 finding 不成立。

不得只表達意見，必須提供可驗證證據，例如：

* source code
* documentation
* tests
* actual behavior
* data
* contract
* compatibility rule

Reviewer 的結論本身不是 source of truth。

任何會影響最終結果的重要 factual claim，Primary AI 都應自行驗證。

Primary AI 同時必須檢查 Reviewer 的建議是否引入：

* circular dependency
* non-atomic behavior
* undefined ownership
* compatibility break
* new failure mode
* incomplete interface
* untestable requirement
* scope creep

---

## 9. Consensus Loop

若第一輪後仍存在實質未解決 finding，繼續 Cross-AI review。

後續輪次只處理尚未解決的問題。

不要重新進行完整首輪 review，除非新的 evidence 顯示原先 assumptions 已失效。

將以下內容提供給同一 Reviewer：

* 原始 task / target
* 原 finding
* Primary AI 的 `AGREE / PARTIAL / DISAGREE`
* 新 evidence
* Primary AI 提出的修改方案

Reviewer 必須重新核對 Primary AI 的回覆，不得禮貌附和。

對每個未解決 finding，Reviewer同樣標示：

* `AGREE`
* `PARTIAL`
* `DISAGREE`

若 Reviewer 提出新的 finding：

* 必須真的由新 evidence 或修改方案產生
* 必須使用新的 Finding ID
* 必須附 evidence、failure scenario 與 recommendation
* 不得為延長討論而重述舊 finding

事實爭議應優先透過：

* source
* tests
* documentation
* contract
* non-destructive verification

解決。

不要為了結束流程製造假共識。

也不要為了追求形式上的一致，無限討論純文字偏好或無法技術證明的主觀差異。

---

## 10. Termination

Cross-AI review 只有在以下情況之一成立時停止。

### A. `CONSENSUS_ACCEPTED`

Reviewer 只有在所有實質技術問題都已解決後，才能明確輸出：

`CONSENSUS_ACCEPTED`

成立條件至少包括：

* 所有 BLOCKER / HIGH findings 已解決
* 沒有未處理的重大 contradiction
* ownership 與 responsibility boundary 已確定
* state transitions 沒有衝突
* interfaces / inputs / outputs 已足夠明確
* compatibility rules 已定義
* failure handling 已定義
* 重要操作的 sequencing 與 atomicity 已明確
* 必要 tests 可以直接實作
* binding requirements 不需要實作者自行猜測重要決策

Reviewer 輸出 `CONSENSUS_ACCEPTED` 後，Primary AI 必須再自行檢查一次。

只有 Primary AI 也明確接受，才算最終共識成立。

### B. User Decision Required

若剩餘分歧屬於：

* product preference
* UX preference
* cost / latency / quality tradeoff
* irreversible choice
* risk tolerance
* business priority
* 多個技術方案皆成立但沒有客觀唯一答案

停止技術辯論並交由使用者決定。

必須清楚列出：

* 選項
* 各自 tradeoff
* 雙方共同同意的事實
* 真正需要使用者決策的部分

### C. Unresolved Technical Block

若必要 evidence 無法取得，或外部限制使技術事實無法驗證，明確標示為 `BLOCKED`。

不得把 `BLOCKED` 包裝成 consensus。

---

## 11. Failure Handling

必須處理 Reviewer invocation 的執行失敗，包括：

* execution failure
* timeout
* unavailable tool
* authentication failure
* permission failure
* invalid output
* invalid structured data
* incomplete response
* session failure

處理原則：

1. 判斷是否能安全重試。
2. 不得因回覆較慢而重複送出同一個仍可能執行中的 request。
3. 若原 Reviewer 不可用，可選擇另一個適合的 AI Agent。
4. 若 structured output 無效，可在不改變 review scope 的前提下要求重新輸出。
5. 不得把 Primary AI 自己產生的內容冒充 Reviewer 結果。
6. 若使用者明確要求 Cross-AI review，而實際上無法取得第二 AI，必須明確回報未完成 Cross-AI requirement。
7. Reviewer failure 不代表 Primary 原始工作一定錯誤，但不得宣稱已完成雙模型共識。

---

## 12. Reference Invocations

以下只表示常見 invocation pattern。

實際 command、flags 與 capabilities 應依目前工具版本、執行環境與任務需求調整。

### Codex

```bash
codex exec "<review-prompt>" \
  -C "<workdir>" \
  --sandbox read-only \
  --json
```

### Claude Code

```bash
claude -p "<review-prompt>" \
  --output-format json \
  --permission-mode plan
```

### OpenCode

```bash
opencode run "<review-prompt>" \
  --dir "<workdir>" \
  --format json
```

依實際環境可調整：

* model
* flags
* reasoning / effort
* permissions
* agent
* working directory
* session
* timeout
* output format
* available tools

Reference commands 不是 binding interface。

不得假設示例中的：

* executable
* flag
* permission mode
* JSON schema
* session behavior

在所有版本或環境中都固定存在。

應先以實際工具能力為準，再選擇最接近以下原則的 invocation：

**independent model + focused context + minimum permission + structured result + verifiable review**

---

## Final Principle

Primary AI 保有 ownership。

Reviewer 提供獨立 challenge。

Review 必須基於 evidence，而不是 authority。

分歧必須經過驗證，而不是禮貌消失。

流程持續到：

**CONSENSUS_ACCEPTED**

或：

**真正需要使用者裁決的分歧**

核心流程：

**Primary independent execution → select independent reviewer → focused review → ACCEPT / NEEDS_REVISION / BLOCKED → Primary AGREE / PARTIAL / DISAGREE → unresolved-only review loop → CONSENSUS_ACCEPTED or user decision**
