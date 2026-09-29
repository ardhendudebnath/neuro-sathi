import { NextResponse } from "next/server";
import { API_BASE_URL, CSRF_HEADER, TOKEN_COOKIE, cookieOptions, forwardedFor } from "@/lib/server";

export async function POST(req: Request) {
  if (req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const res = await fetch(`${API_BASE_URL}/auth/verify`, {
    method: "POST",
    headers: { "content-type": "application/json", ...forwardedFor(req) },
    body: await req.text(),
    cache: "no-store",
  });
  const data = await res.json().catch(() => ({ detail: "Sign-in failed" }));
  if (!res.ok) return NextResponse.json(data, { status: res.status });

  if (data.user?.role === "user") {
    // The dashboard is for caregivers, health workers and admins; elderly users use the phone app.
    return NextResponse.json({ detail: "Please use the NEURO-SATHI phone app to sign in." }, { status: 403 });
  }
  const out = NextResponse.json({ user: data.user });
  out.cookies.set(TOKEN_COOKIE, data.access_token, cookieOptions);
  return out;
}
