"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

const credentialsSchema = z.object({
  email: z.string().trim().email(),
  password: z.string().min(1),
});

export async function signInWithPassword(formData: FormData) {
  const credentials = credentialsSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });
  if (!credentials.success) redirect("/login?error=invalid-input");

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(credentials.data);
  if (error) redirect("/login?error=credentials");

  redirect("/portal");
}

export async function signInWithGoogle() {
  const appUrl = process.env.NEXT_PUBLIC_APP_URL;
  if (!appUrl) redirect("/login?error=configuration");

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${appUrl.replace(/\/$/, "")}/auth/callback` },
  });
  if (error || !data.url) redirect("/login?error=oauth");

  redirect(data.url);
}
