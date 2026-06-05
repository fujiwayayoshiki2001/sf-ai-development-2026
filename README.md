# Salesforce AI駆動開発 研修用リポジトリ

このリポジトリは、AI駆動開発研修で使用する開発環境の雛形です。

## クイックスタート

1. このリポジトリを WSL の任意のディレクトリにクローンする
2. Zscaler 証明書を `.devcontainer/zscaler-root.cer` に配置する
3. VS Code で開き、右下の通知から「Reopen in Container」をクリック
4. コンテナビルド完了後、ターミナルで各種認証を実施
   - `gh auth login`
   - `claude`
   - `sf org login web --alias DevHub --set-default-dev-hub`
   - `sf org create scratch --definition-file config/project-scratch-def.json --alias training --set-default --duration-days 30`
   - `sf project deploy start`

詳細な手順は **「AI駆動開発 環境構築手順書」** を参照してください。

## ディレクトリ構成

- `.devcontainer/` — Dev Container の設定（Dockerfile, devcontainer.json）
- `config/` — スクラッチ組織定義
- `force-app/` — Salesforce ソースコード
- `sfdx-project.json` — Salesforce プロジェクト定義

## トラブル時の連絡先

不明点・問題があれば講師までご質問ください。
GG