// Deletes the calling user's account. Apple requires an in-app deletion path
// for any app that offers account creation (App Review 5.1.1(v)) — shipping
// without this is a rejection.
//
// It has to live server-side: removing a row from `auth.users` needs the
// service-role key, which bypasses RLS and must never be in the app bundle.
// The key is injected into Edge Functions by Supabase; it is not committed.
//
// What goes with the user, by cascade: their `profiles` row, and every
// `profile_installs` link. Their `ai_usage` rows survive, because they are
// keyed to a random install UUID and — once the links are gone — no longer
// point at a person. That leaves our cost accounting intact while the account
// and everything identifying about it is genuinely deleted.
//
// Recipes, Kitchen and cook history are not touched here: they never left the
// device. Deleting the account also does NOT cancel the subscription, which
// lives on the Apple ID; the app says so before asking for confirmation.

import { createClient } from "jsr:@supabase/supabase-js@2";

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ error: "missing token" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // The caller's own token decides whose account this is. Nothing in the
  // request body is trusted, so there is no way to ask for someone else's.
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    return json({ error: "invalid token" }, 401);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  return json({ deleted: true }, 200);
});
