import "./globals.css";
import "./brand.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Concept Spaces — Intelligence, Given Form.",
  description: "Human-governed architecture, engineering and construction intelligence."
};

export default function RootLayout({children}:{children:React.ReactNode}) {
  return <html lang="en"><body>{children}</body></html>;
}
