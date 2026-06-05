# プロジェクトルール

このファイルは Claude Code が自動的に読み込みます。
すべての対話でここに記載されたルールに従って動作します。

---

## プロジェクト概要

2026年度 Salesforce 研修「AI駆動開発」用のテンプレートリポジトリです。

- **対象**: Sales Cloud Enterprise Edition
- **API バージョン**: 63.0
- **使用言語**: Apex、JavaScript (LWC)、SOQL、Flow XML

---

## Apex コーディング規約

### 命名規約

| 対象 | 規約 | 例 |
|---|---|---|
| クラス名 | PascalCase | `DailyReportService` |
| メソッド名 | camelCase | `aggregateWeeklyKpi` |
| 変数名 | camelCase、意味のある英単語 | `targetAccounts` |
| 定数 | UPPER_SNAKE_CASE、`static final` | `MAX_BATCH_SIZE` |
| カスタムオブジェクト | PascalCase + `__c` | `DailyReport__c` |
| カスタム項目 | PascalCase + `__c` | `VisitAccount__c` |
| テストクラス | 対象クラス名 + `Test` | `DailyReportServiceTest` |
| テストメソッド | `test<対象機能>_<シナリオ>` | `testInsert_HappyPath` |

### 禁止される変数名

- `temp`, `temp1`, `data`, `data1`, `x`, `y`, `z`, `aaa`
- その他、用途が読み取れない名前

### 設計ルール

- **SOQL/DML はループの外で実行**(ガバナ制限違反の防止)
- **必ずバルク化**(1件ずつ処理しない)
- メソッドは 20 行以内を目標、最大 40 行
- クラスは 200 行以内を目標、最大 300 行
- 1メソッドの責務は1つに絞る
- マジックナンバー禁止、必ず定数化

---

## エラーハンドリング

- すべての DML は try-catch で囲む
- 例外を握りつぶさない(`catch (Exception e) {}` 禁止)
- 標準例外(IllegalArgumentException 等)ではなく、カスタム例外を作成
- カスタム例外名: `<機能名>Exception`(例: `DailyReportException`)
- エラーメッセージは日本語で、ユーザーに何が起きたか分かるように

### 例

```apex// ❌ 悪い例
try {
insert records;
} catch (Exception e) {
// 何もしない
}// ✅ 良い例
try {
insert records;
} catch (DmlException e) {
System.debug(LoggingLevel.ERROR, '日報の挿入に失敗: ' + e.getMessage());
throw new DailyReportException('日報の保存に失敗しました。', e);
}
```
---

## テストルール

- **すべての Apex クラスにテストクラスを必須で作成**
- **カバレッジ 90% 以上**
- ハッピーパス + 異常系の両方をテスト
- アサーション(System.assertEquals 等)を必ず入れる
- `@isTest(SeeAllData=false)` を必ず指定
- `@TestSetup` で共通データを作成(重複を避ける)
- テストはお互いに独立(実行順に依存しない)

---

## LWC ルール(機能追加期に該当)

- 1コンポーネント = `xxx.html` + `xxx.js` + `xxx.js-meta.xml` の3ファイル
- ファイル名は camelCase(例: `dailyReportList`)
- `@api` プロパティと `@track` 状態を明示
- エラーは `ShowToastEvent` でユーザー通知
- 標準コンポーネント(`lightning-*`)を優先して使用
- Apex 呼び出しは `@AuraEnabled` を付ける

---

## セキュリティ

- **FLS(Field-Level Security)チェックを必ず実施**
- **CRUD チェックを必ず実施**
- SOQL では `WITH SECURITY_ENFORCED` を活用
- 動的 SOQL では `String.escapeSingleQuotes()` を使用
- 個人情報をデバッグログに出力しない

---

## ファイル配置ルールforce-app/main/default/
├── classes/         Apex クラス、テストクラス
├── triggers/        Apex トリガー
├── lwc/             Lightning Web Components
├── objects/         カスタムオブジェクト
├── flows/           Flow
└── permissionsets/  権限セット

---

## Git 運用

- **ブランチ名**: `feature/<機能名>` または `<個人名>/<機能>`
- **コミットメッセージ**: 日本語OK、何を変更したかを明確に
- **Conventional Commits 推奨**: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`
- main ブランチへの直接 push は禁止、必ず PR 経由

---

## AI への共通指示

Claude(AI)がコードを書く・変更する際は、以下を必ず守ること:

1. **このCLAUDE.mdのルールに必ず従う**
2. **既存コードの命名規約と一致させる**
3. **テストクラスも一緒に作成・更新する**
4. **エラーハンドリングを必ず含める**
5. **セキュリティチェック(FLS/CRUD)を考慮する**
6. **不明な点はコードを書く前に質問する**
7. **大きな変更は段階的に提案する**
8. **コードを書いた後、自身でルール準拠をチェックする**

---

## このプロジェクトでの開発の流れ

1. main から feature ブランチを切る
2. ローカルで開発(`/refactor`、`/test` 等のスラッシュコマンド活用)
3. 自分のスクラッチ組織にデプロイして動作確認
4. テスト実行
5. 動作OKなら commit、push
6. GitHub で PR 作成
7. チーム内レビュー
8. main にマージ
9. 統合スクラ

| テストメソッド | `test<対象機能>_<シナリオ>` | `testInsert_HappyPath` |

### 禁止される変数名

- `temp`, `temp1`, `data`, `data1`, `x`, `y`, `z`, `aaa`
- その他、用途が読み取れない名前

### 設計ルール

- **SOQL/DML はループの外で実行**(ガバナ制限違反の防止)
- **必ずバルク化**(1件ずつ処理しない)
- メソッドは 20 行以内を目標、最大 40 行
- クラスは 200 行以内を目標、最大 300 行
- 1メソッドの責務は1つに絞る
- マジックナンバー禁止、必ず定数化

---
## エラーハンドリング

- すべての DML は try-catch で囲む
- 例外を握りつぶさない(`catch (Exception e) {}` 禁止)
- 標準例外(IllegalArgumentException 等)ではなく、カスタム例外を作成
- カスタム例外名: `<機能名>Exception`(例: `DailyReportException`)
- エラーメッセージは日本語で、ユーザーに何が起きたか分かるように

### 例

```apex
// ❌ 悪い例
try {
    insert records;
} catch (Exception e) {
    // 何もしない
}

// ✅ 良い例
try {
    insert records;
} catch (DmlException e) {
    System.debug(LoggingLevel.ERROR, '日報の挿入に失敗: ' + e.getMessage());
    throw new DailyReportException('日報の保存に失敗しました。', e);
}
```

---
## テストルール

- **すべての Apex クラスにテストクラスを必須で作成**
- **カバレッジ 90% 以上**
- ハッピーパス + 異常系の両方をテスト
- アサーション(System.assertEquals 等)を必ず入れる
- `@isTest(SeeAllData=false)` を必ず指定
- `@TestSetup` で共通データを作成(重複を避ける)
- テストはお互いに独立(実行順に依存しない)

---

## LWC ルール(機能追加期に該当)

- 1コンポーネント = `xxx.html` + `xxx.js` + `xxx.js-meta.xml` の3ファイル
- ファイル名は camelCase(例: `dailyReportList`)
- `@api` プロパティと `@track` 状態を明示
- エラーは `ShowToastEvent` でユーザー通知
- 標準コンポーネント(`lightning-*`)を優先して使用
- Apex 呼び出しは `@AuraEnabled` を付ける

---

## セキュリティ

- **FLS(Field-Level Security)チェックを必ず実施**
- **CRUD チェックを必ず実施**
- SOQL では `WITH SECURITY_ENFORCED` を活用
- 動的 SOQL では `String.escapeSingleQuotes()` を使用
- 個人情報をデバッグログに出力しない

---

## ファイル配置ルール
force-app/main/default/
├── classes/         Apex クラス、テストクラス
├── triggers/        Apex トリガー
├── lwc/             Lightning Web Components
├── objects/         カスタムオブジェクト
├── flows/           Flow
└── permissionsets/  権限セット

---

## Git 運用

- **ブランチ名**: `feature/<機能名>` または `<個人名>/<機能>`
- **コミットメッセージ**: 日本語OK、何を変更したかを明確に
- **Conventional Commits 推奨**: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`
- main ブランチへの直接 push は禁止、必ず PR 経由

---

## AI への共通指示

Claude(AI)がコードを書く・変更する際は、以下を必ず守ること:

1. **このCLAUDE.mdのルールに必ず従う**
2. **既存コードの命名規約と一致させる**
3. **テストクラスも一緒に作成・更新する**
4. **エラーハンドリングを必ず含める**
5. **セキュリティチェック(FLS/CRUD)を考慮する**
6. **不明な点はコードを書く前に質問する**
7. **大きな変更は段階的に提案する**
8. **コードを書いた後、自身でルール準拠をチェックする**

---

## このプロジェクトでの開発の流れ

1. main から feature ブランチを切る
2. ローカルで開発(`/refactor`、`/test` 等のスラッシュコマンド活用)
3. 自分のスクラッチ組織にデプロイして動作確認
4. テスト実行
5. 動作OKなら commit、push
6. GitHub で PR 作成
7. チーム内レビュー
8. main にマージ
9. 統合スクラッチに反映
