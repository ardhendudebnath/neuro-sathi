import { NextResponse, type NextRequest } from "next/server";

// Pages need a session cookie; the API itself still verifies the token on every call.
export function middleware(req: NextRequest) {
  if (!req.cookies.get("ns_token")) {
    return NextResponse.redirect(new URL("/login", req.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!login|api/|_next/|favicon.ico).*)"],
};
