import { readFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { type NextRequest, NextResponse } from "next/server";
import { securityHeadersForRunner } from "./lib/security-headers";

const SESSION_TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function configuredWebPort() {
  const candidate = Number(process.env.CONTROL_MODULE_WEB_PORT);
  return Number.isInteger(candidate) && candidate >= 1025 && candidate <= 65535
    ? candidate
    : 1025;
}

function configuredRunnerPort() {
  const candidate = Number(process.env.CONTROL_MODULE_RUNNER_PORT);
  return Number.isInteger(candidate) && candidate >= 1025 && candidate <= 65535
    ? candidate
    : 10001;
}

function applySecurityHeaders(response: NextResponse, runnerPort: number) {
  for (const { key, value } of securityHeadersForRunner(runnerPort)) {
    response.headers.set(key, value);
  }
  return response;
}

function dashboardOrigin(request: NextRequest, webPort: number) {
  const host = request.headers.get("host")?.toLowerCase() || "";
  if (host !== `127.0.0.1:${webPort}` && host !== `localhost:${webPort}`) return "";
  return `http://${host}`;
}

function apiRequestIsAllowed(request: NextRequest, origin: string) {
  const suppliedOrigin = request.headers.get("origin");
  if (suppliedOrigin && suppliedOrigin !== origin) return false;
  const fetchSite = request.headers.get("sec-fetch-site");
  return !fetchSite || fetchSite === "same-origin";
}

async function sessionToken() {
  const dataDirectory = process.env.CONTROL_MODULE_DATA_DIR?.trim() || "";
  if (!isAbsolute(dataDirectory)) return "";
  try {
    const token = (await readFile(join(dataDirectory, "runtime", "session-token"), "utf8")).trim();
    return SESSION_TOKEN_PATTERN.test(token) ? token : "";
  } catch {
    return "";
  }
}

function jsonError(message: string, status: number, runnerPort: number) {
  const response = NextResponse.json({ error: message }, { status });
  response.headers.set("Cache-Control", "no-store, private");
  return applySecurityHeaders(response, runnerPort);
}

async function forwardRunnerRequest(request: NextRequest, runnerPort: number, origin: string) {
  const token = await sessionToken();
  if (!token) return jsonError("The local command runner is not ready.", 503, runnerPort);

  const headers = new Headers({
    Accept: request.headers.get("accept") || "application/json",
    Origin: origin,
    "X-Control-Token": token,
  });
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("Content-Type", contentType);

  try {
    const body = request.method === "GET" || request.method === "HEAD"
      ? undefined
      : await request.arrayBuffer();
    const upstream = await fetch(
      `http://127.0.0.1:${runnerPort}${request.nextUrl.pathname}${request.nextUrl.search}`,
      {
        method: request.method,
        headers,
        body,
        cache: "no-store",
      },
    );
    const response = new NextResponse(await upstream.arrayBuffer(), {
      status: upstream.status,
      headers: {
        "Cache-Control": "no-store, private",
        "Content-Type": upstream.headers.get("content-type") || "application/json; charset=utf-8",
      },
    });
    return applySecurityHeaders(response, runnerPort);
  } catch {
    return jsonError("The local command runner is offline.", 503, runnerPort);
  }
}

export async function proxy(request: NextRequest) {
  const webPort = configuredWebPort();
  const runnerPort = configuredRunnerPort();
  const origin = dashboardOrigin(request, webPort);
  if (!origin) return jsonError("Invalid local dashboard host.", 403, runnerPort);

  if (request.nextUrl.pathname.startsWith("/api/")) {
    if (!apiRequestIsAllowed(request, origin)) {
      return jsonError("Cross-site dashboard requests are not allowed.", 403, runnerPort);
    }
    return forwardRunnerRequest(request, runnerPort, origin);
  }

  const response = NextResponse.next();
  return applySecurityHeaders(response, runnerPort);
}

export const config = {
  matcher: "/:path*",
};
