import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import FIRSTNAME from '@salesforce/schema/Lead.FirstName';
import LASTNAME from '@salesforce/schema/Lead.LastName';
import COMPANY from '@salesforce/schema/Lead.Company';
import TITLE from '@salesforce/schema/Lead.Title';
import INDUSTRY from '@salesforce/schema/Lead.Industry';
import EMAIL from '@salesforce/schema/Lead.Email';
import PHONE from '@salesforce/schema/Lead.Phone';
import STATUS from '@salesforce/schema/Lead.Status';
import LEADSOURCE from '@salesforce/schema/Lead.LeadSource';
import EMPLOYEES from '@salesforce/schema/Lead.NumberOfEmployees';

// 表示・編集する主要項目（スコア系の自動計算項目は leadScoreCard 側に委ねる）
const FIELDS = [
    FIRSTNAME,
    LASTNAME,
    COMPANY,
    TITLE,
    INDUSTRY,
    EMAIL,
    PHONE,
    STATUS,
    LEADSOURCE,
    EMPLOYEES
];

/**
 * リード詳細コンポーネント。
 * lightning-record-form（view モード）で主要項目を表示し、インライン編集・保存を行う。
 * FLS・必須チェック・保存エラーは record-form が標準処理する。
 * Lead レコードページのほか、カスタムタブ等に配置可能（その場合は recordId 未設定で案内を表示）。
 */
export default class LeadDetail extends LightningElement {
    @api recordId;

    objectApiName = LEAD_OBJECT.objectApiName;
    fields = FIELDS;

    get hasRecord() {
        return !!this.recordId;
    }

    handleSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: '保存しました',
                message: 'リード情報を更新しました',
                variant: 'success'
            })
        );
    }

    handleError() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'エラー',
                message: '保存に失敗しました。入力内容をご確認ください。',
                variant: 'error'
            })
        );
    }
}
