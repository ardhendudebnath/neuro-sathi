import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  API_BASE_URL,
  CSRF_HEADER,
  REFRESH_COOKIE,
  TOKEN_COOKIE,
  accessCookie,
  clearedCookie,
  forwardedFor,
  renewAccess,
  type Renewal,
} from "@/lib/server";

// Forwards the browser's request to the API with the bearer token from the
// httpOnly cookie, renewing that token with the session cookie when it has
// expired. Only API paths the dashboard needs are allowed.
const ALLOWED = [/^me(\/.*)?$/, /^links(\/.*)?$/, /^dashboard\//, /^users\/[0-9a-f-]{36}\//, /^content\//, /^admin\//];

type Ctx = { params: Promise<{ path: string[] }> };
type Renewed = Extract<Renewal, { ok: true }>;

/** The session is over: clear the cookies so the browser goes back to the sign-in page. */
function signedOut(): NextResponse {
  const out = NextResponse.json({ detail: "Not signed in" }, { status: 401 });
  out.cookies.set(TOKEN_COOKIE, "", clearedCookie);
  out.cookies.set(REFRESH_COOKIE, "", clearedCookie);
  return out;
}

/** Renewal failed for a temporary reason: keep the session and let the page retry. */
function unavailable(): NextResponse {
  return NextResponse.json({ detail: "The service is busy. Please try again in a moment." }, { status: 503 });
}

async function forward(req: Request, ctx: Ctx): Promise<Response> {
  const { path } = await ctx.params;
  const joined = path.map(encodeURIComponent).join("/");
  if (!ALLOWED.some((re) => re.test(joined))) {
    return NextResponse.json({ detail: "Not found" }, { status: 404 });
  }
  if (req.method !== "GET" && req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }

  const jar = await cookies();
  const refresh = jar.get(REFRESH_COOKIE)?.value;
  let token = jar.get(TOKEN_COOKIE)?.value;
  let renewed: Renewed | null = null;

  if (!token) {
    // The access cookie has expired (it lasts as long as its token): renew before calling the API.
    if (!refresh) return signedOut();
    const renewal = await renewAccess(req, refresh);
    if (!renewal.ok) return renewal.ended ? signedOut() : unavailable();
    renewed = renewal;
    token = renewal.accessToken;
  }

  const search = new URL(req.url).search;
  const ctype = req.headers.get("content-type");
  const payload = req.method === "GET" || req.method === "HEAD" ? undefined : await req.arrayBuffer();
  const call = (bearer: string) =>
    fetch(`${API_BASE_URL}/${joined}${search}`, {
      method: req.method,
      headers: { authorization: `Bearer ${bearer}`, ...forwardedFor(req), ...(ctype ? { "content-type": ctype } : {}) },
      body: payload,
      cache: "no-store",
      redirect: "manual",
    });

  let res = await call(token);
  if (res.status === 401 && refresh && !renewed) {
    // The API refused a token that had not run out here: renew once and retry.
    const renewal = await renewAccess(req, refresh);
    if (!renewal.ok) return renewal.ended ? signedOut() : unavailable();
    renewed = renewal;
    res = await call(renewal.accessToken);
  }
  if (res.status === 401) return signedOut();

  const headers = new Headers();
  for (const name of ["content-type", "retry-after"]) {
    const value = res.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set("cache-control", "no-store");
  const out = new NextResponse(res.status === 204 ? null : await res.arrayBuffer(), { status: res.status, headers });
  if (renewed) out.cookies.set(TOKEN_COOKIE, renewed.accessToken, accessCookie(renewed.expiresIn));
  return out;
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const PATCH = forward;
export const DELETE = forward;
