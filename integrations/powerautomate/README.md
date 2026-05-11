# Power Automate 連携

`mail` エージェント Phase 1 で利用する Power Automate フローの仕様書と Claude 側呼び出しヘルパー。
Microsoft Graph 直結ではなく、**深津 KO さんのテナント上で構築する Power Automate フロー** を HTTP トリガで叩く構成。

## 全体像

```
   Claude Code (mail エージェント)
            │ curl POST (Bearer or shared secret)
            ▼
   Power Automate HTTP トリガ (KO さん作成)
            │ Microsoft Graph コネクタ
            ▼
   Outlook / Teams (KO さんの M365)
```

理由:
- 社内 IT のテナントアプリ登録 (Azure AD) なしで進められる
- KO さん本人の権限で動くので余計なスコープを増やさない
- 失敗時のログが Power Automate 側に残る

## 認証

- 各フローは **Bearer token** または **共有シークレット** を `x-claude-secret` ヘッダで受け取る方式
- Claude 側のシークレットは `.env.powerautomate` (gitignore) に保存
- フロー側でヘッダ検証 → 一致しなければ 401

## 環境変数 (`.env.powerautomate`)

```bash
PA_UNREAD_MAILS_URL="https://prod-XX.japaneast.logic.azure.com:443/workflows/.../triggers/manual/paths/invoke?..."
PA_TEAMS_NOTIFY_URL="https://prod-XX.japaneast.logic.azure.com:443/workflows/.../triggers/manual/paths/invoke?..."
PA_SHARED_SECRET="<KO さんが発行する 32 byte ランダム文字列>"
```

> Power Automate の URL には署名パラメータ (`sig=...`) が含まれているため、URL 自体が一次認証。
> その上で `x-claude-secret` ヘッダで二段階に絞る。

## フロー一覧

| フロー | 役割 | 仕様 |
|---|---|---|
| `get-unread-mails` | 未読メールを最大 N 件取得 | [flows/get-unread-mails.md](flows/get-unread-mails.md) |
| `teams-notify` | Teams チャネル / チャットへの通知投稿 | [flows/teams-notify.md](flows/teams-notify.md) |

## 呼び出し方 (Claude 側)

`scripts/call_flow.sh` の共通ヘルパー経由で叩く:

```bash
# 未読取得
./integrations/powerautomate/scripts/call_flow.sh get-unread-mails '{"top": 50}'

# Teams 通知
./integrations/powerautomate/scripts/call_flow.sh teams-notify "$(cat workflows/<run-id>/teams-payload.json)"
```

## セキュリティ・運用ルール

1. URL とシークレットは絶対にコミットしない (`.env.powerautomate` は gitignore)
2. Claude のターミナル出力にも URL / シークレットを露出させない
3. 取得した未読メール本文は `workflows/<run-id>/inbox-raw.json` に保存 (gitignore)
4. Teams 通知前には必ずユーザー確認 (送信実行はユーザー手動 or 承認後のみ)
5. レート制限: 1 分あたり 10 回まで (Power Automate Free プランの上限を考慮)
6. フロー側のログ保持期間は 28 日 (Power Automate 既定)。長期保管が必要ならフロー内で OneDrive へ書き出す

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 401 Unauthorized | シークレット不一致 / URL の `sig` 期限切れ | `.env.powerautomate` を確認 / Power Automate でトリガを再生成 |
| 504 Gateway Timeout | Graph API が遅い | フロー側にリトライポリシーを追加 |
| 文字化け | UTF-8 ヘッダ未設定 | フロー応答に `Content-Type: application/json; charset=utf-8` を明示 |
| Teams 通知が届かない | Teams コネクタの権限切れ | Power Automate でコネクタを再認証 |

## Phase 2 以降の拡張候補

- メール送信フロー (`send-mail`) の追加 — ユーザー承認後の自動送信
- カレンダー予定作成 (`create-meeting`) — 既存の Calendar MCP で代替可能なので優先度低
- AXROSS 出力到着検知 (`watch-onedrive`) — keiri エージェントの取込トリガ化
