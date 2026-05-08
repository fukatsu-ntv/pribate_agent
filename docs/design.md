# 業務エージェントチーム 設計ドキュメント

## 1. 目的とスコープ

業務全般のタスクを Claude Code 上で自動・半自動的に処理するエージェントチームを構築する。

### 対象タスク

| # | タスク | 主要アクション |
|---|---|---|
| 1 | メールチェック・返信 | 受信トレイ確認 / 重要度判定 / 下書き作成 / 返信送信 |
| 2 | 精算処理 | 領収書 OCR / 経費分類 / 申請書作成 / 申請ワークフロー投入 |
| 3 | 企画書の作成 | 構成立案 / ドラフト執筆 / レビュー反映 / 体裁整形 |
| 4 | 企画のブレスト | アイデア発散 / 評価軸設定 / 収束 / 次アクション抽出 |
| 5 | 市場リサーチ | 情報収集 / 出典管理 / 要約 / インサイト抽出 |
| 6 | タスクコントロール | 全体状況の把握 / 優先順位付け / 期日管理 / リマインド |

## 2. アーキテクチャ

### 2.1 構成パターン: オーケストレーター集中型

```
                       ┌────────────────────────┐
                       │  User (Claude Code)    │
                       └───────────┬────────────┘
                                   │
                       ┌───────────▼────────────┐
                       │  Orchestrator          │
                       │  (メイン Claude)       │
                       │  - タスク分解          │
                       │  - サブエージェント振分│
                       │  - 結果統合            │
                       └─┬──┬──┬──┬──┬──┬──────┘
                         │  │  │  │  │  │
       ┌─────────────────┘  │  │  │  │  └────────────────┐
       │   ┌─────────────────┘  │  │  └──────┐           │
       │   │   ┌─────────────────┘  └──┐     │           │
       ▼   ▼   ▼                       ▼     ▼           ▼
   ┌─────┐┌────┐┌─────┐            ┌─────┐┌──────┐┌───────────┐
   │mail ││ex- ││plan-│            │brain││market││task-      │
   │     ││pense│doc  │            │store││ -res ││controller │
   └──┬──┘└─┬──┘└──┬──┘            └──┬──┘└──┬───┘└─────┬─────┘
      │     │      │                  │      │           │
      ▼     ▼      ▼                  ▼      ▼           ▼
   Outlook OneDrive Word/PPT       (LLM)   WebSearch  Planner/
                                                       Tasks
```

### 2.2 ディレクトリ構成

```
pribate_agent/
├── docs/
│   ├── design.md                # 本ドキュメント
│   └── agents/                  # 各エージェントの詳細仕様
│       ├── mail.md
│       ├── expense.md
│       ├── plan-doc.md
│       ├── brainstorm.md
│       ├── market-research.md
│       └── task-controller.md
├── .claude/
│   ├── agents/                  # サブエージェント定義 (Markdown)
│   │   ├── mail.md
│   │   ├── expense.md
│   │   ├── plan-doc.md
│   │   ├── brainstorm.md
│   │   ├── market-research.md
│   │   └── task-controller.md
│   ├── commands/                # スラッシュコマンド (定型ワークフロー)
│   │   ├── morning-brief.md
│   │   ├── reply-mails.md
│   │   └── new-proposal.md
│   └── settings.json            # 権限・MCP設定
├── templates/                   # 企画書・精算書テンプレート
│   ├── proposal.md
│   └── expense-report.md
├── workflows/                   # 定型ワークフローのプロンプト
└── CLAUDE.md                    # プロジェクト全体の方針
```

## 3. 各エージェント仕様

### 3.1 共通仕様

- **言語**: 日本語で対話・出力 (引用・固有名詞は原語のまま)
- **トーン**: ビジネス文書としての敬体 (です・ます調)
- **出典**: 外部情報を扱う場合は必ず出典 URL / ファイルパスを明記
- **権限境界**: 送信・申請・公開などの不可逆操作は「下書き作成のみ」をデフォルトとし、ユーザー承認後に実行

### 3.2 mail (メール担当)

| 項目 | 内容 |
|---|---|
| 役割 | Outlook の受信・送信処理 |
| 入力 | "未読メール一覧をください" / "Aさんに〜の返信を" |
| 出力 | 要約一覧 / 返信ドラフト / カテゴリ分類 |
| ツール | Outlook MCP, Read, Write |
| 権限 | 送信は承認制 (デフォルトは下書き保存のみ) |

主な機能:
- 受信トレイの要約 (重要度・要返信フラグ付与)
- 返信ドラフト生成 (過去のやり取りを文脈に含める)
- スレッド検索 (件名/送信者/期間)
- カレンダー連携 (会議候補日の抽出 → calendar MCP へ橋渡し)

### 3.3 expense (精算担当)

| 項目 | 内容 |
|---|---|
| 役割 | 経費精算の準備と申請補助 |
| 入力 | 領収書ファイル / 経費明細 / "今月の交通費を集計して" |
| 出力 | 経費明細表 / 精算申請書ドラフト |
| ツール | OneDrive MCP, Read, Write |
| 権限 | 申請送信は承認制 |

主な機能:
- 領収書 (画像/PDF) からの金額・日付・摘要抽出
- 勘定科目への自動分類 (社内ルールは `templates/expense-rules.md` を参照)
- 月次サマリー
- 申請フォーマットへの転記

### 3.4 plan-doc (企画書作成担当)

| 項目 | 内容 |
|---|---|
| 役割 | 企画書 / 提案書の執筆 |
| 入力 | 企画概要 / brainstorm の成果物 / market-research の調査結果 |
| 出力 | Word/PowerPoint 互換の Markdown ドラフト |
| ツール | Read, Write, OneDrive MCP |
| 権限 | ローカル/OneDrive への保存は自動、外部共有は承認制 |

主な機能:
- 標準構成 (背景 / 課題 / 提案 / 実行計画 / KPI / 体制 / スケジュール / 予算) でのドラフト
- テンプレート `templates/proposal.md` をベースに展開
- 数値や引用は market-research の出典を保持

### 3.5 brainstorm (ブレスト担当)

| 項目 | 内容 |
|---|---|
| 役割 | アイデア発散と収束 |
| 入力 | テーマ / 制約条件 / 評価軸 |
| 出力 | アイデアリスト / マトリクス評価 / 推奨案 |
| ツール | Read, Write |
| 権限 | 読み書きのみ (副作用なし) |

主な機能:
- SCAMPER / クレイジー8 / 逆転発想 など複数フレームワークでの発散
- 評価軸 (実現性 × インパクト等) でのマトリクス化
- 上位案を plan-doc へ受け渡せる形式に整形

### 3.6 market-research (市場リサーチ担当)

| 項目 | 内容 |
|---|---|
| 役割 | 市場・競合・トレンド調査 |
| 入力 | 調査テーマ / スコープ (期間・地域・業界) |
| 出力 | 調査メモ (出典付き) / インサイト要約 |
| ツール | WebSearch, WebFetch, OneDrive MCP |
| 権限 | 読み取りのみ |

主な機能:
- 一次情報優先の情報収集 (公式発表 / 統計 / 一次取材)
- 出典 URL / アクセス日を必ず記録
- 主張と事実を分離して記述

### 3.7 task-controller (タスクコントロール担当)

| 項目 | 内容 |
|---|---|
| 役割 | 全タスクの状況管理とリマインド |
| 入力 | 各エージェントのアウトプット / カレンダー / Planner |
| 出力 | 日次ブリーフ / 期日リマインド / 進捗ダッシュボード |
| ツール | Calendar MCP, OneDrive MCP, Read, Write |
| 権限 | 期日変更などは承認制 |

主な機能:
- 朝の To-Do ブリーフ生成
- 期日が近いタスクのアラート
- 各エージェントの完了報告を集約

## 4. 外部連携 (Microsoft 365)

### 4.1 利用予定 MCP / API

| サービス | 接続方法 | 用途 | 状態 |
|---|---|---|---|
| Outlook (メール) | Microsoft Graph MCP | mail | **要セットアップ** |
| OneDrive | File MCP (現在接続中) または Graph MCP | expense / plan-doc / market-research | 一部利用可 |
| Teams | Microsoft Graph MCP | (将来) 通知・会議連携 | 任意 |
| Outlook Calendar | Calendar MCP (現在接続中) | task-controller / mail | 利用可 |
| Planner / To Do | Microsoft Graph MCP | task-controller | **要セットアップ** |

### 4.2 認証方針

- Microsoft Graph は OAuth2 (Authorization Code Flow) を想定
- トークンはローカル `~/.config/pribate_agent/` に保存 (gitignore)
- 必要スコープ:
  - `Mail.Read`, `Mail.Send`, `Mail.ReadWrite`
  - `Files.ReadWrite`
  - `Calendars.ReadWrite`
  - `Tasks.ReadWrite`

## 5. 協調プロトコル (オーケストレーター集中型)

### 5.1 タスク受領 → 振り分けフロー

1. ユーザー指示を Orchestrator が受領
2. Orchestrator がタスクを分解し、依存関係を判定
3. 独立タスクは並列でサブエージェントに委譲
4. 依存タスクは順次実行 (例: market-research → brainstorm → plan-doc)
5. 各サブエージェントの結果を Orchestrator が統合
6. ユーザーへ最終回答 / 承認依頼

### 5.2 サブエージェント間データ受け渡し形式

中間成果物は Markdown ファイルとして `workflows/<run-id>/` に保存し、
次のエージェントへはファイルパスで渡す。生のテキストを長文でコンテキスト経由
にしない (コンテキスト消費・再現性確保のため)。

```
workflows/2026-05-08-newproduct/
├── 01-research.md      # market-research の成果物
├── 02-ideas.md         # brainstorm の成果物
└── 03-proposal.md      # plan-doc の成果物
```

### 5.3 承認ゲート

不可逆 / 外部影響のある操作は必ず人間承認:
- メール送信
- 精算申請の最終提出
- 外部共有 (Teams 投稿、メール CC 追加 等)
- カレンダーの確定送信

## 6. 定型ワークフロー (スラッシュコマンド)

| コマンド | 内容 |
|---|---|
| `/morning-brief` | task-controller が当日の予定 + 未読メール要約 + 期日タスクをまとめる |
| `/reply-mails` | mail が未返信メールを抽出し、優先度順にドラフトを順次提示 |
| `/new-proposal <テーマ>` | market-research → brainstorm → plan-doc を順次起動し企画書ドラフトを作る |
| `/monthly-expense` | expense が当月分の領収書を集計し申請ドラフトを作成 |

## 7. セキュリティ・運用

- 機密情報 (顧客名、金額) を含む中間ファイルは `workflows/` に置き gitignore
- API トークンは環境変数 / シークレットマネージャ経由で参照
- 各エージェントの実行ログを `logs/` に保存し、後追い可能にする
- 月次で `templates/` と `docs/agents/` を見直し、ナレッジを反映

## 8. ロードマップ

| Phase | 内容 | 完了条件 |
|---|---|---|
| 0 | 設計ドキュメント (本書) | レビュー完了 |
| 1 | サブエージェント雛形 6 体 | `.claude/agents/*.md` を Claude Code から呼び出せる |
| 2 | Microsoft Graph MCP 接続 | mail / calendar / OneDrive が読み取り可能 |
| 3 | 定型ワークフロー実装 | `/morning-brief` `/reply-mails` `/new-proposal` 動作 |
| 4 | テンプレートと社内ルール反映 | 精算ルール / 企画書テンプレ / 文体ガイド整備 |
| 5 | 承認ゲート整備 | 送信・申請が承認制で動作、ログ可視化 |

## 9. 未決事項 (要確認)

- [ ] Microsoft Graph MCP の利用可否 (社内 IT ポリシー / Azure AD アプリ登録)
- [ ] 精算ワークフロー: 自社の経費精算システム (Concur / freee / 楽楽精算 等) はどれか
- [ ] 企画書テンプレート: 既存の社内フォーマットがあるか
- [ ] 出力形式: Word / PowerPoint / Markdown のどれを正とするか
- [ ] ブレスト / リサーチで参照可能な社内ナレッジベースの有無
