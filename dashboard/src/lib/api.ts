// Browser-side API helper. Calls go to this app's /api/proxy, which adds the
// token from the httpOnly cookie. The custom header blocks cross-site form posts.

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

function detail(body: unknown, fallback: string): string {
  if (body && typeof body === "object" && "detail" in body) {
    const d = (body as { detail: unknown }).detail;
    if (typeof d === "string") return d;
    if (Array.isArray(d) && d[0]?.msg) return String(d[0].msg);
  }
  return fallback;
}

async function request<T>(url: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(url, { ...init, headers: { "x-ns-csrf": "1", ...(init.headers ?? {}) } });
  if (res.status === 401 && typeof window !== "undefined" && !url.startsWith("/api/auth/")) {
    window.location.href = "/login";
  }
  if (res.status === 429) {
    const wait = res.headers.get("retry-after");
    throw new ApiError(429, `Too many requests. Please wait ${wait ?? "a little"} seconds and try again.`);
  }
  if (res.status === 204) return undefined as T;
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new ApiError(res.status, detail(body, "Something went wrong. Please try again."));
  return body as T;
}

const json = (method: string, data: unknown): RequestInit => ({
  method,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(data),
});

export const api = {
  get: <T>(path: string) => request<T>(`/api/proxy${path}`),
  post: <T>(path: string, data?: unknown) => request<T>(`/api/proxy${path}`, json("POST", data ?? {})),
  patch: <T>(path: string, data: unknown) => request<T>(`/api/proxy${path}`, json("PATCH", data)),
  put: <T>(path: string, data: unknown) => request<T>(`/api/proxy${path}`, json("PUT", data)),
  del: (path: string) => request<void>(`/api/proxy${path}`, { method: "DELETE" }),
  upload: <T>(path: string, form: FormData) => request<T>(`/api/proxy${path}`, { method: "POST", body: form }),
  auth: <T>(step: "otp" | "verify" | "logout", data?: unknown) => request<T>(`/api/auth/${step}`, json("POST", data ?? {})),
};
