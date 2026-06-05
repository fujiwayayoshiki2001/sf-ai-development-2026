/**
 * LeadTrigger のロジックを担うハンドラ。
 * トリガー本体はロジックを持たず、本クラスへ委譲する。
 *
 * before insert / before update のコンテキストで Score__c を再計算する。
 * before コンテキストのため追加の DML は不要（バルクセーフ）。
 */
public with sharing class LeadTriggerHandler {
    /**
     * リードのスコアを一括で再計算し、各レコードの Score__c に設定する。
     * SOQL/DML を行わず、メモリ上の値のみで計算するため大量件数でも安全。
     *
     * @param newLeads トリガーの Trigger.new（before コンテキスト）
     */
    public static void recalculateScores(List<Lead> newLeads) {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }
        for (Lead targetLead : newLeads) {
            targetLead.Score__c = LeadController.calculateScore(targetLead);
        }
    }
}