# Power Automate セットアップ手順書 (mail エージェント Phase 1)

深津 KO さん自身が Power Automate の画面で 2 つのフローを作るための逐次手順書。
所要時間は 30 〜 45 分の見込み。ブロックされたら該当ステップ番号を教えてください、その単位でサポートします。

## 0. 事前準備

### 0.1 ライセンス確認

- Power Automate Free または Premium のライセンスがあること
  - 確認: https://make.powerautomate.com/ にログインして「自分のフロー」が開ければ OK
- Outlook (Exchange Online) / Teams のコネクタが使えること
  - 確認: https://make.powerautomate.com/connections/ で `Office 365 Outlook` と `Microsoft Teams` が一覧に出るか

### 0.2 共有シークレット生成

ローカルのターミナルで実行 (Mac / Linux):
```bash
openssl rand -base64 32
```

Windows (PowerShell):
```powershell
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }))
```

出力された 44 文字程度の文字列をメモ。**後で `.env.powerautomate` と Power Automate のフロー両方に貼る**。例: `9pJ3XwYxqK1eL/aV8sP+rGZ2HM4nB6tCdE0FfQ7sK9o=`

> このシークレットは「Claude が Power Automate を叩くときの合言葉」。漏れたら誰でも KO さんのメールを引けてしまうので、生成したらこの後の `.env.powerautomate` 以外には貼らないでください (このチャットにも貼らない)。

### 0.3 Teams の通知先 ID を取得

通知をどこに飛ばすか先に決める:

- **A. 自分宛の Power Automate ボットチャット** (オススメ・楽)
  - フロー側で `Post adaptive card in a chat or channel` → `Chat with Flow bot` を選ぶだけ。ID 不要
- **B. 任意のチャネル**
  - Teams で対象チャネルを開く → `…` → `チャネルへのリンクを取得`
  - URL 内の `groupId=` が **team_id**、`channelId=` が **channel_id**
- **C. 任意の個人 / グループチャット**
  - Teams で対象チャットを開く → URL の `https://teams.microsoft.com/l/chat/<chat_id>/...` の `<chat_id>` 部分

**Phase 1 では A. が一番速い**ので、本書では A を前提に進めます。

---

## 1. フロー 1: `get-unread-mails` を作る

### 1.1 新規作成

1. https://make.powerautomate.com/ にログイン
2. 左メニュー「**自分のフロー (My flows)**」→ 上部「**+ 新しいフロー (New flow)**」→ 「**インスタント クラウド フロー (Instant cloud flow)**」
3. フロー名: `claude-get-unread-mails`
4. トリガー選択: 「**HTTP 要求の受信時 (When a HTTP request is received)**」 → 作成

### 1.2 トリガーの設定

1. トリガーのタイル「**HTTP 要求の受信時**」を開く
2. 「**要求本文の JSON スキーマ**」に以下を貼る:
   ```json
   {
     "type": "object",
     "properties": {
       "top": { "type": "integer" },
       "since_iso": { "type": "string" },
       "folder": { "type": "string" }
     }
   }
   ```
3. 「**詳細オプション (Show advanced options)**」を開き、「**方法 (Method)**」を `POST` に
4. **このまま保存はせず先へ**。HTTP POST URL は最後にコピー (保存後に確定する)

### 1.3 シークレット検証

1. 「**+ 新しいステップ**」→ 「**コントロール → 条件 (Condition)**」
2. 条件式:
   - 左: 動的コンテンツ `headers > x-claude-secret` (見つからない場合は 「**式 (expression)**」タブで `triggerOutputs()?['headers']?['x-claude-secret']` を入力)
   - 演算子: `次の値に等しい (is equal to)`
   - 右: 0.2 で生成したシークレット文字列を貼り付け
3. 条件タイトルを `verify-secret` に変更 (任意)
4. 「**いいえ (If no)**」分岐に:
   - 「**応答 (Response)**」アクション追加
   - Status Code: `401`
   - Body: `{"error":"unauthorized"}`
   - その後ろに「**コントロール → 終了 (Terminate)**」を追加し Status を `Succeeded` に
5. 「**はい (If yes)**」分岐に以降のステップを置いていく

### 1.4 未読取得

「**はい**」分岐内:

1. 「**+ 新しいアクション**」→ 「**Office 365 Outlook → メールを取得する (V3) / Get emails (V3)**」
2. パラメータ:
   - Folder: `Inbox` (動的に変えたい場合は `coalesce(triggerBody()?['folder'], 'Inbox')`)
   - Search Query: 空白
   - Filter Query: `isRead eq false`
   - Top: 動的コンテンツ `top` (なければ式 `coalesce(triggerBody()?['top'], 50)`)
   - Include Attachments: `No`
   - Order By: `receivedDateTime desc`
3. (任意) `since_iso` がある場合は Filter Query を分岐:
   ```
   if(empty(triggerBody()?['since_iso']),
      'isRead eq false',
      concat('isRead eq false and receivedDateTime ge ', triggerBody()?['since_iso']))
   ```
   を式で入れる

### 1.5 整形 (Select)

1. 「**+ 新しいアクション**」→ 「**データ操作 → 選択 (Select)**」
2. From: 動的コンテンツ `value` (Get emails の出力)
3. Map: ビューを「**テキストモード**」(右上のスイッチ) に切り替えて以下を貼る:
   ```json
   {
     "id": "@item()?['id']",
     "subject": "@item()?['subject']",
     "from": {
       "name": "@item()?['from']?['emailAddress']?['name']",
       "address": "@item()?['from']?['emailAddress']?['address']"
     },
     "to": "@item()?['toRecipients']",
     "cc": "@item()?['ccRecipients']",
     "received_at": "@item()?['receivedDateTime']",
     "preview": "@item()?['bodyPreview']",
     "importance": "@item()?['importance']",
     "has_attachments": "@item()?['hasAttachments']",
     "web_link": "@item()?['webLink']",
     "conversation_id": "@item()?['conversationId']"
   }
   ```

### 1.6 応答

1. 「**+ 新しいアクション**」→ 「**応答 (Response)**」
2. Status Code: `200`
3. Headers:
   | Key | Value |
   |---|---|
   | `Content-Type` | `application/json; charset=utf-8` |
4. Body (式モードで):
   ```json
   {
     "count": "@length(body('Select'))",
     "fetched_at": "@utcNow()",
     "items": "@body('Select')"
   }
   ```
   ※ `@length(...)` などはそのまま貼れば動的に解決されます

### 1.7 保存 & URL コピー

1. 右上「**保存 (Save)**」
2. トリガー「HTTP 要求の受信時」をもう一度開く
3. 「**HTTP POST URL**」欄に長い URL が表示される (`...sig=...`)
4. **コピーボタン** を押してクリップボードに保存
5. 後で `.env.powerautomate` の `PA_UNREAD_MAILS_URL=` に貼り付ける

### 1.8 動作確認

「**テスト**」→ 「**手動**」→ 「**テスト**」→ 別ウィンドウで curl:

```bash
curl -X POST '<コピーした URL>' \
  -H 'Content-Type: application/json' \
  -H 'x-claude-secret: <0.2 のシークレット>' \
  -d '{"top": 5}'
```

200 と未読 5 件分の JSON が返れば OK。401 なら 1.3 の比較を見直し。

---

## 2. フロー 2: `teams-notify` を作る

### 2.1 新規作成

1. 「**自分のフロー**」→ 「**+ 新しいフロー**」→ 「**インスタント クラウド フロー**」
2. 名前: `claude-teams-notify`
3. トリガー: 「**HTTP 要求の受信時**」→ 作成

### 2.2 トリガー設定

1. 要求本文 JSON スキーマ (Phase 1 ミニマム版):
   ```json
   {
     "type": "object",
     "required": ["title", "items"],
     "properties": {
       "title": { "type": "string" },
       "summary": { "type": "string" },
       "items": {
         "type": "array",
         "items": {
           "type": "object",
           "properties": {
             "subject": { "type": "string" },
             "from": { "type": "string" },
             "received_at": { "type": "string" },
             "reason": { "type": "string" },
             "deadline_hint": { "type": "string" },
             "web_link": { "type": "string" }
           }
         }
       },
       "run_id": { "type": "string" }
     }
   }
   ```
2. 詳細オプション → Method: `POST`

### 2.3 シークレット検証

フロー 1 と同じ手順 (1.3) で `verify-secret` 条件を追加。「いいえ」は 401 で終了。

### 2.4 Adaptive Card 生成 (Compose アクション)

「はい」分岐内:

1. 「**+ 新しいアクション**」→ 「**データ操作 → 作成 (Compose)**」
2. Inputs に以下を貼る:
   ```json
   {
     "type": "AdaptiveCard",
     "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
     "version": "1.4",
     "body": [
       { "type": "TextBlock", "text": "@{triggerBody()?['title']}", "weight": "Bolder", "size": "Large", "color": "Attention" },
       { "type": "TextBlock", "text": "@{coalesce(triggerBody()?['summary'], '')}", "wrap": true, "isSubtle": true, "spacing": "Small" },
       {
         "type": "Container",
         "$data": "@triggerBody()?['items']",
         "separator": true,
         "spacing": "Medium",
         "items": [
           { "type": "TextBlock", "text": "📧 ${subject}", "weight": "Bolder", "wrap": true },
           { "type": "TextBlock", "text": "From: ${from} · ${received_at}", "isSubtle": true, "size": "Small" },
           { "type": "TextBlock", "text": "理由: ${reason}", "wrap": true, "size": "Small" },
           { "type": "TextBlock", "text": "期限: ${deadline_hint}", "color": "Attention", "size": "Small", "isVisible": "${deadline_hint != null}" },
           {
             "type": "ActionSet",
             "actions": [
               { "type": "Action.OpenUrl", "title": "Outlook で開く", "url": "${web_link}" }
             ]
           }
         ]
       }
     ]
   }
   ```
3. アクション名を `compose-card` に変更 (任意)

> `${...}` は Adaptive Card テンプレート構文。Power Automate の式ではないのでクォートをそのまま残します。

### 2.5 Teams 投稿

1. 「**+ 新しいアクション**」→ 「**Microsoft Teams → チャットまたはチャネルでアダプティブ カードを投稿する (Post adaptive card in a chat or channel)**」
2. パラメータ:
   - Post as: `Flow bot`
   - Post in: `Chat with Flow bot`
   - Recipient: 深津さん自身のメールアドレス (or `me()`)
   - Adaptive Card: 動的コンテンツから `compose-card` の出力 (Outputs) を選択

> チャネルに投げたい場合は Post in を `Channel` に切り替え、Team / Channel を選ぶ。

### 2.6 応答

1. 「**応答 (Response)**」アクション
2. Status: `200`
3. Body:
   ```json
   {
     "posted": true,
     "message_id": "@{body('チャットまたはチャネルでアダプティブ_カードを投稿する')?['messageId']}",
     "posted_at": "@utcNow()"
   }
   ```
   ※ アクション名が日本語環境とで揺れます。実際の名前をエディタの右上「**コード ビュー**」で確認するか、動的コンテンツから挿入してください。

### 2.7 保存 & URL コピー

フロー 1 と同様、保存 → HTTP POST URL をコピーして後で `PA_TEAMS_NOTIFY_URL=` に貼り付け。

### 2.8 動作確認

```bash
curl -X POST '<コピーした URL>' \
  -H 'Content-Type: application/json' \
  -H 'x-claude-secret: <シークレット>' \
  -d '{
    "title": "テスト通知",
    "summary": "セットアップ確認です",
    "items": [
      {
        "subject": "テストメール",
        "from": "test@example.com",
        "received_at": "2026-05-11T08:00:00Z",
        "reason": "セットアップ確認",
        "web_link": "https://outlook.office.com"
      }
    ]
  }'
```

Teams (Flow bot とのチャット) にカードが届けば OK。

---

## 3. Claude 側の設定

1. リポジトリのルートで:
   ```bash
   cp .env.powerautomate.example .env.powerautomate
   ```
2. `.env.powerautomate` を開き、以下を埋める:
   ```bash
   PA_UNREAD_MAILS_URL="<1.7 でコピーした URL>"
   PA_TEAMS_NOTIFY_URL="<2.7 でコピーした URL>"
   PA_SHARED_SECRET="<0.2 で生成した文字列>"
   ```
3. ファイルが gitignore されているか確認:
   ```bash
   git check-ignore .env.powerautomate
   # → 出力に .env.powerautomate と出れば除外されている
   ```
4. ヘルパー動作確認:
   ```bash
   ./integrations/powerautomate/scripts/call_flow.sh get-unread-mails '{"top": 3}'
   ```
   3 件以下の未読 JSON が返れば成功

---

## 4. mail エージェント起動の確認

Claude Code に対して:

> 「未読チェックして、緊急があれば Teams に通知の準備して」

と話しかける。`mail` エージェントが起動し、以下を順に出すはず:

1. `workflows/<run-id>/inbox-raw.json` 作成
2. スコアリング結果サマリ表示
3. Teams payload プレビュー
4. 「この内容で Teams に通知しますか? (yes/no/編集)」承認待ち

承認したら `teams-notify` が呼ばれ、Teams に Adaptive Card が届きます。

---

## 5. トラブルシュート

| 症状 | 想定原因 | 対処 |
|---|---|---|
| `401 unauthorized` | ヘッダ名スペル違い (`x-claude-secret`) / シークレット不一致 | フロー 1.3 / 2.3 の条件式と `.env` を見比べる |
| `400 Bad Request` | 要求本文の JSON スキーマと curl の body が乖離 | スキーマ側か body を合わせる |
| Outlook コネクタが「接続が壊れています」 | テナント側の再認証要求 | https://make.powerautomate.com/connections/ で再ログイン |
| Teams にカードが届かない | Post in が `Chat with Flow bot` でないチャネル指定で権限不足 | Flow bot を対象チャネルに追加するか、当面は個人チャット (Flow bot) で試す |
| `Action 'チャットまたはチャネル...' は見つかりません` | アクション名 (日本語/英語) の取得式が違う | コードビューで実アクション名を確認し、応答 Body の式を差し替える |
| `.env.powerautomate` がコミットされそう | gitignore 漏れ | `.gitignore` の `.env.*` ルールを確認 |

---

## 6. (任意) 強化案

セットアップが安定したら段階的に追加:

- **重要送信者リスト**: Power Automate の「変数」アクションでホワイトリストを管理し、応答 JSON に `vip: true` を付与してエージェント側のスコアリングを簡素化
- **大量受信時のページング**: 50 件を超える未読がある日向けに `skipToken` 対応
- **送信フロー (Phase 2)**: `claude-send-mail` を追加し、`mail` エージェントの「ドラフト → 承認 → 送信」を自動化
- **OneDrive 添付保存フロー**: 添付が必要なメールを `keiri/data/input/` などに自動保存

ここまで来たら `mail` エージェントは KO さんの代わりに毎朝未読をトリアージし、緊急分だけ Teams 通知できる状態になります。

---

最終更新: 2026 年 5 月 11 日
