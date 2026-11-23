"use strict";

// Run: node --test tests/test_study_admin.cjs (no packages or live service).
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const sourcePath = path.join(__dirname, "../app/static/admin/study.js");
const source = fs.readFileSync(sourcePath, "utf8");
const stamp = "2026-10-20T00:00:00";
const idle = () => new Promise((resolve) => setImmediate(resolve));
const page = (data) => ({ data, total: data.length });

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function item(id, listId, changes = {}) {
  return {
    id, list_id: listId, video_id: id, source: "nas", source_data: {},
    title: `Lesson ${id}`, thumbnail_url: null, status: "planned",
    position_seconds: 0, duration_seconds: 600, favorite: false, sort_order: id,
    last_watched_at: null, completed_at: null, created_at: stamp, updated_at: stamp,
    ...changes,
  };
}

class Element {
  constructor(tag = "div", id = "") {
    this.tagName = tag.toUpperCase(); this.id = id; this.children = [];
    this.attributes = {}; this.dataset = {}; this.value = "";
    this.disabled = false; this.checked = false; this.hidden = false;
    this.listeners = new Map(); this._text = "";
  }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map((child) => child.textContent).join(""); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this._text = ""; this.children = children; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  addEventListener(name, handler) { this.listeners.set(name, handler); }
  showModal() { this.open = true; }
  close() { this.open = false; }
  click() { return this.disabled ? undefined : this.onclick?.({ target: this }); }
  querySelectorAll(selector) {
    const matches = (node) => selector === "input[type=checkbox]"
      ? node.tagName === "INPUT" && node.type === "checkbox"
      : node.tagName.toLowerCase() === selector;
    return this.children.flatMap((child) => [
      ...(matches(child) ? [child] : []), ...child.querySelectorAll(selector),
    ]);
  }
}

async function setup() {
  const elements = new Map();
  const get = (id) => {
    if (!elements.has(id)) elements.set(id, new Element("div", id));
    return elements.get(id);
  };
  const views = ["lists", "notes", "subscriptions", "focus", "preferences"].map(get);
  const tabs = views.map((view) => {
    const tab = new Element("button"); tab.dataset.view = view.id; return tab;
  });
  const document = {
    getElementById: get,
    createElement: (tag) => new Element(tag),
    querySelectorAll: (selector) => selector === ".view" ? views : selector === "[data-view]" ? tabs : [],
  };
  get("sort").value = "sort_order";
  get("updatesGrouped").checked = true;
  const db = {
    lists: [1, 2].map((id) => ({ id, name: `List ${id}`, description: "", sort_order: id, archived: false, created_at: stamp, updated_at: stamp })),
    items: [item(101, 1), item(102, 1), item(201, 2)],
    notes: [{ id: 1, item_id: 101, content: "Old note", position_seconds: 15, image_data: null, created_at: stamp, updated_at: stamp }],
    focus: [{ id: 1, item_id: 101, elapsed_seconds: 60, started_at: stamp, ended_at: "2026-10-20T00:01:00", completed: true, created_at: stamp }],
    subscriptions: [{ id: 1, source: "nas", kind: "category", category_id: 7, name: "Old subscription", enabled: true, paused: false }],
    updates: [{ id: 1, subscription_id: 1, source: "nas", video_id: 101, title: "Old update", source_data: {}, duration_seconds: 600, read: false, seen: false, published_at: stamp, created_at: stamp }],
    preferences: {
      home_card_order: ["continue", "lists", "focus", "updates", "shortcuts"], home_hidden_cards: [],
      notifications_enabled: false, background_refresh_enabled: false, layout: "auto",
      double_tap_left: "none", double_tap_center: "play_pause", double_tap_right: "seek_forward",
      double_tap_left_width: 0.2, double_tap_right_width: 0.4, double_tap_height: 0.75,
      double_tap_seek_seconds: 30, long_press_action: "speed", long_press_speed: 3,
    },
    archive: null,
  };
  const requests = [], downloads = [], imported = [], confirmations = [];
  const controls = { intercept: null, confirm: true };
  const archive = () => db.archive ?? {
    kind: "study-backup", version: 1, exported_at: stamp,
    lists: db.lists, items: db.items, notes: db.notes, focus: db.focus,
    subscriptions: [], updates: [], watch_history: [], preferences: db.preferences,
  };
  function respond(request) {
    const { pathname, method, body, query } = request;
    if (method === "GET") {
      if (pathname === "/auth/profile") return { is_admin: true };
      if (pathname === "/study/stats") return {
        today_seconds: 60, total_seconds: 60, sessions: db.focus.length,
        completed_items: db.items.filter((row) => row.status === "completed").length,
        streak_days: 1, daily: [{ date: "2026-10-20", seconds: 60 }],
      };
      if (pathname === "/study/export") return archive();
      if (pathname === "/study/preferences") return db.preferences;
      if (pathname === "/videos/") return page([{ id: 301, title: "New NAS lesson" }]);
      if (pathname === "/study/items") {
        let rows = db.items.filter((row) => !query.has("list_id") || row.list_id === Number(query.get("list_id")));
        if (query.get("q")) rows = rows.filter((row) => row.title.includes(query.get("q")));
        if (query.get("status")) rows = rows.filter((row) => row.status === query.get("status"));
        return page(rows);
      }
      if (pathname === "/study/notes") return page(db.notes.filter((row) => !query.has("item_id") || row.item_id === Number(query.get("item_id"))));
      if (["/study/subscriptions", "/study/updates"].includes(pathname)) {
        const isUpdates = pathname.endsWith("updates");
        let rows = db[isUpdates ? "updates" : "subscriptions"].filter((row) => !row.deleted);
        const source = query.get("source");
        if (source) rows = rows.filter((row) => ["up", "collection"].includes(source)
          ? row.source === "bilibili" && (isUpdates ? db.subscriptions.find((sub) => sub.id === row.subscription_id)?.kind : row.kind) === source
          : row.source === source);
        if (isUpdates) {
          if (query.has("read")) rows = rows.filter((row) => row.read === (query.get("read") === "true"));
          if (query.has("date_from")) rows = rows.filter((row) => row.published_at.slice(0, 10) >= query.get("date_from"));
          if (query.has("date_to")) rows = rows.filter((row) => row.published_at.slice(0, 10) <= query.get("date_to"));
        }
        const result = page(rows);
        if (isUpdates && query.get("group_by") === "date") {
          const groups = new Map();
          for (const row of rows) { const key = row.published_at.slice(0, 10); if (!groups.has(key)) groups.set(key, []); groups.get(key).push(row); }
          result.groups = [...groups].map(([date, data]) => ({ date, ...page(data) }));
        }
        return result;
      }
      for (const name of ["lists", "focus"]) {
        if (pathname === `/study/${name}`) return page(db[name]);
      }
    }
    if (method === "PUT" && pathname === "/study/preferences") { Object.assign(db.preferences, body); return db.preferences; }
    if (method === "POST" && pathname === "/study/updates/check") return page(db.updates);
    if (method === "POST" && ["/study/subscriptions/batch", "/study/updates/batch"].includes(pathname)) {
      const subscriptions = pathname.includes("subscriptions"), key = subscriptions ? "subscription_ids" : "update_ids";
      const table = subscriptions ? "subscriptions" : "updates";
      assert.deepEqual(Object.keys(body).sort(), ["action", key].sort());
      assert([...(subscriptions ? ["pause", "resume", "read", "delete"] : ["read", "unread", "seen", "delete"])].includes(body.action));
      for (const id of body[key]) {
        const row = db[table].find((row) => row.id === id); assert(row, "bulk target must exist");
        if (body.action === "delete") row.deleted = true;
        else if (["pause", "resume"].includes(body.action)) { row.enabled = body.action === "resume"; row.paused = !row.enabled; }
        else {
          const updates = subscriptions ? db.updates.filter((update) => update.subscription_id === id) : [row];
          updates.forEach((update) => { update.seen = true; if (body.action !== "seen") update.read = body.action === "read"; });
        }
      }
      return { [body.action === "delete" ? "deleted" : "updated"]: body[key].length };
    }
    if (["PUT", "DELETE"].includes(method) && /^\/study\/(subscriptions|updates)\/\d+$/.test(pathname)) {
      const [, , table, id] = pathname.split("/");
      const row = db[table].find((row) => row.id === Number(id)); assert(row);
      if (method === "DELETE") row.deleted = true;
      else { Object.assign(row, body); if ("enabled" in body) row.paused = !row.enabled; }
      return method === "DELETE" ? { deleted: 1 } : row;
    }
    if (method === "PUT" && /^\/study\/items\/\d+$/.test(pathname)) {
      const row = db.items.find((entry) => entry.id === Number(pathname.split("/").pop()));
      assert(row, "PUT target must exist in the mock API"); Object.assign(row, body); return row;
    }
    if (method === "DELETE" && /^\/study\/items\/\d+$/.test(pathname)) {
      db.items = db.items.filter((row) => row.id !== Number(pathname.split("/").pop())); return { deleted: 1 };
    }
    if (method === "POST" && pathname === "/study/items/reorder") {
      const rows = db.items.filter((row) => row.list_id === body.list_id);
      assert.deepEqual([...body.item_ids].sort(), rows.map((row) => row.id).sort(), "reorder must contain every item in its list");
      return page(body.item_ids.map((id, index) => ({ ...rows.find((row) => row.id === id), sort_order: index })));
    }
    if (method === "POST" && pathname === "/study/items/batch") {
      for (const id of body.item_ids) assert(db.items.some((row) => row.id === id));
      if (body.action === "remove") db.items = db.items.filter((row) => !body.item_ids.includes(row.id));
      else db.items.filter((row) => body.item_ids.includes(row.id)).forEach((row) => row.status = body.action === "complete" ? "completed" : "planned");
      return { [body.action === "remove" ? "deleted" : "updated"]: body.item_ids.length };
    }
    if (method === "POST" && pathname === "/study/items") {
      const row = item(body.video_id, body.list_id, { ...body, status: "completed" }); db.items.push(row); return row;
    }
    if (method === "POST" && pathname === "/study/import") { imported.push(body); return { imported: {}, id_map: {} }; }
    throw new Error(`Unexpected mock request: ${method} ${pathname}`);
  }
  const sandbox = {
    document, URLSearchParams, Blob,
    URL: { createObjectURL(blob) { downloads.push(blob); return "blob:study-test"; }, revokeObjectURL() {} },
    setTimeout(callback) { callback(); },
    localStorage: { getItem(key) { assert.equal(key, "bioStatAdminToken"); return "test-token"; } },
    confirm(message) { confirmations.push(message); return controls.confirm; },
    FormData: class {
      *[Symbol.iterator]() {
        for (const label of get("fields").children) for (const input of label.children) yield [input.name, input.value];
      }
    },
    async fetch(url, options) {
      const parsed = new URL(url, "http://study.invalid");
      assert.equal(parsed.origin, "http://study.invalid", "tests must never call a real service");
      assert.equal(options.headers.Authorization, "Bearer test-token");
      const request = {
        pathname: parsed.pathname.replace(/^\/api\/v1/, ""), query: parsed.searchParams,
        method: options.method, body: options.body === undefined ? undefined : JSON.parse(options.body),
      };
      requests.push(request);
      const intercepted = controls.intercept?.(request);
      const data = await (intercepted === undefined ? respond(request) : intercepted);
      const snapshot = structuredClone(data);
      return { ok: true, status: 200, async json() { return snapshot; } };
    },
  };
  const context = vm.createContext(sandbox);
  const run = (expression) => vm.runInContext(expression, context);
  const read = (expression) => structuredClone(run(expression));
  vm.runInContext(source, context, { filename: sourcePath });
  await idle();
  assert.equal(read("state.itemsListId"), 1, "the real script must finish its normal bootstrap");
  return {
    db, controls, requests, downloads, imported, confirmations, get, run, read,
    rows: () => get("items").children,
    switchList(id) { get("listFilter").value = String(id); return get("listFilter").onchange({ target: get("listFilter") }); },
    tab(view) { return tabs.find((tab) => tab.dataset.view === view).click(); },
    completed: () => Number(get("stats").children[2].children[0].textContent),
    writes: () => requests.filter((request) => request.method !== "GET"),
    async importFile(file) { const target = get("import"); target.files = [file]; target.value = "chosen.json"; await target.onchange({ target }); },
  };
}

test("bootstrap reads the actual collection envelopes and keeps NAS and Bilibili metadata", async () => {
  const app = await setup();
  app.db.items.push(item(103, 1, { source: "bilibili", video_id: null, source_data: { bvid: "BV17x411w7KC", cid: "123" } }));
  await app.run("loadItems()");
  assert.equal(app.rows().length, 3);
  assert.deepEqual(app.read("state.items[2].source_data"), { bvid: "BV17x411w7KC", cid: "123" });
  assert.equal(app.get("message").textContent, "");
});

test("late list A response cannot replace list B or cause deletion of an A item", async () => {
  const app = await setup();
  const first = deferred(), second = deferred();
  app.controls.intercept = (request) => request.pathname === "/study/items"
    ? (request.query.get("list_id") === "1" ? first.promise : second.promise) : undefined;
  const a = app.run("loadItems()");
  const b = app.switchList(2);
  second.resolve(page([item(201, 2)])); await b;
  first.resolve(page([item(101, 1)])); await a;
  assert.equal(app.read("state.listId"), 2);
  assert.deepEqual(app.read("state.items.map(row => row.id)"), [201]);
  app.controls.intercept = null;
  await app.rows()[0].children[6].children[2].click();
  assert.deepEqual(app.writes().map((request) => [request.method, request.pathname]), [["DELETE", "/study/items/201"]]);
  assert(app.db.items.some((row) => row.id === 101));
});

for (const order of [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]) {
  test(`A-B-A navigation stays on its newest snapshot for response order ${order.join("-")}`, async () => {
    const app = await setup(), pending = [deferred(), deferred(), deferred()];
    const oldRemove = app.rows()[0].children[6].children[2];
    app.db.items.push(item(103, 1));
    let count = 0;
    app.controls.intercept = (request) => request.pathname === "/study/items" ? pending[count++].promise : undefined;
    const loads = [app.run("loadItems()"), app.switchList(2), app.switchList(1)];
    const responses = [[item(101, 1), item(102, 1)], [item(201, 2)], [item(101, 1), item(102, 1), item(103, 1)]];
    for (const index of order) { pending[index].resolve(page(responses[index])); await loads[index]; }
    assert.equal(app.read("state.listId"), 1);
    assert.deepEqual(app.read("state.items.map(row => row.id)"), [101, 102, 103]);
    app.controls.intercept = null;
    await oldRemove.onclick(); assert.equal(app.writes().length, 0);
    await app.rows()[2].children[6].children[2].click();
    assert.deepEqual(app.writes().map((request) => request.pathname), ["/study/items/103"]);
    assert(app.db.items.some((row) => row.id === 201));
  });
}

test("loading clears old rows and blocks retained delete, select, status, reorder and batch handlers", async () => {
  const app = await setup();
  const oldRow = app.rows()[0], pending = deferred();
  const checkbox = oldRow.children[0].children[0];
  checkbox.checked = true; checkbox.onchange();
  app.controls.intercept = (request) => request.pathname === "/study/items" ? pending.promise : undefined;
  const loading = app.switchList(2);
  assert.equal(app.rows().length, 0);
  for (const id of ["selectAll", "batchComplete", "batchPlan", "batchRemove"]) assert(app.get(id).disabled);
  assert.equal(app.get("items").attributes["aria-busy"], "true");
  await oldRow.children[6].children[2].onclick();
  await oldRow.children[4].children[0].onchange();
  await oldRow.children[5].children[1].onclick();
  checkbox.checked = true; checkbox.onchange();
  await app.get("batchRemove").onclick();
  assert.equal(app.read("state.selected.size"), 0);
  assert.equal(app.writes().length, 0);
  pending.resolve(page([item(201, 2)])); await loading;
  assert.equal(app.get("items").attributes["aria-busy"], "false");
  assert.equal(app.get("batchRemove").disabled, false);
  // Even after B loads, a retained handler from A must stay invalid.
  await oldRow.children[6].children[2].onclick();
  assert.equal(app.writes().length, 0);
});

test("same-list searches also ignore responses from older filters", async () => {
  const app = await setup(); const first = deferred(), second = deferred();
  app.controls.intercept = (request) => request.pathname === "/study/items"
    ? (request.query.get("q") === "101" ? first.promise : second.promise) : undefined;
  app.get("query").value = "101"; const a = app.run("loadItems()");
  app.get("query").value = "102"; const b = app.run("loadItems()");
  second.resolve(page([item(102, 1)])); await b;
  first.resolve(page([item(101, 1)])); await a;
  assert.deepEqual(app.read("state.items.map(row => row.id)"), [102]);
});

test("an old failure cannot unlock or report an error over a newer pending request", async () => {
  const app = await setup(); const first = deferred(), second = deferred();
  app.controls.intercept = (request) => request.pathname === "/study/items"
    ? (request.query.get("list_id") === "1" ? first.promise : second.promise) : undefined;
  const a = app.run("loadItems()"); const b = app.switchList(2);
  first.reject(new Error("obsolete request failed")); await a;
  assert.equal(app.get("batchRemove").disabled, true);
  assert.equal(app.get("message").textContent, "");
  second.resolve(page([item(201, 2)])); await b;
});

test("a failed current request stays empty and cannot revive old selections", async () => {
  const app = await setup(); const pending = deferred();
  app.controls.intercept = (request) => request.pathname === "/study/items" ? pending.promise : undefined;
  const loading = app.switchList(2);
  pending.reject(new Error("current request failed")); await loading;
  assert.equal(app.rows().length, 0);
  assert.equal(app.get("batchRemove").disabled, true);
  assert.equal(app.read("state.selected.size"), 0);
  assert.match(app.get("message").textContent, /current request failed/);
  await app.get("batchRemove").onclick();
  assert.equal(app.writes().length, 0);
});

test("a response with another list's items is rejected even if it is the newest response", async () => {
  const app = await setup();
  app.controls.intercept = (request) => request.pathname === "/study/items" ? page([item(201, 2)]) : undefined;
  await app.run("run(loadItems)");
  assert.equal(app.rows().length, 0);
  assert.equal(app.get("batchRemove").disabled, true);
  assert.equal(app.writes().length, 0);
});

test("reorder posts the exact item permutation and captured list ID", async () => {
  const app = await setup();
  await app.rows()[0].children[5].children[1].click();
  assert.deepEqual(app.writes()[0].body, { list_id: 1, item_ids: [102, 101] });
});

test("batch actions only submit the freshly loaded list's selected IDs", async () => {
  const app = await setup(); await app.switchList(2);
  app.get("selectAll").checked = true; app.get("selectAll").onchange({ target: app.get("selectAll") });
  await app.get("batchComplete").click();
  assert.deepEqual(app.writes()[0].body, { action: "complete", item_ids: [201] });
  assert.equal(app.completed(), 1);
});

test("global refresh reloads notes and preserves the selected item filter", async () => {
  const app = await setup(); await app.run("showNotes(101)");
  app.db.notes[0].content = "Refreshed note";
  const start = app.requests.length; await app.get("refresh").click();
  assert.equal(app.read("state.view"), "notes");
  assert.equal(app.read("state.noteItemId"), 101);
  assert.match(app.get("noteRows").textContent, /Refreshed note/);
  assert(app.requests.slice(start).some((request) => request.pathname === "/study/notes" && request.query.get("item_id") === "101"));
});

test("global refresh reloads both subscriptions and cached updates", async () => {
  const app = await setup(); await app.tab("subscriptions");
  app.db.subscriptions[0].name = "Refreshed subscription"; app.db.updates[0].title = "Refreshed update";
  await app.get("refresh").click();
  assert.equal(app.read("state.view"), "subscriptions");
  assert.match(app.get("subscriptionRows").textContent, /Refreshed subscription/);
  assert.match(app.get("updateRows").textContent, /Refreshed update/);
});

test("global refresh reloads focus records", async () => {
  const app = await setup(); await app.tab("focus");
  app.db.focus.push({ ...app.db.focus[0], id: 2 });
  await app.get("refresh").click();
  assert.equal(app.read("state.view"), "focus");
  assert.equal(app.get("focusRows").children.length, 2);
});

for (const view of ["notes", "subscriptions", "focus"]) {
  test(`successful import refreshes the current ${view} view`, async () => {
    const app = await setup(); await app.tab(view);
    app.controls.intercept = (request) => {
      if (request.pathname !== "/study/import") return undefined;
      app.db.notes[0].content = "Imported note"; app.db.subscriptions[0].name = "Imported subscription";
      app.db.focus.push({ ...app.db.focus[0], id: 2 });
      return { imported: {}, id_map: {} };
    };
    await app.importFile({ size: 13, async text() { return '{"version":1}'; } });
    assert.equal(app.read("state.view"), view);
    if (view === "notes") assert.match(app.get("noteRows").textContent, /Imported note/);
    if (view === "subscriptions") assert.match(app.get("subscriptionRows").textContent, /Imported subscription/);
    if (view === "focus") assert.equal(app.get("focusRows").children.length, 2);
    assert.equal(app.get("import").value, "");
  });
}

test("single status changes immediately refresh completion statistics", async () => {
  const app = await setup(); const select = app.rows()[0].children[4].children[0];
  assert.equal(app.completed(), 0);
  select.value = "completed"; await select.onchange();
  assert.deepEqual(app.writes()[0].body, { status: "completed" });
  assert.equal(app.completed(), 1);
});

test("an editor opened for an obsolete item snapshot cannot submit a write", async () => {
  const app = await setup();
  await app.rows()[0].children[6].children[0].click();
  assert.equal(app.get("editor").open, true);
  await app.switchList(2);
  await app.get("editorForm").onsubmit({ preventDefault() {}, currentTarget: app.get("editorForm") });
  assert.equal(app.writes().length, 0);
  assert.equal(app.get("editor").open, true);
  assert(app.get("editorError").textContent.length > 0);
  assert.equal(app.get("saveEditor").disabled, false);
});

test("single removal immediately refreshes completion statistics", async () => {
  const app = await setup(); app.db.items[0].status = "completed";
  await app.run("load()"); assert.equal(app.completed(), 1);
  await app.rows()[0].children[6].children[2].click();
  assert.equal(app.completed(), 0);
});

test("adding a NAS item that inherits completion also refreshes statistics", async () => {
  const app = await setup();
  await app.get("nasSearch").onsubmit({ preventDefault() {} });
  await app.get("nasRows").children[0].children[1].click();
  assert.equal(app.completed(), 1);
  assert.deepEqual(app.writes()[0].body, { list_id: 1, source: "nas", video_id: 301, title: "New NAS lesson" });
});

test("an older statistics response cannot overwrite a newer total", async () => {
  const app = await setup(); const first = deferred(), second = deferred(); let count = 0;
  app.controls.intercept = (request) => request.pathname === "/study/stats" ? (++count === 1 ? first.promise : second.promise) : undefined;
  const a = app.run("loadStats()"); const b = app.run("loadStats()");
  const stats = (completed_items) => ({ today_seconds: 0, total_seconds: 0, completed_items, streak_days: 0 });
  second.resolve(stats(2)); await b; first.resolve(stats(0)); await a;
  assert.equal(app.completed(), 2);
});

test("an exported backup with eight valid-size images remains importable above 20 MiB", async () => {
  const app = await setup();
  const raw = Buffer.alloc(2 * 1024 * 1024);
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(raw);
  const image = raw.toString("base64");
  app.db.notes = Array.from({ length: 8 }, (_, index) => ({ ...app.db.notes[0], id: index + 1, image_data: image }));
  await app.get("export").click();
  const backup = app.downloads[0]; assert(backup.size > 20 * 1024 * 1024);
  await app.importFile(backup);
  assert.equal(app.imported.length, 1);
  assert.equal(app.imported[0].notes.length, 8);
  assert.equal(app.imported[0].notes[7].image_data, image);
  assert.equal(app.imported[0].version, 1);
  assert.equal(app.get("message").textContent, "");
});

test("cancelled imports do not read files or send mutations", async () => {
  const app = await setup(); app.controls.confirm = false;
  await app.importFile({ size: 30 * 1024 * 1024, text() { throw new Error("must not read a cancelled file"); } });
  assert.equal(app.writes().length, 0); assert.equal(app.get("import").value, "");
});

test("invalid JSON reports an error without posting an import", async () => {
  const app = await setup(); await app.importFile({ size: 1, async text() { return "{"; } });
  assert.equal(app.writes().length, 0);
  assert(app.get("message").textContent.length > 0);
  assert.equal(app.get("import").value, "");
});

test("new controls and preferences tab exist in the served HTML", () => {
  const html = fs.readFileSync(path.join(__dirname, "../app/static/admin/study.html"), "utf8");
  for (const id of ["preferencesForm", "homeCardRows", "savePreferences", "notificationsEnabled", "backgroundEnabled", "preferenceLayout", "subscriptionFilters", "subscriptionSource", "updatesFrom", "updatesTo", "updatesGrouped", "updatesUnread", "selectSubscriptions", "selectUpdates", "subscriptionsPause", "subscriptionsResume", "subscriptionsRead", "subscriptionsDelete", "updatesRead", "updatesUnreadAction", "updatesDelete"]) assert(html.includes(`id="${id}"`), id);
  assert(html.includes('data-view="preferences"'));
});

test("preferences reorder, visibility and opt-ins persist without overwriting player gestures", async () => {
  const app = await setup(); await app.tab("preferences");
  assert.equal(app.get("notificationsEnabled").checked, false);
  assert.equal(app.get("backgroundEnabled").checked, false);
  assert.equal(app.writes().length, 0);
  await app.get("homeCardRows").children[0].children[2].children[1].click();
  const hidden = app.get("homeCardRows").children[2].children[0]; hidden.checked = false; hidden.onchange();
  app.get("notificationsEnabled").checked = true; app.get("backgroundEnabled").checked = true;
  app.get("preferenceLayout").value = "compact";
  await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.deepEqual(app.writes()[0].body, {
    home_card_order: ["lists", "continue", "focus", "updates", "shortcuts"], home_hidden_cards: ["focus"],
    notifications_enabled: true, background_refresh_enabled: true, layout: "compact",
  });
  assert.equal(app.db.preferences.double_tap_left, "none");
  assert.equal(app.db.preferences.double_tap_left_width, 0.2);
  assert.equal(app.db.preferences.double_tap_right_width, 0.4);
  assert.equal(app.db.preferences.double_tap_height, 0.75);
  assert.equal(app.db.preferences.double_tap_seek_seconds, 30);
  assert.equal(app.db.preferences.long_press_speed, 3);
  assert.equal(app.get("homeCardRows").children[2].children[0].checked, false);
  assert.equal(app.get("preferencesStatus").textContent, "已保存");
});

test("preference loads reject obsolete responses and saving while not loaded", async () => {
  const app = await setup(), first = deferred(), second = deferred(); let count = 0;
  app.controls.intercept = (request) => request.pathname === "/study/preferences" ? (count++ ? second.promise : first.promise) : undefined;
  const a = app.tab("preferences"), b = app.run("loadPreferences()");
  await app.get("preferencesForm").onsubmit({ preventDefault() {} }); assert.equal(app.writes().length, 0);
  second.resolve({ ...app.db.preferences, layout: "comfortable", notifications_enabled: true }); await b;
  first.resolve({ ...app.db.preferences, layout: "compact" }); await a;
  assert.equal(app.get("preferenceLayout").value, "comfortable");
  assert.equal(app.get("notificationsEnabled").checked, true);
});

test("preference writes are serialized and failures keep unsaved changes retryable", async () => {
  const app = await setup(); await app.tab("preferences"); const pending = deferred();
  app.controls.intercept = (request) => request.method === "PUT" && request.pathname === "/study/preferences" ? pending.promise : undefined;
  app.get("notificationsEnabled").checked = true;
  const save = app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert(app.get("savePreferences").disabled);
  await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.equal(app.writes().length, 1);
  pending.reject(new Error("preferences unavailable")); await save;
  assert.equal(app.get("notificationsEnabled").checked, true);
  assert.equal(app.get("savePreferences").disabled, false);
  assert.equal(app.get("preferencesStatus").textContent, "");
  assert.match(app.get("message").textContent, /preferences unavailable/);
  app.controls.intercept = null; await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.equal(app.db.preferences.notifications_enabled, true);
});

test("an obsolete preference failure does not overwrite a newer success", async () => {
  const app = await setup(), first = deferred(), second = deferred(); let count = 0;
  app.controls.intercept = (request) => request.pathname === "/study/preferences" ? (count++ ? second.promise : first.promise) : undefined;
  const old = app.tab("preferences"), current = app.run("loadPreferences()");
  second.resolve({ ...app.db.preferences, layout: "compact" }); await current;
  first.reject(new Error("obsolete preference failure")); await old;
  assert.equal(app.get("message").textContent, "");
  assert.equal(app.get("preferenceLayout").value, "compact");
});

test("a failed later save clears the old saved status and a hidden form cannot write", async () => {
  const app = await setup(); await app.tab("preferences");
  await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.equal(app.get("preferencesStatus").textContent, "已保存");
  app.controls.intercept = (request) => request.method === "PUT" && request.pathname === "/study/preferences" ? Promise.reject(new Error("later failure")) : undefined;
  await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.equal(app.get("preferencesStatus").textContent, "");
  await app.tab("lists"); const count = app.writes().length;
  await app.get("preferencesForm").onsubmit({ preventDefault() {} });
  assert.equal(app.writes().length, count);
});

test("source, UTC date, unread and grouping filters use the actual API contract", async () => {
  const app = await setup();
  app.db.subscriptions.push({ id: 2, name: "Online", source: "bilibili", kind: "up", enabled: true });
  app.db.updates.push({ ...app.db.updates[0], id: 2, subscription_id: 2, source: "bilibili", title: "Online update" });
  app.get("subscriptionSource").value = "up"; app.get("updatesFrom").value = "2026-10-20";
  app.get("updatesTo").value = "2026-10-20"; app.get("updatesUnread").checked = true;
  await app.tab("subscriptions");
  const subRequest = app.requests.findLast((request) => request.pathname === "/study/subscriptions");
  const request = app.requests.findLast((request) => request.pathname === "/study/updates");
  assert.deepEqual(Object.fromEntries(subRequest.query), { source: "up" });
  assert.deepEqual(Object.fromEntries(request.query), { source: "up", date_from: "2026-10-20", date_to: "2026-10-20", read: "false", group_by: "date" });
  assert.match(app.get("subscriptionRows").textContent, /Online/);
  assert(!app.get("updateRows").textContent.includes("Old update"));
  assert.equal(app.get("updateRows").children[0].tagName, "H3");
  assert.equal(app.get("updateRows").children[0].textContent, "2026-10-20");
  app.get("updatesGrouped").checked = false;
  await app.get("subscriptionFilters").onsubmit({ preventDefault() {} });
  assert.equal(app.get("updateRows").children[0].tagName, "DIV");
});

for (const [button, action] of [["subscriptionsPause", "pause"], ["subscriptionsResume", "resume"], ["subscriptionsRead", "read"], ["subscriptionsDelete", "delete"]]) {
  test(`subscription ${action} batches submit only selected IDs`, async () => {
    const app = await setup(); await app.tab("subscriptions");
    const check = app.get("subscriptionRows").children[0].children[0]; check.checked = true; check.onchange();
    await app.get(button).click();
    assert.deepEqual(app.writes()[0].body, { subscription_ids: [1], action });
    assert.equal(app.writes()[0].pathname, "/study/subscriptions/batch");
    assert.equal(app.read("state.subscriptionSelected.size"), 0);
    if (["pause", "resume"].includes(action)) assert.equal(app.db.subscriptions[0].enabled, action === "resume");
  });
}

for (const [button, action] of [["updatesRead", "read"], ["updatesUnreadAction", "unread"], ["updatesDelete", "delete"]]) {
  test(`update ${action} batches submit only selected IDs`, async () => {
    const app = await setup(); await app.tab("subscriptions");
    app.get("selectUpdates").checked = true;
    app.get("selectUpdates").onchange({ target: app.get("selectUpdates") });
    await app.get(button).click();
    assert.deepEqual(app.writes()[0].body, { update_ids: [1], action });
    assert.equal(app.writes()[0].pathname, "/study/updates/batch");
    assert.equal(app.read("state.updateSelected.size"), 0);
  });
}

for (const order of [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]) {
  test(`subscription response order ${order.join("-")} cannot select or delete obsolete rows`, async () => {
    const app = await setup(); await app.tab("subscriptions");
    const oldRow = app.get("subscriptionRows").children[0], pending = Array.from({ length: 3 }, () => [deferred(), deferred()]);
    let subs = 0, updates = 0;
    app.controls.intercept = (request) => request.pathname === "/study/subscriptions" ? pending[subs++][0].promise
      : request.pathname === "/study/updates" ? pending[updates++][1].promise : undefined;
    const loads = [app.run("subscriptions()"), app.run("subscriptions()"), app.run("subscriptions()")];
    assert(app.get("subscriptionsDelete").disabled); assert(app.get("updatesDelete").disabled);
    oldRow.children[0].checked = true; oldRow.children[0].onchange();
    await oldRow.children[3].onclick(); await app.get("subscriptionsDelete").onclick();
    assert.equal(app.writes().length, 0);
    const current = { id: 2, name: "Newest subscription", source: "bilibili", kind: "up", enabled: true };
    for (const index of order) {
      pending[index][0].resolve(page(index === 2 ? [current] : app.db.subscriptions));
      pending[index][1].resolve(page(index === 2 ? [{ ...app.db.updates[0], id: 2, subscription_id: 2 }] : app.db.updates));
      await loads[index];
    }
    assert.deepEqual(app.read("state.subscriptions.map(row => row.id)"), [2]);
    assert.deepEqual(app.read("state.updates.map(row => row.id)"), [2]);
    await oldRow.children[3].onclick(); assert.equal(app.writes().length, 0);
    app.db.subscriptions.push(current); app.controls.intercept = null;
    await app.get("subscriptionRows").children[0].children[3].click();
    assert.deepEqual(app.writes().map((request) => request.pathname), ["/study/subscriptions/2"]);
    assert.equal(app.db.subscriptions[0].deleted, undefined);
  });
}

test("filter reload clears selections and blocks retained update actions while pending or failed", async () => {
  const app = await setup(); await app.tab("subscriptions");
  const row = app.get("updateRows").children.find((entry) => entry.tagName === "DIV");
  row.children[0].checked = true; row.children[0].onchange();
  const pending = deferred(); app.controls.intercept = (request) => request.pathname === "/study/updates" ? pending.promise : undefined;
  const loading = app.get("subscriptionFilters").onsubmit({ preventDefault() {} });
  assert.equal(app.read("state.updateSelected.size"), 0);
  await row.children[2].onclick(); await app.get("updatesDelete").onclick();
  assert.equal(app.writes().length, 0);
  pending.reject(new Error("update load failed")); await loading;
  assert.equal(app.get("updateRows").children.length, 0);
  await app.get("updatesDelete").onclick(); assert.equal(app.writes().length, 0);
});

test("cancelled deletes and repeated in-flight bulk clicks cannot mutate twice", async () => {
  const app = await setup(); await app.tab("subscriptions");
  app.get("selectSubscriptions").checked = true; app.get("selectSubscriptions").onchange({ target: app.get("selectSubscriptions") });
  app.controls.confirm = false; await app.get("subscriptionsDelete").click(); assert.equal(app.writes().length, 0);
  const pending = deferred(); app.controls.intercept = (request) => request.pathname === "/study/subscriptions/batch" ? pending.promise : undefined;
  const saving = app.get("subscriptionsPause").click();
  await app.get("subscriptionsPause").onclick(); assert.equal(app.writes().length, 1);
  pending.resolve({ updated: 1 }); await saving;
});
