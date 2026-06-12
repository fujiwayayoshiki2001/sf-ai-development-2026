import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeadList from '@salesforce/apex/LeadController.getLeadList';
import searchLeads from '@salesforce/apex/LeadController.searchLeads';

const MAX_ROWS = 200;
const SEARCH_DELAY_MS = 300;

// カテゴリフィルタの選択肢（「すべて」は空文字 = 全件）
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
        sortable: true,
        initialWidth: 110
    },
    { label: 'カテゴリ', fieldName: 'Lead_Category__c', type: 'text', initialWidth: 120 }
];

/**
 * リード一覧コンポーネント。
 * - カテゴリ別フィルタ（@wire getLeadList、空 = 全件）
 * - 名前・会社名検索（imperative searchLeads）
 * - スコア列でのクライアントソート
 * - 行（名前）クリックで標準のリード詳細へ遷移
 * カスタムタブ等への配置を想定。
 */
export default class LeadList extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    categoryOptions = CATEGORY_OPTIONS;

    selectedCategory = '';
    @track categoryLeads = [];
    @track searchResults;
    searchKey = '';
    error;
    isSearching = false;

    sortedBy = 'Score__c';
    sortedDirection = 'desc';

    delayTimeout;

    // ===== カテゴリ別取得（@wire） =====
    @wire(getLeadList, { category: '$selectedCategory', limitSize: MAX_ROWS })
    wiredLeads({ error, data }) {
        if (data) {
            this.categoryLeads = this.sortData([...data]);
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.categoryLeads = [];
            this.showError('リストの取得に失敗しました');
        }
    }

    // 検索中は検索結果を、そうでなければカテゴリ別結果を表示
    get displayLeads() {
        return this.searchResults !== undefined ? this.searchResults : this.categoryLeads;
    }

    get hasLeads() {
        return this.displayLeads && this.displayLeads.length > 0;
    }

    get isLoading() {
        return this.isSearching;
    }

    get recordCount() {
        return this.displayLeads ? this.displayLeads.length : 0;
    }

    get isSearchMode() {
        return this.searchResults !== undefined;
    }

    // ===== イベントハンドラ =====
    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        // カテゴリ変更時は検索モードを解除
        this.clearSearch();
    }

    handleSearchInput(event) {
        const key = event.target.value;
        window.clearTimeout(this.delayTimeout);
        // 入力のたびに API を叩かないようデバウンス
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.delayTimeout = setTimeout(() => {
            this.runSearch(key);
        }, SEARCH_DELAY_MS);
    }

    runSearch(key) {
        this.searchKey = key;
        if (!key || key.trim() === '') {
            this.clearSearch();
            return;
        }
        this.isSearching = true;
        searchLeads({ searchTerm: key })
            .then((result) => {
                this.searchResults = this.sortData([...result]);
                this.error = undefined;
            })
            .catch((err) => {
                this.error = err;
                this.searchResults = [];
                this.showError('検索に失敗しました');
            })
            .finally(() => {
                this.isSearching = false;
            });
    }

    clearSearch() {
        this.searchKey = '';
        this.searchResults = undefined;
    }

    handleClearSearch() {
        this.clearSearch();
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });
        }
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        if (this.searchResults !== undefined) {
            this.searchResults = this.sortData([...this.searchResults]);
        } else {
            this.categoryLeads = this.sortData([...this.categoryLeads]);
        }
    }

    // ===== ユーティリティ =====
    sortData(rows) {
        const field = this.sortedBy;
        const factor = this.sortedDirection === 'asc' ? 1 : -1;
        return rows.sort((a, b) => {
            const aVal = a[field] ?? '';
            const bVal = b[field] ?? '';
            if (aVal === bVal) {
                return 0;
            }
            return aVal > bVal ? factor : -factor;
        });
    }

    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'エラー', message, variant: 'error' })
        );
    }
}
