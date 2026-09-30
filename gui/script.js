// サーバーのベースURL
const BASE_URL = 'http://localhost:3000';

// DOM要素の取得
const urlInput = document.getElementById('urlInput');
const addButton = document.getElementById('addButton');
const refreshButton = document.getElementById('refreshButton');
const targetsContainer = document.getElementById('targetsContainer');
const resultsContainer = document.getElementById('resultsContainer');

// 監視対象のリスト
let targets = [];

// 監視結果のリスト
let results = [];

// 初期化処理
function init() {
    loadTargets();
    loadResults();
    
    // イベントリスナーの設定
    addButton.addEventListener('click', addTarget);
    refreshButton.addEventListener('click', checkAllTargets);
    
    // 5秒ごとに自動更新
    setInterval(loadTargets, 5000);
    setInterval(loadResults, 5000);
}

// 監視対象を読み込む
async function loadTargets() {
    try {
        const response = await fetch(`${BASE_URL}/api/targets`);
        if (response.ok) {
            const data = await response.json();
            targets = data.targets || [];
            renderTargets();
        }
    } catch (error) {
        console.error('監視対象の読み込みに失敗しました:', error);
    }
}

// 監視結果を読み込む
async function loadResults() {
    try {
        const response = await fetch(`${BASE_URL}/api/results`);
        if (response.ok) {
            const data = await response.json();
            results = data.results || [];
            renderResults();
        }
    } catch (error) {
        console.error('監視結果の読み込みに失敗しました:', error);
    }
}

// 監視対象を表示
function renderTargets() {
    targetsContainer.innerHTML = '<h2>監視対象一覧</h2>';
    
    if (targets.length === 0) {
        targetsContainer.innerHTML += '<p>監視対象がありません</p>';
        return;
    }
    
    const targetsList = document.createElement('div');
    targetsList.className = 'targets-list';
    
    targets.forEach(target => {
        const targetItem = document.createElement('div');
        targetItem.className = 'target-item';
        targetItem.innerHTML = `
            <div class="target-info">
                <div class="target-url">${escapeHtml(target.url)}</div>
                <div class="target-status">ID: ${target.id}</div>
            </div>
            <button class="delete-button" onclick="deleteTarget(${target.id})">削除</button>
        `;
        targetsList.appendChild(targetItem);
    });
    
    targetsContainer.appendChild(targetsList);
}

// 監視結果を表示
function renderResults() {
    resultsContainer.innerHTML = '<h2>監視結果</h2>';
    
    if (results.length === 0) {
        resultsContainer.innerHTML += '<p>監視結果がありません</p>';
        return;
    }
    
    const resultsList = document.createElement('div');
    resultsList.className = 'results-list';
    
    // 最新の結果から表示
    const sortedResults = [...results].sort((a, b) => {
        return new Date(b.timestamp) - new Date(a.timestamp);
    });
    
    sortedResults.forEach(result => {
        const resultItem = document.createElement('div');
        resultItem.className = 'result-item';
        
        // ステータスに応じたクラスを設定
        let statusClass = '';
        if (result.status === 'OK') {
            statusClass = 'status-ok';
        } else if (result.status === 'NG') {
            statusClass = 'status-ng';
        }
        
        resultItem.innerHTML = `
            <div class="result-header">
                <div class="result-url">${escapeHtml(result.url)}</div>
                <div class="result-timestamp">${formatDateTime(result.timestamp)}</div>
            </div>
            <div class="result-content">
                <div class="result-status ${statusClass}">${result.status}</div>
                ${result.http_status ? `<div class="result-http-status">HTTP ${result.http_status}</div>` : ''}
            </div>
        `;
        
        resultsList.appendChild(resultItem);
    });
    
    resultsContainer.appendChild(resultsList);
}

// 新しい監視対象を追加
async function addTarget() {
    const url = urlInput.value.trim();
    if (!url) {
        alert('URLを入力してください');
        return;
    }
    
    try {
        const response = await fetch(`${BASE_URL}/api/targets`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ url: url })
        });
        
        if (response.ok) {
            urlInput.value = '';
            loadTargets();
            loadResults();
        } else {
            const errorData = await response.json();
            alert('追加に失敗しました: ' + (errorData.error || '不明なエラー'));
        }
    } catch (error) {
        console.error('監視対象の追加に失敗しました:', error);
        alert('追加に失敗しました');
    }
}

// 監視対象を削除
async function deleteTarget(id) {
    if (!confirm('本当に削除しますか？')) {
        return;
    }
    
    try {
        const response = await fetch(`${BASE_URL}/api/targets/${id}`, {
            method: 'DELETE'
        });
        
        if (response.ok) {
            loadTargets();
            loadResults();
        } else {
            const errorData = await response.json();
            alert('削除に失敗しました: ' + (errorData.error || '不明なエラー'));
        }
    } catch (error) {
        console.error('監視対象の削除に失敗しました:', error);
        alert('削除に失敗しました');
    }
}

// 全ての監視対象をチェック
async function checkAllTargets() {
    try {
        const response = await fetch(`${BASE_URL}/api/check`, {
            method: 'POST'
        });
        
        if (response.ok) {
            loadResults();
        } else {
            const errorData = await response.json();
            alert('チェックに失敗しました: ' + (errorData.error || '不明なエラー'));
        }
    } catch (error) {
        console.error('監視チェックに失敗しました:', error);
        alert('チェックに失敗しました');
    }
}

// HTMLエスケープ
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// 日時フォーマット
function formatDateTime(dateTimeString) {
    const date = new Date(dateTimeString);
    return date.toLocaleString('ja-JP');
}

// 初期化
init();