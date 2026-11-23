"use strict";
const $ = (id) => document.getElementById(id);
const state = {
  lists: [], items: [], selected: new Set(), listId: null, saving: false,
  view: "lists", noteItemId: null, itemsListId: null, itemsLoading: false,
  loadRequest: 0, itemsRequest: 0, statsRequest: 0, notesRequest: 0,
  subscriptionsRequest: 0, focusRequest: 0,
  subscriptionsLoading: false, subscriptionSelected: new Set(), updateSelected: new Set(),
  subscriptions: [], updates: [], preferencesRequest: 0, preferences: null, preferencesSaving: false,
};
const statuses = { planned: "未开始", learning: "学习中", completed: "已完成" };
function node(tag, text, className) { const el = document.createElement(tag); if (text != null) el.textContent = text; if (className) el.className = className; return el; }
function action(text, handler, danger = false) { const el = node("button", text, danger ? "danger" : ""); el.type = "button"; el.onclick = () => run(handler); return el; }
async function api(path, method = "GET", body) {
  const token = localStorage.getItem("bioStatAdminToken");
  if (!token) throw new Error("请返回管理台登录");
  const response = await fetch(`/api/v1${path}`, { method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!response.ok) { const data = await response.json().catch(() => ({})); if (response.status === 401) throw new Error("登录已失效，请返回管理台登录"); throw new Error(typeof data.detail === "string" ? data.detail : `请求失败 (${response.status})`); }
  return response.status === 204 ? null : response.json();
}
async function run(fn) { $("message").textContent = ""; try { await fn(); } catch (error) { $("message").textContent = error.message; } }
function time(seconds) { return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`; }
function empty(target, text) { target.replaceChildren(node("p", text)); }
async function load() {
  const request = ++state.loadRequest;
  const [lists] = await Promise.all([api("/study/lists"), loadStats()]);
  if (request !== state.loadRequest) return;
  state.lists = lists.data; if (!state.lists.some((x) => x.id === state.listId)) state.listId = state.lists[0]?.id ?? null;
  $("listFilter").replaceChildren(...state.lists.map((list) => { const option = node("option", `${list.name}${list.archived ? "（归档）" : ""}`); option.value = list.id; return option; }));
  $("listFilter").value = state.listId ?? "";
  await refreshView();
}
async function loadStats() {
  const request = ++state.statsRequest;
  const stats = await api("/study/stats");
  if (request !== state.statsRequest) return;
  $("stats").replaceChildren(...[["今日专注", `${Math.round(stats.today_seconds / 60)} 分钟`], ["累计专注", `${Math.round(stats.total_seconds / 60)} 分钟`], ["已完成课程", stats.completed_items], ["连续学习", `${stats.streak_days} 天`]].map(([label, value]) => { const el = node("div", null, "stat"); el.append(node("strong", value), node("span", label)); return el; }));
}
async function refreshView() {
  if (state.view === "notes") return showNotes(state.noteItemId);
  if (state.view === "subscriptions") return subscriptions();
  if (state.view === "focus") return focus();
  if (state.view === "preferences") return loadPreferences();
  return loadItems();
}
function itemsCurrent(request = state.itemsRequest, listId = state.itemsListId) {
  return !state.itemsLoading && listId != null && state.itemsListId === listId && state.listId === listId && request === state.itemsRequest;
}
function requireItems(request, listId) {
  if (!itemsCurrent(request, listId)) throw new Error("清单已更新，请等待加载完成后重试");
}
function itemControls() {
  const disabled = !itemsCurrent();
  for (const id of ["selectAll", "batchComplete", "batchPlan", "batchRemove"]) $(id).disabled = disabled;
  $("items").setAttribute("aria-busy", String(state.itemsLoading));
}
async function refreshItemsAndStats() {
  await Promise.all([loadItems(), loadStats()]);
}
async function loadItems() {
  const request = ++state.itemsRequest;
  const listId = state.listId;
  const query = $("query").value, sort = $("sort").value, status = $("status").value;
  state.itemsLoading = true; state.itemsListId = null; state.items = [];
  state.selected.clear(); $("selectAll").checked = false;
  $("items").replaceChildren(); itemControls();
  try {
    if (!listId) { empty($("items"), "暂无学习清单"); return; }
    const params = new URLSearchParams({ list_id: listId, q: query, sort });
    if (status) params.set("status", status);
    const response = await api(`/study/items?${params}`);
    // A stale response must never install rows or handlers for a different list.
    if (request !== state.itemsRequest || listId !== state.listId) return;
    if (response.data.some((item) => item.list_id !== listId)) throw new Error("课程与当前清单不匹配，请刷新后重试");
    state.items = response.data; state.itemsListId = listId;
    $("items").replaceChildren(...state.items.map((item, index) => {
      const tr = node("tr"); const check = node("input"); check.type = "checkbox"; check.setAttribute("aria-label", `选择${item.title}`); check.onchange = () => { if (!itemsCurrent(request, listId)) { check.checked = false; return; } check.checked ? state.selected.add(item.id) : state.selected.delete(item.id); };
      const td = node("td"); td.append(check); tr.append(td, node("td", item.title), node("td", item.source === "nas" ? "NAS" : "B站"));
      const progress = node("progress"); progress.max = item.duration_seconds || 1; progress.value = item.position_seconds;
      const progressTd = node("td", `${time(item.position_seconds)} / ${time(item.duration_seconds)}`); progressTd.append(progress); tr.append(progressTd);
      const select = node("select"); select.setAttribute("aria-label", "学习状态"); Object.entries(statuses).forEach(([key, label]) => { const option = node("option", label); option.value = key; select.append(option); }); select.value = item.status;
      select.onchange = () => run(async () => { requireItems(request, listId); await api(`/study/items/${item.id}`, "PUT", { status: select.value }); await refreshItemsAndStats(); });
      const statusTd = node("td"); statusTd.append(select); tr.append(statusTd);
      const order = node("td"); for (const [label, delta] of [["上移", -1], ["下移", 1]]) { const button = action(label, () => reorder(index, delta, request, listId)); button.disabled = sort !== "sort_order" || !!query || !!status || index + delta < 0 || index + delta >= state.items.length; order.append(button); } tr.append(order);
      const ops = node("td"); ops.append(action("编辑", () => { requireItems(request, listId); editItem(item); }), action("笔记", () => { requireItems(request, listId); return showNotes(item.id); }), action("移除", async () => { requireItems(request, listId); if (!confirm(`从学习清单移除“${item.title}”？不会删除 NAS 文件。`)) return; await api(`/study/items/${item.id}`, "DELETE"); await refreshItemsAndStats(); }, true)); tr.append(ops); return tr;
    }));
  } catch (error) {
    if (request === state.itemsRequest && listId === state.listId) throw error;
  } finally {
    if (request === state.itemsRequest) { state.itemsLoading = false; itemControls(); }
  }
}
async function reorder(index, delta, request, listId) { requireItems(request, listId); const ids = state.items.map((item) => item.id); [ids[index], ids[index + delta]] = [ids[index + delta], ids[index]]; await api("/study/items/reorder", "POST", { list_id: listId, item_ids: ids }); await loadItems(); }
function edit(title, fields, save) {
  $("editorTitle").textContent = title; $("editorError").textContent = ""; $("fields").replaceChildren();
  for (const field of fields) { const label = node("label", field.label); const input = node(field.type === "textarea" ? "textarea" : "input"); input.name = field.name; input.value = field.value ?? ""; if (field.type && field.type !== "textarea") input.type = field.type; input.required = !!field.required; label.append(input); $("fields").append(label); }
  $("editorForm").onsubmit = async (event) => { event.preventDefault(); if (state.saving) return; state.saving = true; $("saveEditor").disabled = true;
    try { await save(Object.fromEntries(new FormData(event.currentTarget))); $("editor").close(); await load(); } catch (error) { $("editorError").textContent = error.message; } finally { state.saving = false; $("saveEditor").disabled = false; } };
  $("editor").showModal();
}
function editList(list) { edit(list ? "编辑学习清单" : "新建学习清单", [{ name: "name", label: "名称", value: list?.name, required: true }, { name: "description", label: "说明", type: "textarea", value: list?.description }], (data) => api(list ? `/study/lists/${list.id}` : "/study/lists", list ? "PUT" : "POST", data)); }
function editItem(item) { const request = state.itemsRequest, listId = state.itemsListId; edit("编辑学习项", [{ name: "title", label: "标题", value: item.title, required: true }, { name: "position_seconds", label: "续播位置（秒）", value: item.position_seconds, type: "number" }], (data) => { requireItems(request, listId); return api(`/study/items/${item.id}`, "PUT", { title: data.title, position_seconds: Number(data.position_seconds) }); }); }
async function showNotes(itemId) {
  selectView("notes"); state.noteItemId = itemId ?? null;
  const request = ++state.notesRequest;
  const rows = (await api(`/study/notes${itemId ? `?item_id=${itemId}` : ""}`)).data;
  const allItems = (await api("/study/items")).data;
  if (request !== state.notesRequest || state.view !== "notes") return;
  $("noteRows").replaceChildren(...rows.map((note) => { const row = node("div", null, "row"); const content = node("div", null, "content"); content.append(node("strong", `${allItems.find((item) => item.id === note.item_id)?.title ?? "课程"} · ${time(note.position_seconds)}`), node("p", note.content));
    if (note.image_data || note.image_base64) { const image = node("img", null, "note-image"); image.alt = "视频截图笔记"; const data = (note.image_data || note.image_base64).split(",").pop(); let mime = "image/png"; if (data.startsWith("/9j/")) mime = "image/jpeg"; else if (data.startsWith("UklGR")) mime = "image/webp"; else if (data.startsWith("R0lGOD")) mime = "image/gif"; image.src = `data:${mime};base64,${data}`; content.append(image); }
    row.append(content, action("编辑", () => edit("编辑笔记", [{ name: "content", label: "内容", value: note.content, type: "textarea", required: true }, { name: "position_seconds", label: "时间点（秒）", value: note.position_seconds, type: "number" }], async (data) => { await api(`/study/notes/${note.id}`, "PUT", { content: data.content, position_seconds: Number(data.position_seconds) }); await showNotes(itemId); })), action("删除", async () => { if (confirm("删除这条笔记？")) { await api(`/study/notes/${note.id}`, "DELETE"); await showNotes(itemId); } }, true)); return row; }));
  if (!rows.length) empty($("noteRows"), "暂无笔记");
}
async function subscriptions() {
  const request = ++state.subscriptionsRequest;
  state.subscriptionsLoading = true; state.subscriptionSelected.clear(); state.updateSelected.clear();
  state.subscriptions = []; state.updates = [];
  for (const id of ["selectSubscriptions", "selectUpdates"]) $(id).checked = false;
  $("subscriptionRows").replaceChildren(); $("updateRows").replaceChildren(); subscriptionControls();
  const source = $("subscriptionSource").value;
  const subParams = new URLSearchParams(), params = new URLSearchParams();
  if (source) { subParams.set("source", source); params.set("source", source); }
  if ($("updatesFrom").value) params.set("date_from", $("updatesFrom").value);
  if ($("updatesTo").value) params.set("date_to", $("updatesTo").value);
  if ($("updatesUnread").checked) params.set("read", "false");
  if ($("updatesGrouped").checked) params.set("group_by", "date");
  try {
    const [subscriptions, updates] = await Promise.all([api(`/study/subscriptions${subParams.size ? `?${subParams}` : ""}`), api(`/study/updates${params.size ? `?${params}` : ""}`)]);
    if (request !== state.subscriptionsRequest || state.view !== "subscriptions") return;
    state.subscriptions = subscriptions.data; state.updates = updates.data;
    $("subscriptionRows").replaceChildren(...subscriptions.data.map((sub) => {
      const row = node("div", null, "row"), check = selection(sub.id, state.subscriptionSelected, request, `选择订阅 ${sub.name}`);
      row.append(check, node("div", `${sub.name} · ${sub.source === "nas" ? "NAS分类" : sub.kind} · ${sub.enabled === false ? "已暂停" : "启用"}`, "content"),
        action(sub.enabled === false ? "恢复" : "暂停", async () => { requireSubscriptions(request); await api(`/study/subscriptions/${sub.id}`, "PUT", { enabled: sub.enabled === false }); await subscriptionsReload(); }),
        action("删除订阅", async () => { requireSubscriptions(request); if (confirm("删除订阅及其更新记录？")) { await api(`/study/subscriptions/${sub.id}`, "DELETE"); await subscriptionsReload(); } }, true)); return row;
    }));
    const rows = [];
    for (const group of updates.groups ?? [{ data: updates.data }]) {
      if (group.date) rows.push(node("h3", group.date));
      for (const update of group.data) {
        const row = node("div", null, "row");
        row.append(selection(update.id, state.updateSelected, request, `选择更新 ${update.title}`), node("div", `${update.read ? "已读" : "未读"} · ${update.title}`, "content"),
          action("标记已读", async () => { requireSubscriptions(request); await api(`/study/updates/${update.id}`, "PUT", { read: true, seen: true }); await subscriptionsReload(); }));
        rows.push(row);
      }
    }
    $("updateRows").replaceChildren(...rows);
    if (!subscriptions.total) empty($("subscriptionRows"), "暂无订阅");
    if (!updates.total) empty($("updateRows"), "暂无更新");
  } catch (error) {
    if (request === state.subscriptionsRequest && state.view === "subscriptions") throw error;
  } finally {
    if (request === state.subscriptionsRequest) { state.subscriptionsLoading = false; subscriptionControls(); }
  }
}
function requireSubscriptions(request = state.subscriptionsRequest) {
  if (state.subscriptionsLoading || state.view !== "subscriptions" || request !== state.subscriptionsRequest) throw new Error("订阅已更新，请等待加载完成后重试");
}
function subscriptionControls() {
  for (const id of ["selectSubscriptions", "selectUpdates", "subscriptionsPause", "subscriptionsResume", "subscriptionsRead", "subscriptionsDelete", "updatesRead", "updatesUnreadAction", "updatesDelete"]) $(id).disabled = state.subscriptionsLoading || state.view !== "subscriptions";
}
function selection(id, selected, request, label) {
  const check = node("input"); check.type = "checkbox"; check.setAttribute("aria-label", label);
  check.onchange = () => { if (state.subscriptionsLoading || request !== state.subscriptionsRequest || state.view !== "subscriptions") { check.checked = false; return; } check.checked ? selected.add(id) : selected.delete(id); };
  return check;
}
async function subscriptionsReload() { await subscriptions(); }
const homeCards = { continue: "继续学习", lists: "学习列表", focus: "专注计时", updates: "订阅更新", shortcuts: "快捷入口" };
async function loadPreferences() {
  if (state.preferencesSaving) return;
  const request = ++state.preferencesRequest;
  state.preferences = null; $("savePreferences").disabled = true; $("preferencesStatus").textContent = ""; $("homeCardRows").replaceChildren();
  let preferences;
  try { preferences = await api("/study/preferences"); }
  catch (error) { if (request === state.preferencesRequest && state.view === "preferences") throw error; return; }
  if (request !== state.preferencesRequest || state.view !== "preferences") return;
  state.preferences = preferences;
  $("notificationsEnabled").checked = preferences.notifications_enabled;
  $("backgroundEnabled").checked = preferences.background_refresh_enabled;
  $("preferenceLayout").value = preferences.layout;
  renderHomeCards(request); $("savePreferences").disabled = false;
}
function renderHomeCards(request) {
  const preferences = state.preferences;
  $("homeCardRows").replaceChildren(...preferences.home_card_order.map((key, index) => {
    const row = node("div", null, "row"), check = node("input"); check.type = "checkbox"; check.checked = !preferences.home_hidden_cards.includes(key); check.setAttribute("aria-label", `显示 ${homeCards[key]}`);
    check.onchange = () => { if (request !== state.preferencesRequest || state.preferencesSaving) return; preferences.home_hidden_cards = check.checked ? preferences.home_hidden_cards.filter((card) => card !== key) : [...new Set([...preferences.home_hidden_cards, key])]; };
    const controls = node("div", null, "card-controls");
    for (const [label, delta, symbol] of [["上移", -1, "\u2191"], ["下移", 1, "\u2193"]]) {
      const button = action(symbol, () => {
        if (request !== state.preferencesRequest || state.preferencesSaving) return;
        const order = preferences.home_card_order; [order[index], order[index + delta]] = [order[index + delta], order[index]]; renderHomeCards(request);
      });
      button.title = `${label} ${homeCards[key]}`; button.setAttribute("aria-label", button.title); button.disabled = index + delta < 0 || index + delta >= preferences.home_card_order.length; controls.append(button);
    }
    row.append(check, node("span", homeCards[key], "content"), controls); return row;
  }));
}
async function focus() { const request = ++state.focusRequest; const rows = (await api("/study/focus")).data; if (request !== state.focusRequest || state.view !== "focus") return; $("focusRows").replaceChildren(...rows.map((entry) => node("div", `${new Date(`${entry.started_at.replace(/Z$/, "")}Z`).toLocaleString()} · ${Math.round(entry.elapsed_seconds / 60)} 分钟 · ${entry.completed ? "已完成" : "已结束"}`, "row"))); if (!rows.length) empty($("focusRows"), "暂无专注记录"); }
function selectView(view) { state.view = view; document.querySelectorAll(".view").forEach((section) => section.hidden = section.id !== view); document.querySelectorAll("[data-view]").forEach((button) => button.setAttribute("aria-pressed", button.dataset.view === view)); }
document.querySelectorAll("[data-view]").forEach((button) => button.onclick = () => run(async () => { selectView(button.dataset.view); if (state.view === "notes") state.noteItemId = null; await refreshView(); }));
$("refresh").onclick = () => run(load); $("listFilter").onchange = () => { state.listId = Number($("listFilter").value); return run(loadItems); }; $("search").onsubmit = (event) => { event.preventDefault(); return run(loadItems); };
$("newList").onclick = () => editList(); $("editList").onclick = () => { const list = state.lists.find((list) => list.id === state.listId); if (list) editList(list); };
$("deleteList").onclick = () => run(async () => { if (!state.listId || !confirm("删除整个学习清单及笔记？NAS 原视频文件不受影响。")) return; await api(`/study/lists/${state.listId}`, "DELETE"); state.listId = null; await load(); });
$("selectAll").onchange = (event) => { if (!itemsCurrent()) { event.target.checked = false; return; } state.selected = new Set(event.target.checked ? state.items.map((item) => item.id) : []); $("items").querySelectorAll("input[type=checkbox]").forEach((input) => input.checked = event.target.checked); };
for (const [id, name] of [["batchComplete", "complete"], ["batchPlan", "plan"], ["batchRemove", "remove"]]) $(id).onclick = () => run(async () => { requireItems(); if (!state.selected.size) throw new Error("请先选择课程"); if (name === "remove" && !confirm("移除所选学习项及其笔记？不删除原视频文件。")) return; await api("/study/items/batch", "POST", { action: name, item_ids: [...state.selected] }); await load(); });
$("closeEditor").onclick = $("cancelEditor").onclick = () => { if (!state.saving) $("editor").close(); }; $("editor").addEventListener("cancel", (event) => { if (state.saving) event.preventDefault(); });
$("addNas").onclick = () => { if (!state.listId) return run(() => { throw new Error("请先创建清单"); }); $("nasPicker").showModal(); }; $("closeNas").onclick = () => $("nasPicker").close();
$("nasSearch").onsubmit = (event) => { event.preventDefault(); return run(async () => { const data = await api(`/videos/?${new URLSearchParams({ search: $("nasQuery").value, sort: "episode", limit: 200 })}`); $("nasRows").replaceChildren(...data.data.map((video) => { const row = node("div", null, "row"); const button = action("添加", async () => { button.disabled = true; try { await api("/study/items", "POST", { list_id: state.listId, source: "nas", video_id: video.id, title: video.title }); button.textContent = "已添加"; await refreshItemsAndStats(); } catch (error) { button.disabled = false; throw error; } }); row.append(node("div", video.title, "content"), button); return row; })); $("nasMessage").textContent = `${data.total ?? data.data.length} 条结果`; }); };
$("addBili").onclick = () => { if (!state.listId) return; edit("添加B站课程", [{ name: "title", label: "课程标题", required: true }, { name: "bvid", label: "BV号", required: true }, { name: "cid", label: "分P的CID（可空）", type: "number" }], (data) => api("/study/items", "POST", { list_id: state.listId, source: "bilibili", title: data.title, source_data: { bvid: data.bvid.trim(), ...(data.cid ? { cid: Number(data.cid) } : {}) } })); };
$("subscriptionFilters").onsubmit = (event) => { event.preventDefault(); return run(subscriptions); };
for (const [id, selected, target] of [["selectSubscriptions", "subscriptionSelected", "subscriptionRows"], ["selectUpdates", "updateSelected", "updateRows"]]) {
  $(id).onchange = (event) => {
    if (state.subscriptionsLoading || state.view !== "subscriptions") { event.target.checked = false; return; }
    const rows = target === "subscriptionRows" ? state.subscriptions : state.updates;
    state[selected].clear(); if (event.target.checked) rows.forEach((row) => state[selected].add(row.id));
    $(target).querySelectorAll("input[type=checkbox]").forEach((check) => check.checked = event.target.checked);
  };
}
for (const [id, resource, selected, key, operation] of [
  ["subscriptionsPause", "subscriptions", "subscriptionSelected", "subscription_ids", "pause"],
  ["subscriptionsResume", "subscriptions", "subscriptionSelected", "subscription_ids", "resume"],
  ["subscriptionsRead", "subscriptions", "subscriptionSelected", "subscription_ids", "read"],
  ["subscriptionsDelete", "subscriptions", "subscriptionSelected", "subscription_ids", "delete"],
  ["updatesRead", "updates", "updateSelected", "update_ids", "read"],
  ["updatesUnreadAction", "updates", "updateSelected", "update_ids", "unread"],
  ["updatesDelete", "updates", "updateSelected", "update_ids", "delete"],
]) $(id).onclick = () => run(async () => {
  requireSubscriptions(); const ids = [...state[selected]];
  if (!ids.length) throw new Error("请先选择记录");
  if (operation === "delete" && !confirm("删除所选记录？")) return;
  const request = state.subscriptionsRequest;
  state.subscriptionsLoading = true; subscriptionControls();
  try { await api(`/study/${resource}/batch`, "POST", { [key]: ids, action: operation }); await subscriptionsReload(); }
  finally { if (request === state.subscriptionsRequest) { state.subscriptionsLoading = false; subscriptionControls(); } }
});
$("preferencesForm").onsubmit = (event) => { event.preventDefault(); return run(async () => {
  if (state.view !== "preferences" || state.preferencesSaving || !state.preferences) throw new Error("偏好尚未加载完成");
  const payload = {
    home_card_order: [...state.preferences.home_card_order], home_hidden_cards: [...state.preferences.home_hidden_cards],
    notifications_enabled: $("notificationsEnabled").checked, background_refresh_enabled: $("backgroundEnabled").checked,
    layout: $("preferenceLayout").value,
  };
  state.preferencesSaving = true;
  $("preferencesStatus").textContent = "";
  for (const tag of ["input", "select", "button"]) $("preferencesForm").querySelectorAll(tag).forEach((control) => control.disabled = true);
  $("savePreferences").disabled = true;
  try {
    await api("/study/preferences", "PUT", payload);
    state.preferencesSaving = false; await loadPreferences(); $("preferencesStatus").textContent = "已保存";
  } finally {
    state.preferencesSaving = false;
    for (const tag of ["input", "select", "button"]) $("preferencesForm").querySelectorAll(tag).forEach((control) => control.disabled = false);
    $("savePreferences").disabled = !state.preferences;
    if (state.preferences) renderHomeCards(state.preferencesRequest);
  }
}); };
$("checkUpdates").onclick = () => run(async () => { await api("/study/updates/check", "POST"); await subscriptions(); });
$("export").onclick = () => run(async () => { const blob = new Blob([JSON.stringify(await api("/study/export"), null, 2)], { type: "application/json" }); const url = URL.createObjectURL(blob); const a = node("a"); a.href = url; a.download = "biostat-study.json"; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); });
$("import").onchange = (event) => run(async () => { const file = event.target.files[0]; if (!file) return; try { if (!confirm("合并导入学习清单、笔记与记录？")) return; await api("/study/import", "POST", JSON.parse(await file.text())); await load(); } finally { event.target.value = ""; } });
run(async () => { const profile = await api("/auth/profile"); if (!profile.is_admin) throw new Error("需要管理员账号"); await load(); });
