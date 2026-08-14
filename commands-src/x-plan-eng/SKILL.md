---
name: x-plan-eng
description: 把工作表中的每項工作定義完整，建立 Issue/Spike/WG 文件、Owner、branch/worktree，準備到可直接執行。
---

# x-plan-eng

## When to use

- `x-discovery` 已建立 `hub.md`，需要把工作逐項準備到可以直接開工。
- 單一複雜需求需要完整工程規劃，即使沒有 Dev Hub 也可使用。

本 Skill 不實作產品程式碼，也不做最終 code review。

## Inputs

通用輸入：專案背景、repo 文件、程式碼、Prompt。Cycle mode 額外讀 `hub.md` 與指定 `WK-XXX`；Standalone mode 直接以使用者需求作為單一工作。

## Outputs

- `work-items/IS-XXX-<slug>.md` 或 `SP-XXX-<slug>.md`
- `work-groups/WG-XXX-<slug>.md`
- 更新 `hub.md` 的 formal item、Owner、WG、status
- `1 WG = 1 branch = 1 worktree = 1 PR` 的執行環境

## Required workflow

1. 選定一項、指定多項，或全部 `ready-for-planning` rows。
2. 深入讀 repo，確認現況、既有 pattern、interfaces、schema 與相關 tests。
3. 分類為 `IS-XXX`（可直接實作）或 `SP-XXX`（需實驗才能決策）。
4. 定義 problem、scope、architecture/data flow、dependencies、failure modes、implementation order、tests、acceptance 與 DoR。
5. Assign Owner 時建立或分配 WG；一個 item 同時只屬於一個 WG。
6. 建立 branch/worktree，更新 status 為 `ready`，確認未參與規劃的 implementer 可直接開始；重跑時重用既有 WG branch/worktree，絕不建立重複項目。

## Handover

- `IS-XXX` → `implement IS-XXX` 或 `continue`。
- `SP-XXX` → `execute SP-XXX` 或 `continue`；完成後回填 evidence/結論。

## Bundled assets

- `templates/issue.md`：IS 的 scope、architecture/data flow、risk、tests、acceptance 與 DoR 模板。
- `templates/spike.md`：單一核心問題、evidence 與 decision rule 的 SP 模板。
- `templates/work-group.md`：`1 WG = 1 branch = 1 worktree = 1 PR` 的執行邊界模板。

建立檔案前先讀取並保留未知 Markdown 區段；更新必須 atomic。只有產品方向、scope、priority 或 user-visible behavior 才詢問 Owner，技術選擇先提出有證據的推薦方案。
