// ===== 状态管理 =====
let state = {
  targets: [],
  selectedIds: new Set(),
  isWiping: false,
  isScanning: false,
};

// ===== DOM 引用 =====
const $ = id => document.getElementById(id);
const targetList = $('targetList');
const targetCount = $('targetCount');
const emptyState = $('emptyState');
const listState = $('listState');
const wipeBtn = $('wipeBtn');
const mainPanel = $('mainPanel');

// ===== Tauri 命令（通过 __TAURI_INTERNALS__）=====
async function invoke(cmd, args = {}) {
  if (!window.__TAURI_INTERNALS__?.invoke) {
    console.warn('Tauri IPC 不可用');
    return null;
  }
  try {
    return await window.__TAURI_INTERNALS__.invoke(cmd, args);
  } catch (e) {
    console.warn('Tauri IPC 错误:', e);
    return null;
  }
}

// ===== 渲染目标列表 =====
function render() {
  const enabled = state.targets.filter(t => t.enabled).length;
  targetCount.textContent = `${enabled}/${state.targets.length}`;

  const hasData = state.targets.length > 0;
  emptyState.style.display = hasData ? 'none' : 'flex';
  listState.style.display = hasData ? 'flex' : 'none';

  if (!hasData) return;

  targetList.innerHTML = state.targets.map(t => `
    <div class="target-item ${state.selectedIds.has(t.id) ? 'selected' : ''}"
         data-id="${t.id}" onclick="toggleSelect('${t.id}')">
      <span class="target-dot ${t.enabled ? 'on' : 'off'}"></span>
      <div class="target-info">
        <div class="target-name">${esc(t.name)}</div>
        <div class="target-path">${esc(t.file_path)}</div>
      </div>
    </div>
  `).join('');

  updateWipeBtn();
  updateRightPanel();
}

function esc(s) { return s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c]); }

// ===== 选择 =====
function toggleSelect(id) {
  if (state.selectedIds.has(id)) {
    state.selectedIds.delete(id);
  } else {
    state.selectedIds.add(id);
  }
  render();
}

function isSelected(id) { return state.selectedIds.has(id); }

// ===== 清除按钮 =====
function updateWipeBtn() {
  const n = state.selectedIds.size;
  wipeBtn.textContent = `🗑 清除所选 (${n})`;
  wipeBtn.disabled = n === 0 || state.isWiping;
  wipeBtn.style.background = (n === 0 || state.isWiping) ? '#c7c7cc' : '#ff3b30';
}

// ===== 右侧面板 =====
function updateRightPanel() {
  const sel = state.selectedIds;
  if (state.isScanning) { showView('scanAnimation'); return; }
  if (sel.size === 0) { showView('rightEmpty'); return; }
  if (sel.size === 1) {
    const t = state.targets.find(x => x.id === [...sel][0]);
    if (t) { showDetail(t); return; }
  }
  // 多选
  showMultiSelect();
}

function showView(id) {
  ['rightEmpty','scanAnimation','multiSelectInfo','detailView','resultsView'].forEach(v =>
    $(v).style.display = v === id ? 'flex' : 'none');
}

// ===== 多选 =====
function showMultiSelect() {
  showView('multiSelectInfo');
  $('selectedCount').textContent = state.selectedIds.size;
  $('selectedList').innerHTML = [...state.selectedIds].map(id => {
    const t = state.targets.find(x => x.id === id);
    if (!t) return '';
    return `<div class="selected-item">
      <span class="target-dot ${t.enabled ? 'on' : 'off'}"></span>
      <span>${esc(t.name)}</span>
      <span style="color:var(--secondary);font-size:11px">${esc(t.file_path)}</span>
    </div>`;
  }).join('');
}

// ===== 详情 =====
function showDetail(t) {
  showView('detailView');
  $('detailView').innerHTML = `
    <div class="detail-section">
      <h4>基本信息</h4>
      <div class="detail-row">
        <label>名称</label>
        <input type="text" value="${esc(t.name)}"
               onchange="updateTarget('${t.id}','name',this.value)">
      </div>
      <div class="detail-row">
        <label>文件路径</label>
        <span class="mono">${esc(t.file_path)}</span>
        <button class="btn-small" onclick="pickFile('${t.id}')">选择…</button>
      </div>
      <div class="detail-row">
        <label>实际路径</label>
        <span class="mono">${esc(t.expanded_path || t.file_path)}</span>
        <button class="btn-link" onclick="revealFinder('${esc(t.file_path)}')">在访达中显示</button>
      </div>
      <div class="detail-row">
        <label>启用</label>
        <input type="checkbox" ${t.enabled ? 'checked' : ''}
               onchange="updateTarget('${t.id}','enabled',this.checked)">
      </div>
    </div>
    <div class="detail-section">
      <h4>自定义匹配模式</h4>
      <div class="custom-patterns-area">
        <textarea onchange="updateTarget('${t.id}','customPatterns',this.value)">${esc(t.custom_patterns?.join('\n') || '')}</textarea>
      </div>
    </div>
    <div class="detail-section">
      <h4>预扫描</h4>
      <button class="btn-small" onclick="scanFile('${t.id}')">扫描此文件</button>
    </div>
  `;
}

function updateTarget(id, field, value) {
  const t = state.targets.find(x => x.id === id);
  if (!t) return;
  if (field === 'customPatterns') {
    t.custom_patterns = value.split('\n').map(s => s.trim()).filter(s => s);
  } else if (field === 'enabled') {
    t.enabled = value;
  } else if (field === 'name') {
    t.name = value;
  }
  render();
}

// ===== 扫描 =====
async function startScan() {
  state.isScanning = true;
  render();
  $('scanStatus').textContent = '扫描 ~/ 目录下的配置文件…';

  const result = await invoke('cmd_scan');
  if (!result) return;

  let added = 0, skipped = 0;
  for (const f of result) {
    if (state.targets.some(t => t.file_path === f.path)) {
      skipped++;
    } else {
      state.targets.push({
        id: crypto.randomUUID(),
        name: f.name,
        file_path: f.path,
        enabled: true,
        custom_patterns: [],
      });
      added++;
    }
  }
  state.isScanning = false;
  // 自动选中所有新增目标
  if (added > 0) {
    state.selectedIds = new Set(state.targets.map(t => t.id));
  }
  render();

  showResults([{
    target_name: '自动扫描',
    status: 'success',
    message: `发现 ${result.length} 个文件，新增 ${added} 个，${skipped} 个已存在`,
  }]);
}

// ===== 清除 =====
async function confirmWipe() {
  if (state.selectedIds.size === 0) return;
  state.isWiping = true;
  updateWipeBtn();

  const targets = [...state.selectedIds].map(id => state.targets.find(t => t.id === id)).filter(Boolean);
  const results = await invoke('cmd_wipe', { targets });
  state.isWiping = false;

  if (!results) return;

  // 自动移除
  const autoRemove = $('autoRemove').checked;
  if (autoRemove) {
    for (const r of results) {
      if (r.status === 'success' && r.target_id) {
        state.targets = state.targets.filter(t => t.id !== r.target_id);
        state.selectedIds.delete(r.target_id);
      }
    }
  }

  render();
  showResults(results);

  // 结果摘要提示
  const success = results.filter(r => r.status === 'success').length;
  const failed = results.filter(r => r.status === 'failed').length;
  const skipped = results.filter(r => r.status === 'skipped').length;
  let summary = '';
  if (success > 0) summary += `✅ 成功清除 ${success} 个文件\n`;
  if (failed > 0) summary += `❌ ${failed} 个文件清除失败\n`;
  if (skipped > 0) summary += `⏭️ ${skipped} 个已跳过\n`;
  if (summary) invoke('cmd_alert', { message: summary.trim() });
}

// ===== 显示结果 =====
function showResults(results) {
  showView('resultsView');
  let html = '<h4 style="margin-bottom:12px">清除结果</h4>';
  let success = 0;
  for (const r of results) {
    const icon = r.status === 'success' ? '✅' : r.status === 'skipped' ? '⏭️' : '❌';
    if (r.status === 'success') success++;
    html += `<div class="result-item">
      <span class="icon">${icon}</span>
      <div>
        <div>${esc(r.target_name)}</div>
        <div class="result-msg">${esc(r.message)}</div>
      </div>
    </div>`;
  }
  html += `<div style="margin-top:12px;font-size:12px;color:var(--secondary)">
    成功: ${success} / 总计: ${results.length}
    <button class="btn-link" onclick="showView('rightEmpty')" style="margin-left:12px">清除结果</button>
  </div>`;
  $('resultsView').innerHTML = html;
}

// ===== 文件选择器 =====
async function pickFile(id) {
  const t = state.targets.find(x => x.id === id);
  if (!t) return;
  const parent = t.file_path.split('/').slice(0, -1).join('/') || undefined;
  const path = await invoke('cmd_pick_file', { defaultDir: parent });
  if (path) {
    t.file_path = path;
    t.name = path.split('/').slice(-2).join('/');
    render();
  }
}

function revealFinder(path) {
  invoke('cmd_reveal', { path });
}

async function scanFile(id) {
  const t = state.targets.find(x => x.id === id);
  if (!t) return;
  const results = await invoke('cmd_scan_file', { path: t.file_path, customPatterns: t.custom_patterns });
  if (!results) return;
  const msg = results.length
    ? `发现以下匹配项：\n${results.join('\n')}`
    : '未发现 API Key。';
  invoke('cmd_alert', { message: msg });
}

async function addCustom() {
  const path = await invoke('cmd_pick_file', { defaultDir: '~' });
  if (path) {
    const name = path.split('/').slice(-2).join('/');
    state.targets.push({
      id: crypto.randomUUID(),
      name: name || path,
      file_path: path,
      enabled: true,
      custom_patterns: [],
    });
    state.selectedIds = new Set([state.targets[state.targets.length - 1].id]);
    render();
  }
}

// ===== 扫描动画驱动 =====
let animAngle = 0;
let animTimer = null;
function startScanAnimation() {
  if (animTimer) return;
  animAngle = 0;
  const mag = $('magnifier');
  if (!mag) return;
  animTimer = setInterval(() => {
    animAngle += 0.063;
    if (animAngle > Math.PI * 2) animAngle -= Math.PI * 2;
    const x = Math.cos(animAngle) * 44;
    const y = Math.sin(animAngle) * 22;
    mag.style.transform = `translate(${x}px, ${y}px)`;
  }, 20);
}
function stopScanAnimation() {
  if (animTimer) { clearInterval(animTimer); animTimer = null; }
}

// 重写 startScan 以包含动画
const originalStartScan = startScan;
startScan = async function() {
  state.isScanning = true;
  render();
  startScanAnimation();
  $('scanStatus').textContent = '扫描 ~/ 目录下的配置文件…';
  await originalStartScan();
  stopScanAnimation();
};

// ===== 键盘快捷键 =====
document.addEventListener('keydown', e => {
  if (e.metaKey && e.key === 'a') {
    e.preventDefault();
    if (state.targets.length > 0) {
      state.selectedIds = new Set(state.targets.map(t => t.id));
      render();
    }
  }
  if (e.key === 'Delete' && state.selectedIds.size > 0) {
    state.targets = state.targets.filter(t => !state.selectedIds.has(t.id));
    state.selectedIds.clear();
    render();
  }
});

// ===== 初始化 =====
render();
