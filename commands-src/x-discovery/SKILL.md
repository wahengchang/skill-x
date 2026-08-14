---
name: x-discovery
description: 掃描專案或指定範圍，建立 Cycle、專案總覽與工作總表；找齊工作但不深入實作。
---

# x-discovery

## When to use

- 新專案、既有系統、功能區域或風險區域需要「完整攤開看清楚」。
- 需要建立後續可持續更新的工作池。

不要用於單一工作的完整工程規劃、實作、review 或 debug。

## Inputs

通用輸入：專案背景、repo 文件、程式碼、Prompt。若已有 Cycle，可指定更新該 Cycle。

## Outputs

- `.dev-hub/active/cycle-<datetime>-<slug>/hub.md`
- 必要 evidence：`artifacts/discovery/`
- 工作候選只先登錄為 `WK-XXX`；正式 IS/SP 文件由 `x-plan-eng` 建立。

## Required workflow

1. **建立或選擇 Cycle**：同一個明確 scope 的重跑應更新既有 Cycle，不重複建檔。
2. **先探索**：讀必要 docs、code、config、schema、Git history；能自行確認的內容不要詢問 Owner。
3. **輸出四種視圖**：主模組總覽、模組依賴與資料流、子模組拆解、工作總表。
4. **工作登錄**：每列包含工作、原因、影響區域、風險、優先序、type hint、status。
5. **未知分類**：`ready-for-planning`、`owner-decision` 或 `no-action`；正式分類由 `x-plan-eng` 完成。
6. **收尾**：Owner 只讀 `hub.md` 就能看到全貌、工作與決策點。

## Work table minimum

| Candidate | Work | Type hint | Why | Area | Risk | Priority | Status | Formal item | Owner | WG |
|---|---|---|---|---|---|---|---|---|---|---|

## Handover

完成後推薦：`continue` → `x-plan-eng` 處理全部或指定 `WK-XXX`。

## Bundled assets

- `templates/cycle-hub.md`：新 Cycle 的可讀 source-of-truth 模板。
- `scripts/x-paths`：從 linked worktree 解析 main repository root 與 `.dev-hub`。
- `scripts/x-id`：原子保留 ID；`WK-NNN` 只存在於 hub 工作表，正式 `IS/SP/WG/RV/DBG` 才建立 canonical `.md` 路徑。
- `scripts/x-cycle`：建立或重用同 scope 的 Cycle，並以 `cycle-hub.md` 初始化 `hub.md`。

所有 temporary/runtime/worktree state 都必須留在 project-local `.dev-hub/`，不得建立 global `~/.x-*` 或 shared `/tmp` state。
確保 `.dev-hub/active/`、`.dev-hub/worktrees/`、`.dev-hub/runtime/` 被 ignore，而 `.dev-hub/logs/` 保持 tracked。
