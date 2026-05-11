# Flow: teams-notify

Teams のチャネル or 個人チャットに通知 (Adaptive Card) を投稿する Power Automate フロー。
深津 KO さん用の緊急メール通知の到着口。

## トリガ

**種別**: HTTP 要求の受信時

### リクエスト本文 JSON Schema

```json
{
  "type": "object",
  "required": ["target", "title", "items"],
  "properties": {
    "target": {
      "type": "object",
      "description": "投稿先 (chat か channel どちらか)",
      "properties": {
        "kind": { "type": "string", "enum": ["chat", "channel"] },
        "chat_id": { "type": "string", "description": "kind=chat の場合" },
        "team_id": { "type": "string", "description": "kind=channel の場合" },
        "channel_id": { "type": "string", "description": "kind=channel の場合" }
      }
    },
    "title": {
      "type": "string",
      "description": "通知タイトル (例: 緊急メール 3 件)"
    },
    "summary": {
      "type": "string",
      "description": "1 行サマリ"
    },
    "items": {
      "type": "array",
      "description": "緊急メールの一覧 (最大 10)",
      "maxItems": 10,
      "items": {
        "type": "object",
        "required": ["subject", "from", "reason", "web_link"],
        "properties": {
          "subject": { "type": "string" },
          "from": { "type": "string", "description": "表示名 (例: 山田太郎 / 株式会社 X)" },
          "received_at": { "type": "string", "format": "date-time" },
          "urgency": { "type": "string", "enum": ["high", "medium"] },
          "reason": { "type": "string", "description": "なぜ緊急と判定したか (短く)" },
          "deadline_hint": { "type": "string", "description": "本文から抽出した期限 (任意)" },
          "web_link": { "type": "string", "description": "Outlook Web で開くリンク" }
        }
      }
    },
    "run_id": {
      "type": "string",
      "description": "対応する workflows/<run-id> (トレース用、任意)"
    }
  }
}
```

### ヘッダ検証

`x-claude-secret` が一致しなければ 401。

## 主要アクション

1. **Compose: Adaptive Card JSON 構築**

   推奨レイアウト:
   ```json
   {
     "type": "AdaptiveCard",
     "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
     "version": "1.4",
     "body": [
       { "type": "TextBlock", "text": "@{triggerBody()?['title']}", "weight": "Bolder", "size": "Large" },
       { "type": "TextBlock", "text": "@{triggerBody()?['summary']}", "wrap": true, "isSubtle": true },
       {
         "type": "Container",
         "items": [
           {
             "type": "ColumnSet",
             "columns": [
               { "type": "Column", "width": "stretch", "items": [
                   { "type": "TextBlock", "text": "📧 {{subject}}", "weight": "Bolder", "wrap": true },
                   { "type": "TextBlock", "text": "From: {{from}} · {{received_at}}", "isSubtle": true, "size": "Small" },
                   { "type": "TextBlock", "text": "理由: {{reason}}", "wrap": true, "size": "Small" },
                   { "type": "TextBlock", "text": "期限: {{deadline_hint}}", "color": "Attention", "size": "Small", "isVisible": "@{not(equals(item()?['deadline_hint'], null))}" }
                 ]
               }
             ]
           },
           {
             "type": "ActionSet",
             "actions": [
               { "type": "Action.OpenUrl", "title": "Outlook で開く", "url": "{{web_link}}" }
             ]
           }
         ],
         "$data": "@triggerBody()?['items']"
       }
     ]
   }
   ```
   ※ Adaptive Card は実フロー作成時にビジュアルエディタで微調整可。

2. **分岐**: `target.kind` で投稿先を切替
   - `chat`: 「Post adaptive card in a chat or channel」→ `Post in: Chat with Flow bot` または `Group chat`
   - `channel`: 「Post adaptive card in a chat or channel」→ Team + Channel 指定

3. **応答**:
   - Status: 200
   - Body: `{"posted": true, "message_id": "<Teams メッセージ ID>", "posted_at": "@utcNow()"}`

## レスポンス JSON Schema

```json
{
  "type": "object",
  "properties": {
    "posted": { "type": "boolean" },
    "message_id": { "type": "string" },
    "posted_at": { "type": "string", "format": "date-time" }
  }
}
```

## エラー応答

| 状況 | Status |
|---|---|
| ヘッダ不一致 | 401 |
| Teams コネクタ失敗 | 502 |
| target 指定不正 | 400 |

## テスト方法

```bash
curl -X POST "$PA_TEAMS_NOTIFY_URL" \
  -H "Content-Type: application/json" \
  -H "x-claude-secret: $PA_SHARED_SECRET" \
  -d @workflows/<run-id>/teams-payload.json
```

## 注意

- Teams 通知は **承認ゲートを通った後** に呼ぶ。誤検知が多いうちはユーザー確認 → 手動実行
- カードのテキストに機密情報 (金額・取引先名) を入れすぎない (Teams のログに残るため、件名 + 理由程度に抑える)
- 投稿先 (chat_id / channel_id) は KO さんの Teams 環境で事前取得し、`.env.powerautomate` で固定する
