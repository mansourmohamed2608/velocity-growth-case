"use client";

import { useState } from "react";

export function CopyButton({ value }: { value: string }) {
  const [status, setStatus] = useState<"idle" | "copied" | "failed">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setStatus("copied");
    } catch {
      setStatus("failed");
    }
  }

  return (
    <div className="copy-control">
      <button className="button button-primary" onClick={copy} type="button">
        {status === "copied" ? "Link copied" : "Copy report link"}
      </button>
      <span aria-live="polite" className="copy-feedback" role="status">
        {status === "copied"
          ? "Copied to clipboard."
          : status === "failed"
            ? "Could not copy—select the link instead."
            : ""}
      </span>
    </div>
  );
}

export function PrintButton() {
  return (
    <button
      className="button button-quiet report-print-button"
      onClick={() => window.print()}
      type="button"
    >
      Print or save PDF
    </button>
  );
}
