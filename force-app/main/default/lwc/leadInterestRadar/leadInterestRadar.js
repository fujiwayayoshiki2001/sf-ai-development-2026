import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chartjs from '@salesforce/resourceUrl/chartjs';
import getInterests from '@salesforce/apex/LeadController.getInterests';

// レーダーチャートの軸（10トピック。Lead_Interest__c.Interest_Topic__c の選択肢と一致）
const TOPIC_AXES = [
    'データ統合',
    '業務効率化',
    'セキュリティ強化',
    'コスト削減',
    'DX 推進',
    '既存システム置き換え',
    'クラウド移行',
    '自動化',
    'AI 活用',
    'ガバナンス強化'
];
const LEVEL_MAX = 100; // Interest_Level__c の最大値

const CHART_FILL = 'rgba(21, 137, 238, 0.2)';
const CHART_LINE = 'rgba(21, 137, 238, 1)';

/**
 * リードの興味（Lead_Interest__c）を10トピックの軸でレーダー表示する。
 * Chart.js（Static Resource）を loadScript で読み込み、getInterests のデータで描画する。
 * 興味が無い場合は Empty State を表示する。Lead レコードページ（右カラム）への配置を想定。
 */
export default class LeadInterestRadar extends LightningElement {
    @api recordId;

    interests;
    error;
    chartjsLoaded = false;
    chart;
    isLoading = true;

    @wire(getInterests, { leadId: '$recordId' })
    wiredInterests({ error, data }) {
        if (data) {
            this.interests = data;
            this.error = undefined;
            this.isLoading = false;
            this.renderChart();
        } else if (error) {
            this.error = error;
            this.interests = undefined;
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'エラー',
                    message: '興味情報の取得に失敗しました',
                    variant: 'error'
                })
            );
        }
    }

    get hasData() {
        return this.interests && this.interests.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && !this.hasData;
    }

    get showChart() {
        return !this.isLoading && !this.error && this.hasData;
    }

    renderedCallback() {
        if (this.chartjsLoaded) {
            return;
        }
        this.chartjsLoaded = true;
        loadScript(this, chartjs)
            .then(() => {
                this.renderChart();
            })
            .catch((err) => {
                this.error = err;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'エラー',
                        message: 'チャートライブラリの読み込みに失敗しました',
                        variant: 'error'
                    })
                );
            });
    }

    // スクリプトとデータが揃い、かつ canvas が存在するときだけ描画する
    renderChart() {
        if (!this.chartjsLoaded || !this.hasData) {
            return;
        }
        const canvas = this.template.querySelector('canvas.radar');
        if (!canvas) {
            return;
        }

        // 既存チャートがあれば破棄して再描画（recordId 切替・データ更新に対応）
        if (this.chart) {
            this.chart.destroy();
        }

        const ctx = canvas.getContext('2d');
        // eslint-disable-next-line no-undef
        this.chart = new window.Chart(ctx, {
            type: 'radar',
            data: {
                labels: TOPIC_AXES,
                datasets: [
                    {
                        label: '興味度',
                        data: this.buildAxisValues(),
                        backgroundColor: CHART_FILL,
                        borderColor: CHART_LINE,
                        pointBackgroundColor: CHART_LINE,
                        borderWidth: 2
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                legend: { display: false },
                scale: {
                    ticks: { beginAtZero: true, min: 0, max: LEVEL_MAX, stepSize: 20 }
                }
            }
        });
    }

    // トピックごとに最大の Interest_Level__c を軸値に採用（同一トピック複数時）
    buildAxisValues() {
        const byTopic = {};
        this.interests.forEach((row) => {
            const topic = row.Interest_Topic__c;
            const level = row.Interest_Level__c || 0;
            if (byTopic[topic] === undefined || level > byTopic[topic]) {
                byTopic[topic] = level;
            }
        });
        return TOPIC_AXES.map((topic) => byTopic[topic] || 0);
    }

    disconnectedCallback() {
        if (this.chart) {
            this.chart.destroy();
            this.chart = undefined;
        }
    }
}
