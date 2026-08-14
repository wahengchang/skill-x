---
name: x-discovery
description: 掃描專案或指定範圍，建立 Cycle、專案總覽與工作總表；找齊工作但不深入實作。
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


# x-discovery

## When to use

- 新專案、既有系統、功能區域或風險區域需要完整攤開看清楚。
- 需要建立後續可持續更新的工作池。

不要用於單一工作的完整工程規劃、實作、review 或 debug。

## Inputs

通用輸入：使用者 Prompt / 明確目標、專案背景、repo 文件、程式碼與 Git 狀態。若已有 Cycle，可指定更新該 Cycle。

## Outputs

- `.dev-hub/active/cycle-<datetime>-<slug>/hub.md`
- 必要 evidence：`artifacts/discovery/`
- 工作候選只登錄為 `WK-XXX`；正式 IS/SP 文件由 `x-plan-eng` 建立

## Required workflow

1. **建立或選擇 Cycle**：同一個明確 scope 的重跑更新既有 Cycle，不重複建檔；若同 slug 對應多個 Cycle，停止並要求明確 target。
2. **Repo-first 探索**：讀必要 docs、code、config、schema、Git history；能自行確認的內容不要詢問 Owner。
3. **輸出四種視圖**：主模組總覽、模組依賴與資料流、子模組拆解、工作總表。
4. **工作登錄**：每列包含工作、原因、影響區域、風險、優先序、type hint、status。
5. **未知分類**：`ready-for-planning`、`owner-decision` 或 `no-action`；正式分類由 `x-plan-eng` 完成。
6. **收尾**：Owner 只讀 `hub.md` 就能看到全貌、工作與決策點。

## Work table minimum

| Candidate | Work | Type hint | Why | Area | Risk | Priority | Status | Formal item | Owner | WG |
|---|---|---|---|---|---|---|---|---|---|---|

## Handover / continue

每次完成都輸出 `Current state / Completed / Blockers / Owner decision / Next / Target`。收到 `continue` 時依序使用：明確 target → 上次 `Handover.Next` → WG stage → 唯一 active WG → Cycle 中最高優先且 ready 的 WG；仍有多個合理目標才詢問一次。

預設完成狀態：`discovery-complete`；下一步：`x-plan-eng`；Target：本 Cycle 或指定 `WK-XXX`。

## Bundled assets

- `templates/cycle-hub.md`：Cycle source-of-truth 模板。
- `scripts/x-paths`：從 linked worktree 解析 main repository root 與 `.dev-hub`。
- `scripts/x-id`：collision-safe 配發 `WK/IS/SP/WG/RV/DBG` ID。
- `scripts/x-cycle`：建立或重用同 scope Cycle，portable 初始化 `hub.md`。

所有 temporary/runtime/worktree state 都必須留在 main repository 的 project-local `.dev-hub/`。確保 `.dev-hub/active/`、`.dev-hub/worktrees/`、`.dev-hub/runtime/` 被 ignore，而 `.dev-hub/logs/` 保持 tracked。
