/**
 * LeadValidator の単体テスト。
 *
 * 必須項目（LastName / Company）・メール形式のバリデーションと、
 * 会社名による重複検索を検証する。エラーは addError() で項目に設定されるため、
 * hasErrors() / getErrors() で確認する。
 *
 * 検証観点: 正常系 / 必須項目欠落 / メール形式不正 / 空メールのスキップ /
 *           重複検索 / null・空ガード / バルク(200件)。
 */
@isTest
private class LeadValidatorTest {

    /**
     * 正常なリードはエラーにならないことを検証する。
     */
    @isTest
    static void testValidLead() {
        Lead lead = new Lead(
            LastName = 'Yamada', Company = 'Acme', Email = 'taro@example.com'
        );
        Test.startTest();
        LeadValidator.validate(new List<Lead>{ lead });
        Test.stopTest();

        System.assert(!lead.hasErrors(), '正常なリードはエラーにならないはず');
    }

    /**
     * LastName が空の場合にエラーが設定されることを検証する。
     */
    @isTest
    static void testMissingLastName() {
        Lead lead = new Lead(Company = 'Acme');
        Test.startTest();
        LeadValidator.validateRequiredFields(lead);
        Test.stopTest();

        System.assert(lead.hasErrors(), 'LastName 欠落でエラーになるはず');
    }

    /**
     * Company が空の場合にエラーが設定されることを検証する。
     */
    @isTest
    static void testMissingCompany() {
        Lead lead = new Lead(LastName = 'Yamada');
        Test.startTest();
        LeadValidator.validateRequiredFields(lead);
        Test.stopTest();

        System.assert(lead.hasErrors(), 'Company 欠落でエラーになるはず');
    }

    /**
     * 不正なメール形式でエラーが設定されることを検証する。
     */
    @isTest
    static void testInvalidEmail() {
        Lead lead = new Lead(LastName = 'Yamada', Company = 'Acme', Email = 'not-an-email');
        Test.startTest();
        LeadValidator.validateEmail(lead);
        Test.stopTest();

        System.assert(lead.hasErrors(), '不正なメール形式でエラーになるはず');
    }

    /**
     * 正しいメール形式ではエラーにならないことを検証する。
     */
    @isTest
    static void testValidEmail() {
        Lead lead = new Lead(LastName = 'Yamada', Company = 'Acme', Email = 'a.b+c@sub.example.co.jp');
        Test.startTest();
        LeadValidator.validateEmail(lead);
        Test.stopTest();

        System.assert(!lead.hasErrors(), '正しいメール形式はエラーにならないはず');
    }

    /**
     * メールが空（null/blank）の場合は検証をスキップしエラーにならないことを検証する。
     */
    @isTest
    static void testBlankEmailSkipped() {
        Lead nullEmail = new Lead(LastName = 'Yamada', Company = 'Acme');
        Lead blankEmail = new Lead(LastName = 'Yamada', Company = 'Acme', Email = '');

        Test.startTest();
        LeadValidator.validateEmail(nullEmail);
        LeadValidator.validateEmail(blankEmail);
        Test.stopTest();

        System.assert(!nullEmail.hasErrors(), 'null メールはスキップされエラーにならないはず');
        System.assert(!blankEmail.hasErrors(), '空メールはスキップされエラーにならないはず');
    }

    /**
     * 会社名による重複検索が、同一会社名の既存リードを返すことを検証する。
     */
    @isTest
    static void testFindDuplicatesByCompany() {
        // 同一会社名のリードを2件作成（重複ルール回避のため LastName/メールは別々に）
        List<Lead> leads = new List<Lead>{
            new Lead(LastName = 'A', Company = 'Dup Corp', Email = 'a@example.com'),
            new Lead(LastName = 'B', Company = 'Dup Corp', Email = 'b@example.com')
        };
        insert leads;

        Test.startTest();
        Map<String, List<Lead>> result =
            LeadValidator.findDuplicatesByCompany(new Set<String>{ 'Dup Corp' });
        Test.stopTest();

        System.assert(result.containsKey('Dup Corp'), 'Dup Corp がキーに含まれるはず');
        System.assertEquals(2, result.get('Dup Corp').size(),
            '同一会社名の2件が返るはず');
    }

    /**
     * 重複検索の null / 空入力ガードを検証する。
     */
    @isTest
    static void testFindDuplicatesEmptyInput() {
        Test.startTest();
        System.assertEquals(0, LeadValidator.findDuplicatesByCompany(null).size(),
            'null 入力は空 Map のはず');
        System.assertEquals(0, LeadValidator.findDuplicatesByCompany(new Set<String>()).size(),
            '空集合は空 Map のはず');
        Test.stopTest();
    }

    /**
     * validate() の null / 空リストガードを検証する（例外なし）。
     */
    @isTest
    static void testValidateNullAndEmpty() {
        Test.startTest();
        LeadValidator.validate(null);
        LeadValidator.validate(new List<Lead>());
        LeadValidator.validateRequiredFields(null);
        LeadValidator.validateEmail(null);
        Test.stopTest();

        System.assert(true, 'ガードにより例外なく完了するはず');
    }

    /**
     * バルク（200件）で正常なリードがすべてエラーにならないことを検証する。
     */
    @isTest
    static void testValidateBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);

        Test.startTest();
        LeadValidator.validate(leads);
        Test.stopTest();

        for (Lead lead : leads) {
            System.assert(!lead.hasErrors(), '正常な200件はエラーにならないはず');
        }
    }
}
