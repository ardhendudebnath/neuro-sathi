"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { AlertsPanel } from "@/components/AlertsPanel";
import { MemoryBookPanel } from "@/components/MemoryBookPanel";
import { RemindersPanel } from "@/components/RemindersPanel";
import { TopBar } from "@/components/TopBar";
import { TrendChart } from "@/components/TrendChart";
import { api, ApiError } from "@/lib/api";
import { GAME_NAMES } from "@/lib/format";
import type { Alert, DailyTrend, LinkedUserSummary, Recommendation } from "@/lib/types";

type Tab = "overview" | "memories" | "reminders";

export default function PersonPage() {
  const { id } = useParams<{ id: string }>();
  const [tab, setTab] = useState<Tab>("overview");
  const [person, setPerson] = useState<LinkedUserSummary | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .get<LinkedUserSummary[]>("/dashboard/users")
      .then((all) => {
        const p = all.find((x) => x.user.id === id);
        if (p) setPerson(p);
        else setError("This person is not linked to your account.");
      })
      .catch((e) => setError(e instanceof ApiError ? e.message : "Could not load"));
  }, [id]);

  return (
    <>
      <TopBar />
      <main className="shell">
        <p>
          <Link href="/">← All people</Link>
        </p>
        {error && <div className="error">{error}</div>}
        {person && (
          <>
            <h1>{person.user.name ?? "Unnamed"}</h1>
            <p className="muted">
              {person.relationship ? `Your ${person.relationship}` : "Linked"} · {person.user.region ?? "Region not set"} · App language:{" "}
              {person.user.language}
            </p>
            <div className="tabs" role="tablist">
              {(["overview", "memories", "reminders"] as Tab[]).map((t) => (
                <button key={t} role="tab" aria-selected={tab === t} onClick={() => setTab(t)}>
                  {t === "overview" ? "Overview" : t === "memories" ? "Memory book" : "Reminders"}
                </button>
              ))}
            </div>
            {tab === "overview" && <Overview userId={id} />}
            {tab === "memories" && <MemoryBookPanel userId={id} />}
            {tab === "reminders" && <RemindersPanel userId={id} />}
          </>
        )}
      </main>
    </>
  );
}

function Overview({ userId }: { userId: string }) {
  const [days, setDays] = useState(30);
  const [trends, setTrends] = useState<DailyTrend[] | null>(null);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [recs, setRecs] = useState<Recommendation[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    Promise.all([
      api.get<DailyTrend[]>(`/dashboard/users/${userId}/trends?days=${days}`),
      api.get<Alert[]>(`/dashboard/users/${userId}/alerts`),
      api.get<Recommendation[]>(`/dashboard/users/${userId}/recommendations`),
    ])
      .then(([t, a, r]) => {
        setTrends(t);
        setAlerts(a);
        setRecs(r);
      })
      .catch((e) => setError(e instanceof ApiError ? e.message : "Could not load"));
  }, [userId, days]);
  useEffect(load, [load]);

  const series = (pick: (d: DailyTrend) => number | null) => (trends ?? []).map((d) => ({ day: d.day, value: pick(d) }));
  const pct = (v: number) => `${Math.round(v * 100)}%`;
  const secs = (v: number) => `${(v / 1000).toFixed(1)}s`;
  const num = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1));
  const done = (trends ?? []).reduce((s, d) => s + d.reminders_done, 0);
  const missed = (trends ?? []).reduce((s, d) => s + d.reminders_missed, 0);

  return (
    <div className="stack">
      {error && <div className="error">{error}</div>}
      <AlertsPanel alerts={alerts} onChange={load} />
      <div className="row spread">
        <h2 style={{ margin: 0 }}>Trends</h2>
        <label className="row" style={{ flexDirection: "row", alignItems: "center" }}>
          Period
          <select value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={14}>2 weeks</option>
            <option value={30}>30 days</option>
            <option value={90}>90 days</option>
          </select>
        </label>
      </div>
      <p className="notice">
        Trends compare this person with their own usual pattern. They help you decide when to check in; they are not a diagnosis.
      </p>
      {trends && (
        <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))" }}>
          <TrendChart title="Activities per day" points={series((d) => d.sessions)} format={num} />
          <TrendChart title="Correct answers" points={series((d) => d.accuracy)} format={pct} />
          <TrendChart
            title="Average answer time"
            points={series((d) => d.avg_response_ms)}
            format={secs}
            color="var(--chart-2)"
            higherIsBetter={false}
          />
          <TrendChart title="Activities finished" points={series((d) => d.completion_rate)} format={pct} />
        </div>
      )}
      <section className="card">
        <h2>Reminders in this period</h2>
        <p>
          <strong>{done}</strong> done · <strong>{missed}</strong> missed
          {done + missed > 0 && <span className="muted"> ({pct(done / (done + missed))} done)</span>}
        </p>
      </section>
      <section className="card">
        <h2>Suggested activities</h2>
        {recs.length === 0 ? (
          <p className="muted">Suggestions appear after the phone syncs.</p>
        ) : (
          <ol>
            {recs.map((r) => (
              <li key={r.game_slug}>
                <strong>{GAME_NAMES[r.game_slug] ?? r.game_slug}</strong> (level {r.level}) <span className="muted">· {r.reason}</span>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  );
}
