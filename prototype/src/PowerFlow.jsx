import { useMemo, useRef, useState, useLayoutEffect } from 'react';
import { ReactFlow, Handle, Position, MarkerType } from '@xyflow/react';
import { Plug, Laptop, BatteryCharging, BatteryHigh, CaretRight } from '@phosphor-icons/react';
import '@xyflow/react/dist/style.css';
import { watt } from './model';

function MetricNode({ data }) {
  const Icon = data.kind === 'input' ? Plug : data.kind === 'system' ? Laptop : data.charging ? BatteryCharging : BatteryHigh;
  return <div className={`metric-node ${data.kind} ${data.tone || ''}`}>
    <Handle type="target" position={data.kind === 'input' ? Position.Bottom : Position.Top} id="in" />
    {data.kind === 'system' && <Handle type="target" position={Position.Right} id="battery-in" style={{ top: 26 }} />}
    <button className="metric-button" onClick={() => data.onDetail(data.kind)} aria-label={`查看${data.label}说明`}>
      <Icon size={data.kind === 'input' ? 43 : 44} weight={data.kind === 'input' ? 'fill' : 'regular'} aria-hidden="true" />
      <span className="metric-copy"><span className="metric-label">{data.label}</span><span className="metric-value">{data.disconnected ? '未接入' : watt(data.value, data.kind === 'battery')}{!data.disconnected && <small>W</small>}</span></span>
    </button>
    {data.kind === 'input' && <button className="adapter-caption" onClick={() => data.onDetail('adapter')}>{data.disconnected ? '当前由电池供电' : <>供电能力 {data.capacity} W <span>· 系统报告 <CaretRight size={11} /></span></>}</button>}
    <Handle type="source" position={data.kind === 'battery' ? Position.Left : Position.Bottom} id="out" />
  </div>;
}
const nodeTypes = { metric: MetricNode };

export function PowerFlow({ scenario, theme, onDetail }) {
  const container = useRef(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => { const observer = new ResizeObserver(entries => { const w = entries[0].contentRect.width; if(w > 0) setWidth(w); }); observer.observe(container.current); return () => observer.disconnect(); }, []);
  const zoom = Math.min(1, width / 368);
  const nodes = useMemo(() => [
    { id: 'input', type: 'metric', position: { x: 62, y: 0 }, data: { kind: 'input', label: '电源输入', value: scenario.input, capacity: scenario.capacity, disconnected: scenario.capacity == null, onDetail }, style: { width: 244, height: 88 } },
    { id: 'system', type: 'metric', position: { x: 10, y: 124 }, data: { kind: 'system', label: scenario.estimated ? '整机耗电 · 估算' : '整机耗电', value: scenario.system, onDetail }, style: { width: 150, height: 100 } },
    { id: 'battery', type: 'metric', position: { x: 208, y: 124 }, data: { kind: 'battery', label: scenario.estimatedBattery ? `${scenario.batteryLabel} · 估算` : scenario.batteryLabel, value: scenario.battery, charging: scenario.battery > 0, tone: scenario.tone, onDetail }, style: { width: 150, height: 100 } },
  ], [scenario, onDetail]);
  const edges = useMemo(() => {
    const blue = theme === 'dark' ? '#83ACFF' : '#316BCF';
    const batteryColor = scenario.tone === 'warning' ? (theme === 'dark' ? '#F0BD72' : '#98600D') : (theme === 'dark' ? '#77D4C3' : '#147E76');
    const edge = (source, target, color) => ({ id: `${source}-${target}`, source, target, sourceHandle: 'out', targetHandle: source === 'battery' ? 'battery-in' : 'in', type: source === 'battery' ? 'straight' : 'smoothstep', markerEnd: { type: MarkerType.ArrowClosed, color, width: 16, height: 16 }, style: { stroke: color, strokeWidth: 1.7 }, pathOptions: { borderRadius: 10, offset: 8 }, focusable: false });
    if (scenario.stale || scenario.input == null) return [];
    const result = [];
    if (scenario.capacity != null) result.push(edge('input', 'system', blue));
    if (scenario.battery > 0) result.push(edge('input', 'battery', blue));
    if (scenario.battery < 0) result.push(edge('battery', 'system', batteryColor));
    return result;
  }, [scenario, theme]);
  return <div ref={container} className="power-flow" style={{height:width > 0 ? 226 * zoom : 226}} aria-label="电源、整机与电池的功率流向">{width > 0 && <ReactFlow style={{width,height:226 * zoom,background:'transparent'}} nodes={nodes} edges={edges} nodeTypes={nodeTypes} nodesDraggable={false} nodesConnectable={false} elementsSelectable={false} nodesFocusable={false} edgesFocusable={false} panOnDrag={false} zoomOnScroll={false} zoomOnPinch={false} zoomOnDoubleClick={false} preventScrolling={false} viewport={{ x: (width-368*zoom)/2, y: 0, zoom }} colorMode={theme} />}</div>;
}
