"use client";

// Small dependency-free SVG line chart: one series, gaps where there is no data.

interface Props {
  title: string;
  points: { day: string; value: number | null }[];
  format: (v: number) => string;
  color?: string;
  higherIsBetter?: boolean;
}

const W = 520;
const H = 160;
const PAD = { top: 12, right: 12, bottom: 24, left: 44 };

export function TrendChart({ title, points, format, color = "var(--chart-1)", higherIsBetter = true }: Props) {
  const values = points.map((p) => p.value).filter((v): v is number => v !== null);
  if (values.length === 0) {
    return (
      <figure className="card" style={{ margin: 0 }}>
        <figcaption>
          <h3>{title}</h3>
        </figcaption>
        <p className="muted small">No data yet for this period.</p>
      </figure>
    );
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  const lo = min === max ? min * 0.9 : min - (max - min) * 0.1;
  const hi = min === max ? max * 1.1 || 1 : max + (max - min) * 0.1;
  const x = (i: number) => PAD.left + (i * (W - PAD.left - PAD.right)) / Math.max(points.length - 1, 1);
  const y = (v: number) => PAD.top + (1 - (v - lo) / (hi - lo || 1)) * (H - PAD.top - PAD.bottom);

  // Break the path wherever a day has no data.
  let d = "";
  let pen = false;
  points.forEach((p, i) => {
    if (p.value === null) {
      pen = false;
      return;
    }
    d += `${pen ? "L" : "M"}${x(i).toFixed(1)},${y(p.value).toFixed(1)} `;
    pen = true;
  });

  const recent = values.slice(-7);
  const earlier = values.slice(0, -7);
  const avg = (a: number[]) => a.reduce((s, v) => s + v, 0) / a.length;
  let summary = `Latest ${format(values[values.length - 1])}.`;
  if (earlier.length >= 3 && recent.length >= 2) {
    const change = avg(recent) - avg(earlier);
    const better = higherIsBetter ? change > 0 : change < 0;
    summary = `Last 7 days ${format(avg(recent))}, earlier ${format(avg(earlier))}${Math.abs(change) > 1e-9 ? (better ? " (better)" : " (worse)") : ""}.`;
  }
  const ticks = [lo + (hi - lo) * 0.1, (lo + hi) / 2, hi - (hi - lo) * 0.1];

  return (
    <figure className="card" style={{ margin: 0 }}>
      <figcaption>
        <h3>{title}</h3>
        <p className="muted small">{summary}</p>
      </figcaption>
      <svg className="chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${title}. ${summary}`}>
        {ticks.map((t) => (
          <g key={t}>
            <line className="grid-line" x1={PAD.left} x2={W - PAD.right} y1={y(t)} y2={y(t)} />
            <text x={PAD.left - 6} y={y(t) + 4} textAnchor="end">
              {format(t)}
            </text>
          </g>
        ))}
        <text x={PAD.left} y={H - 6}>
          {points[0].day.slice(5)}
        </text>
        <text x={W - PAD.right} y={H - 6} textAnchor="end">
          {points[points.length - 1].day.slice(5)}
        </text>
        <path className="line" d={d} stroke={color} />
        {points.map((p, i) =>
          p.value === null ? null : (
            <circle key={p.day} className="dot" cx={x(i)} cy={y(p.value)} r={3} fill={color}>
              <title>{`${p.day}: ${format(p.value)}`}</title>
            </circle>
          ),
        )}
      </svg>
    </figure>
  );
}
