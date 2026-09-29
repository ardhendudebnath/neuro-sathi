import { NextResponse } from "next/server";
import { API_BASE_URL, CSRF_HEADER, forwardedFor } from "@/lib/server";

export async function POST(req: Request) {
  if (req.headers.get(CSRF_HEADER) !== "1") {
    return NextResponse.json({ detail: "Bad request" }, { status: 400 });
  }
  const res = await fetch(`${API_BASE_URL}/auth/otp`, {
    method: "POST",
    headers: { "content-type": "application/json", ...forwardedFor(req) },
    body: await req.text(),
    cache: "no-store",
  });
  const headers = new Headers({ "content-type": "application/json" });
  const retry = res.headers.get("retry-after");
  if (retry) headers.set("retry-after", retry);
  return new NextResponse(await res.text(), { status: res.status, headers });
}
