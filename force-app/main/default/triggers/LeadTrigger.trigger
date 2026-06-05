/**
 * Lead オブジェクトのトリガー。
 * 登録時・更新時にスコア（Score__c）を自動で再計算する。
 * ロジックは LeadTriggerHandler に委譲する（ロジックレストリガー）。
 */
trigger LeadTrigger on Lead (before insert, before update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        LeadTriggerHandler.recalculateScores(Trigger.new);
    }
}