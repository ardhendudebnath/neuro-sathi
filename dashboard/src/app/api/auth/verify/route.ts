import { NextResponse } from "next/server";
import {
  API_BASE_URL,
  CSRF_HEADER,
  REFRESH_COOKIE,
  TOKEN_COOKIE,
  accessCookie,
  endSession,
  forwardedFor,
  refreshCookie,
} from "@/lib/server";

export async function POST(req: Request) {
  if (req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const form = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const res = await fetch(`${API_BASE_URL}/auth/verify`, {
    method: "POST",
    headers: { "content-type": "application/json", ...forwardedFor(req) },
    body: JSON.stringify({ ...form, device: "dashboard" }),
    cache: "no-store",
  });
  const data = await res.json().catch(() => ({ detail: "Sign-in failed" }));
  if (!res.ok) return NextResponse.json(data, { status: res.status });

  if (data.user?.role === "user") {
    // The dashboard is for caregivers, health workers and admins; elderly users use the phone app.
    if (data.refresh_token) await endSession(req, data.refresh_token);
    return NextResponse.json({ detail: "Please use the NEURO-SATHI phone app to sign in." }, { status: 403 });
  }
  const out = NextResponse.json({ user: data.user });
  out.cookies.set(TOKEN_COOKIE, data.access_token, accessCookie(data.expires_in));
  if (data.refresh_token) out.cookies.set(REFRESH_COOKIE, data.refresh_token, refreshCookie);
  return out;
}
