import { NextResponse } from "next/server";
import { CSRF_HEADER, TOKEN_COOKIE, cookieOptions } from "@/lib/server";

export async function POST(req: Request) {
  if (req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const out = NextResponse.json({ ok: true });
  out.cookies.set(TOKEN_COOKIE, "", { ...cookieOptions, maxAge: 0 });
  return out;
}
