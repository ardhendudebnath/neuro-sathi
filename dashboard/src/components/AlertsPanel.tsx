"use client";

import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { dateTime } from "@/lib/format";
import type { Alert } from "@/lib/types";

const LABEL: Record<Alert["severity"], string> = { info: "Info", watch: "Keep an eye", check_in: "Check in" };

export function AlertsPanel({ alerts, onChange }: { alerts: Alert[]; onChange: () => void }) {
  const [error, setError] = useState<string | null>(null);

  async function ack(id: string) {
    setError(null);
    try {
      await api.post(`/dashboard/alerts/${id}/ack`);
      onChange();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Could not update");
    }
  }

  return (
    <section className="card stack">
      <h2>Alerts</h2>
      {error && <div className="error">{error}</div>}
      {alerts.length === 0 ? (
        <p className="muted">No open alerts. Changes against their usual pattern will show here.</p>
      ) : (
        <ul className="list">
          {alerts.map((a) => (
            <li key={a.id} className="stack" style={{ gap: 8 }}>
              <div className="row spread">
                <span className={`badge ${a.severity}`}>{LABEL[a.severity]}</span>
                <span className="muted small">{dateTime(a.created_at)}</span>
              </div>
              <p style={{ margin: 0 }}>{a.message}</p>
              <div>
                <button className="secondary" onClick={() => ack(a.id)}>
                  I have checked in
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
