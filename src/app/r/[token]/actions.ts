"use server";

import { randomBytes } from "node:crypto";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";

import {
  createPublicClient,
  digestForPostgres,
  reportCookieName,
  reportTokenPattern,
} from "@/lib/public-report";

const unlockSchema = z.object({
  token: z.string().regex(reportTokenPattern),
  password: z.string().min(1).max(128),
});

export async function unlockReport(formData: FormData) {
  const parsed = unlockSchema.safeParse({
    token: formData.get("token"),
    password: formData.get("password"),
  });
  if (!parsed.success) redirect(`/r/invalid?error=invalid`);

  const sessionToken = randomBytes(32).toString("base64url");
  const supabase = createPublicClient();
  const result = await supabase.rpc("create_public_report_session", {
    target_token_digest: digestForPostgres(parsed.data.token),
    plain_password: parsed.data.password,
    target_session_digest: digestForPostgres(sessionToken),
  });
  if (result.error || result.data !== true)
    redirect(`/r/${encodeURIComponent(parsed.data.token)}?error=invalid`);

  const cookieStore = await cookies();
  cookieStore.set(reportCookieName(parsed.data.token), sessionToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    path: `/r/${parsed.data.token}`,
    maxAge: 60 * 60,
  });
  redirect(`/r/${encodeURIComponent(parsed.data.token)}`);
}
