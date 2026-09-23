export const appearanceOptions = ['system', 'light', 'dark'];
export const normalizeAppearance = value => appearanceOptions.includes(value) ? value : 'system';
export const resolveAppearance = (preference, systemDark) => normalizeAppearance(preference) === 'system' ? (systemDark ? 'dark' : 'light') : preference;
export const watt = (value, signed = false) => value == null ? '—' : `${signed && value > 0 ? '+' : value < 0 ? '−' : ''}${Math.abs(value).toFixed(1)}`;

export const scenarios = {
  charging: { name: '插电充电', status: '外接电源 · 正在充电', input: 61.6, battery: 27.6, system: 34, capacity: 65, percent: 65, batteryLabel: '充入电池', chargingLabel: '正在充电', time: '预计充满约 2 小时 · 估算', tone: 'good', source: '功率来自设备遥测' },
  battery: { name: '电池供电', status: '电池供电', input: 0, battery: -12.4, system: 12.4, capacity: null, percent: 54, batteryLabel: '电池放电', chargingLabel: '正在放电', time: '预计还可使用约 4 小时 · 估算', tone: 'normal', source: '整机耗电由电池功率估算', estimated: true },
  paused: { name: '充电暂停', status: '外接电源 · 充电已暂停', input: 18.2, battery: 0, system: 18.2, capacity: 65, percent: 80, batteryLabel: '电池净功率', chargingLabel: '充电已暂停', time: 'macOS 已暂停充电 · 示例状态', tone: 'normal', source: '功率来自设备遥测' },
  supplement: { name: '插电仍在放电', status: '外接电源 · 电池补充供电', input: 30, battery: -15, system: 45, capacity: 30, percent: 42, batteryLabel: '电池放电', chargingLabel: '正在补充供电', time: '外部供电暂未覆盖全部用电', tone: 'warning', source: '功率来自设备遥测' },
  missing: { name: '部分数据缺失', status: '外接电源 · 正在充电', input: null, battery: 24.8, system: null, capacity: 65, percent: 65, batteryLabel: '充入电池', chargingLabel: '正在充电', time: '充满时间暂未提供', tone: 'good', source: '输入与整机功率暂未提供', estimatedBattery: true },
  stale: { name: '数据暂未更新', status: '数据暂未更新', input: null, battery: null, system: null, capacity: 65, percent: 65, batteryLabel: '电池净功率', chargingLabel: '等待更新', time: '最后更新于 19:42 · 数据已过期', tone: 'normal', source: '等待新的有效读数', stale: true },
  full: { name: '电池已充满', status: '外接电源 · 已充满', input: 14.1, battery: 0, system: 14.1, capacity: 65, percent: 100, batteryLabel: '电池净功率', chargingLabel: '已充满', time: '当前由外接电源供电', tone: 'good', source: '功率来自设备遥测' },
};

export function makeHistory(scenario, period = 15) {
  const end = Date.parse('2026-09-23T19:42:00+08:00');
  return Array.from({ length: 31 }, (_, i) => {
    const delta = Math.sin(i * 1.6) * 1.2 + Math.cos(i * .5) * .7;
    const input = scenario.input == null ? null : scenario.input === 0 ? 0 : +(scenario.input + (i === 30 ? 0 : delta)).toFixed(1);
    const battery = scenario.battery == null ? null : scenario.battery === 0 ? 0 : +(scenario.battery + (i === 30 ? 0 : delta * .8)).toFixed(1);
    const system = scenario.system == null ? null : +(input == null || battery == null ? scenario.system : input - battery).toFixed(1);
    const timestamp = new Date(end - (30 - i) * period * 60_000 / 30);
    return { timestamp: timestamp.toISOString(), label: timestamp.toLocaleTimeString('zh-CN', { timeZone: 'Asia/Hong_Kong', hour: '2-digit', minute: '2-digit', hour12: false }), input, battery, system };
  });
}

export function historyCsv(history, scenario) {
  return '\ufeff' + ['timestamp_utc,timezone,state,input_W,battery_net_W,system_W,adapter_capability_W,quality', ...history.map(row => [row.timestamp, 'Asia/Hong_Kong', scenario.name, row.input ?? '', row.battery ?? '', row.system ?? '', scenario.capacity ?? '', 'demo'].join(','))].join('\r\n');
}
