/**
 * Lead オブジェクトのトリガー。
 * ロジックは持たず、LeadTriggerHandler に委譲する薄いトリガー。
 * bypassTrigger が立っている場合は早期 return して再帰を防止する。
 */
trigger LeadTrigger on Lead (before insert, before update, after insert, after update) {
    if (LeadTriggerHandler.bypassTrigger) {
        return;
    }

    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            LeadTriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            LeadTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            LeadTriggerHandler.afterInsert(Trigger.new, Trigger.newMap);
        } else if (Trigger.isUpdate) {
            LeadTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap, Trigger.newMap);
        }
    }
}
