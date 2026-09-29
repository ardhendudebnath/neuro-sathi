import "server-only";

// Server-side only. The browser never sees the API token or the API address:
// it talks to this Next.js app, which keeps the token in an httpOnly cookie.
export const API_BASE_URL = process.env.API_BASE_URL ?? "http://localhost:8000";
export const TOKEN_COOKIE = "ns_token";
export const CSRF_HEADER = "x-ns-csrf";

export const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "strict" as const,
  path: "/",
  maxAge: 60 * 60 * 24 * 7,
};

/** Headers passed through to the API so it can rate-limit by the real client IP. */
export function forwardedFor(req: Request): Record<string, string> {
  const xff = req.headers.get("x-forwarded-for");
  const real = req.headers.get("x-real-ip");
  const ip = xff?.split(",")[0]?.trim() || real || "";
  return ip ? { "x-forwarded-for": ip } : {};
}
