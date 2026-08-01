export function securityHeadersForRunner(runnerPort = 10001) {
  const safeRunnerPort = Number.isInteger(runnerPort) && runnerPort >= 1025 && runnerPort <= 65535
    ? runnerPort
    : 10001;
  return [
    {
      key: "Content-Security-Policy",
      value: [
        "default-src 'self'",
        "base-uri 'none'",
        `connect-src 'self' http://127.0.0.1:${safeRunnerPort} http://localhost:${safeRunnerPort}`,
        "frame-ancestors 'none'",
        "form-action 'self'",
        "img-src 'self' data:",
        "object-src 'none'",
        "script-src 'self' 'unsafe-inline'",
        "style-src 'self' 'unsafe-inline'",
        "worker-src 'none'",
      ].join("; "),
    },
    { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
    { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
    { key: "Permissions-Policy", value: "camera=(), geolocation=(), microphone=()" },
    { key: "Referrer-Policy", value: "no-referrer" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
  ] as const;
}

export const SECURITY_HEADERS = securityHeadersForRunner();
