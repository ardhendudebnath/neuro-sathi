import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { CSRF_HEADER, REFRESH_COOKIE, TOKEN_COOKIE, clearedCookie, endSession } from "@/lib/server";

export async function POST(req: Request) {
  if (req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const refresh = (await cookies()).get(REFRESH_COOKIE)?.value;
  if (refresh) await endSession(req, refresh); // so the session cannot be reused if the cookie was copied
  const out = NextResponse.json({ ok: true });
  out.cookies.set(TOKEN_COOKIE, "", clearedCookie);
  out.cookies.set(REFRESH_COOKIE, "", clearedCookie);
  return out;
}
