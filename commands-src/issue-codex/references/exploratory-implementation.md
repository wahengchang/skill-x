# Exploratory Implementation

**explore → select → plan → implement**

需求不算模糊，但「怎麼做」還沒定：先探索（了解現況與方案）→ 選定一個方案 → 出計畫 → 實作。核心是把「理解與決策」放在「寫 code」之前。

## 現成做法與參考

- **OpenSpec**：artifact flow 為 `proposal → specs → design → tasks → implement`；四原則「fluid not rigid、iterative not waterfall、easy not complex、brownfield-first」；spec 是 single source of truth。
- **Superpowers**：brainstorm → approve design → plan → TDD implement → review → verify；**把初始請求當「不完整的需求」而非「實作規格」**。
- **Arc**：select → plan → implement（先選方案，再規劃，再執行）。

## 可萃取的原則

1. **先列 2–3 個方案與 trade-off，再選一個**——不要直接照第一個念頭做。
2. **設計要經使用者批准才動工**（Superpowers 的 gate：No code before design）。
3. **澄清問題一次問一個**——不要一次倒一長串。
4. **計畫要具體**——檔案路徑、小任務、先寫測試、驗證指令、commit 邊界。
5. **規格是會變的（fluid not rigid、iterative not waterfall）**——邊做邊精煉，不鎖死 phase gate。
6. **brownfield-first**——先看既有 codebase 與慣例，別從空白開始。
7. **證據勝過聲稱**——做完要跑測試，不能只說「應該可以」。

## 對照 skill 的準備

| 開 Ticket 前準備 | Ticket 內容準備 |
|---|---|
| 判定「做法未定、需要探索選方案」→ 走這條 | Goal 寫清楚「要達成什麼」 |
| 若需使用者在多方案間拍板，**先問** | Context 記錄現況、動機、已知約束 |
| 檢查是否已有可套用的方案，避免重複探索 | Requirements 寫可觀察結果，不預先鎖死方案 |

## 適用時機

- 功能方向清楚，但技術方案未定
- 需要先理解既有架構再決定怎麼做
- 「成果明確、HOW 留白」的工作

> 對應 skill 三模式：**探索選方案的工作交給 Codex 做 → `open-implementation`**；**若使用者在開 Ticket 前已選定方案 → `precise`**（HOW 已定，不再是 open）。模式要在使用者是否選完方案**之後**才定。
