// 画面と同じサーバーへ問い合わせる
const BASE_URL = '';

// DOM要素の取得
const urlInput = document.getElementById('urlInput');
const addButton = document.getElementById('addButton');
const refreshButton = document.getElementById('refreshButton');
const targetsContainer = document.getElementById('targetsContainer');
const resultsContainer = document.getElementById('resultsContainer');
const checkIntervalInput = document.getElementById('checkInterval');
const intervalUnitSelect = document.getElementById('intervalUnit');
const saveSettingsButton = document.getElementById('saveSettings');

// 監視対象のリスト
let targets = [];

// 監視結果のリスト
let results = [];

// 画面の再取得。チェック間隔とは別に、結果が出たらすぐ見えるようにする。
const displayRefreshMs = 5000;

// 設定
let settings = {
    checkIntervalSeconds: 300,
    checkIntervalUnit: 'seconds'
};

// 初期化処理
function init() {
    loadSettings();
    loadTargets();
    loadResults();
    setInterval(loadTargets, displayRefreshMs);
    setInterval(loadResults, displayRefreshMs);

    addButton.addEventListener('click', addTarget);
    refreshButton.addEventListener('click', checkAllTargets);
    saveSettingsButton.addEventListener('click', saveSettings);
}

// 設定を読み込む
async function loadSettings() {
    try {
        const response = await fetch(`${BASE_URL}/api/settings`);
        if (!response.ok) {
            updateSettingsUI();
            return;
        }
        const data = await response.json();
        settings.checkIntervalSeconds = data.checkIntervalSeconds !== undefined ? data.checkIntervalSeconds : 300;
        settings.checkIntervalUnit = data.checkIntervalUnit || 'seconds';
        updateSettingsUI();
    } catch (error) {
        console.error('設定の読み込みに失敗しました:', error);
        updateSettingsUI();
    }
}

// 設定を更新
function updateSettingsUI() {
    checkIntervalInput.value = settings.checkIntervalSeconds;
    
    // 単位を変換して表示
    let unit = settings.checkIntervalUnit || 'seconds';
    let value = settings.checkIntervalSeconds;
    
    if (unit === 'minutes' && value > 0) {
        // 最小間隔60秒をクリップして表示（1分未満なら1分に）
        checkIntervalInput.value = Math.max(1, value / 60);
        intervalUnitSelect.value = 'minutes';
    } else if (unit === 'hours' && value > 0) {
        // 最小間隔60秒をクリップして表示（1時間未満なら1時間に）
        checkIntervalInput.value = Math.max(1, value / 3600);
        intervalUnitSelect.value = 'hours';
    } else {
        checkIntervalInput.value = Math.max(1, value);
        intervalUnitSelect.value = 'seconds';
    }
}

// 設定を保存
async function saveSettings() {
    let input = parseInt(checkIntervalInput.value);
    const unit = intervalUnitSelect.value;
    
    // 範囲チェック（単位を考慮して秒換算）
    let secondsValue;
    if (unit === 'minutes') {
        secondsValue = input * 60;
    } else if (unit === 'hours') {
        secondsValue = input * 3600;
    } else {
        secondsValue = input;
    }
    
    // 秒換算後の範囲チェック
    if (isNaN(secondsValue)) {
        alert('有効な数値を入力してください');
        return;
    }
    if (secondsValue < 1) {
        alert('最小値は1秒です。1秒にクリップして保存します。');
        secondsValue = 1;
    }
    
    // 範囲チェック（上限）
    if (secondsValue > 86400) {
        alert('最大値は24時間（86400秒）です');
        return;
    }
    
    try {
        const response = await fetch(`${BASE_URL}/api/settings`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                checkIntervalSeconds: secondsValue,
                checkIntervalUnit: unit
            })
        });
        const data = await response.json();
        if (!response.ok) {
            alert('保存に失敗しました: ' + (data.error || '不明なエラー'));
            return;
        }
        settings.checkIntervalSeconds = data.checkIntervalSeconds;
        settings.checkIntervalUnit = data.checkIntervalUnit;
        updateSettingsUI();
        alert('確認間隔を ' + data.checkIntervalSeconds + ' 秒に保存しました。次のチェックから反映されます。');
    } catch (error) {
        console.error('設定の保存に失敗しました:', error);
        alert('保存に失敗しました');
    }
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
    
    // 最新の結果から10件だけ表示する。サーバー側の履歴はそのまま残す。
    const sortedResults = [...results].sort((a, b) => {
        return new Date(b.timestamp) - new Date(a.timestamp);
    }).slice(0, 10);
    
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