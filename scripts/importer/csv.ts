import { readFile } from "node:fs/promises";

import { parse } from "csv-parse/sync";
import iconv from "iconv-lite";

import type { SourceRecord } from "./types";

const headerAliases: Record<string, string> = {
  e_mail: "email",
  mobile: "phone",
  pays: "country",
};

function canonicalHeader(header: string) {
  const normalized = header.trim().toLowerCase().replaceAll(" ", "_");
  return headerAliases[normalized] ?? normalized;
}

export async function readSourceCsv(
  filePath: string,
  options: { delimiter: "," | ";"; encoding: "utf8" | "win1252" },
): Promise<SourceRecord[]> {
  const buffer = await readFile(filePath);
  const decoded = iconv.decode(buffer, options.encoding);
  const records = parse(decoded, {
    bom: true,
    columns: (headers: string[]) => headers.map(canonicalHeader),
    delimiter: options.delimiter,
    // Deliberately malformed rows still need to reach validation so their row and
    // rejection reason are persisted instead of aborting the whole file.
    relax_column_count: true,
    skip_empty_lines: true,
  }) as Record<string, unknown>[];

  return records.map((record, index) => ({
    rowNumber: index + 2,
    values: Object.fromEntries(
      Object.entries(record).map(([key, value]) => [key, value == null ? "" : String(value)]),
    ),
  }));
}
