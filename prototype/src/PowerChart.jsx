import { useEffect, useRef } from 'react';
import Chart from 'chart.js/auto';

export function PowerChart({ rows, theme, series = ['battery'], compact = false, onPoint }) {
  const canvas = useRef(null);
  const chart = useRef(null);
  const selection = useRef(30);
  const seriesKey = series.join(',');
  useEffect(() => {
    const dark = theme === 'dark';
    const colors = { input: dark ? '#83ACFF' : '#316BCF', battery: dark ? '#77D4C3' : '#147E76', system: dark ? '#C4BCD8' : '#726482' };
    const labels = { input: '电源输入', battery: '电池净功率', system: '整机耗电' };
    chart.current = new Chart(canvas.current, {
      type: 'line',
      data: { labels: rows.map(row => row.label), datasets: series.map(key => ({ label: labels[key], data: rows.map(row => row[key]), borderColor: colors[key], backgroundColor: dark ? '#77D4C31A' : '#147E7614', borderWidth: compact ? 1.7 : 2, borderDash: key === 'system' ? [4, 4] : undefined, pointRadius: 0, pointHoverRadius: 4, tension: .32, fill: compact ? 'origin' : false, spanGaps: false })) },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        interaction: { mode: 'index', intersect: false },
        onHover: (_, elements) => { if (elements.length && onPoint) onPoint(rows[elements[0].index]); },
        plugins: { legend: { display: false }, tooltip: { enabled: !compact, backgroundColor: dark ? '#111923' : '#FFFFFF', titleColor: dark ? '#F2F5FA' : '#202632', bodyColor: dark ? '#B5BFCC' : '#606C7E', borderColor: dark ? '#414B59' : '#D4DCE7', borderWidth: 1, padding: 10, displayColors: true, callbacks: { label: ctx => `${ctx.dataset.label}：${ctx.raw == null ? '—' : ctx.raw + ' W'}` } } },
        scales: {
          x: { grid: { display: false }, border: { display: false }, afterBuildTicks: axis => { if(compact) axis.ticks = [{value:0},{value:rows.length-1}]; }, ticks: { color: dark ? '#B5BFCC' : '#606C7E', maxTicksLimit: compact ? 2 : 4, maxRotation: 0, font: { size: 10, family: '-apple-system, sans-serif' } } },
          y: { position: compact ? 'right' : 'left', beginAtZero: true, min: compact ? Math.min(0,Math.floor(Math.min(...rows.map(r=>r.battery??0))/20)*20) : undefined, max: compact ? Math.max(0,Math.ceil(Math.max(...rows.map(r=>r.battery??0))/20)*20) || (rows.some(r=>r.battery<0)?0:20) : undefined, ticks: { color: dark ? '#B5BFCC' : '#606C7E', maxTicksLimit: compact ? 2 : 5, font: { size: 10 }, callback: value => `${value}${compact && value !== 0 ? ' W' : ''}` }, border: { display: false }, grid: { color: context => context.tick.value === 0 ? (dark ? '#6B778A' : '#A8B7C9') : (dark ? '#414B5960' : '#D4DCE780') } },
        },
      },
    });
    return () => chart.current?.destroy();
  }, [rows, theme, seriesKey, compact]);
  const keyDown = event => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    selection.current = Math.max(0, Math.min(rows.length - 1, selection.current + (event.key === 'ArrowLeft' ? -1 : 1)));
    onPoint?.(rows[selection.current]);
  };
  return <div className={compact ? 'chart compact-chart' : 'chart'}><canvas ref={canvas} role="img" aria-label={compact ? '最近 15 分钟电池功率示例趋势' : '功率趋势示例，左右方向键查看采样点'} tabIndex={compact ? -1 : 0} onKeyDown={keyDown} /></div>;
}
