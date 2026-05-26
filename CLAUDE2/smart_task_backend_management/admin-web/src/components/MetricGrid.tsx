interface MetricGridProps {
  stats: Record<string, number>;
  onMetricClick?: (key: string) => void;
}

const METRICS = [
  { key: 'users', label: '用户', tab: 'user' as const },
  { key: 'teams', label: '团队', tab: 'team' as const },
  { key: 'onlineDevices', label: '在线设备', tab: null },
  { key: 'tasks', label: '任务', tab: 'list' as const },
  { key: 'distributions', label: '分发', tab: 'distribution' as const },
  { key: 'todayComments', label: '今日评论', tab: null },
] as const;

function Metric({ label, value, clickable, onClick }: { label: string; value: number; clickable: boolean; onClick?: () => void }) {
  const style: React.CSSProperties = clickable
    ? { cursor: 'pointer', transition: 'box-shadow 0.15s' }
    : {};
  return (
    <div
      className="metric"
      style={style}
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onClick={clickable ? onClick : undefined}
      onKeyDown={clickable ? (e) => { if (e.key === 'Enter') onClick?.(); } : undefined}
    >
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

export default function MetricGrid({ stats, onMetricClick }: MetricGridProps) {
  return (
    <section className="metric-grid">
      {METRICS.map((m) => (
        <Metric
          key={m.key}
          label={m.label}
          value={stats[m.key] ?? 0}
          clickable={!!m.tab && !!onMetricClick}
          onClick={m.tab && onMetricClick ? () => onMetricClick(m.key) : undefined}
        />
      ))}
    </section>
  );
}
