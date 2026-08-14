---
name: x-debug
description: 以 evidence 驗證 root cause 後修復、補 regression test 並重新驗證。
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


# x-debug

## Iron law

**沒有 root-cause investigation，不得先修。**

## When to use

- 已有錯誤、失敗測試、production symptom、review finding，但原因不清楚。
- 不用於一般 feature planning 或「順便重構」。

## Inputs

通用輸入：使用者 Prompt / 明確目標、專案背景、repo 文件、程式碼與 Git 狀態；另加 symptom、reproduction、logs/stack trace、review finding、affected branch/work item。

## Outputs

- `artifacts/debug/DBG-XXX.md` 或 standalone debug report
- root-cause fix、regression test、verification evidence
- WG context 下更新 work item / WG / `hub.md`

## Required workflow

1. 收集 symptom、reproduction、recent changes 與相關 code path。
2. 提出具體且可測試的 root-cause hypothesis。
3. 用 log/assertion/minimal experiment 驗證；錯誤則回到 evidence gathering，不猜。
4. 三個 hypothesis 失敗後停止並升級。
5. 確認 root cause 後做最小修正，限制 blast radius。
6. 新增 regression test：無 fix 時失敗、有 fix 時通過。
7. 重現原問題、跑相關與必要 full tests，產生 debug report。

## Handover

WG context 下，任何 fix 都使舊 review stale；下一步固定是 `x-review`，不是直接 `x-ship`。

## Bundled assets

- `templates/debug-report.md`：記錄 symptom、hypothesis、evidence、confirmed root cause、fix、regression 與 handover。

Standalone mode 沒有 Cycle 時，將 evidence 寫在 project-local `.dev-hub/runtime/x-debug-*/` 或使用者指定路徑；有 Cycle/WG 時寫入 `artifacts/debug/DBG-XXX.md` 並更新 work item、WG 與 `hub.md`。不得以 symptom-only patch 取代已驗證的 root-cause fix。
