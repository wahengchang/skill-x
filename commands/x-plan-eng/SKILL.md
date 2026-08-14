---
name: x-plan-eng
description: 把工作表中的每項工作定義完整，建立 Issue/Spike/WG 文件、Owner、branch/worktree，準備到可直接執行。
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


# x-plan-eng

## When to use

- `x-discovery` 已建立 `hub.md`，需要把一項、選定多項或全部工作準備到可直接開工。
- 單一複雜需求需要完整工程規劃，即使沒有 Dev Hub 也可使用。

本 Skill 不實作產品程式碼，也不做最終 code review。

## Inputs

通用輸入：使用者 Prompt / 明確目標、專案背景、repo 文件、程式碼與 Git 狀態。Cycle mode 額外讀 `hub.md` 與指定 `WK-XXX`；Standalone mode 直接以使用者需求作為單一工作。

## Outputs

- `work-items/IS-XXX-<slug>.md` 或 `SP-XXX-<slug>.md`
- `work-groups/WG-XXX-<slug>.md`
- 更新 `hub.md` 的 formal item、Owner、WG、status
- `1 WG = 1 branch = 1 worktree = 1 PR` 的可執行環境

## Required workflow

1. **選定工作**：一項、指定多項，或全部 `ready-for-planning` rows；先查既有 formal item/WG，重跑不得 duplicate。
2. **Repo-first evidence**：深入讀現況、既有 patterns、interfaces、schema、相關 tests 與 history。不要把可查問題丟給 Owner。
3. **Scope challenge**：逐項確認現有 code 是否已部分解題、最小完整 change 是什麼、是否有 built-in/current pattern 可避免自製平行系統；把不阻塞核心目標的內容明確列為 out-of-scope。
4. **分類 Work Type**：`IS-XXX` = 已能定義實作與 acceptance；`SP-XXX` = 必須先靠 experiment/prototype/research 才能決策。
5. **完成工程定義**：problem/goal、scope in/out、architecture/boundaries/data flow、state transitions、interfaces/dependencies、migration/config、failure modes/edge cases/security/data risks、implementation order、tests、acceptance、DoR。複雜 flow 必須用 ASCII diagram。
6. **Spike 規則**：一個 SP 只回答一個核心問題；寫清方法、evidence、decision rule 與唯一可執行結論，不丟選項清單給執行者。
7. **Test design**：列 happy/negative/edge/regression 路徑；需要時畫 test/data-flow 圖，確保未參與規劃的 implementer 能直接執行。
8. **Assign Owner / WG**：使用現有 Agent/team roster，不捏造真人；一 item 同時只屬於一個 WG。重大且接近的 trade-off 要先給具體推薦與理由，再問 Owner。
9. **準備執行**：以 `scripts/x-worktree ensure` 建立或重用 WG branch/worktree；寫回 WG 與 `hub.md`，status 才能變成 `ready`。

## Owner questions

只在產品方向、scope、priority、user-visible behavior、重大不可逆 trade-off 無法由 evidence 解決時詢問。普通技術選擇先給 opinionated recommendation。

## Handover / continue

每次完成都輸出 `Current state / Completed / Blockers / Owner decision / Next / Target`。收到 `continue` 時依序使用：明確 target → 上次 `Handover.Next` → WG stage → 唯一 active WG → Cycle 中最高優先且 ready 的 WG；仍有多個合理目標才詢問一次。

`IS-XXX` → `implement IS-XXX`；`SP-XXX` → `execute SP-XXX`，完成後回填 evidence/結論。

## Bundled assets

- `templates/issue.md`：可由陌生 implementer 直接執行的 IS 工程規格。
- `templates/spike.md`：單一 decisive question 的 SP 模板。
- `templates/work-group.md`：WG 執行與交付邊界。
- `scripts/x-worktree`：idempotent 建立/重用 `1 WG = 1 branch = 1 worktree`。

更新 Markdown 前先讀取並保留未知區段；寫入採 atomic replacement。所有 `.dev-hub` 路徑必須解析到 main repository root。
