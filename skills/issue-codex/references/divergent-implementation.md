# Divergent Implementation

**approach A / B / C → compare → synthesize**

不只探索後選一個，而是**同時展開多個方案**，做出來後比較，最後綜合出一個最佳結果。適合「哪種做法比較好」無法靠紙上談兵決定、必須實做比對的情況。

## 現成做法與參考

- **feature-council**（`michaelboeding/skills`）：把原始請求直接交給多個獨立 solver 各自實作完整 feature，再比較、綜合（synthesize），不是多數決。這就是「多方案並行＋比較綜合」的來源。
- 註：`agent-council`（`andrewvaughan`）是另一套——它的 Product / Feature Council 做 scope 與技術規劃，再接 build lifecycle，**不做**並行的完整實作比較。兩者不要混為一談。

## 可萃取的原則

1. **（可選 hybrid）先評後做**——若想先由規劃 council 篩 scope/priority/design，那是 agent-council 的做法，會**犧牲 feature-council 的純獨立性**（feature-council 明確禁止 orchestrator 探索，直接送 raw prompt 給獨立 solvers）。純 feature-council 沒有這一步。
2. **多方案並行，各自獨立實作**——A、B、C 互不依賴，才能公平比較。
3. **比較要有基準**——比較的是「結果」，不是「誰講得大聲」；基準需事先定義。
4. **最後要綜合（synthesize），不是只挑一個**——把各方案的優點合併成最終版。
5. **成本高**——多份實作成本是 N 倍，只在值得時使用。

## 對照 skill 的準備

| 開 Ticket 前準備 | Ticket 內容準備 |
|---|---|
| 判定「需要實做比對多方案」→ 走這條 | Scope 明確列出要比較的 2–3 個方案 |
| 與使用者確認成本（多份實作）可接受 | 定義比較基準與「綜合」的產出形式 |
| 這是「單一目標多方案」，不是多個獨立目標 | 用 `precise` 骨架（Goal/Context/Scope/Requirements/Acceptance criteria/Verification），**不要用** exploration 的 `Expected output` |

## 適用時機

- 多個技術方案各自都有理，需要實做驗證
- 架構選型、演算法選型、重大重寫方向
- 團隊願意承擔 N 倍實作成本換取較佳決策

> 對應 skill 三模式：`precise`（成果是 code，多方案比較只是「如何做」）。A/B/C 是**同一工程結果的替代實作**——依 duplicate invariant，**不得**拆成多張 issue（會撞「substantially the same outcome」）。要拆單，只有當每個子結果各自可獨立交付、而非僅是不同實作路徑時才成立。若交付物只是「比較報告」且不保留 code，才另開 `exploration` issue。
