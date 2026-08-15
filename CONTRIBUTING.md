# 開發一組新技能：操作手冊

這份文件給「要在這個 repo 裡新增/修改技能」的你自己（或未來接手的人）。README.md 是給使用者看的安裝說明，ARCHITECTURE.md 是給接手工程師看的設計決策；這份文件只講一件事：**動手加技能時，具體步驟跟命名規則是什麼**。

---

## 1. 心智模型：先搞清楚這幾個資料夾

| 資料夾 | 你會做什麼 |
|---|---|
| `commands-src/<name>/SKILL.md` | **唯一手動編輯的地方**。乾淨的技能內容，不含更新檢查樣板文字。 |
| `commands/<name>/SKILL.md` | `bin/build.sh` 產生的部署版本（frontmatter 之後多了 `_shared/update-check-header.md` 的內容）。**永遠不要手動改這裡**，改了下次 build 會被覆蓋。 |
| `opencode-commands/<name>.md` | `bin/build.sh` 產生的 OpenCode v1 command shim，讓技能可用 `/<name>` 叫用。同樣**不要手動改**。 |
| `~/.claude/skills/`、`~/.codex/skills/` 等 | `bin/sync-skills.sh` 把 `commands/` symlink 過去的地方，AI 工具實際讀取的路徑。 |

一句話：**改 `commands-src/` → `bin/build.sh` 重新產生 `commands/` 與 `opencode-commands/` → 三個資料夾一起 commit → push**。

---

## 2. 開發一顆新技能：完整步驟

```bash
cd ~/.skill-x-starter

# 1. 建資料夾，一個技能一個資料夾
mkdir -p commands-src/<skill-name>

# 2. 寫 SKILL.md（frontmatter 只需要 name + description，其餘是技能內容）
cat > commands-src/<skill-name>/SKILL.md <<'EOF'
---
name: <skill-name>
description: 一句話講清楚這個技能做什麼、什麼情況該被觸發。
---

實際的指令內容寫在這裡。
EOF

# 3.（可選）需要輔助檔案就直接放同一個資料夾，build.sh 會原封不動複製
mkdir -p commands-src/<skill-name>/scripts
# commands-src/<skill-name>/scripts/helper.sh ...

# 4. 重新產生部署版本
bin/build.sh

# 5. 跑一次整合測試，確認沒把 build/sync 腳本弄壞
make test

# 6. 本機同步一次，實際用用看（可選但建議）
bin/sync-skills.sh
bin/doctor.sh          # 確認四個技能路徑與 OpenCode command 區段都連結成功

# 7. 三個資料夾一起 commit，push
git add commands-src/<skill-name> commands/<skill-name> opencode-commands/<skill-name>.md
git commit -m "add <skill-name> skill"
git push
```

其他機器要跟上：`git pull && bin/sync-skills.sh`，或什麼都不做，等下次呼叫任一技能時它自己會問你要不要更新。

### 開發一整組（多顆）技能

架構上沒有「技能分組資料夾」這種東西（見 ARCHITECTURE.md 決策 #2：三邊指令集內容完全一致，不分子目錄客製）。一組技能就是「多個 `commands-src/<name>/` 資料夾，name 用同一個字首」——分組純粹靠**命名**跟 git 歷史，細節見下一節。

流程跟單顆技能一樣，差別只在一次做完 2～4 步後，一次 commit 多顆：

```bash
mkdir -p commands-src/myapp-deploy commands-src/myapp-rollback commands-src/myapp-status
# 分別寫好三份 SKILL.md ...
bin/build.sh
make test
git add commands-src commands opencode-commands
git commit -m "add myapp-* skill set (deploy, rollback, status)"
git push
```

### 一組技能共用同一份腳本

如果一組技能要共用腳本或樣板（`x-*` 就是這樣），**不要在每顆技能各放一份副本**——會漂移。作法是把共用檔案放在一個以底線開頭、不含 `SKILL.md` 的目錄（因此 `bin/build.sh` 不會把它當技能），再從各技能 symlink 過去：

```bash
mkdir -p commands-src/_myapp-shared/scripts
# commands-src/_myapp-shared/scripts/helper.sh ...

for s in myapp-deploy myapp-rollback; do
  ln -sfn ../_myapp-shared/scripts "commands-src/$s/scripts"
done
bin/build.sh
```

`bin/build.sh` 會解引用 symlink（`find -L` + `cp -aL`），所以 `commands/<name>/scripts/` 是**真實副本**，執行權限也保留。這是必要的：每顆技能是各自 symlink 進 `~/.claude/skills/<name>` 的，執行期讀不到兄弟技能的檔案（見 ARCHITECTURE.md 決策 #10）。

代價是 `commands/` 底下會出現多份相同副本——那是產生物，跟注入的更新檢查標頭一樣，照常一起 commit。

### 修改既有技能 / 修改共用的更新檢查邏輯

- 改某顆技能：直接改 `commands-src/<name>/SKILL.md`，一樣跑 `bin/build.sh` + `make test` + commit 三個資料夾。
- 改 `_shared/update-check-header.md`（會影響**所有**技能）：改完必須跑一次 `bin/build.sh` 讓全部技能重新套用，然後把 `commands/` 與 `opencode-commands/` 底下所有受影響的變動一併 commit——不要只 commit `_shared/`，不然部署版本會跟原始碼脫節。

---

## 3. 命名規則

技能的 `name` 會變成四件事：`commands-src/<name>/` 的資料夾名、`commands/<name>/` 的資料夾名、symlink 進 `~/.claude/skills/<name>` 等四個路徑時的名字，以及各工具裡的叫用字串（`/<name>`、`$<name>`）——**這是一個跨工具共用的扁平命名空間**，沒有子目錄隔開，所以撞名的代價比一般專案內的檔名撞名更高（AI 工具會直接看到重複或誤導的技能名稱）。

規則：

1. **格式**：全小寫 kebab-case，只用 `a-z`、`0-9`、`-`，以字母開頭。例如 `example-skill`、`myapp-deploy`。不要用底線、大寫、空白或中文。
2. **資料夾名必須等於 frontmatter 裡的 `name:`**。目前 `bin/build.sh` 不會幫你檢查這件事，兩者不一致純粹是人為約定——建立資料夾時把 `name:` 複製貼上過去，不要自己改一份。
3. **具體，避免單一泛用詞**。`deploy`、`test`、`sync` 這種字未來很容易撞名（不管是撞你自己的其他技能，還是撞其他來源裝進同一個 `~/.claude/skills/` 的技能/plugin）。一律搭配領域或專案名詞：`myapp-deploy` 而不是 `deploy`。
4. **一組相關技能用共同字首**：例如同一個專案的維運技能，用 `myapp-` 開頭（`myapp-deploy`、`myapp-rollback`、`myapp-status`）。這樣在 `commands-src/` 目錄列表、`bin/doctor.sh` 輸出裡會自然排在一起，一眼看出彼此相關。
5. **長度**：建議 40 字元以內，太長的名字在各工具的技能選單/描述裡容易被截斷。
6. **`description` 要講清楚「觸發時機」，不只是「做什麼」**。這欄位會被 AI 工具用來判斷什麼時候該主動叫用這個技能，寫得越具體（例如「當使用者要求產生週報時」而不是「產生報告」），觸發準確度越高。

---

## 4. 常見錯誤

- **改了 `commands/` 卻沒改 `commands-src/`**：下次任何人跑 `bin/build.sh` 都會把你的改動蓋掉。永遠改 `commands-src/`。
- **改了 `commands-src/` 但忘記跑 `bin/build.sh` 就 commit**：`commands/` 會跟原始碼不同步，其他機器 `sync-skills.sh` 之後拿到的是舊的部署版本。
- **只 commit 了其中一個資料夾**：三個一定要一起 commit，這是這個架構「不需要在每台機器上跑 build 工具鏈」的前提（見 ARCHITECTURE.md 決策 #7）。
- **共用資料夾放了 `SKILL.md`**：`commands-src/_x-shared/SKILL.md` 會讓 build 把它當成一顆名為 `_x-shared` 的技能。共用目錄底下只放支援檔。
- **`name:` 跟資料夾名不一致**：目前無自動檢查，純靠自律；建議寫的當下就對照一次。
- **跑 `make test` 前沒裝 `ripgrep`**：測試腳本用 `rg` 做輸出比對，`brew install ripgrep` / `apt install ripgrep` 先裝好。

---

## 5. 提交前檢查清單

- [ ] `commands-src/<name>/SKILL.md` 的 `name:` 跟資料夾名一致
- [ ] 命名符合第 3 節規則（kebab-case、具體、必要時共用字首）
- [ ] `description:` 講清楚做什麼 + 何時觸發
- [ ] 跑過 `bin/build.sh`
- [ ] 跑過 `make test`，全部 PASS
- [ ] `commands-src/`、`commands/` 和 `opencode-commands/` 一起 commit
