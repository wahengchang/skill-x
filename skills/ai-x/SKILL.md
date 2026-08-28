---
name: ai-x
description: Complete a task independently as the primary AI, then invoke a separate AI agent as an independent reviewer/challenger and run an evidence-backed consensus loop (verdicts ACCEPT / NEEDS_REVISION / BLOCKED / USER_DECISION_REQUIRED, adjudication AGREE / PARTIAL / DISAGREE) ending in CONSENSUS_ACCEPTED, USER_DECISION_REQUIRED, or BLOCKED; use when you want a second AI opinion or an independent cross-model review of research, analysis, code, plans, or any deliverable.
---

# ai-x — Cross-AI Consensus Review Protocol

使用 `ai-x` 讓主要 AI（Primary）與另一個獨立 AI Agent（Reviewer）對同一項工作進行交叉審查、反駁與改進。

**Primary 獨立執行 → 選擇獨立 Reviewer → 獨立審查 → Primary 裁決 → 僅處理未解決 finding 的共識迴圈 → `CONSENSUS_ACCEPTED` / `USER_DECISION_REQUIRED` / `BLOCKED`**

## 1. 角色

### Primary AI

Primary 對原始任務與最終成果負責：先獨立完成任務、自行驗證 Reviewer 的 findings、整合有價值的修改、在真正無法由證據解決的取捨時交由使用者決定。Primary 不得把最終決策責任轉交給 Reviewer。

### Reviewer（Supporting AI）

Reviewer 是獨立的 reviewer / challenger / consultant，不是主要執行者。其責任是：獨立檢查 Primary 成果、找出 correctness / assumption / risk / gap / implementation 問題、提供 evidence-backed findings、挑戰 Primary 判斷、在後續輪次驗證 Primary 的回覆。

Reviewer 不實作原始任務，也不修改被審查的產品檔案；review 期間一律 read-only（見第 6 節）。

## 2. 流程總覽

唯一權威的狀態機，其餘章節都指向此處：

1. Primary 先獨立完成任務。
2. Primary 建立聚焦的 Review Request，選擇適合的獨立 Reviewer（新 session）。
3. Reviewer 獨立審查，給出第一輪 verdict：`ACCEPT` / `NEEDS_REVISION` / `BLOCKED` / `USER_DECISION_REQUIRED`。
4. Primary 逐項 adjudicate findings：`AGREE` / `PARTIAL` / `DISAGREE`，並套用修改。
5. 若仍有未解決 finding，進入共識迴圈：Reviewer 對 Primary 回覆逐項標 `FIX_VERIFIED` / `FINDING_UPHELD` / `FINDING_REVISED` / `FINDING_WITHDRAWN`。
6. 結束於 `CONSENSUS_ACCEPTED` / `USER_DECISION_REQUIRED` / `BLOCKED`（見第 11 節）。

## 3. Primary 獨立執行

呼叫 Reviewer 前，Primary 必須先獨立完成原始任務（research、analysis、report、writing、development、debugging、planning、architecture、review、design、technical specification 等）。

順序必須是 **Primary 獨立成果 → 獨立審查**，而非 **Reviewer 提案 → Primary 跟隨**。Primary 不應先問 Reviewer「該怎麼做」，再把答案當成自己的方案。

## 4. Reviewer 選擇

選擇適合任務的第二 AI Agent（Codex、Claude Code、OpenCode、CLI agent、SDK/API、MCP tool、sub-agent 等），考慮任務能力、domain、repository/context access、tools、permissions、structured output、model/reasoning diversity、latency/cost。

其他條件相近時，優先選能提供不同模型、工具鏈或推理路徑的 Reviewer。目的是獨立第二意見，應使用新 session；只有後續追問/反駁同一 Reviewer 時才 resume。

## 5. Review Context

呼叫 Reviewer 前，建立聚焦的 Review Request，包含：原始任務、Primary 成果、被審 artifacts/files、必要 repository context、使用者限制與 acceptance criteria、Reviewer 角色、檢查重點、預期 output format。

不要傳入無關的大量 context，但不得省略 Reviewer 驗證 finding 所需的原始資料——Reviewer 必須能直接檢查 source、artifact、files、documents，而非只依賴 Primary 的摘要。若需提高獨立性，可兩階段：Reviewer 先依原始 task/target/evidence 獨立判斷，再看 Primary 成果並 critique。

## 6. Invocation 與權限

在相關 project/work directory 執行 Reviewer。優先 non-interactive、structured/machine-readable output、最低必要權限。

**Reviewer 一律 read-only**：可使用非破壞性驗證（讀 source、repository search、static inspection、既有 tests、typecheck、lint、dry-run、read-only commands、隔離的暫時驗證），但不得進行 destructive operation、deployment、publishing、irreversible migration，也不得修改任何 tracked product files。

若使用者要求 Reviewer 實作修改，結束 review phase、另開 implementation phase，再由 Primary 以乾淨 diff 重新 review。review 期間不存在任何可修改 review target 的例外。

## 7. 第一輪 Verdict

Reviewer 第一輪先獨立審查，再給 verdict，並在非 `ACCEPT` 時附 findings。

| Verdict | 意義 |
|---|---|
| `ACCEPT` | 無需修改的實質問題（可含非阻擋 minor suggestion）。 |
| `NEEDS_REVISION` | 有 finding，且有合理可實作的修正方向。 |
| `BLOCKED` | 技術/事實阻塞：需求矛盾、缺必要資訊、ownership 未定、interface 未定、compatibility 衝突、不可安全實作、關鍵事實無法驗證。 |
| `USER_DECISION_REQUIRED` | 必須由使用者做產品/UX/成本/風險/商業取捨。 |

`ACCEPT` 是 Reviewer 提出的共識候選：Primary 完成第 11 節 A 的最終自查後，即成為 `CONSENSUS_ACCEPTED`。

第一輪 verdict 的後續路由：`ACCEPT` → 第 11 節 A；`NEEDS_REVISION` → 第 9 節 adjudication；`BLOCKED` / `USER_DECISION_REQUIRED` → 在 Primary 確認後直接到第 11 節 C / B。

## 8. Finding Schema

每項 finding 使用穩定 ID（`F-001`…），後續輪次沿用同一 ID，不得重新編號。所有 finding（含後續輪次新增者）一律包含：

| Field | Requirement |
|---|---|
| ID | 穩定且唯一 |
| Severity | BLOCKER / HIGH / MEDIUM / LOW |
| Claim | 明確指出問題 |
| Evidence | 程式碼、文件、資料、行為或可驗證推理 |
| Failure Scenario | 何種情況下實際失效 |
| Impact | 對 correctness / compatibility / security / UX / implementation 的影響 |
| Recommendation | 精確可實作的修改建議 |
| Verification | 如何驗證已解決 |

**Severity 門檻**：`BLOCKER` 與 `HIGH` 阻擋 `ACCEPT` / `CONSENSUS_ACCEPTED`。`MEDIUM` 與 `LOW` 不阻擋，但 Primary 必須逐項 adjudicate；未解決的 `MEDIUM` 須以 accepted-risk 記錄理由。

Review 重點（依任務調整）：correctness、contradictions、ownership、responsibility overlap、state transitions、data flow、failure modes、atomicity、idempotency、concurrency、compatibility、interfaces、assumptions、security、implementation feasibility、test gaps。writing/research 任務可改用：factual accuracy、unsupported claims、missing evidence、structure、clarity、audience fit、contradictory reasoning、omitted alternatives。

## 9. Primary Adjudication

Primary 逐項獨立判斷，標 `AGREE` / `PARTIAL` / `DISAGREE`。Reviewer 的結論本身不是 source of truth；重要 factual claim Primary 一律自行驗證。

- `AGREE`：finding 成立，確實需要處置。說明 resolution 類型並據實回覆：
  - `change_applied`：採取何種修改、如何滿足 requirement。
  - `requires_user`：此 finding 需使用者決策（見第 11 節 B）。
  - `blocked_external`：外部阻塞，無可安全合法的內容修改。
- `PARTIAL`：指出同意/不同意部分、原建議問題、採用的精確替代方案。
- `DISAGREE`：finding 不成立，或經查證現狀已滿足其要求（無需修改）。必須附可驗證證據（source、documentation、tests、behavior、data、contract、compatibility rule），不得只表態。

Primary 同時檢查 Reviewer 建議是否引入 circular dependency、non-atomic behavior、undefined ownership、compatibility break、new failure mode、incomplete interface、untestable requirement、scope creep。

## 10. Consensus Loop

「未解決 finding」定義：任何尚未被 Reviewer 標為 `FIX_VERIFIED` 或 `FINDING_WITHDRAWN` 的 finding 都是未解決。Primary 的 `AGREE/PARTIAL/DISAGREE` 只代表 Primary 立場，不能自行關閉 finding——第一輪非 `ACCEPT` verdict 的每個 finding 都須進入迴圈由 Reviewer 確認。

後續輪次只處理未解決問題，不重做完整首輪 review，除非新 evidence 使原 assumptions 失效。提供同一 Reviewer：原始 task/target、原 finding、Primary 的 `AGREE/PARTIAL/DISAGREE`、新 evidence、Primary 的修改方案。Reviewer 不得禮貌附和，逐項標：

- `FIX_VERIFIED`：Primary 修改已驗證，finding CLOSED。
- `FINDING_WITHDRAWN`：認同 Primary 反駁，撤回，finding CLOSED。
- `FINDING_REVISED`：接受部分、調整 finding；以修訂後的 finding 重新進入 adjudication（仍 OPEN）。
- `FINDING_UPHELD`：維持原 finding，Primary 回應不足（仍 OPEN）。

**迴圈退出**：

- 所有 finding CLOSED 且滿足第 11 節 A 條件 → `CONSENSUS_ACCEPTED`。
- 某一 `BLOCKER`/`HIGH` finding 在交換證據後仍被 `FINDING_UPHELD`，且雙方都無法提出決定性驗證時，依性質 escalation：主觀取捨 → `USER_DECISION_REQUIRED`（第 11 節 B）；技術事實無法驗證 → `BLOCKED`（`evidence_unavailable`，第 11 節 C）。
- 不得在仍有 OPEN 的 `BLOCKER`/`HIGH` finding 時宣告 `CONSENSUS_ACCEPTED`。

新 finding 必須真的由新 evidence 或修改方案產生、使用新 ID、符合第 8 節完整 schema，不得重述舊 finding。事實爭議優先以 source / tests / documentation / contract / 非破壞性驗證解決。不製造假共識，也不無限討論無法技術證明的純主觀差異。

## 11. Termination

只在下列之一成立時停止：

### A. `CONSENSUS_ACCEPTED`

所有 `BLOCKER` / `HIGH` findings 已解決，且：無未處理重大 contradiction、ownership/responsibility boundary 已定、state transitions 無衝突、interfaces/inputs/outputs 已明確、compatibility rules 已定義、failure handling 已定義、重要操作 sequencing/atomicity 已明確、必要 tests 可直接實作、binding requirements 不需實作者猜測重要決策。

Reviewer 明確輸出 `CONSENSUS_ACCEPTED` 後，Primary 仍須自行檢查一次；只有 Primary 也明確接受，才算成立。

### B. `USER_DECISION_REQUIRED`

剩餘分歧屬 product/UX preference、cost/latency/quality tradeoff、irreversible choice、risk tolerance、business priority，或多元技術方案皆成立但無客觀唯一答案時，停止技術辯論，列出：選項、各自 tradeoff、雙方共同同意的事實、真正需使用者決策的部分。

### C. `BLOCKED`

必要 evidence 無法取得、外部限制使技術事實無法驗證，或無法取得任何第二 AI 時，標 `BLOCKED`（reason 可用 `evidence_unavailable` / `review_unavailable`）。不得把 `BLOCKED` 包裝成共識，也不得在無 Reviewer 時自行製造共識。

## 12. Failure Handling

處理 Reviewer invocation 的 execution failure、timeout、unavailable tool、authentication/permission failure、invalid output、invalid structured data、incomplete response、session failure：

1. 判斷能否安全重試；不得因回覆較慢而重複送出仍可能執行中的 request。
2. 原 Reviewer 不可用可改選另一適合 AI Agent。
3. structured output 無效，可在不改變 review scope 下要求重新輸出。
4. 不得以 Primary 自己的內容冒充 Reviewer 結果。
5. 無法取得第二 AI 時，回報 `BLOCKED`（`review_unavailable`），不得宣稱已完成 Cross-AI consensus。Reviewer failure 不代表 Primary 工作錯誤，但也不代表已達成雙模型共識。

## 13. Reference Invocations

以下只是常見 invocation pattern，非 binding interface；實際 command/flags 以工具版本與環境為準。選用時以「independent model + focused context + minimum permission + structured result + verifiable review」為原則。

```bash
# Codex
codex exec "<review-prompt>" -C "<workdir>" --sandbox read-only --json

# Claude Code
claude -p "<review-prompt>" --output-format json --permission-mode plan

# OpenCode
opencode run "<review-prompt>" --dir "<workdir>" --format json
```

可依環境調整 model、flags、reasoning/effort、permissions、agent、working directory、session、timeout、output format、available tools。不得假設示例中的 executable、flag、permission mode、JSON schema、session behavior 在所有版本皆固定存在。

## 結語

Primary 保有 ownership；Reviewer 提供獨立 challenge；review 基於 evidence 而非 authority；分歧經由驗證解決而非禮貌消失。流程持續到 `CONSENSUS_ACCEPTED`、`USER_DECISION_REQUIRED` 或 `BLOCKED`。
