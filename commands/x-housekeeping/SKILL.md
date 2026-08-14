---
name: x-housekeeping
description: 安全清除完成 worktree、merged local branch、runtime/tmp，並將完成 Cycle 壓成短 log。
---

<!-- 此區塊由 bin/build.sh 自動加入，請勿直接修改部署版本。 -->

## 執行前更新檢查

執行本技能前，先從目前 `SKILL.md` 的實體路徑向上尋找 skill-x-starter repository，並執行其 `bin/update-check`。

- 找不到 repository 或找不到 `bin/update-check`（例如雲端 / 容器部署只複製了技能檔案，沒有腳本）：直接執行技能，不要提及更新檢查。
- `UP_TO_DATE` 或沒有輸出：直接執行技能，不要向使用者提及更新檢查。
- `UPGRADE_AVAILABLE <local> <remote>`：先用目前工具的互動詢問能力詢問使用者是否更新，不可靜默更新。
- 使用者同意：執行同一 repository 的 `bin/apply-update.sh`，成功後繼續技能。
- 使用者拒絕：執行 `bin/snooze.sh`（預設延後 7 天），再繼續技能。
- 檢查或更新失敗：不要阻擋技能；只在失敗會影響本次任務時簡短告知。


# x-housekeeping

## When to use

- PR 已 merge，需要清理 WG branch/worktree。
- Cycle 所有 work items 已終止，需要關閉並留下永久 log。
- repo 內存在 stale `.dev-hub/runtime/`、orphan worktree metadata 或已完成 tmp。

## Inputs

通用輸入：使用者 Prompt / 明確目標、專案背景、repo 文件、程式碼與 Git 狀態；另加 Git worktree/branch/PR state 與 Cycle/WG files。預設只清理已證明安全的項目。

## Outputs

- 刪除完成 worktree、merged/integrated local branch、safe runtime/tmp
- `git worktree prune`（需要時）
- `.dev-hub/logs/cycle-*.md`
- Cycle closure / housekeeping commit

## Safety gates

不得刪除 dirty worktree、未 push/未到達 remote integration target 的 commit、active/unmerged branch、狀態不確定的 work item/WG，或 remote branch（除非使用者明確要求）。

## Required workflow

1. 先 fetch/prune relevant remote，掃 `.dev-hub/active`、`worktrees`、`runtime` 與 `git worktree list`。
2. 對每項分類：safe-remove / active / orphan-needs-proof / blocked。
3. `scripts/x-clean` 必須同時證明 candidate 已整合到 local target **且**已到達該 target 的 remote/upstream；只 locally merged 不算 safe。
4. safe worktree 使用 `git worktree remove`；之後需要才 `git worktree prune`。
5. 只刪已 remote-proven integrated 的 local branch；remote branch 預設永不刪除。
6. 清除已完成 standalone runtime / Cycle tmp；不碰 active evidence。
7. Cycle closure gate：全部 work items 為 `done/cancelled/deferred`，且無 active/unmerged WG。
8. 產生短 Cycle log，刪 active Cycle directory，commit 新 log。

## Handover / continue

每次完成都輸出 `Current state / Completed / Blockers / Owner decision / Next / Target`。收到 `continue` 時依序使用：明確 target → 上次 `Handover.Next` → WG stage → 唯一 active WG → Cycle 中最高優先且 ready 的 WG；仍有多個合理目標才詢問一次。

若尚有 unmerged/unpushed work，`Next` 必須是完成/等待該 PR，不得強制清理。

## Bundled assets

- `templates/cycle-log.md`：Cycle closure 的短永久紀錄。
- `scripts/x-clean`：安全判斷與移除 linked worktree/local branch；remote reachability 是 hard gate。
