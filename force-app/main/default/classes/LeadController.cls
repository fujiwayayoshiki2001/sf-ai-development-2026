/**
 * LWC からの呼び出し窓口となるコントローラ。
 *
 * @AuraEnabled メソッドを公開し、処理は LeadService / LeadScoringService に委譲する。
 * 例外は AuraHandledException でラップし、詳細はログに、ユーザーには分かりやすい
 * メッセージを返す。読み取り専用メソッドは cacheable=true、状態変更メソッドは cacheable=false。
 *
 * 主なメソッド:
 *  - getScoreBreakdown(Id)         : 3軸スコアの内訳
 *  - getInterests(Id)              : リードの興味レコード一覧
 *  - recalculateScore(Id)          : スコア再計算（状態変更）
 *
 * SOQL を含むため with sharing を宣言する。
 */
public with sharing class LeadController {

    /**
     * 指定リードの 3 軸スコアの内訳を返す。
     * @param leadId 対象 Lead Id
     * @return { attribute, behavior, interest, total } の Map
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getScoreBreakdown(Id leadId) {
        try {
            return LeadService.getScoreBreakdown(leadId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getScoreBreakdown Error: ' + e.getMessage());
            throw new AuraHandledException('スコアの取得に失敗しました');
        }
    }

    /**
     * 指定リードに紐づく興味レコードを取得する。
     * @param leadId 対象 Lead Id
     * @return Lead_Interest__c のリスト
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead_Interest__c> getInterests(Id leadId) {
        try {
            return LeadService.getInterests(leadId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getInterests Error: ' + e.getMessage());
            throw new AuraHandledException('興味情報の取得に失敗しました');
        }
    }

    /**
     * 指定リードのスコアを再計算する（状態変更を伴うため cacheable=false）。
     * @param leadId 対象 Lead Id
     */
    @AuraEnabled
    public static void recalculateScore(Id leadId) {
        try {
            if (leadId == null) {
                throw new AuraHandledException('リード ID が指定されていません');
            }
            LeadScoringService.calculateScores(new Set<Id>{ leadId });
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'recalculateScore Error: ' + e.getMessage());
            throw new AuraHandledException('スコアの再計算に失敗しました');
        }
    }
}
