import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchLeads from '@salesforce/apex/LeadController.searchLeads';

const CATEGORY_OPTIONS = [
    { label: 'すべて', value: '' },
    { label: 'Hot', value: 'Hot' },
    { label: 'Warm', value: 'Warm' },
    { label: 'Cold', value: 'Cold' },
    { label: 'Low', value: 'Low' }
];

const COLUMNS = [
    {
        label: '名前',
        fieldName: 'Name',
        type: 'button',
        typeAttributes: { label: { fieldName: 'Name' }, variant: 'base', name: 'view' }
    },
    { label: '会社', fieldName: 'Company', type: 'text' },
    {
        label: 'スコア',
        fieldName: 'Score__c',
        type: 'number',
        cellAttributes: { alignment: 'left' },
        initialWidth: 110
    },
    { label: 'カテゴリ', fieldName: 'Lead_Category__c', type: 'text', initialWidth: 120 }
];

/**
 * 高度な検索コンポーネント。
 * キーワード（名前・会社名）を imperative の LeadController.searchLeads で検索し、
 * カテゴリ・最小スコアでクライアント側の絞り込みを重ねる（複数条件検索）。
 * カスタムタブへの配置を想定。
 */
export default class LeadSearch extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    categoryOptions = CATEGORY_OPTIONS;

    keyword = '';
    category = '';
    minScore;

    @track results;
    isLoading = false;
    error;
    hasSearched = false;

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get resultCount() {
        return this.results ? this.results.length : 0;
    }

    get noResults() {
        return this.hasSearched && !this.isLoading && !this.hasResults;
    }

    handleKeywordChange(event) {
        this.keyword = event.target.value;
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleMinScoreChange(event) {
        const value = event.target.value;
        this.minScore = value === '' || value === null ? undefined : Number(value);
    }

    handleKeyup(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    handleSearch() {
        if (!this.keyword || this.keyword.trim() === '') {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '入力エラー',
                    message: '検索キーワード（名前・会社名）を入力してください',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isLoading = true;
        searchLeads({ searchTerm: this.keyword })
            .then((data) => {
                this.results = this.applyFilters(data);
                this.error = undefined;
            })
            .catch((err) => {
                this.error = err;
                this.results = [];
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'エラー',
                        message: '検索に失敗しました',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.hasSearched = true;
                this.isLoading = false;
            });
    }

    // カテゴリ・最小スコアでクライアント側の絞り込みを適用する
    applyFilters(rows) {
        return rows.filter((row) => {
            const categoryOk = !this.category || row.Lead_Category__c === this.category;
            const scoreOk =
                this.minScore === undefined ||
                (row.Score__c !== null &&
                    row.Score__c !== undefined &&
                    row.Score__c >= this.minScore);
            return categoryOk && scoreOk;
        });
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: event.detail.row.Id,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });
        }
    }
}
