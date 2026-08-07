# Towerbound upload key —— 備份指引

**呢一份係成個 repo 入面唯一一樣「唔見咗補救唔到」嘅嘢。** 程式碼、美術、
平衡數值全部喺 git 入面,一部新機 clone 返落嚟就一模一樣。條 key 唔喺 git 入面
(而且刻意唔可以喺),所以佢淨係存在於下面講嗰幾個地方。

---

## 1. 而家喺邊

| 嘢 | 路徑 |
|---|---|
| Keystore | `%USERPROFILE%\keystores\towerbound-upload.keystore` |
| 密碼 / alias | `%USERPROFILE%\keystores\towerbound-upload.credentials.env` |

兩個都**刻意放喺 project 資料夾以外**。`export_presets.cfg` 入面一個密碼字元都
冇 —— build 嗰陣經環境變數(`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` /
`_USER` / `_PASSWORD`)餵俾 Godot,由 `tools\android_build.ps1` 讀上面嗰個
credentials 檔。

`.gitignore` 加咗 `*.keystore` / `*.jks` / `*.credentials.env` 做保險:就算將來
有人 copy 一份落 project 資料夾「方便啲」,git 都唔會幫佢推上 GitHub。

### 條 key 嘅資料

```
alias      : towerbound-upload
演算法      : RSA 4096, SHA384withRSA
有效期      : 2026-08-07 → 2053-12-23
SHA-256    : BC:6F:8B:D0:AC:1A:BC:49:9C:CF:46:32:EE:DC:49:07:66:0B:21:01:41:2D:EB:F4:3B:7C:43:77:C9:44:FA:F9
SHA-1      : 0F:20:2A:0E:E3:35:F5:41:36:A6:63:18:06:98:E4:C9:B6:37:33:97
```

指紋抄咗喺呢度係為咗**驗證**用:將來由備份還原返一個 keystore,先對一對指紋
啱唔啱,先好用佢簽嘢。指紋係公開資料,唔係秘密 —— 秘密係嗰個密碼。

---

## 2. Jack 而家要做嘅事(唔好等)

備份要**同時滿足兩個條件**先算數:一,唔喺呢部電腦;二,keystore 同密碼要
分開放(一個地方俾人爆咗,唔會兩樣一齊冇)。

- [ ] **A. Keystore 檔上密碼管理器 / 加密雲端**
      將 `towerbound-upload.keystore` 放入一個有密碼保護嘅地方 ——
      1Password / Bitwarden 嘅附件、或者一個加密咗嘅雲端資料夾。
      **唔好**放喺一個未加密嘅 Google Drive / OneDrive 資料夾。

- [ ] **B. 密碼**存喺**另一個**地方 —— 通常就係密碼管理器嗰筆記錄本身。
      唔好同 keystore 檔擺埋喺同一個 zip / 同一個資料夾。

- [ ] **C. 離線一份**
      一支 USB 手指或者一部外置硬碟,放喺屋企另一個地方(唔係同一張枱)。
      Keystore + 密碼寫喺紙上面,一齊放。呢一份係「雲端帳戶被鎖 / 被盜」
      嗰個情況嘅答案。

- [ ] **D. 上載第一個 AAB 嗰陣,喺 Play Console 開 Play App Signing**
      (新 app 預設就係開住。)開咗之後,你手上呢條係 **upload key**,
      而 Play 自己保管住真正嘅 **app signing key**。呢個分別好重要 ——
      見下面第 3 節。

- [ ] **E. 上載成功之後,喺 Play Console 記低 app signing key 嘅 SHA-256**
      (Play Console → 測試與發布 → 應用程式完整性 → 應用程式簽署)。
      抄返落嚟呢個檔。

---

## 3. 唔見咗會點?

**要分清楚兩條 key。**

### 如果開咗 Play App Signing(建議,亦係新 app 嘅預設)

- 唔見咗 **upload key** = **有得救**。去 Play Console 申請重設 upload key,
  Google 會叫你上載一條新嘅,審核之後就可以繼續出 update。麻煩,要等,
  但個 app 唔會死,玩家嘅存檔同評分都唔會冇。
- **app signing key** 由 Google 保管,你根本冇份唔見。

### 如果**冇**開 Play App Signing(自己揸住 signing key)

- 唔見咗條 key = **呢個 app 完咗**。Android 唔容許用另一條 key 簽同一個
  package name 嘅 update。後果係:
  - 冇得再出任何更新,連修一個閃退都唔得;
  - 唯一出路係換一個 package name 重新上架,即係一個全新嘅 app;
  - 已經裝咗嘅玩家**唔會**收到更新,亦都唔會由舊 app 過渡到新 app;
  - 舊 app 嘅評分、下載數、排名全部帶唔走。

**所以第 2 節嘅 D 唔係「有時間先做」。** 開咗 Play App Signing,上面整段
最壞情況就變成「麻煩但有得救」。

### 密碼唔見咗,keystore 仲喺度

一樣係死。keystore 冇「重設密碼」呢回事 —— 佢係一個加密容器,冇密碼就開唔到。
所以密碼要同 keystore 一齊備份,但唔擺同一個位。

---

## 4. 換機 / 重灌之後點還原

1. 由備份攞返 `towerbound-upload.keystore`,放返
   `%USERPROFILE%\keystores\` 之下。
2. 用密碼對一對指紋:
   ```powershell
   & "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe" `
     -list -v -keystore "$env:USERPROFILE\keystores\towerbound-upload.keystore" `
     -alias towerbound-upload
   ```
   SHA-256 要同上面第 1 節嗰串**一個字元都唔差**。唔啱 = 攞錯咗個檔,唔好用。
3. 重新寫返 `towerbound-upload.credentials.env`(格式見嗰個檔本身嘅註解)。
4. `powershell -File tools\android_build.ps1` —— 出返嚟嘅 aab 應該可以直接
   上 Play Console 而唔會俾佢話「簽名唔啱」。

---

## 5. 唔准做嘅嘢

- ❌ 唔准 `git add` 任何 `.keystore` / `.jks` / credentials 檔。
- ❌ 唔准將密碼寫入 `export_presets.cfg`(嗰個檔入 repo)。
- ❌ 唔准將密碼寫入任何 `.ps1` / `.py` / CI 設定檔嘅原始碼入面。
- ❌ 唔准將 keystore 放入 `dist\`(嗰度嘅嘢係俾人下載嘅)。
- ❌ 一條 key 一旦推上過公開 repo,**就算之後 force-push 刪咗都當洩漏咗** ——
  GitHub 嘅 commit 內容喺 fork / cache / 第三方鏡像度仲搵得返。嗰個情況要
  當條 key 已經冇咗,行第 3 節嘅 upload key 重設程序。
