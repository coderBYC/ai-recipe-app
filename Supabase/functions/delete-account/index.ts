import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type DeleteAccountResponse = {
  ok: boolean;
  deleted_user_id?: string;
  error?: string;
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(
      { ok: false, error: "Missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY" },
      500
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "Missing bearer token" }, 401);
  }
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ ok: false, error: "Empty bearer token" }, 401);
  }

  // User-scoped client (anonymous key + caller JWT) to identify caller.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const {
    data: { user },
    error: authErr,
  } = await userClient.auth.getUser();
  if (authErr || !user) {
    return json({ ok: false, error: "Unauthorized user" }, 401);
  }

  // Admin client (service role) to delete from auth.users.
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { error: delErr } = await adminClient.auth.admin.deleteUser(user.id);
  if (delErr) {
    return json({ ok: false, error: delErr.message }, 400);
  }

  return json({ ok: true, deleted_user_id: user.id }, 200);
});

function json(body: DeleteAccountResponse, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
