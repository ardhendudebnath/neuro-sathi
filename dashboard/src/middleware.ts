import { NextResponse, type NextRequest } from "next/server";

// Pages need a session. The access cookie expires about hourly and is renewed
// by the API proxy, so the longer-lived session cookie counts too. The API
// itself still verifies the token on every call.
export function middleware(req: NextRequest) {
  if (!req.cookies.get("ns_token") && !req.cookies.get("ns_refresh")) {
    return NextResponse.redirect(new URL("/login", req.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!login|api/|_next/|favicon.ico).*)"],
};
