---
name: code-review
description: 三軸審查一份 diff——Standards（repo 規範 + CLAUDE.md/AGENTS.md + Fowler code smell baseline）、Spec（是否符合原始需求）、Correctness（bug 掃描，帶 git 歷史脈絡）。接受本機 fixed point（commit/branch/tag）或 GitHub PR 編號。每軸平行 sub-agent 審查，findings 逐條打信心分數過濾雜訊，三軸分開回報在對話裡，絕不主動貼到別處。Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to "review since X" / "review PR #N".
---

# Code Review（三軸）

三軸審查一份 diff：**Standards**（符不符合規範）、**Spec**（符不符合原始需求）、**Correctness**（有沒有 bug，含歷史脈絡）。三軸平行審查、分開回報，不合併不跨軸排名——一個改動可能規範全過但邏輯是錯的，或反過來，分開報告才不會被其中一軸的訊號蓋掉另一軸。

## 輸入模式

- **本機模式**：使用者給一個 fixed point（commit SHA、branch、tag、`main`、`HEAD~5`）。比對 `git diff <fixed-point>...HEAD`（三點，對 merge-base）。
- **PR 模式**：使用者給一個 GitHub PR 編號或連結。改用 `gh pr diff <N>` 取 diff、`gh pr view <N> --json state,isDraft,mergeable,title,body` 取中繼資料。

使用者沒講清楚就問，不要用猜的填 fixed point。

## Process

### 1. 資格檢查（直接查，不開 agent）

- **本機模式**：`git rev-parse <fixed-point>` 要能解析；diff 不可為空。失敗在這裡回報，不要留到平行 sub-agent 裡才爆炸。
- **PR 模式**：先查 `state`/`isDraft`——已關閉、已合併、draft 就停下回報，問使用者是否仍要審。
- **瑣碎 diff 檢查**：整個 diff 只有 lockfile、純格式化、或純 rename（沒有邏輯變更）——直接說明「這是瑣碎變更，略過三軸深度審查」並停在這裡。這一步用意是省成本；因為判斷條件是機械檢查（看 diff 內容），不需要為此開一個 agent。

### 2. 找 Spec 來源

依序找，找到第一個就用：

1. commit message 裡的 issue 參照（`#123`、`Closes #45`、GitLab `!67`）——用 `gh issue view` / `glab issue view` 取內容。
2. 使用者當參數傳的路徑。
3. `docs/`、`specs/`、`.scratch/` 下跟 branch 名或 feature 同名的 PRD/spec 檔。
4. 都找不到就問使用者哪裡有 spec；使用者說沒有，Spec sub-agent 就報「無 spec 可用」，不硬找。

（如果這個 repo 有 `docs/agents/issue-tracker.md`——`setup-matt-pocock-skills` 留下的設定——優先照它講的工作流程走；沒有這個檔案是正常狀態，不代表要停下來要求使用者先跑那個 skill。）

### 3. 找 Standards 來源

repo 內任何說明「程式該怎麼寫」的文件：`CODING_STANDARDS.md`、`CONTRIBUTING.md`、根目錄與異動檔案所在目錄的 `CLAUDE.md`/`AGENTS.md`。

在文件之上，Standards 軸永遠帶著下面這份 **smell baseline**（即使 repo 什麼都沒寫也適用）。兩條規則綁住它：

- **repo 規範優先**——文件寫的規範贏過 baseline；repo 認可的作法，baseline 對應的 smell 就不算。
- **永遠是判斷，不是鐵律**——每個 smell 都是「疑似」的標籤，不是硬性違規；工具（linter/formatter）已經在管的直接跳過。

逐一對照 diff：

- **Mysterious Name** — 函式/變數/型別的名字看不出它做什麼、存什麼。→ 重新命名；想不出誠實的名字，代表設計本身模糊。
- **Duplicated Code** — 同樣的邏輯形狀出現在這次改動的兩處以上。→ 抽出共用邏輯，兩處都呼叫它。
- **Feature Envy** — 一個方法伸手拿別的物件的資料，比拿自己的還多。→ 把方法搬到它真正在用的那個資料旁邊。
- **Data Clumps** — 同一組欄位/參數老是一起出現（其實想變成一個型別）。→ 包成一個型別，整包傳遞。
- **Primitive Obsession** — 用 primitive 或字串頂替一個該有自己型別的 domain 概念。→ 給這個概念一個小型別。
- **Repeated Switches** — 同一種 `switch`/`if` 鏈對同一個型別在這次改動裡重複出現。→ 換成多型，或共用一份 map。
- **Shotgun Surgery** — 一個邏輯上的改動，逼得這次 diff 要散彈打進很多檔案。→ 把該一起變的邏輯收進同一個模組。
- **Divergent Change** — 同一個檔案/模組在這次改動裡因為好幾個不相干的原因被改。→ 拆開，讓每個模組只因一個理由改動。
- **Speculative Generality** — 為 spec 沒要求的需求加的抽象、參數、掛勾。→ 刪掉；等真正需要再加回來。
- **Message Chains** — 呼叫端不該依賴的長串 `a.b().c().d()` 導航。→ 把這串走法藏進第一個物件的一個方法後面。
- **Middle Man** — 一個 class/函式幾乎只是轉手把呼叫傳下去。→ 拿掉它，直接呼叫真正的目標。
- **Refused Bequest** — 子類/實作忽略或覆寫掉繼承來的大部分東西。→ 拿掉繼承關係，改用組合。

### 4. 找 Correctness 用的歷史脈絡

- 對這次異動到的檔案跑 `git log --oneline -- <path>`（需要細節再用 `-p`），看這段程式碼過去是不是常出包、這次改動是不是在無意間回退了之前的修正。
- **PR 模式限定**：翻同一批檔案過去的 PR 討論（`gh pr list --search "..." --state all` 或 `gh search prs`），看有沒有之前留下、這次改動可能還適用的意見。本機模式沒有 PR 可查，略過這條，不用勉強找替代品。

### 5. 平行開三個 sub-agent

一次訊息開三個 `Agent` 呼叫（`general-purpose`），彼此不共用 context：

**Standards sub-agent** — 給：diff 指令、commit 清單、步驟 3 找到的規範來源檔案清單、完整貼上 smell baseline 12 條。brief：「逐檔案/hunk 回報 (a) 違反哪條文件規範——引用檔案＋規則；(b) 命中哪個 baseline smell——引用 hunk。文件規範可以是硬違規，baseline smell 永遠是判斷；文件規範蓋過 baseline。工具已經在管的跳過。400 字以內。」

**Spec sub-agent** — 給：diff 指令、commit 清單、spec 內容或路徑。brief：「回報 (a) spec 要求但沒做或做一半的；(b) diff 裡做了但 spec 沒要求的（範圍蔓延）；(c) 看起來做了但實作方向錯的。每條都要引用 spec 原文。400 字以內。」沒找到 spec 就不開這個 agent，在最終報告註明「無 spec 可用」。

**Correctness sub-agent** — 給：diff 指令、commit 清單、步驟 4 找到的歷史脈絡摘要。brief：「只針對這次改動本身找明顯 bug，不要跑去讀改動以外的大範圍程式碼；鎖定會實際影響功能的問題，略過吹毛求疵與可能的偽陽性。如果歷史脈絡顯示這段程式碼曾經出過包、或這次改動疑似回退了舊修正，特別標註並引用是哪次 commit/PR。400 字以內。」

### 6. 信心評分，過濾雜訊

三個 sub-agent 都回來後，開一個 `model: "haiku"` 的 Agent，把所有 finding 連同規範來源清單、spec 內容一起丟進去，照下面 rubric 逐條打 0–100 分：

- 0：站不住腳的偽陽性，或是既有問題、不是這次引入的。
- 25：可能是真的，但沒查證；若是風格類，文件沒明講。
- 50：查證過是真的，但影響小、算吹毛求疵。
- 75：查證過，很可能實務上會踩到；文件有明講，或會直接影響功能。
- 100：查證過且確定，實務上會頻繁發生，證據直接支持。

**只留下 ≥ 80 分的 finding**，其餘直接丟掉，不要留在報告裡湊數。

這一步刻意指定便宜模型：打分數是「照 rubric 核對」的機械判斷，不需要重推理，把貴的模型留給步驟 5 那三個真正要下判斷的 sub-agent。

### 7. 彙總回報

用 `## Standards`、`## Spec`、`## Correctness` 三個標題分開列出過濾後的 finding，**不合併、不跨軸重排名**（理由見下）。每條附上信心分數。

每軸結尾一行摘要：過濾後幾條／原始幾條（讓使用者知道濾掉了多少雜訊）、該軸最嚴重的問題（如果有）。不要跨軸挑一個「總冠軍」。

最後加一句：這份報告只留在對話裡，沒有貼到任何地方；要貼到 PR 或 issue，使用者確認要貼之後才用 `gh pr comment` / `gh issue comment` 動手。**絕不主動貼**，即使是在 PR 模式下審查、即使找到的都是高信心問題。

## 為什麼分三軸

- 規範全過、邏輯是錯的 → Standards pass，Correctness fail。
- 完全照 spec 做、但破壞專案慣例 → Spec pass，Standards fail。
- 規範跟 spec 都對、但有個明顯 bug（可能是這次新引入，也可能是歷史遺留在這次改動裡復發）→ Standards pass、Spec pass、Correctness fail。

三軸分開報告，才不會被其中一軸的訊號蓋掉另一軸。
