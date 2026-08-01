// ===== 状态管理 =====
let state = {
  targets: [],
  selectedIds: new Set(),
  viewedId: null,        // 当前查看的目标 id（单击设置）
  isWiping: false,
  isScanning: false,
  // 路径检查结果缓存：{ filePath: boolean }
  pathStatus: {},
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

// ===== 持久化 =====
async function saveTargets() {
  await invoke('cmd_save_targets', { targets: state.targets });
}

async function loadTargets() {
  const result = await invoke('cmd_load_targets');
  if (result && result.length > 0) {
    state.targets = result;
  }
  return result;
}

// ===== 路径检查 =====
async function checkPath(path) {
  if (state.pathStatus[path] !== undefined) {
    return state.pathStatus[path];
  }
  const exists = await invoke('cmd_check_path', { path });
  state.pathStatus[path] = exists ?? false;
  return state.pathStatus[path];
}

async function checkAllPaths() {
  const paths = state.targets.map(t => t.file_path);
  const tasks = paths.map(p => checkPath(p));
  await Promise.all(tasks);
}

function isPathFailed(t) {
  return t && !state.pathStatus[t.file_path];
}

// ===== 渲染目标列表 =====
function render() {
  const selected = state.selectedIds.size;
  targetCount.textContent = `${selected}/${state.targets.length}`;

  const hasData = state.targets.length > 0;
  emptyState.style.display = hasData ? 'none' : 'flex';
  listState.style.display = hasData ? 'flex' : 'none';

  if (!hasData) return;

  targetList.innerHTML = state.targets.map(t => {
    const failed = isPathFailed(t);
    const isViewed = state.viewedId === t.id;
    return `
    <div class="target-item ${state.selectedIds.has(t.id) ? 'selected' : ''} ${failed ? 'path-failed' : ''} ${isViewed ? 'viewed' : ''}"
         data-id="${t.id}">
      <span class="checkbox-custom ${state.selectedIds.has(t.id) ? 'checked' : ''}"
            onclick="event.stopPropagation(); toggleSelect('${t.id}')"></span>
      <div class="target-click" onclick="viewTarget('${t.id}')">
        ${failed ? '<span class="path-warning" title="路径失效">⚠️</span>' : ''}
        <div class="target-info">
          <div class="target-name">${esc(t.name)}${failed ? ' <span class="path-failed-label">（路径失效）</span>' : ''}</div>
          <div class="target-path ${failed ? 'path-failed-text' : ''}">${esc(t.file_path)}</div>
        </div>
        <span class="target-dot ${t.enabled ? 'on' : 'off'}"></span>
      </div>
    </div>
  `;
  }).join('');

  updateWipeBtn();
  updateRightPanel();
  // 更新全选按钮文字
  const btnSelectAll = document.getElementById('btnSelectAll');
  if (btnSelectAll) {
    const allSelected = state.targets.length > 0 && state.selectedIds.size === state.targets.length;
    btnSelectAll.textContent = allSelected ? '取消全选' : '全选';
  }
}

function esc(s) { return s.replace(/[&<>\"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'})[c]); }

// ===== 点击处理 =====

// 单击行 → 查看详情（不改变选中状态）
function viewTarget(id) {
  const t = state.targets.find(x => x.id === id);
  if (!t) return;

  // 如果路径失效，弹出提示
  if (isPathFailed(t)) {
    handleFailedPath(id, t);
    return;
  }

  state.viewedId = id;
  render();
}

// 复选框 → 切换选中
function toggleSelect(id) {
  const t = state.targets.find(x => x.id === id);
  if (!t) return;
  if (state.selectedIds.has(id)) {
    state.selectedIds.delete(id);
  } else {
    state.selectedIds.add(id);
  }
  render();
}

// 路径失效处理
async function handleFailedPath(id, t) {
  const ok = await invoke('cmd_confirm', { message: '路径失效：\n' + t.file_path + '\n\n确定要从列表中移除此文件吗？' });
  if (ok) {
    state.targets = state.targets.filter(x => x.id !== id);
    state.selectedIds.delete(id);
    if (state.viewedId === id) state.viewedId = null;
    delete state.pathStatus[t.file_path];
    render();
    await saveTargets();
  }
}

function isSelected(id) { return state.selectedIds.has(id); }

// ===== 清除按钮 =====
function updateWipeBtn() {
  const n = state.selectedIds.size;
  wipeBtn.textContent = `🗑 清除所选 (${n})`;
  wipeBtn.disabled = n === 0 || state.isWiping;
}

// ===== 右侧面板 =====
function updateRightPanel() {
  if (state.isScanning) { showView('scanAnimation'); return; }

  // 优先显示正在查看的项
  if (state.viewedId) {
    const t = state.targets.find(x => x.id === state.viewedId);
    if (t) { showDetail(t); return; }
  }

  // 多选摘要
  if (state.selectedIds.size > 0) {
    showMultiSelect();
    return;
  }

  // 空状态
  showView('rightEmpty');
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
      <span>${esc(t.name)}</span>
      <span style="color:var(--text-secondary);font-size:11px">${esc(t.file_path)}</span>
      <span class="target-dot ${t.enabled ? 'on' : 'off'}"></span>
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
      <div style="display:flex;align-items:center;gap:6px">
        <h4>自定义匹配模式</h4>
        <span class="pattern-help-tip" onclick="showPatternTips()" title="点击查看使用说明">ⓘ</span>
      </div>
      <div class="custom-patterns-area">
        <textarea onblur="updateTarget('${t.id}','customPatterns',this.value)" placeholder="每行一个匹配关键字，例如：sklearn / openai_api_key">${esc(t.custom_patterns?.join('\n') || '')}</textarea>
      </div>
      <!-- 使用说明弹窗 -->
      <div id="patternTips" class="pattern-tips" style="display:none">
        <div class="pattern-tips-header">
          <h5>ⓘ 自定义匹配模式使用说明</h5>
          <button class="pattern-tips-close" onclick="hidePatternTips()">✕</button>
        </div>
        <p><strong>🔍 匹配方式</strong></p>
        <ul class="pattern-tips-list">
          <li>每行输入一个关键字，支持多行</li>
          <li>只要某行<span class="tip-code">包含</span>关键字，就会匹配</li>
        </ul>
        <p><strong>🗑 清除行为</strong></p>
        <ul class="pattern-tips-list">
          <li>匹配到 <code>=</code> 或 <code>:</code> → 清除后面的值，保留 key 名</li>
          <li>与内置模式重复的关键字不会重复匹配</li>
        </ul>
        <p><strong>📝 示例</strong></p>
        <div class="pattern-tips-example">
          <div>sklearn</div>
          <div>openai_api_key</div>
          <div>ANTHROPIC_TOKEN</div>
        </div>
      </div>
    </div>
    <div class="detail-section">
      <h4>预扫描</h4>
      <button class="btn-small" onclick="scanFile('${t.id}')">扫描此文件</button>
    </div>
  `;
}

async function updateTarget(id, field, value) {
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
  await saveTargets();
}

// ===== 扫描 =====
const originalStartScan = async function() {
  render();
  $('scanStatus').textContent = '开始扫描…';

  // 监听进度事件
  let unlisten = null;
  try {
    unlisten = await window.__TAURI_INTERNALS__?.event?.listen('scan-progress', (event) => {
      $('scanStatus').textContent = event.payload;
    });
  } catch (e) {
    // 老版本 Tauri 可能不支持事件
  }

  const result = await invoke('cmd_scan');
  if (unlisten) unlisten();

  if (!result) { state.isScanning = false; render(); return; }

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
  // 检查路径（新增的路径需要更新 pathStatus）
  await checkAllPaths();
  render();
  // 保存
  await saveTargets();

  showResults([{
    target_name: '自动扫描',
    status: 'success',
    message: `发现 ${result.length} 个文件，新增 ${added} 个，${skipped} 个已存在`,
  }]);
};

async function startScan() {
  state.isScanning = true;
  render();
  startScanAnimation();
  $('scanStatus').textContent = '开始扫描…';
  await originalStartScan();
  stopScanAnimation();
  $('scanStatus').textContent = '扫描完成';
}

// ===== 清除 =====
async function confirmWipe() {
  if (state.selectedIds.size === 0) return;
  state.isWiping = true;
  updateWipeBtn();

  const targets = [...state.selectedIds].map(id => state.targets.find(t => t.id === id)).filter(Boolean);
  if (targets.length > 0) {
    invoke('cmd_alert', { message: '即将清除: ' + targets[0].file_path });
  }
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
    await saveTargets();
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
  html += `<div style="margin:12px 0 0;font-size:12px;color:var(--text-secondary)">
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
    // 更新路径状态
    state.pathStatus[path] = true;
    render();
    await saveTargets();
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
    state.pathStatus[path] = true;
    render();
    await saveTargets();
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

// ===== 键盘快捷键 =====
document.addEventListener('keydown', e => {
  if (e.metaKey && e.key === 'a') {
    e.preventDefault();
    selectAll();
  }
  if (e.key === 'Delete' && state.selectedIds.size > 0) {
    state.targets = state.targets.filter(t => !state.selectedIds.has(t.id));
    state.selectedIds.clear();
    render();
    saveTargets();
  }
});

// ===== 列表操作 =====
function selectAll() {
  if (state.targets.length === 0) return;
  const allSelected = state.selectedIds.size === state.targets.length;
  if (allSelected) {
    state.selectedIds.clear();
  } else {
    // 全选时排除路径失效的
    state.selectedIds = new Set(
      state.targets.filter(t => !isPathFailed(t)).map(t => t.id)
    );
  }
  render();
}

async function clearList() {
  if (state.selectedIds.size === 0) return;
  const n = state.selectedIds.size;
  const ok = await invoke('cmd_confirm', { message: `确定要从列表中移除选中的 ${n} 个文件吗？\n（不会删除文件本身）` });
  if (ok) {
    state.targets = state.targets.filter(t => !state.selectedIds.has(t.id));
    state.selectedIds.clear();
    if (state.viewedId && !state.targets.some(t => t.id === state.viewedId)) state.viewedId = null;
    render();
    await saveTargets();
  }
}

// ===== 自定义模式说明 =====
function showPatternTips() {
  const el = $('patternTips');
  if (el) el.style.display = 'block';
}
function hidePatternTips() {
  const el = $('patternTips');
  if (el) el.style.display = 'none';
}

// ===== 清除本地数据 =====
async function clearData() {
  const ok = await invoke('cmd_confirm', { message: '确定要清除所有本地数据吗？\n（清除目标列表将被清空，不影响已扫描的文件）' });
  if (ok) {
    const cleared = await invoke('cmd_clear_data');
    if (cleared !== false) {
      state.targets = [];
      state.selectedIds.clear();
      state.viewedId = null;
      state.pathStatus = {};
      render();
      invoke('cmd_alert', { message: '本地数据已清除' });
    }
  }
}

// ===== 初始化 =====
(async () => {
  await loadTargets();
  // 先检查路径再渲染，避免首次显示全部失效
  await checkAllPaths();
  render();
})();
