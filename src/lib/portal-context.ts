import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export interface PortalContext {
  brandId: string;
  brandCode: string;
  brandName: string;
  role: "owner" | "analyst";
  userEmail: string;
}

export async function requirePortalContext(): Promise<PortalContext> {
  const supabase = await createClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) redirect("/login");

  const { data, error } = await supabase.rpc("current_portal_context").maybeSingle();
  if (error) throw new Error("Your workspace could not be loaded.", { cause: error });
  if (!data) redirect("/unauthorized");

  const context = data as {
    brand_id: string;
    brand_code: string;
    brand_name: string;
    role: "owner" | "analyst";
  };

  return {
    brandId: context.brand_id,
    brandCode: context.brand_code,
    brandName: context.brand_name,
    role: context.role,
    userEmail: user.email ?? "Authenticated user",
  };
}
