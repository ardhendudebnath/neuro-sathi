"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { clock, DAY_NAMES, days } from "@/lib/format";
import type { Reminder, ReminderKind } from "@/lib/types";

const KINDS: { value: ReminderKind; label: string }[] = [
  { value: "medication", label: "Medicine" },
  { value: "hydration", label: "Drink water" },
  { value: "meal", label: "Meal" },
  { value: "activity", label: "Activity" },
  { value: "appointment", label: "Appointment" },
  { value: "custom", label: "Other" },
];
const kindLabel = (k: ReminderKind) => KINDS.find((x) => x.value === k)?.label ?? k;

export function RemindersPanel({ userId }: { userId: string }) {
  const [items, setItems] = useState<Reminder[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api
      .get<Reminder[]>(`/users/${userId}/reminders`)
      .then(setItems)
      .catch((e) => setError(e instanceof ApiError ? e.message : "Could not load"));
  }, [userId]);
  useEffect(load, [load]);

  async function run(fn: () => Promise<unknown>) {
    setError(null);
    try {
      await fn();
      load();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Could not update");
    }
  }

  return (
    <div className="stack">
      <AddReminder userId={userId} onAdded={load} />
      {error && <div className="error">{error}</div>}
      <section className="card">
        <h2>Reminders</h2>
        {items?.length === 0 && <p className="muted">No reminders yet.</p>}
        <ul className="list">
          {items?.map((r) => (
            <li key={r.id} className="row spread">
              <div>
                <strong>
                  {clock(r.time_of_day)} · {r.title}
                </strong>
                <div className="muted small">
                  {kindLabel(r.kind)} · {days(r.days_of_week)}
                  {r.note ? ` · ${r.note}` : ""}
                  {!r.active && " · paused"}
                </div>
              </div>
              <div className="row">
                <button className="secondary" onClick={() => run(() => api.patch(`/users/${userId}/reminders/${r.id}`, { active: !r.active }))}>
                  {r.active ? "Pause" : "Resume"}
                </button>
                <button
                  className="danger"
                  onClick={() => confirm("Delete this reminder?") && run(() => api.del(`/users/${userId}/reminders/${r.id}`))}
                >
                  Delete
                </button>
              </div>
            </li>
          ))}
        </ul>
        <p className="muted small">Changes reach the phone at its next sync; reminders then fire on the phone even without internet.</p>
      </section>
    </div>
  );
}

function AddReminder({ userId, onAdded }: { userId: string; onAdded: () => void }) {
  const [kind, setKind] = useState<ReminderKind>("medication");
  const [title, setTitle] = useState("");
  const [time, setTime] = useState("08:00");
  const [dayList, setDayList] = useState<number[]>([0, 1, 2, 3, 4, 5, 6]);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggleDay = (d: number) => setDayList(dayList.includes(d) ? dayList.filter((x) => x !== d) : [...dayList, d].sort());

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.post(`/users/${userId}/reminders`, {
        kind,
        title,
        time_of_day: `${time}:00`,
        days_of_week: dayList,
        note: note || undefined,
      });
      setTitle("");
      setNote("");
      onAdded();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not add");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card stack">
      <h2>Add a reminder</h2>
      {error && <div className="error">{error}</div>}
      <form className="form" onSubmit={submit}>
        <label>
          Type
          <select value={kind} onChange={(e) => setKind(e.target.value as ReminderKind)}>
            {KINDS.map((k) => (
              <option key={k.value} value={k.value}>
                {k.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          What
          <input value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={160} placeholder="Metformin 500 mg" />
        </label>
        <label>
          Time
          <input type="time" value={time} onChange={(e) => setTime(e.target.value)} required />
        </label>
        <label>
          Note
          <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={255} placeholder="after breakfast" />
        </label>
        <fieldset className="row" style={{ gridColumn: "1 / -1", border: "none", padding: 0, margin: 0 }}>
          <legend className="small" style={{ fontWeight: 600, marginBottom: 6 }}>
            Days
          </legend>
          {DAY_NAMES.map((name, d) => (
            <button
              key={name}
              type="button"
              className={dayList.includes(d) ? "" : "secondary"}
              aria-pressed={dayList.includes(d)}
              onClick={() => toggleDay(d)}
              style={{ minWidth: 56 }}
            >
              {name}
            </button>
          ))}
        </fieldset>
        <button disabled={busy || !title || dayList.length === 0}>{busy ? "Saving…" : "Add reminder"}</button>
      </form>
    </section>
  );
}
