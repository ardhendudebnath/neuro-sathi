"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import type { MemoryEntry } from "@/lib/types";

const EMPTY = { kind: "person", title: "", person_name: "", relationship: "", event_date: "", place: "", description: "" };

export function MemoryBookPanel({ userId }: { userId: string }) {
  const [entries, setEntries] = useState<MemoryEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api
      .get<MemoryEntry[]>(`/users/${userId}/memory-book`)
      .then(setEntries)
      .catch((e) => setError(e instanceof ApiError ? e.message : "Could not load"));
  }, [userId]);
  useEffect(load, [load]);

  async function remove(id: string) {
    if (!confirm("Remove this memory? It will also disappear from their phone.")) return;
    try {
      await api.del(`/users/${userId}/memory-book/${id}`);
      load();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Could not remove");
    }
  }

  return (
    <div className="stack">
      <AddMemory userId={userId} onAdded={load} />
      {error && <div className="error">{error}</div>}
      {entries?.length === 0 && <p className="muted">No memories yet. Family photos with names work best.</p>}
      <div className="grid">
        {entries?.map((e) => (
          <article key={e.id} className="card stack" style={{ gap: 8 }}>
            {e.photo_key && <Photo userId={userId} entryId={e.id} alt={e.title} />}
            <h3 style={{ margin: 0 }}>{e.title}</h3>
            <div className="muted small">
              {[e.person_name && e.person_name !== e.title ? e.person_name : null, e.relationship, e.place, e.event_date]
                .filter(Boolean)
                .join(" · ")}
            </div>
            {e.description && <p className="small">{e.description}</p>}
            <div className="row spread">
              <span className="muted small">Added by {e.updated_by_role === "user" ? "them" : "a caregiver"}</span>
              <button className="danger" onClick={() => remove(e.id)}>
                Remove
              </button>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}

function Photo({ userId, entryId, alt }: { userId: string; entryId: string; alt: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    // Short-lived signed URL, fetched only after the API's ownership check.
    api
      .get<{ url: string }>(`/users/${userId}/memory-book/${entryId}/photo`)
      .then((r) => setUrl(r.url))
      .catch(() => setUrl(null));
  }, [userId, entryId]);
  if (!url) return <div className="photo" aria-hidden />;
  // eslint-disable-next-line @next/next/no-img-element -- signed, expiring URL; next/image would cache it
  return <img className="photo" src={url} alt={alt} />;
}

function AddMemory({ userId, onAdded }: { userId: string; onAdded: () => void }) {
  const [form, setForm] = useState(EMPTY);
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof EMPTY) => (e: { target: { value: string } }) => setForm({ ...form, [k]: e.target.value });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      let photo_key: string | undefined;
      if (file) {
        if (file.size > 10 * 1024 * 1024) throw new ApiError(413, "Photo must be 10 MB or smaller");
        const fd = new FormData();
        fd.append("file", file);
        photo_key = (await api.upload<{ photo_key: string }>(`/users/${userId}/memory-book/upload`, fd)).photo_key;
      }
      const body = Object.fromEntries(Object.entries(form).filter(([, v]) => v !== ""));
      await api.post(`/users/${userId}/memory-book`, { ...body, photo_key });
      setForm(EMPTY);
      setFile(null);
      (e.target as HTMLFormElement).reset();
      onAdded();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not add");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card stack">
      <h2>Add a memory</h2>
      <p className="muted small">These become personal memory activities on their phone, such as &ldquo;Who is this?&rdquo;.</p>
      {error && <div className="error">{error}</div>}
      <form className="form" onSubmit={submit}>
        <label>
          Type
          <select value={form.kind} onChange={set("kind")}>
            <option value="person">Person</option>
            <option value="place">Place</option>
            <option value="date">Important date</option>
            <option value="memory">Memory</option>
          </select>
        </label>
        <label>
          Title
          <input value={form.title} onChange={set("title")} required maxLength={160} placeholder="Rina's wedding" />
        </label>
        <label>
          Person&apos;s name
          <input value={form.person_name} onChange={set("person_name")} maxLength={120} />
        </label>
        <label>
          Relationship to them
          <input value={form.relationship} onChange={set("relationship")} maxLength={60} placeholder="granddaughter" />
        </label>
        <label>
          Date
          <input type="date" value={form.event_date} onChange={set("event_date")} />
        </label>
        <label>
          Place
          <input value={form.place} onChange={set("place")} maxLength={160} placeholder="Jorhat" />
        </label>
        <label style={{ gridColumn: "1 / -1" }}>
          A few words
          <textarea value={form.description} onChange={set("description")} maxLength={2000} />
        </label>
        <label>
          Photo (JPEG, PNG or WebP, up to 10 MB)
          <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        </label>
        <button disabled={busy || !form.title}>{busy ? "Saving…" : "Add memory"}</button>
      </form>
    </section>
  );
}
