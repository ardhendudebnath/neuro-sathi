"use client";

import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { TopBar } from "@/components/TopBar";
import { api, ApiError } from "@/lib/api";
import { relative } from "@/lib/format";
import type { LinkedUserSummary } from "@/lib/types";

export default function HomePage() {
  const [people, setPeople] = useState<LinkedUserSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api
      .get<LinkedUserSummary[]>("/dashboard/users")
      .then(setPeople)
      .catch((e) => setError(e instanceof ApiError ? e.message : "Could not load"));
  }, []);

  useEffect(load, [load]);

  return (
    <>
      <TopBar />
      <main className="shell stack">
        <div>
          <h1>People you care for</h1>
          <p className="muted">Activity and changes compared with each person&apos;s own usual pattern.</p>
        </div>
        {error && <div className="error">{error}</div>}
        {people === null && !error && <p className="muted">Loading…</p>}
        {people?.length === 0 && (
          <div className="notice">
            No one linked yet. Ask them to open <strong>Settings → Link a caregiver</strong> in the NEURO-SATHI app and read you the
            code.
          </div>
        )}
        <div className="grid">
          {people?.map((p) => (
            <Link key={p.user.id} href={`/users/${p.user.id}`} className="card stack" style={{ textDecoration: "none", color: "inherit" }}>
              <div className="row spread">
                <h2 style={{ margin: 0 }}>{p.user.name ?? "Unnamed"}</h2>
                {p.open_alerts > 0 ? (
                  <span className="badge check_in">
                    {p.open_alerts} alert{p.open_alerts === 1 ? "" : "s"}
                  </span>
                ) : (
                  <span className="badge ok">No alerts</span>
                )}
              </div>
              <div className="muted small">
                {p.relationship ? `Your ${p.relationship}` : "Linked"} · {p.user.region ?? "Region not set"}
              </div>
              <div className="row spread small">
                <span>Last active: {relative(p.last_active)}</span>
                <span>{p.sessions_7d} activities this week</span>
              </div>
            </Link>
          ))}
        </div>
        <LinkForm onLinked={load} />
      </main>
    </>
  );
}

function LinkForm({ onLinked }: { onLinked: () => void }) {
  const [code, setCode] = useState("");
  const [relationship, setRelationship] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      await api.post("/links/redeem", { code: code.trim().toUpperCase(), relationship: relationship || undefined });
      setMsg({ ok: true, text: "Linked. You can now see their activity and manage their memory book." });
      setCode("");
      setRelationship("");
      onLinked();
    } catch (err) {
      setMsg({ ok: false, text: err instanceof ApiError ? err.message : "Could not link" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card stack">
      <h2>Link a new person</h2>
      <form className="form" onSubmit={submit}>
        <label>
          Code from their app
          <input value={code} onChange={(e) => setCode(e.target.value)} maxLength={12} placeholder="ABCD2345" required />
        </label>
        <label>
          They are your…
          <input value={relationship} onChange={(e) => setRelationship(e.target.value)} placeholder="mother, patient…" maxLength={60} />
        </label>
        <button disabled={busy || code.trim().length < 6}>Link</button>
      </form>
      {msg && <div className={msg.ok ? "notice" : "error"}>{msg.text}</div>}
    </section>
  );
}
