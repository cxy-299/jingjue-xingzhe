// 在 Node 中运行页面脚本，验证固定地图与预览规划逻辑；不接触串口或电机。
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const html = fs.readFileSync(path.join(__dirname, "..", "web", "dashboard.html"), "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script, "页面内应包含规划脚本");
const mapData = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "config", "nav-map-2m.json"), "utf8"));
mapData.occupied = fs.readFileSync(path.join(__dirname, "..", "fpga", "nav", "nav_map_20x20.mem"), "utf8")
  .trim().split(/\s+/).map(Number);
assert.equal(mapData.occupied.length, 400);

const elements = new Map();
const context2d = new Proxy({}, { get: () => () => {} });
function element(id) {
  if (!elements.has(id)) {
    elements.set(id, {
      id,
      width: 640,
      height: 640,
      textContent: "",
      value: "",
      checked: false,
      disabled: false,
      listeners: {},
      classList: { toggle() {} },
      getContext: () => context2d,
      querySelector: () => ({ innerHTML: "" }),
      addEventListener(name, callback) { this.listeners[name] = callback; },
    });
  }
  return elements.get(id);
}
const context = vm.createContext({
  document: { getElementById: element, addEventListener() {} },
  location: { protocol: "file:" },
  console,
  Date,
  Math,
  Uint8Array,
  Int16Array,
  mapData,
});
vm.runInContext(script, context, { filename: "dashboard.html" });
vm.runInContext("navMap=mapData; updateMap()", context);

// UI 从与 FPGA 完全相同的 .mem 位图计算示例路线。
let result = vm.runInContext("findRoute(blockedMap(), {x:2,y:17})", context);
assert.equal(result.length - 1, 34);
assert.equal(result[0].x, 18);
assert.equal(result[0].y, 1);
assert.equal(result.at(-1).x, 2);
assert.equal(result.at(-1).y, 17);

const blocked = vm.runInContext("blockedMap()", context);
for (const cell of result) assert.equal(blocked[cell.y * 20 + cell.x], 0);

// 选择终点只更新界面；下发仍需后端开关、串口及人工确认三重条件。
vm.runInContext("chooseGoal(2,17)", context);
assert.equal(element("goalX").value, 2);
assert.equal(element("goalY").value, 17);
assert.equal(element("mapGoalCell").textContent, "(2, 17)");
assert.equal(element("sendGoal").disabled, true);
vm.runInContext("navTxEnabled=true; navSerialConnected=true; updateMap()", context);
assert.equal(element("sendGoal").disabled, true);
element("fpgaReady").checked = true;
vm.runInContext("updateMap()", context);
assert.equal(element("sendGoal").disabled, false);
vm.runInContext("chooseGoal(11,4)", context);
assert.equal(element("sendGoal").disabled, true);
assert.equal(element("fpgaReady").checked, false);

// 障碍内部终点不能绘制伪路线。
result = vm.runInContext("findRoute(blockedMap(), {x:11,y:4})", context);
assert.equal(result.length, 0);

// 复现真实发送流程：空口令、取消确认与后端拒绝都必须留下持续可见的反馈。
async function checkSendFeedback() {
  let submissions = 0;
  let accepted = false;
  context.confirm = () => true;
  context.fetch = async (url, options) => {
    if (url === "/api/status") return { json: async () => ({
      nav_goal_tx_enabled: true, serial_connected: true,
      nav_goal_state: "已开放目标下发", detections: [],
    }) };
    assert.equal(url, "/api/nav/goal");
    submissions += 1;
    assert.deepEqual(JSON.parse(options.body), { map_id: 0x2601, x: 3, y: 12 });
    return { ok: accepted, status: accepted ? 202 : 403,
      json: async () => accepted ? { state: "queued" } : { error: "导航控制口令不正确" } };
  };
  vm.runInContext("chooseGoal(3,12); navTxEnabled=true; navSerialConnected=true", context);
  element("fpgaReady").checked = true;
  const send = element("sendGoal").listeners.click;
  await send();
  assert.match(element("navSubmitStatus").textContent, /请先填写导航控制口令/);
  assert.equal(submissions, 0);

  element("navToken").value = "unit-test-only";
  context.confirm = () => false;
  await send();
  assert.match(element("navSubmitStatus").textContent, /已取消确认/);
  assert.equal(submissions, 0);

  context.confirm = () => true;
  await send();
  assert.match(element("navSubmitStatus").textContent, /HTTP 403.*导航控制口令不正确/);
  await vm.runInContext("refresh()", context);
  assert.match(element("navSubmitStatus").textContent, /HTTP 403.*导航控制口令不正确/);
  assert.equal(element("navStatus").textContent, "已开放目标下发");

  accepted = true;
  element("fpgaReady").checked = true;
  await send();
  assert.match(element("navSubmitStatus").textContent, /终点已排队/);
  assert.equal(submissions, 2);
  assert.equal(element("fpgaReady").checked, false);
  console.log("PASS nav preview: map, send interlock, persistent HTTP feedback");
}
checkSendFeedback().catch(error => { console.error(error); process.exitCode = 1; });
