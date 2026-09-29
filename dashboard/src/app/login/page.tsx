"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { api, ApiError } from "@/lib/api";

type Step = "phone" | "code";

export default function LoginPage() {
  const router = useRouter();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [devCode, setDevCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function sendCode(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const r = await api.auth<{ dev_code?: string | null }>("otp", { phone });
      setDevCode(r.dev_code ?? null);
      setStep("code");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not send the code.");
    } finally {
      setBusy(false);
    }
  }

  async function verify(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await api.auth("verify", { phone, code, name: name || undefined, role: "caregiver" });
      router.replace("/");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not sign in.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="shell" style={{ maxWidth: 440, paddingTop: "10vh" }}>
      <div className="card stack">
        <div>
          <h1>
            NEURO-<span style={{ color: "var(--primary)" }}>SATHI</span> Care
          </h1>
          <p className="muted">For family caregivers and health workers.</p>
        </div>
        {error && (
          <div className="error" role="alert">
            {error}
          </div>
        )}
        {step === "phone" ? (
          <form className="stack" onSubmit={sendCode}>
            <label>
              Mobile number
              <input
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                placeholder="98765 43210"
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/[^\d+]/g, ""))}
                required
              />
            </label>
            <button disabled={busy || phone.length < 10}>{busy ? "Sending…" : "Send code"}</button>
          </form>
        ) : (
          <form className="stack" onSubmit={verify}>
            <p className="small">
              We sent a 6-digit code to <strong>{phone}</strong>.{" "}
              <button type="button" className="secondary" style={{ minHeight: 0, padding: "2px 8px" }} onClick={() => setStep("phone")}>
                Change
              </button>
            </p>
            {devCode && <p className="notice">Development mode: your code is {devCode}</p>}
            <label>
              Code
              <input
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
                required
              />
            </label>
            <label>
              Your name <span className="muted small">(first sign-in only)</span>
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} autoComplete="name" />
            </label>
            <button disabled={busy || code.length !== 6}>{busy ? "Signing in…" : "Sign in"}</button>
          </form>
        )}
        <p className="muted small">
          NEURO-SATHI supports care; it does not diagnose. Please contact a doctor for medical concerns.
        </p>
      </div>
    </main>
  );
}
