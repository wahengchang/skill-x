---
name: x-ship
description: 完成 final gates、文件同步、獨立 review、commit/push，並 create-or-update 一個 PR。
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


# x-ship

## When to use

Implementation 已完成，準備正式交付 branch / WG。不得在 base branch 上直接 ship feature work。

## Inputs

通用輸入 + current branch/worktree、final work item/WG、tests、acceptance、review status、remote/PR context。

## Outputs

- final code/docs commits
- pushed branch
- 一個 create-or-update PR
- Cycle mode 下更新 WG、IS/SP 與 `hub.md`

## Required order

1. Preflight：辨識 base、branch、diff、uncommitted work、WG/PR ownership。
2. Sync base：fetch + merge/rebase 依 repo policy；無法安全解 conflict 時停止。
3. Final content：跑 tests/acceptance，完成 factual documentation sync。
4. 對最終內容計算 fingerprint；沒有 fresh `x-review` approval 時 dispatch `x-review` 或 BLOCKED。
5. Review 通過後不得再修改內容；跑不改檔的 tests/checks。
6. Commit、驗證 committed tree 與 reviewed fingerprint 相同，push + create-or-update 一個 PR。
7. 更新 WG、work items 與 `hub.md`。

## Stop gates

- merge conflict、in-branch test failure、review changes requested、沒有 fresh independent reviewer、destructive release decision、required credential/remote 缺失。

## Handover

PR 建立後等待 merge；merge 完成 → `x-housekeeping`。

## Bundled assets

- `../x-review/scripts/x-review-target`：在 final review gate 使用；預設 worktree fingerprint 必須包含未提交內容。
- `../x-review/templates/review-result.md`：確認 final independent approval 的 implementer/reviewer identity 與 reviewed fingerprint。

不得從 base branch 直接 ship feature work。任何 final content 改動都使 review stale；required credential、merge conflict、test failure 或 independent reviewer 不可用時必須 BLOCKED，不得略過 gate。
