import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { API_BASE_URL, CSRF_HEADER, TOKEN_COOKIE, forwardedFor } from "@/lib/server";

// Forwards the browser's request to the API with the bearer token from the
// httpOnly cookie. Only API paths the dashboard needs are allowed.
const ALLOWED = [/^me(\/.*)?$/, /^links(\/.*)?$/, /^dashboard\//, /^users\/[0-9a-f-]{36}\//, /^content\//, /^admin\//];

type Ctx = { params: Promise<{ path: string[] }> };

async function forward(req: Request, ctx: Ctx): Promise<Response> {
  const { path } = await ctx.params;
  const joined = path.map(encodeURIComponent).join("/");
  if (!ALLOWED.some((re) => re.test(joined))) {
    return NextResponse.json({ detail: "Not found" }, { status: 404 });
  }
  if (req.method !== "GET" && req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const token = (await cookies()).get(TOKEN_COOKIE)?.value;
  if (!token) return NextResponse.json({ detail: "Not signed in" }, { status: 401 });

  const search = new URL(req.url).search;
  const headers: Record<string, string> = { authorization: `Bearer ${token}`, ...forwardedFor(req) };
  const ctype = req.headers.get("content-type");
  if (ctype) headers["content-type"] = ctype;

  const res = await fetch(`${API_BASE_URL}/${joined}${search}`, {
    method: req.method,
    headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : await req.arrayBuffer(),
    cache: "no-store",
    redirect: "manual",
  });
  const outHeaders = new Headers();
  for (const h of ["content-type", "retry-after"]) {
    const v = res.headers.get(h);
    if (v) outHeaders.set(h, v);
  }
  outHeaders.set("cache-control", "no-store");
  return new NextResponse(res.status === 204 ? null : await res.arrayBuffer(), { status: res.status, headers: outHeaders });
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const PATCH = forward;
export const DELETE = forward;
