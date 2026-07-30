/**
 * 商談化データ シードデータ検証スクリプト（読み取りのみ）
 * カテゴリ別の Convert/Close 件数・商談化率・月別 Convert 数（Opportunity.CloseDate 基準）を確認する。
 */
final String SEED_EMAIL = 'seed_conv_%@example.com';
final String NAME_LIKE = '%SEED_CONVERTED%';

// 1) 総件数
System.debug('VERIFY leadCount=' + [SELECT COUNT() FROM Lead WHERE Email LIKE :SEED_EMAIL]);
System.debug('VERIFY convertedCount=' + [SELECT COUNT() FROM Lead WHERE Email LIKE :SEED_EMAIL AND IsConverted = true]);
System.debug('VERIFY closedNotConvertedCount=' + [SELECT COUNT() FROM Lead WHERE Email LIKE :SEED_EMAIL AND Status = 'Closed - Not Converted']);
System.debug('VERIFY opportunityCount=' + [SELECT COUNT() FROM Opportunity WHERE Name LIKE :NAME_LIKE]);

// 2) カテゴリ別の Convert / Close 件数・商談化率
Map<String, Integer> convertedByCategory = new Map<String, Integer>();
Map<String, Integer> closedByCategory = new Map<String, Integer>();

for (AggregateResult ar : [
    SELECT Lead_Category__c cat, IsConverted conv, COUNT(Id) c
    FROM Lead
    WHERE Email LIKE :SEED_EMAIL
    GROUP BY Lead_Category__c, IsConverted
]) {
    String category = (String) ar.get('cat');
    Boolean converted = (Boolean) ar.get('conv');
    Integer count = (Integer) ar.get('c');
    if (converted) {
        convertedByCategory.put(category, count);
    } else {
        closedByCategory.put(category, count);
    }
}

for (String category : new List<String>{ 'Hot', 'Warm', 'Cold', 'Low' }) {
    Integer converted = convertedByCategory.containsKey(category) ? convertedByCategory.get(category) : 0;
    Integer closed = closedByCategory.containsKey(category) ? closedByCategory.get(category) : 0;
    Integer total = converted + closed;
    Decimal rate = total > 0 ? (Decimal.valueOf(converted) * 100 / total).setScale(1) : 0;
    System.debug('VERIFY category=' + category + ' total=' + total
        + ' converted=' + converted + ' closed=' + closed + ' conversionRate=' + rate + '%');
}

// 3) 月別 Convert 数（Opportunity.CloseDate 基準）
for (AggregateResult ar : [
    SELECT CALENDAR_YEAR(CloseDate) y, CALENDAR_MONTH(CloseDate) m, COUNT(Id) c
    FROM Opportunity
    WHERE Name LIKE :NAME_LIKE
    GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)
    ORDER BY CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)
]) {
    System.debug('VERIFY month=' + ar.get('y') + '-' + String.valueOf(ar.get('m')).leftPad(2, '0')
        + ' convertedCount=' + ar.get('c'));
}

// 4) スコア降順トップ5（目視確認用）
for (Lead topLead : [
    SELECT Name, Score__c, Lead_Category__c, IsConverted, Status
    FROM Lead WHERE Email LIKE :SEED_EMAIL
    ORDER BY Score__c DESC LIMIT 5
]) {
    System.debug('VERIFY top ' + topLead.Name + ' score=' + topLead.Score__c
        + ' category=' + topLead.Lead_Category__c
        + ' converted=' + topLead.IsConverted + ' status=' + topLead.Status);
}
