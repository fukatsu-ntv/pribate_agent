# Flow: get-unread-mails

未読メールを最新 N 件取得して JSON で返す Power Automate フロー。
深津 KO さんが自身のテナントで作成する。

## トリガ

**種別**: HTTP 要求の受信時 (When a HTTP request is received)

### リクエスト本文 JSON Schema

```json
{
  "type": "object",
  "properties": {
    "top": {
      "type": "integer",
      "description": "取得件数 (デフォルト 50, 最大 100)",
      "default": 50,
      "maximum": 100
    },
    "since_iso": {
      "type": "string",
      "format": "date-time",
      "description": "この時刻以降の未読のみ (省略時は無制限)"
    },
    "folder": {
      "type": "string",
      "description": "対象フォルダ (省略時は受信トレイ)",
      "default": "Inbox"
    }
  }
}
```

### ヘッダ検証

トリガ直後に「条件」アクションを置き:

```
triggerOutputs()['headers']['x-claude-secret']  is equal to  <共有シークレット>
```

不一致なら HTTP 応答 401 を返して終了。

## 主要アクション

1. **Outlook: Get emails (V3)**
   - フォルダ: Inbox (パラメータで上書き可)
   - 検索クエリ: `isRead eq false`
   - Top: `@triggerBody()?['top']`
   - Order By: `receivedDateTime desc`
   - `since_iso` が来ていれば `receivedDateTime ge @{triggerBody()?['since_iso']}` を追加
2. **Select アクション** (Data Operations) でフィールド整形:
   ```
   {
     "id": item()?['id'],
     "subject": item()?['subject'],
     "from": item()?['from']?['emailAddress'],
     "to": item()?['toRecipients'],
     "cc": item()?['ccRecipients'],
     "received_at": item()?['receivedDateTime'],
     "preview": item()?['bodyPreview'],
     "importance": item()?['importance'],
     "has_attachments": item()?['hasAttachments'],
     "web_link": item()?['webLink'],
     "conversation_id": item()?['conversationId']
   }
   ```
3. **応答 (Response)**:
   - Status: 200
   - Headers: `Content-Type: application/json; charset=utf-8`
   - Body:
     ```json
     {
       "count": "@length(body('Select'))",
       "fetched_at": "@utcNow()",
       "items": "@body('Select')"
     }
     ```

## レスポンス JSON Schema

```json
{
  "type": "object",
  "properties": {
    "count": { "type": "integer" },
    "fetched_at": { "type": "string", "format": "date-time" },
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "subject": { "type": "string" },
          "from": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "address": { "type": "string" }
            }
          },
          "to": { "type": "array" },
          "cc": { "type": "array" },
          "received_at": { "type": "string", "format": "date-time" },
          "preview": { "type": "string" },
          "importance": { "type": "string", "enum": ["low", "normal", "high"] },
          "has_attachments": { "type": "boolean" },
          "web_link": { "type": "string" },
          "conversation_id": { "type": "string" }
        },
        "required": ["id", "subject", "from", "received_at", "preview"]
      }
    }
  }
}
```

## エラー応答

| 状況 | Status | Body |
|---|---|---|
| ヘッダ不一致 | 401 | `{"error": "unauthorized"}` |
| Graph 失敗 | 502 | `{"error": "graph_failed", "detail": "..."}` |
| 件数超過 | 400 | `{"error": "top_too_large"}` |

## テスト方法

```bash
curl -X POST "$PA_UNREAD_MAILS_URL" \
  -H "Content-Type: application/json" \
  -H "x-claude-secret: $PA_SHARED_SECRET" \
  -d '{"top": 10}'
```

## 注意

- 本文 (body) は **取得しない** (preview のみ)。本文が必要な場合は別フロー `get-mail-body` を後追いで作成
- 添付ファイル本体も含めない (`has_attachments` フラグのみ)
- 機密保持のため Power Automate の実行履歴は 28 日以内に確認・削除
