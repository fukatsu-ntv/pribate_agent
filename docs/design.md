# 業務エージェントチーム 設計ドキュメント

## 1. 目的とスコープ

深津 KO さん (NTV 編成局 新規事業開発部) の業務を Claude Code 上で半自動化するエージェントチーム。
**Task Controller をハブ**としたディスパッチ型構成。個人タスクは現状スコープ外、業務タスクのみ対応。

### 対象タスク

| # | タスク | 主要アクション | 担当 |
|---|---|---|---|
| 1 | メール業務 | 受信整理 / 要約 / 返信ドラフト / カレンダー連携 | mail |
| 2 | NTV 経理 (P&L) | AXROSS 取込 / 予実管理 / 月次レポート / 11Y5471 中心 | keiri |
| 3 | 企画書・伺書 | 構成立案 / ドラフト執筆 / 上司レビュー先回り | plan-doc |
| 4 | アイデア発散 | 多角的発散 / ロールプレイ / 勝ち筋仮説 | brainstorm |
| 5 | 市場リサーチ | 一次情報収集 / 出典管理 / 過去ストック再利用 | market-research |
| 6 | タスク統制 | **ハブ**: 分解・ディスパッチ・進捗集約・日次ブリーフ | task-controller |

## 2. アーキテクチャ

### 2.1 構成パターン: Task Controller ハブ型

```
                       ┌────────────────────────┐
                       │  User (深津 KO)        │
                       └───────────┬────────────┘
                                   │
                       ┌───────────▼────────────┐
                       │  Main Claude           │
                       │  (Claude Code orchestrator) │
                       └───────────┬────────────┘
                                   │ 原則ここを最初に呼ぶ
                       ┌───────────▼────────────┐
                       │  task-controller       │  ← ハブ
                       │  - タスク分解 / 依存判定 │
                       │  - run-id 払い出し      │
                       │  - Agent ツールで委譲   │
                       └─┬──┬──┬──┬──┬──────────┘
                         │  │  │  │  │
              ┌──────────┘  │  │  │  └─────────┐
              │   ┌─────────┘  │  └─────┐      │
              │   │   ┌────────┘        │      │
              ▼   ▼   ▼                 ▼      ▼
          ┌─────┐┌─────┐┌──────┐    ┌─────┐┌──────────┐
          │mail ││keiri││plan- │    │brain││market-   │
          │     ││     ││doc   │    │store││research  │
          └──┬──┘└──┬──┘└──┬───┘    └──┬──┘└────┬─────┘
             │      │      │            │       │
             ▼      ▼      ▼            ▼       ▼
         Outlook  AXROSS OneDrive    (LLM)  WebFetch
         Calendar SharePt OneDrive          WebSearch
         (M365)   PowerAuto
```

軽微な単発依頼 (例: 「メール 1 通の返信書いて」) は task-controller を経由せず直接呼んでよい。
連鎖依頼 (例: 新規企画起案) は task-controller が起点となる。

### 2.2 ディレクトリ構成

```
pribate_agent/
├── CLAUDE.md                        # プロジェクト全体方針
├── docs/
│   ├── design.md                    # 本ドキュメント
│   ├── requirements.md              # 統合要件 README (深津 KO 提供)
│   └── keiri-readme.md              # 経理エージェント要件 README
├── .claude/
│   ├── agents/                      # サブエージェント定義 (6 体)
│   │   ├── task-controller.md
│   │   ├── mail.md
│   │   ├── keiri.md
│   │   ├── plan-doc.md
│   │   ├── brainstorm.md
│   │   └── market-research.md
│   └── commands/                    # スラッシュコマンド
├── templates/
│   └── ringi.md                     # 伺書テンプレ
├── keiri/                           # 経理エージェント実装本体
│   ├── data/{input,output,archive}/ # gitignore (機密)
│   ├── templates/                   # 11Y5471 / 11Y5818 構造仕様
│   ├── scripts/{powerautomate,shared}/
│   ├── docs/                        # 用語集 / 運用ルール / 業務単位コード一覧
│   └── tests/fixtures/
└── workflows/                       # 実行時中間成果物 (gitignore)
    ├── <run-id>/                    # 連鎖タスクごとの run-id
    └── _research-stock/             # market-research の再利用ストック
```

## 3. 各エージェント仕様

詳細は `.claude/agents/<agent>.md` 参照。ここでは要点のみ。

### 3.1 共通仕様

- **言語**: 日本語 (です・ます調)。引用・固有名詞は原語のまま
- **出典**: 外部情報は URL とアクセス日を併記。事実 / 主張を分ける
- **承認ゲート**: 送信 / 提出 / 上書き / 外部共有は **必ずユーザー承認**
- **機密情報**: `keiri/data/` `workflows/` 以下は gitignore

### 3.2 task-controller (ハブ)
- 全依頼の起点。`Agent` ツールで他エージェントを呼ぶ
- run-id (`workflows/<YYYYMMDD-HHMM-slug>/`) を発行・共有
- 日次ブリーフ生成

### 3.3 mail
- Outlook (Microsoft Graph) 想定。MCP が利用可能ならそれを使用、不可ならドラフトを `workflows/` に出力
- 送信は必ず承認制
- カレンダー / Teams 連携も担当 (Teams 投稿は将来 MCP 対応)

### 3.4 keiri
- NTV 経理 (P&L)。AXROSS 取込 / 予実管理 / 月次レポート
- 編集対象は **11Y5471 のみ**。11Y5818 は参照のみ
- 用語 (概算 / X概 / 概処 / 実概 / 実伝) を厳守
- 詳細仕様: `docs/keiri-readme.md`

### 3.5 plan-doc
- 伺書 / PPT 骨子 / 1 枚サマリの 3 形式を使い分け
- 「Why us / Why now / How win」を必ず織り込む
- 上司レビュー想定の指摘 3 つに先回り

### 3.6 brainstorm
- フレームワーク (SCAMPER / クレイジー 8 / 逆転 / HMW / アナロジー / ロールプレイ)
- 勝ち筋仮説 (Why us / Why now / How win) に落とす

### 3.7 market-research
- 一次情報優先・出典必須
- 過去調査ストック (`workflows/_research-stock/`) を再利用

## 4. Microsoft 365 連携

| サービス | 接続方法 | 用途 | 状態 |
|---|---|---|---|
| Outlook (メール) | Microsoft Graph MCP | mail | 要セットアップ (現セッションで未ロード) |
| Outlook Calendar | Calendar MCP | task-controller / mail | 利用可 (現セッションでロード) |
| OneDrive / SharePoint | File MCP | keiri / plan-doc / market-research | 利用可 (現セッションでロード) |
| Teams | Microsoft Graph MCP | mail (投稿ドラフト) | 要セットアップ |
| Power Automate | HTTP トリガ | keiri (AXROSS 連携) | Phase 1 で設計予定 |
| Planner / To Do | Microsoft Graph MCP | task-controller | 任意 |

### 認証方針
- Microsoft Graph は OAuth2 (Authorization Code Flow)
- トークンはローカル `~/.config/pribate_agent/` (gitignore)
- 必要スコープ: `Mail.ReadWrite` `Mail.Send` `Files.ReadWrite` `Calendars.ReadWrite` `Tasks.ReadWrite` `ChannelMessage.Send`

## 5. 協調プロトコル

### 5.1 ディスパッチフロー

1. ユーザー依頼を Main Claude が受領
2. Main Claude が task-controller を呼ぶ (連鎖タスクの場合)
3. task-controller が分解・依存判定し、`Agent` ツールで専門エージェントを呼ぶ
4. 中間成果物は `workflows/<run-id>/` に Markdown で保存
5. 次エージェントへはファイルパスで受け渡し (コンテキスト圧迫を避ける)
6. task-controller が結果を統合 → Main Claude → ユーザー

### 5.2 中間成果物の置き場

```
workflows/20260508-1030-newproposal/
├── 01-research.md          # market-research
├── 02-ideas.md             # brainstorm 発散
├── 03-winning-hypothesis.md# brainstorm 勝ち筋
└── 04-ringi-draft.md       # plan-doc
workflows/_research-stock/   # 再利用可能な市場データ
workflows/_status/YYYY-MM-DD.md  # 日次ブリーフ
```

### 5.3 承認ゲート

不可逆 / 外部影響のある操作は必ず人間承認:
- メール送信 (Outlook)
- Teams 投稿
- カレンダー確定送信
- AXROSS 連動 / 収支管理シート上書き
- 経理判断 (費目変更 / 予算配分 / 概算戻し)
- 外部共有 (CC 追加 / SharePoint 公開範囲変更)

## 6. 定型ワークフロー (スラッシュコマンド)

| コマンド | 内容 |
|---|---|
| `/morning-brief` | task-controller: 当日予定 + 未読メール要約 + 期日タスク + 経理アラート |
| `/reply-mails` | mail: 未返信メールを優先度順にドラフト |
| `/new-proposal <テーマ>` | task-controller → market-research → brainstorm → plan-doc |
| `/monthly-expense` | (旧) → `/monthly-keiri` に置換予定: keiri が月次予実 + クローズ提案 |

## 7. セキュリティ・運用

- 機密情報 (取引先名・金額・予算) を含む中間ファイルは `workflows/` `keiri/data/` に置き gitignore
- API トークンは環境変数 / シークレットマネージャ経由
- 経理データを Anthropic API 以外の外部 API へ送信しない
- 各エージェントの実行ログを `logs/` に保存

## 8. ロードマップ

| Phase | 内容 | 完了条件 |
|---|---|---|
| 0 | 設計 + 要件 README 統合 | 本書 + `docs/keiri-readme.md` がレビュー済み |
| 1 | サブエージェント定義の確立 | 6 体の `.claude/agents/*.md` が運用に乗る |
| 2 | Microsoft Graph MCP 接続 | mail / Outlook / Teams が読み取り可能 |
| 3 | 経理 Phase 1 実証 | AXROSS サンプル取込 → 予実集計が 11Y5471 で動く |
| 4 | 定型ワークフロー実装 | `/morning-brief` `/new-proposal` 動作 |
| 5 | 承認ゲート整備 | 送信・上書きが承認制で動作、ログ可視化 |

## 9. 未決事項

- [ ] Microsoft Graph MCP (Outlook / Teams) の社内 IT 承認
- [ ] AXROSS 出力ファイルの正式保存パス (OneDrive / SharePoint)
- [ ] Power Automate トリガ設計
- [ ] 上司レビューフォーマット (伺書 / PPT のどちらを正にするか)
- [ ] 過去調査ストックのスキーマ統一
