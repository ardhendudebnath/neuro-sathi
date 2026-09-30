import "server-only";

// Server-side only. The browser never sees the API tokens or the API address:
// it talks to this Next.js app, which keeps both tokens in httpOnly cookies.
export const API_BASE_URL = process.env.API_BASE_URL ?? "http://localhost:8000";
export const TOKEN_COOKIE = "ns_token"; // access token, about an hour
export const REFRESH_COOKIE = "ns_refresh"; // session token, used only to renew the access token
export const CSRF_HEADER = "x-ns-csrf";

const base = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "strict" as const,
  path: "/",
};

/** The access cookie lives as long as the token inside it. */
export const accessCookie = (expiresInSeconds: number) => ({ ...base, maxAge: Math.max(60, expiresInSeconds) });

/** Matches the API's session lifetime: 90 days without use. */
export const refreshCookie = { ...base, maxAge: 60 * 60 * 24 * 90 };

export const clearedCookie = { ...base, maxAge: 0 };

/** Headers passed through to the API so it can rate-limit by the real client IP. */
export function forwardedFor(req: Request): Record<string, string> {
  const xff = req.headers.get("x-forwarded-for");
  const real = req.headers.get("x-real-ip");
  const ip = xff?.split(",")[0]?.trim() || real || "";
  return ip ? { "x-forwarded-for": ip } : {};
}

export type Renewal = { ok: true; accessToken: string; expiresIn: number } | { ok: false; ended: boolean };

/**
 * Renews the access token with the session token. `ended` is true only when
 * the API says the session is over; a network or server error is temporary
 * and must not sign the caregiver out.
 */
export async function renewAccess(req: Request, refreshToken: string): Promise<Renewal> {
  try {
    const res = await fetch(`${API_BASE_URL}/auth/refresh`, {
      method: "POST",
      headers: { "content-type": "application/json", ...forwardedFor(req) },
      body: JSON.stringify({ refresh_token: refreshToken }),
      cache: "no-store",
    });
    if (res.status === 401) return { ok: false, ended: true };
    if (!res.ok) return { ok: false, ended: false };
    const data = (await res.json()) as { access_token: string; expires_in: number };
    return { ok: true, accessToken: data.access_token, expiresIn: data.expires_in };
  } catch {
    return { ok: false, ended: false };
  }
}

/** Ends a session on the API. Best effort: it also expires by itself. */
export async function endSession(req: Request, refreshToken: string): Promise<void> {
  await fetch(`${API_BASE_URL}/auth/logout`, {
    method: "POST",
    headers: { "content-type": "application/json", ...forwardedFor(req) },
    body: JSON.stringify({ refresh_token: refreshToken }),
    cache: "no-store",
  }).catch(() => undefined);
}
