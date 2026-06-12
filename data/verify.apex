/**
 * Phase 8 シードデータ検証スクリプト（読み取りのみ）
 * 投入後の件数・スコア計算・カテゴリ分散を確認する。
 */
final String SEED_TAG = 'SEED_DATA_PHASE8';
final String SEED_EMAIL = 'seed%@example.com';

// 1) 件数
System.debug('VERIFY leadCount=' + [SELECT COUNT() FROM Lead WHERE Email LIKE :SEED_EMAIL]);
System.debug('VERIFY scoredCount=' + [SELECT COUNT() FROM Lead WHERE Email LIKE :SEED_EMAIL AND Score__c != null]);
System.debug('VERIFY campaignCount=' + [SELECT COUNT() FROM Campaign WHERE Name LIKE 'Seed:%']);
System.debug('VERIFY memberCount=' + [SELECT COUNT() FROM CampaignMember WHERE Campaign.Name LIKE 'Seed:%']);
System.debug('VERIFY interestCount=' + [SELECT COUNT() FROM Lead_Interest__c WHERE Source__c = :SEED_TAG]);

// 2) カテゴリ分散
for (AggregateResult ar : [
    SELECT Lead_Category__c cat, COUNT(Id) c
    FROM Lead WHERE Email LIKE :SEED_EMAIL
    GROUP BY Lead_Category__c
    ORDER BY COUNT(Id) DESC
]) {
    System.debug('VERIFY category ' + ar.get('cat') + ' = ' + ar.get('c'));
}

// 3) 興味トピックの分散
for (AggregateResult ar : [
    SELECT Interest_Topic__c topic, COUNT(Id) c
    FROM Lead_Interest__c WHERE Source__c = :SEED_TAG
    GROUP BY Interest_Topic__c
    ORDER BY COUNT(Id) DESC
]) {
    System.debug('VERIFY topic ' + ar.get('topic') + ' = ' + ar.get('c'));
}

// 4) スコア降順トップ5（目視確認用）
for (Lead l : [
    SELECT Name, Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c, Lead_Category__c
    FROM Lead WHERE Email LIKE :SEED_EMAIL
    ORDER BY Score__c DESC LIMIT 5
]) {
    System.debug('VERIFY top ' + l.Name + ' total=' + l.Score__c
        + ' (属性' + l.Attribute_Score__c + '/行動' + l.Behavior_Score__c
        + '/興味' + l.Interest_Score__c + ') ' + l.Lead_Category__c);
}
