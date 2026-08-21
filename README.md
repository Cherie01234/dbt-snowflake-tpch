# dbt-snowflake-tpch

Snowflake の TPC-H サンプルデータを題材に、**dbt Core による3層構成のELTパイプライン**を設計・実装した学習プロジェクトです。

実装そのものより、**「なぜその設計にしたか」を言語化すること**を目的にしています。設計判断は下記 [設計判断](#設計判断) に記載しています。

---

## 技術構成

| 要素 | 内容 |
|---|---|
| DWH | Snowflake（Enterprise / AWS ap-northeast-1） |
| 変換 | dbt Core 1.12.3 + dbt-snowflake 1.12.0 |
| Python | 3.10.6 |
| ソースデータ | `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1`（Snowflake標準提供の共有DB） |

Warehouse は `XSMALL` / `AUTO_SUSPEND=60s` とし、Resource Monitor でクレジット上限とアラートを設定しています。

---

## データモデル

```
SNOWFLAKE_SAMPLE_DATA.TPCH_SF1  (source)
├── orders    ─┐
├── lineitem  ─┤
├── customer  ─┤
└── nation    ─┘
                │
      ┌─────────┴──────────────────────────┐
      │  staging (view)                    │
      │  ├── stg_tpch__orders              │
      │  ├── stg_tpch__lineitems           │
      │  ├── stg_tpch__customers           │
      │  └── stg_tpch__nations             │
      └─────────┬──────────────────────────┘
                │
      ┌─────────┴──────────────────────────┐
      │  marts (table)                     │
      │  ├── fct_orders     1,500,000 rows │
      │  └── dim_customers    150,000 rows │
      └────────────────────────────────────┘
```

| モデル | 層 | 実体 | 内容 |
|---|---|---|---|
| `stg_tpch__orders` | staging | view | 注文ヘッダ。カラム名を統一 |
| `stg_tpch__lineitems` | staging | view | 注文明細。カラム名を統一 |
| `stg_tpch__customers` | staging | view | 顧客マスタ。カラム名を統一 |
| `stg_tpch__nations` | staging | view | 国マスタ。カラム名を統一 |
| `fct_orders` | marts | table | 注文ファクト。明細を注文単位に集約し、`net_revenue` を算出 |
| `dim_customers` | marts | table | 顧客ディメンション。国マスタを結合 |

---

## 設計判断

### 1. なぜ staging は view、marts は table にしたか

**staging層は type 変換とリネームだけの薄い層**で、実体を持たせるとストレージを二重に消費するうえ、ソースの更新が即座に反映されなくなります。そのため `view` としました。

**marts層は JOIN と集計を含み、かつ BIツールやアナリストから繰り返し参照される層**です。`view` のままだと参照のたびに600万行（`lineitem`）の集約が再計算されます。BIのダッシュボードは開くたびに同じクエリを投げるため、`table` として実体化しないとコンピュートコストが積み上がります。

> なお `view` は「ストレージコストがゼロ」であって「コストゼロ」ではありません。参照のたびに裏のSELECTが実行されるため、コンピュートコストは発生します。この区別が、層ごとに materialization を使い分ける根拠になっています。

### 2. staging層の責務をどこまでと定義したか

**やること**

ソーステーブル1つにつきモデル1つを対応させ、以下のみを行います。

1. カラム名の統一（`O_` / `L_` / `C_` プレフィックスの除去、スネークケース化）
2. 型変換
3. 軽微なクレンジング

**やらないこと**

JOIN・集計・フィルタ・ビジネスロジックは**一切持ち込みません**。

**理由**

staging層を「ソースの素直な写像」に保つことで、

1. 下流がソース側の命名規則を知らなくて済む
2. ソース側の変更の影響が staging層で吸収される
3. 同じ staging モデルを複数の marts から再利用できる

### 3. 命名規約とその理由

**規約**

- staging層： `stg_<ソース名>__<エンティティ名>`
- marts層： `fct_`（ファクト） / `dim_`（ディメンション）のプレフィックス

**理由**

1. プレフィックスにより、**ファイル名だけで層と役割が判別できる**。`dbt run --select stg_*` のような選択実行もしやすくなる
2. **アンダースコア2つ**は、ソース名とエンティティ名の境界を機械的に判別するため。将来 `stg_salesforce__orders` と `stg_tpch__orders` が並んだとき、シングルだと区切りが読み取れない
3. **最も重要な理由：dbtではモデル名がそのまま DWH のテーブル名になる。** つまり命名規約＝DWHの命名規約であり、後から変更すると下流のBI・クエリ・レポートがすべて壊れる。だからプロジェクト開始時に決めて文書化する価値が高い

---

## セットアップ

```bash
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

`~/.dbt/profiles.yml` に接続情報を配置します。

```yaml
dbt_tpch_practice:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <ORGNAME-ACCOUNTNAME>
      user: <YOUR_USER>
      password: <YOUR_PASSWORD>
      role: <YOUR_ROLE>
      warehouse: <YOUR_WAREHOUSE>
      database: <YOUR_DATABASE>
      schema: <YOUR_SCHEMA>
      threads: 4
```

```bash
dbt debug
dbt run
```

---

## 今後の実装予定

- [ ] `fct_orders` の incremental 化（`merge` 戦略 + lookback による遅延到着データ対応）
- [ ] full-refresh と incremental のコンピュートコスト比較（実測）
- [ ] dbt test（generic / singular）と `severity: warn / error` の設計
- [ ] テスト失敗時の運用手順（RUNBOOK）
- [ ] `intermediate` 層の追加による3層化
- [ ] DEV / PRD の環境分離とロール設計
- [ ] GitHub Actions による CI

---

## 振り返り

### 気づいたこと

**dbt は層単位で待ち合わせをしない。**
`dbt run` のログを見ると、`dim_customers` は `stg_tpch__orders` の完了を待たずに起動していました。dbtは `ref()` から構築した依存グラフを見て、**自分が実際に依存しているモデルだけ**を待ちます。`dim_customers` が必要とするのは `customers` と `nations` だけなので、`orders` の完了は待ちません。「staging層が全部終わってから marts層」という層単位の逐次実行ではない、という点は実行計画を読むうえで重要でした。

**モデルファイルを削除しても、DWH上のオブジェクトは消えない。**
`dbt init` が生成したサンプルモデルを削除しても、Snowflake上のテーブル／ビューは残り続けます（orphaned relations）。手動で `DROP` が必要でした。実務では定期的な棚卸しが要る箇所だと理解しました。

**Snowflake の識別子は引用符なしなら大文字に正規化される。**
ユーザー名を大文字で入力しても接続できたのはこのためです。同じルールがDB名・スキーマ名・テーブル名にも適用され、**ダブルクォートで囲むと大文字小文字が固定される**ため、dbt では識別子を引用符で囲まないのが原則だと理解しました。

**`dbt compile` が最も有用なデバッグ手段。**
`target/compiled/` に Jinja 展開後の生SQLが出力されます。`ref()` が実テーブル名に置き換わった状態を確認でき、そのまま Snowsight に貼って実行できます。

### 詰まったところ

（実装を進めながら追記）
