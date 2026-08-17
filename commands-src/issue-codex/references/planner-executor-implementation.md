# Planner–Executor Implementation

**strong model → research / judge / plan → cheaper model → implement → strong model → review**

把「想」和「做」拆給不同能力的模型：強模型負責研究、判斷、規劃與最終審查；便宜模型只負責照計畫實作。核心是「規劃與審查的品質，不由實作者自己把關」。

## 現成做法與參考

- **shadcn/improve**：一個 standalone 的 read-only advisor skill（非 shadcn CLI v4 內建 skill）。預設流程是 survey codebase → 審查 findings → 寫出計畫；只有明確的 `execute <plan>` 變體才會派一個**獨立的 executor** 去實作、再由 advisor review 其 diff。它本身不內建 agent-council 組合。

## 可萃取的原則

1. **規劃與審查用強模型，實作用便宜模型**——省成本，但品質閘門不降。
2. **先 survey 再計畫**——強模型先盤點現況，計畫才有依據。
3. **實作者照計畫走，不重新詮釋需求**——計畫是契約。
4. **最終審查獨立於實作**——實作者不能自己當裁判。
5. **checkpoint**——長流程中設檢查點，避免一路做偏。

## 對照 skill 的準備

| 開 Ticket 前準備 | Ticket 內容準備 |
|---|---|
| 判定工作夠大、值得分「規劃/實作/審查」→ 走這條 | Goal 寫清楚成果，供規劃模型對齊 |
| 確認實作可由便宜模型照計畫完成 | Scope 寫明邊界，計畫不得超出 |
| 準備好驗證基準，供審查模型比對 | Verification 寫明最終審查要核對什麼 |

## 適用時機

- 較大、較複雜的工作，值得花強模型做規劃
- 想節省 token 成本、又想維持品質
- 有明確驗證基準可讓強模型審查

> 對照 skill 三模式：**issue-codex 不實作 planner–executor 的角色分離**。它的 dispatch 是單一 Codex 任務，由同一個任務 inspect → implement → 自我 review diff，**沒有**選不同模型、也沒有獨立的最終審查者。因此開 Ticket 時**不得**在 ticket 中承諾「會由強模型規劃、便宜模型實作、強模型獨立審查」——除非未來加上了真的能指派這些角色的 dispatch 契約。目前只能把「規劃、實作、審查」的**完成條件**寫清楚，執行策略仍由 Codex 自行決定。
