const ALARM = "guardian-paws-minute";
const STATE_KEY = "usage-v1";
const RULE_BASE = 1000;

function today() { return new Date().toISOString().slice(0, 10); }
function hostFor(url) { try { const host = new URL(url).hostname.toLowerCase(); return host.replace(/^www\./, ""); } catch { return null; } }
function configuredLimit(host, policy) {
  const rules = Array.isArray(policy?.siteLimits) ? policy.siteLimits : [];
  return rules.find(item => item && item.host === host && Number.isInteger(item.minutes) && item.minutes > 0) ?? null;
}
function alwaysAllowed(host, policy) { return Array.isArray(policy?.alwaysAllowedSites) && policy.alwaysAllowedSites.includes(host); }
async function policy() { const data = await chrome.storage.managed.get("policy"); return data.policy && typeof data.policy === "object" ? data.policy : { siteLimits: [], alwaysAllowedSites: [] }; }
async function usage() {
  const data = await chrome.storage.local.get(STATE_KEY);
  const state = data[STATE_KEY] && typeof data[STATE_KEY] === "object" ? data[STATE_KEY] : { day: today(), minutes: {} };
  if (state.day !== today()) return { day: today(), minutes: {} };
  return state;
}
async function saveUsage(state) { await chrome.storage.local.set({ [STATE_KEY]: state }); }
async function refreshRules(currentPolicy, currentUsage) {
  const blocked = [];
  for (const item of Array.isArray(currentPolicy.siteLimits) ? currentPolicy.siteLimits : []) {
    if (!item || typeof item.host !== "string" || !Number.isInteger(item.minutes) || item.minutes < 1) continue;
    if (alwaysAllowed(item.host, currentPolicy)) continue;
    if ((currentUsage.minutes[item.host] ?? 0) >= item.minutes) blocked.push(item.host);
  }
  const removeRuleIds = Array.from({ length: 1000 }, (_, index) => RULE_BASE + index);
  const addRules = blocked.slice(0, 1000).map((host, index) => ({
    id: RULE_BASE + index,
    priority: 1,
    action: { type: "redirect", redirect: { extensionPath: "/blocked.html" } },
    condition: { urlFilter: `||${host}^`, resourceTypes: ["main_frame"] }
  }));
  await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds, addRules });
}
async function tick() {
  const [currentPolicy, currentUsage] = await Promise.all([policy(), usage()]);
  const windowInfo = await chrome.windows.getLastFocused().catch(() => null);
  if (windowInfo?.focused) {
    const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    const host = tabs[0] && hostFor(tabs[0].url || "");
    const limit = host && configuredLimit(host, currentPolicy);
    if (host && limit && !alwaysAllowed(host, currentPolicy)) currentUsage.minutes[host] = (currentUsage.minutes[host] ?? 0) + 1;
  }
  await saveUsage(currentUsage);
  await refreshRules(currentPolicy, currentUsage);
}
chrome.runtime.onInstalled.addListener(async () => { await chrome.alarms.create(ALARM, { periodInMinutes: 1 }); await tick(); });
chrome.runtime.onStartup.addListener(async () => { await chrome.alarms.create(ALARM, { periodInMinutes: 1 }); await tick(); });
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === ALARM) void tick(); });
chrome.storage.onChanged.addListener((_, area) => { if (area === "managed") void tick(); });
chrome.tabs.onActivated.addListener(() => void tick());
chrome.windows.onFocusChanged.addListener(() => void tick());
