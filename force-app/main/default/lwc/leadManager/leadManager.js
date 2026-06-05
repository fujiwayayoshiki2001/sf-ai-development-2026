import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeads from '@salesforce/apex/LeadController.getLeads';
import recalculateScores from '@salesforce/apex/LeadController.recalculateScores';

const COLUMNS = [
    { label: '氏名', fieldName: 'Name', type: 'text' },
    { label: '会社名', fieldName: 'Company', type: 'text' },
    { label: 'メール', fieldName: 'Email', type: 'email' },
    { label: 'ステータス', fieldName: 'Status', type: 'text' },
    { label: '評価', fieldName: 'Rating', type: 'text' },
    { label: 'スコア', fieldName: 'Score__c', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } }
];

export default class LeadManager extends LightningElement {
    columns = COLUMNS;

    @track statusFilter = '';
    @track highScoreOnly = false;
    @track selectedRowIds = [];

    leads = [];
    wiredLeadsResult;

    statusOptions = [
        { label: 'すべて', value: '' },
        { label: 'Open - Not Contacted', value: 'Open - Not Contacted' },
        { label: 'Working - Contacted', value: 'Working - Contacted' },
        { label: 'Closed - Converted', value: 'Closed - Converted' },
        { label: 'Closed - Not Converted', value: 'Closed - Not Converted' }
    ];

    @wire(getLeads, { statusFilter: '$statusFilter', highScoreOnly: '$highScoreOnly' })
    wiredLeads(result) {
        this.wiredLeadsResult = result;
        if (result.data) {
            this.leads = result.data;
        } else if (result.error) {
            this.showToast('エラー', this.reduceError(result.error), 'error');
        }
    }

    get recordCount() {
        return this.leads ? this.leads.length : 0;
    }

    get hasNoSelection() {
        return this.selectedRowIds.length === 0;
    }

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
    }

    handleHighScoreToggle(event) {
        this.highScoreOnly = event.target.checked;
    }

    handleRowSelection(event) {
        this.selectedRowIds = event.detail.selectedRows.map((row) => row.Id);
    }

    async handleRecalculate() {
        if (this.hasNoSelection) {
            this.showToast('情報', '再計算するリードを選択してください。', 'info');
            return;
        }
        try {
            await recalculateScores({ leadIds: this.selectedRowIds });
            await refreshApex(this.wiredLeadsResult);
            this.showToast('成功', 'スコアを再計算しました。', 'success');
        } catch (error) {
            this.showToast('エラー', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return '処理中にエラーが発生しました。';
    }
}