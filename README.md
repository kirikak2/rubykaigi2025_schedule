# RubyKaigi2025 スケジュールパーサー

RubyKaigi2025のスケジュール情報を公式サイトから取得し、整理するRubyスクリプトです。セッションのタイトル、発表者、時間、会場情報、概要など各種情報を取得し、コンソール表示または各種形式でのファイル出力が可能です。

## 機能

- RubyKaigi2025の公式サイトからスケジュール情報を自動取得
- Day1, Day2, Day3の全セッション情報を解析
- 各セッションの詳細ページから発表概要、発表者情報などを取得
- 午前・午後のセッションごとの整理
- キーノートなどの特別セッションの強調表示
- Markdown形式またはJSON形式でのファイル出力

## インストール

### 必要なもの

- Ruby 2.5以上
- 以下のGem:
  - nokogiri (HTML解析用)
  - json (JSONデータ操作用、標準ライブラリですが明示)

### セットアップ

1. リポジトリをクローンまたはダウンロードします

```bash
git clone https://github.com/kirikak2/rubykaigi2025-parser.git
cd rubykaigi2025-parser
```

2. 必要なGemをインストールします

```bash
bundle install
```

または

```bash
gem install nokogiri
```

## 使い方

### 基本的な使い方

スケジュール情報を取得してコンソールに表示します：

```bash
ruby rubykaigi2025_parser.rb
```

### 詳細情報の取得

各セッションの詳細ページから発表概要や発表者情報も取得します：

```bash
ruby rubykaigi2025_parser.rb --fetch-details
```

### Markdownファイルへの出力

スケジュール情報をMarkdown形式で保存します：

```bash
ruby rubykaigi2025_parser.rb --markdown rubykaigi2025.md
```

詳細情報を含めたMarkdownファイルを生成：

```bash
ruby rubykaigi2025_parser.rb --fetch-details --markdown rubykaigi2025.md
```

### JSONファイルへの出力

スケジュール情報をJSON形式で保存します：

```bash
ruby rubykaigi2025_parser.rb --json rubykaigi2025.json
```

### その他のオプション

ヘルプを表示します：

```bash
ruby rubykaigi2025_parser.rb --help
```

## 出力例

### コンソール出力

```
# RubyKaigi2025 タイムテーブルサマリー

## DAY1: Apr 16

### 午前
10:00-11:00 | Between Character and Character Encoding (JA, Keynote) - Mari Imaizumi
           | 概要: In modern computing, Unicode has become the go-to solution for most scenarios. However, challenges related to character encoding still exist and continue to evolve as we adapt to Unicode. By examining how Ruby handles updates to Unicode, this discussion explores the current issues surrounding character encoding.
11:10-11:40 | Make Parsers Compatible Using Automata Learning (JA) - Hiroya Fujinami
           | 概要: [セッション概要]
...
```

### Markdown出力

生成されるMarkdownファイルには、各セッションの詳細情報（概要、発表者プロフィール、SNSリンクなど）が含まれます。

## 注意点

- 詳細情報の取得には時間がかかります（各セッションページへの個別アクセスが必要なため）
- サーバーに負荷をかけないよう、リクエスト間に待機時間を設けています
- RubyKaigi公式サイトの構造が変更された場合、正しく動作しなくなる可能性があります

## ライセンス

MIT

## 謝辞

このツールはRubyKaigi公式サイトのデータを利用しています。RubyKaigi運営チームおよび関係者の皆様に感謝します。