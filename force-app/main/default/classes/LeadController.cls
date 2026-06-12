/**
 * LWC からの呼び出し窓口となるコントローラ。
 *
 * @AuraEnabled メソッドを公開し、処理は LeadService / LeadScoringService に委譲する。
 * 例外は AuraHandledException でラップし、詳細はログに、ユーザーには分かりやすい
 * メッセージを返す。読み取り専用メソッドは cacheable=true、状態変更メソッドは cacheable=false。
 *
 * 主なメソッド:
 *  - getLeadList(String, Integer)  : カテゴリ別リード一覧
 *  - searchLeads(String)           : 名前・会社名検索
 *  - getScoreBreakdown(Id)         : 3軸スコアの内訳
 *  - getInterests(Id)              : リードの興味レコード一覧
 *  - recalculateScore(Id)          : スコア再計算（状態変更）
 *
 * SOQL を含むため with sharing を宣言する。
 */
public with sharing class LeadController {

    /**
     * リード一覧を取得する。カテゴリが空（「All」）の場合は全カテゴリをスコア降順で返す。
     * @param category  カテゴリ（Hot/Warm/Cold/Low）。空文字/null は全件（All）。
     * @param limitSize 取得上限
     * @return 該当リードのリスト
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead> getLeadList(String category, Integer limitSize) {
        try {
            if (String.isBlank(category)) {
                return LeadService.getAllLeads(limitSize);
            }
            return LeadService.getLeadsByCategory(category, limitSize);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getLeadList Error: ' + e.getMessage());
            throw new AuraHandledException('リストの取得に失敗しました');
        }
    }

    /**
     * 名前・会社名でリードを検索する。
     * @param searchTerm 検索文字列
     * @return 該当リードのリスト
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead> searchLeads(String searchTerm) {
        try {
            return LeadService.searchLeads(searchTerm, null);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'searchLeads Error: ' + e.getMessage());
            throw new AuraHandledException('検索に失敗しました');
        }
    }

    /**
     * 指定リードの 3 軸スコアの内訳を返す。
     * @param leadId 対象 Lead Id
     * @return { attribute, behavior, interest, total } の Map
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getScoreBreakdown(Id leadId) {
        try {
            if (leadId == null) {
                throw new AuraHandledException('リード ID が指定されていません');
            }

            List<Lead> leads = [
                SELECT Id, Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c
                FROM Lead
                WHERE Id = :leadId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (leads.isEmpty()) {
                throw new AuraHandledException('指定されたリードが見つかりません');
            }
            Lead lead = leads[0];

            return new Map<String, Decimal>{
                'attribute' => lead.Attribute_Score__c,
                'behavior'  => lead.Behavior_Score__c,
                'interest'  => lead.Interest_Score__c,
                'total'     => lead.Score__c
            };
        } catch (AuraHandledException e) {
            throw e;
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
            if (leadId == null) {
                throw new AuraHandledException('リード ID が指定されていません');
            }

            return [
                SELECT Id, Interest_Topic__c, Interest_Level__c, Detected_Date__c, Source__c, Notes__c
                FROM Lead_Interest__c
                WHERE Lead__c = :leadId
                WITH SECURITY_ENFORCED
                ORDER BY Interest_Level__c DESC
            ];
        } catch (AuraHandledException e) {
            throw e;
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
