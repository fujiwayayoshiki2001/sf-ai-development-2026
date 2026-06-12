/**
 * Lead のバリデーションを担うクラス。
 *
 * LeadTriggerHandler の beforeInsert / beforeUpdate から呼ばれ、必須項目・メール形式を
 * チェックする。エラーは例外ではなく addError() で該当項目に設定し、1件の不正で
 * 他のリードを巻き込まない（Salesforce のベストプラクティス）。
 * 会社名による重複は警告レベルの参照用メソッドとして提供する。
 *
 * SOQL を含むため with sharing を宣言する。
 *
 * 主なメソッド:
 *  - validate(List<Lead>)               : バルク版メイン。各リードを検証
 *  - validateRequiredFields(Lead)       : 必須項目（LastName / Company）チェック
 *  - validateEmail(Lead)                : メール形式チェック（空はスキップ）
 *  - findDuplicatesByCompany(Set<String>): 会社名重複の参照（Map で返す）
 */
public with sharing class LeadValidator {

    // 標準的なメールアドレス形式の正規表現
    private static final String EMAIL_PATTERN = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';

    /**
     * 複数 Lead をまとめて検証する。
     * @param leads 検証対象の Lead リスト
     */
    public static void validate(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        for (Lead lead : leads) {
            validateRequiredFields(lead);
            validateEmail(lead);
        }
    }

    /**
     * 必須項目（LastName / Company）が空でないかを検証する。
     * 違反時は該当項目に addError() を設定する。
     * @param lead 検証対象の Lead
     */
    public static void validateRequiredFields(Lead lead) {
        if (lead == null) {
            return;
        }
        if (String.isBlank(lead.LastName)) {
            lead.LastName.addError('姓は必須項目です');
        }
        if (String.isBlank(lead.Company)) {
            lead.Company.addError('会社名は必須項目です');
        }
    }

    /**
     * メールアドレスの形式を検証する。空（null/blank）の場合は検証をスキップする。
     * 形式違反時は Email 項目に addError() を設定する。
     * @param lead 検証対象の Lead
     */
    public static void validateEmail(Lead lead) {
        if (lead == null || String.isBlank(lead.Email)) {
            return;
        }
        if (!Pattern.matches(EMAIL_PATTERN, lead.Email)) {
            lead.Email.addError('メールアドレスの形式が正しくありません');
        }
    }

    /**
     * 会社名で既存リードを検索し、重複候補を Map で返す（警告レベルの参照用）。
     * @param companyNames 検索対象の会社名の集合
     * @return 会社名 → 一致した既存 Lead リスト の Map
     */
    public static Map<String, List<Lead>> findDuplicatesByCompany(Set<String> companyNames) {
        Map<String, List<Lead>> result = new Map<String, List<Lead>>();
        if (companyNames == null || companyNames.isEmpty()) {
            return result;
        }

        for (Lead lead : [
            SELECT Id, Name, Company
            FROM Lead
            WHERE Company IN :companyNames
            WITH SECURITY_ENFORCED
        ]) {
            if (!result.containsKey(lead.Company)) {
                result.put(lead.Company, new List<Lead>());
            }
            result.get(lead.Company).add(lead);
        }

        return result;
    }
}
