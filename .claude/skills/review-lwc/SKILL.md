---
name: review-lwc
description: |
  Lightning Web Components (LWC) のコード品質をチェックするスキル。
  LWC 特有の観点（エラーハンドリング、ライフサイクル、Lightning Data Service、
  パフォーマンス、アクセシビリティ）でレビューする。

  以下のような場面で使用：
  - 「LWC をレビューして」
  - 「@wire のエラーハンドリングが適切か確認して」
  - 「このコンポーネントの品質を見て」
  - /review コマンドが LWC ファイル（.js）に対して実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# LWC レビュー

このスキルは、Lightning Web Components (LWC) のコード品質をレビューします。

## あなたの役割

LWC 開発の専門家として、コンポーネントの品質・堅牢性・パフォーマンスをレビューしてください。
Salesforce 公式が推奨する LWC のベストプラクティスに沿って評価します。

## 必ずチェックする項目

### 1. @wire のエラーハンドリング欠如（最重要）

```javascript
// 検出パターン
@wire(getScoreBreakdown, { leadId: '$recordId' })
wiredScore({ data }) {          // ← error を受け取っていない
    if (data) {
        this.score = data;
    }
    // error のとき何も起きず、画面が無言で壊れる
}
```

**問題点**:
`@wire` は `{ data, error }` の両方を返します。`error` を処理しないと、
Apex 側で例外が起きても画面には何も表示されず、ユーザーは「動かない」としか
分かりません。デバッグも困難になります。

**改善案**:

```javascript
@wire(getScoreBreakdown, { leadId: '$recordId' })
wiredScore({ data, error }) {
    if (data) {
        this.score = data;
        this.error = undefined;
    } else if (error) {
        this.error = error;
        this.score = undefined;
        // 必要なら toast でユーザーに通知
    }
}
```

### 2. imperative Apex 呼び出しの try-catch 欠如（最重要）

```javascript
// 検出パターン
async handleRecalculate() {
    await recalculateScore({ leadId: this.recordId });  // ← try-catch なし
    // 失敗すると未処理の Promise 拒否になり、ユーザーに何も伝わらない
}
```

**問題点**:
命令的（imperative）な Apex 呼び出しで例外が起きると、`catch` がないと
エラーが握りつぶされます。ユーザーは操作が成功したのか失敗したのか分かりません。

**改善案**:

```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

async handleRecalculate() {
    try {
        await recalculateScore({ leadId: this.recordId });
        this.dispatchEvent(new ShowToastEvent({
            title: '成功',
            message: 'スコアを再計算しました',
            variant: 'success'
        }));
    } catch (error) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'エラー',
            message: error.body?.message ?? '処理に失敗しました',
            variant: 'error'
        }));
    }
}
```

### 3. innerHTML への直接代入（セキュリティ）

```javascript
// 検出パターン
this.template.querySelector('.container').innerHTML = userInput;  // ← XSS リスク
```

**問題点**:
ユーザー入力や外部データを `innerHTML` にそのまま代入すると、
クロスサイトスクリプティング (XSS) の脆弱性になります。

**改善案**:
- テンプレート構文でバインドする（`{value}`）
- テキストなら `textContent` を使う
- どうしても動的 HTML が必要なら `lwc:dom="manual"` + サニタイズを検討
```html
<!-- テンプレート構文で安全にバインド -->
<div class="container">{userInput}</div>
```

### 4. Lightning Data Service (LDS) を使わない手動取得

```javascript
// 検出パターン
// 単一レコードの項目を表示したいだけなのに、
// わざわざカスタム Apex を呼んでいる
import getLead from '@salesforce/apex/LeadController.getLead';

@wire(getLead, { leadId: '$recordId' })
wiredLead({ data }) { ... }
```

**問題点**:
単一レコードの項目表示なら、`getRecord`（Lightning Data Service）を使う方が
適切です。LDS はキャッシュ・自動更新・FLS 準拠が組み込まれており、
カスタム Apex を書く必要がありません。

**改善案**:

```javascript
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import SCORE_FIELD from '@salesforce/schema/Lead.Score__c';

@wire(getRecord, { recordId: '$recordId', fields: [SCORE_FIELD] })
wiredLead;

get score() {
    return getFieldValue(this.wiredLead.data, SCORE_FIELD);
}
```

> **補足**: 集計や複雑なクエリが必要な場合は Apex が正解です。
> 「単一レコードの項目表示」に限って LDS を推奨します。

### 5. renderedCallback の誤用（パフォーマンス・無限ループ）

```javascript
// 検出パターン
renderedCallback() {
    this.count = this.count + 1;   // ← プロパティ変更で再レンダリング → 無限ループ
    this.loadData();               // ← 毎回のレンダリングで実行される
}
```

**問題点**:
`renderedCallback` はレンダリングのたびに呼ばれます。ここでリアクティブな
プロパティを変更すると再レンダリングが起き、無限ループになります。
また、初期化処理をここに書くと何度も実行されます。

**改善案**:
- 初期化は `connectedCallback` で一度だけ行う
- `renderedCallback` で処理が必要なら、フラグでガードする
```javascript
connectedCallback() {
    this.loadData();   // 初期化は一度だけ
}

renderedCallback() {
    if (this.hasRendered) {
        return;
    }
    this.hasRendered = true;
    // 一度だけ実行したい DOM 依存の処理
}
```

### 6. getter 内での重い処理・副作用（パフォーマンス）

```javascript
// 検出パターン
get sortedLeads() {
    return this.leads.sort((a, b) => b.score - a.score);  // ← 元配列を破壊 + 毎回ソート
}
```

**問題点**:
getter はレンダリングのたびに評価されます。重い処理（ソート・フィルタ）を
毎回行うとパフォーマンスに影響します。また `sort()` は元配列を破壊します。

**改善案**:
- データ取得時に一度だけ加工する
- getter は軽量に保つ
```javascript
// データ取得時にソート
wiredLeads({ data }) {
    if (data) {
        this.leads = [...data].sort((a, b) => b.score - a.score);
    }
}
```

### 7. アクセシビリティの欠如

```html
<!-- 検出パターン -->
<img src={iconUrl} />                          <!-- alt なし -->
<div onclick={handleClick}>クリック</div>       <!-- div にクリック（キーボード操作不可） -->
<lightning-button-icon icon-name="utility:refresh"></lightning-button-icon>  <!-- alternative-text なし -->
```

**問題点**:
スクリーンリーダー利用者や、キーボード操作のユーザーが使えません。
Salesforce はアクセシビリティを重視しており、SLDS コンポーネントも対応しています。

**改善案**:

```html
<img src={iconUrl} alt="スコアアイコン" />
<lightning-button label="クリック" onclick={handleClick}></lightning-button>
<lightning-button-icon
    icon-name="utility:refresh"
    alternative-text="再計算"
    title="再計算">
</lightning-button-icon>
```

### 8. ハードコードされた文言・値

```javascript
// 検出パターン
this.message = 'スコアの計算に失敗しました';   // ← 文言がコードに直書き
if (category === 'Hot') { ... }               // ← マジック文字列
```

**問題点**:
表示文言をコードに直書きすると、多言語対応や文言変更が大変です。
カテゴリ名などのマジック文字列も、変更時に修正漏れを起こします。

**改善案**:
- 表示文言はカスタムラベル（`@salesforce/label`）を使う
- 定数は 1 箇所にまとめる
```javascript
import errorMessage from '@salesforce/label/c.Score_Calc_Error';

this.message = errorMessage;
```

> **研修での補足**: カスタムラベルは発展的な内容です。
> 最低限、「文言や定数がコードに散らばっていないか」を意識できれば十分です。

## 出力フォーマット

```markdown
### [問題 N] @wire のエラーハンドリング欠如

**場所**: `force-app/main/default/lwc/leadScoreCard/leadScoreCard.js` 行 15-20

**現在のコード**:
```javascript
@wire(getScoreBreakdown, { leadId: '$recordId' })
wiredScore({ data }) {
    if (data) { this.score = data; }
}
```

**問題**:
error を処理していないため、Apex 側で例外が起きても画面に何も表示されません。

**改善案**:
```javascript
@wire(getScoreBreakdown, { leadId: '$recordId' })
wiredScore({ data, error }) {
    if (data) {
        this.score = data;
        this.error = undefined;
    } else if (error) {
        this.error = error;
        this.score = undefined;
    }
}
```

**優先度**: 高
```

## サマリー出力

```markdown
## LWC レビュー サマリー

- 検出された問題: X 件
  - 高優先度（エラー処理・セキュリティ）: X 件
  - 中優先度（ライフサイクル・LDS・パフォーマンス）: X 件
  - 低優先度（アクセシビリティ・ハードコード）: X 件

### 推奨される対応順序
1. @wire / imperative 呼び出しのエラーハンドリング（最優先）
2. innerHTML 等のセキュリティ問題
3. ライフサイクルフックの誤用・LDS 活用
4. パフォーマンス・アクセシビリティの改善
```

## 優先度の指針

- **高**: エラーハンドリング欠如、セキュリティ（innerHTML/ハードコード ID）
  → 実害（画面が壊れる・脆弱性）につながる
- **中**: ライフサイクル誤用、LDS 未活用、パフォーマンス
  → 保守性・動作品質に影響
- **低**: アクセシビリティ、ハードコード文言、命名
  → 推奨事項（ただしアクセシビリティは公開画面では重要度が上がる）
## 注意事項

- LWC は「画面」なので、エラーが起きたときに **ユーザーに何が伝わるか** を最優先で見る
- 受講者が書くコンポーネントは基本的なものが多いため、Shadow DOM の詳細や
  Lightning Message Service、Jest テストなど高度な観点は必須にしない
- 命名規則は review-naming と重複するため、LWC 固有の点（コンポーネント名の
  camelCase / kebab-case）以外は深追いしない
- 受講者の学習を促すため、「なぜそうすべきか」を必ず説明する
- 改善案は、このプロジェクトの既存コンポーネント（leadScoreCard / leadInterestRadar）
  のスタイルに沿った形で示す
