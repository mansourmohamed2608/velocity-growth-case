import type { Metadata, Viewport } from "next";
import { Manrope, Newsreader } from "next/font/google";

import "./globals.css";

const sans = Manrope({
  subsets: ["latin"],
  variable: "--font-sans",
});

const display = Newsreader({
  subsets: ["latin"],
  variable: "--font-display",
});

export const metadata: Metadata = {
  title: {
    default: "Relay — Campaign clarity",
    template: "%s · Relay",
  },
  description: "A secure, multi-brand campaign portal for Velocity Growth.",
};

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#f5f1e8",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${sans.variable} ${display.variable}`}>
      <body>{children}</body>
    </html>
  );
}
