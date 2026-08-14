---
name: x-review
description: 由非實作者的獨立 Agent 審查 final diff，管理 findings、fix 與 re-review 閉環。
---

# x-review

## Hard rule: Maker / Checker separation

最終 Reviewer 必須與 implementation Agent 不同，並以 fresh session/context 執行。若 host 無法啟動獨立 Agent，結果是 `BLOCKED_NO_INDEPENDENT_REVIEWER`，不得 self-review 後假裝通過。

Reviewer 預設 read-only。若 Reviewer 修改任何被審查內容，其 independent approval 立即失效，必須由另一個新 Agent 做 final review。

## Inputs

通用輸入 + target branch/base、完整 final diff、IS/SP/WG 文件、tests、repo rules。Standalone mode 可只提供 PR/diff/Prompt。

## Outputs

- Cycle mode：`artifacts/reviews/RV-XXX.md`，並更新 WG / `hub.md`
- Standalone：結構化 review report；需要 handover 時寫入指定路徑或 main repo `.dev-hub/runtime/`

## Required workflow

1. 記錄 implementer identity、reviewer identity、base、target fingerprint；fresh reviewer 優先使用不同 session，host 支援時可用不同 model/provider 作 outside voice。
2. 讀完整 diff，再讀必要的 diff 外 consumer code；不能只 grep。新增 enum/status/API/schema 時必須追全部 consumers/allowlists/switches。
3. **Critical pass**：correctness/data safety、race/concurrency、security/trust boundaries、shell/command injection、enum/value/API/schema completeness。
4. **Completeness pass**：error paths、type/boundary coercion、performance、test gaps、scope/plan completeness、distribution/CI、documentation staleness。只報真實問題，不報 style noise。
5. 每個 finding 必須有 severity、evidence、`file:line`、failure scenario、recommended resolution；聲稱「已處理/有測試/安全」時要指出實際證據，不用 `likely/probably`。
6. Reviewer 不修 code；findings 交回原 implementer。根因不明時交 `x-debug`。
7. Fix 後重新計算 fingerprint，再由獨立 Reviewer re-review；`APPROVED` 必須綁定 final fingerprint，任何內容改動都 stale。

## Verdicts

- `APPROVED`
- `CHANGES_REQUESTED`
- `BLOCKED_NO_INDEPENDENT_REVIEWER`
- `BLOCKED_INSUFFICIENT_EVIDENCE`

## Handover / continue

每次完成都輸出 `Current state / Completed / Blockers / Owner decision / Next / Target`。收到 `continue` 時依序使用：明確 target → 上次 `Handover.Next` → WG stage → 唯一 active WG → Cycle 中最高優先且 ready 的 WG；仍有多個合理目標才詢問一次。

`CHANGES_REQUESTED` → 原 implementer fix / `x-debug`；`APPROVED` → `x-ship`。

## Bundled assets

- `templates/review-result.md`：maker/checker identity、base、fingerprint、findings 與 handover。
- `scripts/x-review-target`：hash tracked + untracked final worktree content；scratch 固定寫 main repo `.dev-hub/runtime/`，並提供 portable SHA-256 fallback。
