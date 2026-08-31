# Direct Implementation

**prompt → implement**

最直接的工作模式：需求與做法都已經清楚，直接把 prompt 交給 agent 一次做完，不做中間的探索、規劃或比較。

## 現成做法與參考

- 社群「issue → 實作」prompt 範本（跨 Claude Code / Codex / Cursor 通用）
- Claude Code 的 `SKILL.md` 任務模板（Objective → Inputs → Operating rules → … → Final response）
- `awesome-goal-prompts` 的契約結構

## 可萃取的原則

1. **完成條件與驗證要可判定**——用 `DONE WHEN` / `VERIFY` 明確「何時算完成、如何驗證」，而非「扮演資深工程師」。
2. **先調查再動手**——改之前先讀 `AGENTS.md`、找到現有實作與測試。
3. **計畫先於編輯**——「計畫清楚前不要改檔案」，但計畫可以很短。
4. **最小安全變更**——不加大依賴、不改不相關檔案、不刪測試讓它通過。
5. **證據不足就停**——需求模糊時停下問，不要猜。
6. **最終回報格式固定**——改了什麼 / 檔案清單 / 指令與結果 / 剩餘風險。

## 對照 skill 的準備

| 開 Ticket 前準備 | Ticket 內容準備 |
|---|---|
| 確認需求與**實作方式**都清楚（兩者皆定才走 direct） | 寫清楚 Acceptance criteria（可勾選） |
| 確認無需探索、無需比較方案 | Verification 給可執行指令或「從 repo 文件發掘」 |
| 確認單一連貫目標 | Scope 標明 out of scope，防 agent 擴張 |

## 適用時機

- 已知**修法**的 bug fix（注意：只知道根因、還不確定怎麼改，不算；那屬於 `open-implementation`）
- 明確規格、做法也指定的小功能

> 對應 skill 三模式中的 `precise`（成果與 HOW 都已定）。
