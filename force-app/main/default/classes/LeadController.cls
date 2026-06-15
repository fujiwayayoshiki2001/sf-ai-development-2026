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

    /**
     * 指定リード群の最終アクション日を本日に更新する（状態変更を伴うため cacheable=false）。
     * LWC からの呼び出しやすさを優先し、引数は List<Id> で受けて内部で Set へ変換する。
     * サービス層が投げる標準例外を、ユーザー向けの AuraHandledException にラップする。
     * @param leadIds 対象 Lead Id のリスト
     */
    @AuraEnabled
    public static void updateLastActionDate(List<Id> leadIds) {
        try {
            Set<Id> idSet = (leadIds == null) ? null : new Set<Id>(leadIds);
            LeadService.updateLastActionDate(idSet);
        } catch (SecurityException e) {
            System.debug(LoggingLevel.ERROR, 'updateLastActionDate Security Error: ' + e.getMessage());
            throw new AuraHandledException('リードの更新権限がありません');
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'updateLastActionDate DML Error: ' + e.getMessage());
            throw new AuraHandledException('最終アクション日の更新に失敗しました');
        }
    }
}
