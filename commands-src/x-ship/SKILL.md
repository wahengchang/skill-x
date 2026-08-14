---
name: x-ship
description: 完成 final gates、文件同步、獨立 review、commit/push，並 create-or-update 一個 PR。
---

# x-ship

## When to use

Implementation 已完成，準備正式交付 branch / WG。不得在 base/default branch 上直接 ship feature work。

## Inputs

通用輸入 + current branch/worktree、final work item/WG、tests、acceptance、review status、remote/PR context。

## Outputs

- final code/docs commits
- pushed branch
- 一個 create-or-update PR
- Cycle mode 下更新 WG、IS/SP 與 `hub.md`

## Required order

1. **Preflight**：辨識 default/base、branch、完整 diff、uncommitted work、WG/PR ownership；在 base/default branch 立即 BLOCKED。
2. **Sync base**：fetch + merge/rebase 依 repo policy；無法安全解 conflict 時停止。
3. **Tests / acceptance**：對 merged state 跑相關與必要 full checks；in-branch failure 不可略過。
4. **Documentation blast-radius audit**：掃 public surface、README/API/examples/config/architecture/TODOS/changelog 等 repo 慣例文件，建立「變更 → 文件」coverage；factual stale docs 直接同步，大型/敘事/安全語意變更交 Owner。ASCII/Mermaid diagram 有 drift 也要處理或明確列 debt。
5. **Independent review gate**：對最終 code + docs 計算 fingerprint；沒有 fresh `x-review` approval 時 dispatch 獨立 reviewer，無法取得則 BLOCKED。
6. **Final verification**：review 通過後不得再改內容；只跑不改檔 checks。
7. **Commit**：按 repo 慣例形成可理解、可 bisect 的 commit；不強加 gstack VERSION/CHANGELOG policy。
8. **Fingerprint check**：committed tree 必須等於 reviewed content；不相等就 stale → `x-review`。
9. **Push + PR**：先查同 head branch 的 open PR；有就 update，沒有才 create。優先使用 host PR provider；shell/gh 可用時可用 `scripts/x-pr ensure`。絕不建立第二個 PR。
10. **Write-back**：WG → `pr-open/shipped`，work items 與 `hub.md` 同步 PR URL、fingerprint、stage。

## Stop gates

merge conflict、in-branch test failure、review changes requested、fresh independent reviewer 不可用、destructive release decision、required credential/remote 缺失。

## Handover / continue

每次完成都輸出 `Current state / Completed / Blockers / Owner decision / Next / Target`。收到 `continue` 時依序使用：明確 target → 上次 `Handover.Next` → WG stage → 唯一 active WG → Cycle 中最高優先且 ready 的 WG；仍有多個合理目標才詢問一次。

PR 建立後 `Next: wait for merge`；merge 完成 → `x-housekeeping`。

## Bundled assets

- `scripts/x-pr`：GitHub CLI adapter 的 idempotent PR create-or-update；host 有 native provider 時可用等價流程。
- `../x-review/scripts/x-review-target`：final review fingerprint。
- `../x-review/templates/review-result.md`：核對 independent approval identity + fingerprint。
