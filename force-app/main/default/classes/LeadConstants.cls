/**
 * プロジェクト全体で使用する定数を集約するクラス。
 *
 * ハードコードを避けるため、閾値・カテゴリ値・スコア上限などはすべて
 * このクラスの static final 定数として一元管理する。
 * SOQL/DML を持たない純粋な定数クラスのため sharing 指定は不要。
 */
public class LeadConstants {

    // ===== カテゴリ閾値 =====
    public static final Integer HOT_THRESHOLD = 180;
    public static final Integer WARM_THRESHOLD = 100;
    public static final Integer COLD_THRESHOLD = 50;

    // ===== カテゴリ値 =====
    public static final String CATEGORY_HOT = 'Hot';
    public static final String CATEGORY_WARM = 'Warm';
    public static final String CATEGORY_COLD = 'Cold';
    public static final String CATEGORY_LOW = 'Low';

    // ===== スコア上限 =====
    public static final Integer ATTRIBUTE_MAX_SCORE = 100;
    public static final Integer BEHAVIOR_MAX_SCORE = 120;
    public static final Integer INTEREST_MAX_SCORE = 80;
    public static final Integer TOTAL_MAX_SCORE = 300;

    // ===== 時間減衰 =====
    public static final Decimal DECAY_FACTOR = 0.95;

    // ===== ステータス更新（陳腐化判定）=====
    public static final Integer STALE_DAYS = 30;
    public static final String STATUS_STALE = 'Stale';

    // ===== スコアタイプ =====
    public static final String SCORE_TYPE_ATTRIBUTE = 'Attribute';
    public static final String SCORE_TYPE_BEHAVIOR = 'Behavior';
    public static final String SCORE_TYPE_INTEREST = 'Interest';

    // ===== 業界 =====
    public static final String INDUSTRY_TECHNOLOGY = 'Technology';
    public static final String INDUSTRY_MANUFACTURING = 'Manufacturing';
    public static final String INDUSTRY_FINANCIAL = 'Financial Services';

    // ===== リードソース =====
    public static final String SOURCE_WEB = 'Web';
    public static final String SOURCE_WEBINAR = 'Webinar';
    public static final String SOURCE_REFERRAL = 'Referral';
}
