import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Control Module",
  description: "Local project runner.",
  icons: {
    icon: [{ url: "/gear.svg", type: "image/svg+xml" }],
    shortcut: "/gear.svg",
  },
};

const themeScript = `
  (function () {
    try {
      var saved = localStorage.getItem("control-module-theme");
      var theme = saved === "light" || saved === "dark"
        ? saved
        : (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
      document.documentElement.dataset.theme = theme;
    } catch (_) {}
  })();
`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
