/**
 * Lead_Interest__c のトリガー。
 * 興味レコードの変更に応じて、紐づく Lead のスコアを再計算する。
 * Lead__c は任意 Lookup のため、null のレコードは対象外とする。
 */
trigger LeadInterestTrigger on Lead_Interest__c (after insert, after update, after delete, after undelete) {
    Set<Id> leadIds = new Set<Id>();

    if (Trigger.isDelete) {
        for (Lead_Interest__c interest : Trigger.old) {
            if (interest.Lead__c != null) {
                leadIds.add(interest.Lead__c);
            }
        }
    } else {
        // insert / update / undelete
        for (Lead_Interest__c interest : Trigger.new) {
            if (interest.Lead__c != null) {
                leadIds.add(interest.Lead__c);
            }
        }
        // update では旧親（付け替え元）も再計算対象に含める
        if (Trigger.isUpdate) {
            for (Lead_Interest__c oldInterest : Trigger.old) {
                if (oldInterest.Lead__c != null) {
                    leadIds.add(oldInterest.Lead__c);
                }
            }
        }
    }

    if (!leadIds.isEmpty()) {
        LeadScoringService.calculateScores(leadIds);
    }
}
