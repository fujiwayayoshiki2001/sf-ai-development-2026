# シードデータ (Phase 8)

研修向けのベースデータを投入するスクリプト群。スコアはトリガーが自動計算するため、
データを投入するだけで属性・行動・興味スコアとカテゴリが反映される。

## 構成

| ファイル | 役割 |
|---|---|
| `seed.apex` | シード投入本体（冪等な Anonymous Apex） |
| `verify.apex` | 投入結果の検証（件数・カテゴリ分散・トピック分散） |
| `load-data.sh` | 投入 → 検証 を一括実行するランナー |

## 採用方式: Anonymous Apex

JSON tree import ではなく Anonymous Apex を採用した理由:

1. **CampaignMemberStatus の追加が必要** — 当組織の既定ステータスは日本語（送信/レスポンスあり）で、
   行動スコアの設定キー（`Webinar_Attended` など）と一致しない。英語ステータスを
   キャンペーンごとに追加してから member を作る必要がある。
2. **カテゴリ分散の精密制御** — 属性・行動・興味を組み合わせて Hot/Warm/Cold/Low に
   意図的に分散させる。
3. **冪等な再投入** — 研修中に何度でも作り直せるよう、先頭で既存シードを削除する。

## 実行（追加の手動操作は不要）

```bash
# デフォルト組織 'training' に投入
./data/load-data.sh

# 組織を指定する場合
./data/load-data.sh my-scratch
```

## 投入されるデータ

- **リード 50件**: 日本語の氏名・会社名、メールは `seed00@example.com`〜`seed49@example.com`。
  カテゴリ分散: Hot 12 / Warm 18 / Cold 14 / Low 6。
- **キャンペーン 6件**: Webinar×2 / Trade Show / Email / White Paper / Demo Request。
  各キャンペーンに英語 CampaignMemberStatus（Registered/Attended/Visited/Sent/Responded/
  Downloaded/Submitted）を追加。
- **CampaignMember 約80件**: すべて投入日付。
- **Lead_Interest__c 約80件**: 10トピックを均等分散、レベル 30〜100。

### カテゴリ設計（属性 + 行動 + 興味 = 合計）

| グループ | 件数 | 属性 | 行動 | 興味 | 合計 |
|---|---|---|---|---|---|
| Hot  | 12 | 85 | 80 (Demo50 + Webinar30) | 80 (上限) | 245 |
| Warm | 18 | 60 | 30 (展示会25 + メール5) | 〜80 | 〜170 |
| Cold | 14 | 50 | 25 または 0 | 0 または 30〜45 | 75〜95 |
| Low  |  6 | 25 | 10 または 0 | 0 | 25〜35 |

## タグ（冪等性のマーカー）

| データ | マーカー |
|---|---|
| Lead | `Description = 'SEED_DATA_PHASE8'` |
| Lead_Interest__c | `Source__c = 'SEED_DATA_PHASE8'` |
| Campaign | `Name LIKE 'Seed:%'` |

`seed.apex` 先頭でこれらを削除してから再生成するため、再実行で重複しない。
