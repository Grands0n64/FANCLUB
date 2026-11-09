import type { Metadata, Viewport } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "Fanclub — Connect. Create. Earn.", description: "Connect with people, discover creators, share content and build your community on Fanclub.", applicationName: "Fanclub" };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#09090b" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }