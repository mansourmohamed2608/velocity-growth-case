"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const links = [
  { href: "/portal", label: "Dashboard" },
  { href: "/portal/contacts", label: "Contacts" },
  { href: "/portal/campaigns", label: "Campaigns" },
];

export function PortalNav() {
  const pathname = usePathname();
  return (
    <nav aria-label="Portal navigation" className="portal-nav">
      {links.map((link) => {
        const active =
          link.href === "/portal" ? pathname === link.href : pathname.startsWith(link.href);
        return (
          <Link aria-current={active ? "page" : undefined} href={link.href} key={link.href}>
            {link.label}
          </Link>
        );
      })}
    </nav>
  );
}
