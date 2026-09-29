"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";

export function TopBar() {
  const router = useRouter();
  async function logout() {
    await api.auth("logout").catch(() => undefined);
    router.replace("/login");
  }
  return (
    <header className="topbar">
      <Link href="/" className="brand">
        NEURO-<span>SATHI</span> <span className="muted small">Care</span>
      </Link>
      <button className="secondary" onClick={logout}>
        Sign out
      </button>
    </header>
  );
}
