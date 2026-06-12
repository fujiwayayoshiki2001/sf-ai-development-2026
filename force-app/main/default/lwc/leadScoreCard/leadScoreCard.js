import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import SCORE_FIELD from '@salesforce/schema/Lead.Score__c';
import ATTRIBUTE_FIELD from '@salesforce/schema/Lead.Attribute_Score__c';
import BEHAVIOR_FIELD from '@salesforce/schema/Lead.Behavior_Score__c';
import INTEREST_FIELD from '@salesforce/schema/Lead.Interest_Score__c';
import CATEGORY_FIELD from '@salesforce/schema/Lead.Lead_Category__c';

// 各軸の最大値（Apex の LeadConstants と対応）。マジックナンバーを避け名前付き定数で保持。
const ATTRIBUTE_MAX = 100;
const BEHAVIOR_MAX = 120;
const INTEREST_MAX = 80;
const TOTAL_MAX = ATTRIBUTE_MAX + BEHAVIOR_MAX + INTEREST_MAX; // 300

const FIELDS = [SCORE_FIELD, ATTRIBUTE_FIELD, BEHAVIOR_FIELD, INTEREST_FIELD, CATEGORY_FIELD];

// カテゴリ → SLDS テーマクラス（色）。ハードコードした色値ではなく SLDS ユーティリティを使用。
const CATEGORY_THEME = {
    Hot: 'slds-theme_error',
    Warm: 'slds-theme_warning',
    Cold: 'slds-theme_info',
    Low: 'slds-theme_shade'
};

/**
 * リードの3軸スコア（属性/行動/興味）と最終スコア・カテゴリを表示するカード。
 * Lightning Data Service（getRecord）で Lead を取得するため、編集後は自動で再描画される。
 * Lead レコードページ（右カラム）への配置を想定。
 */
export default class LeadScoreCard extends LightningElement {
    @api recordId;

    lead;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ error, data }) {
        if (data) {
            this.lead = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.lead = undefined;
        }
    }

    get isLoading() {
        return !this.lead && !this.error;
    }

    get hasData() {
        return !!this.lead;
    }

    // ===== スコア値 =====
    get totalScore() {
        return getFieldValue(this.lead, SCORE_FIELD) ?? 0;
    }
    get attributeScore() {
        return getFieldValue(this.lead, ATTRIBUTE_FIELD) ?? 0;
    }
    get behaviorScore() {
        return getFieldValue(this.lead, BEHAVIOR_FIELD) ?? 0;
    }
    get interestScore() {
        return getFieldValue(this.lead, INTEREST_FIELD) ?? 0;
    }
    get category() {
        return getFieldValue(this.lead, CATEGORY_FIELD);
    }

    // ===== 最大値（テンプレート表示用） =====
    get totalMax() {
        return TOTAL_MAX;
    }
    get attributeMax() {
        return ATTRIBUTE_MAX;
    }
    get behaviorMax() {
        return BEHAVIOR_MAX;
    }
    get interestMax() {
        return INTEREST_MAX;
    }

    // ===== プログレスバー用パーセンテージ =====
    get attributePercent() {
        return this.toPercent(this.attributeScore, ATTRIBUTE_MAX);
    }
    get behaviorPercent() {
        return this.toPercent(this.behaviorScore, BEHAVIOR_MAX);
    }
    get interestPercent() {
        return this.toPercent(this.interestScore, INTEREST_MAX);
    }

    // ===== カテゴリバッジ =====
    get categoryClass() {
        const theme = CATEGORY_THEME[this.category] || 'slds-theme_shade';
        return `slds-badge slds-badge_lightest ${theme}`;
    }
    get categoryAriaLabel() {
        return this.category ? `リードカテゴリ: ${this.category}` : 'リードカテゴリ未設定';
    }
    get hasCategory() {
        return !!this.category;
    }

    toPercent(value, max) {
        if (!value || !max) {
            return 0;
        }
        // 上限を超える場合でも 100% で頭打ち
        return Math.min(Math.round((value / max) * 100), 100);
    }
}
