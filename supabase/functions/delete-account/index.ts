// Deleting an account, for real.
//
// This exists because the app cannot do it. `auth.users` is not reachable
// through PostgREST and the anon key has no business touching it — deleting an
// auth user needs the service role, and a service role key shipped in an .apk
// is a service role key in everyone's hands. So it runs here, and the only
// account it will ever delete is the one that called it.
//
// That last part is the whole security model, so it is worth being explicit:
// the user id is taken from the verified JWT and never from the request body.
// A body parameter would make this "delete any account you can name".
//
// Deploy:
//   supabase link --project-ref <your project ref>
//   supabase functions deploy delete-account
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// The caller's JWT is verified by default, so only signed-in users reach this.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !serviceRole) {
    console.error("delete-account: missing SUPABASE_URL or service role key");
    return json({ error: "not_configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(url, serviceRole, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Resolve the caller from their own token. This is the only place the id
  // being deleted comes from.
  const { data: caller, error: callerError } = await admin.auth.getUser(
    authorization.replace(/^[Bb]earer\s+/, ""),
  );

  if (callerError || !caller?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  const userId = caller.user.id;

  try {
    // Storage first, because it is the part that cannot be cleaned up
    // afterwards. Rows in Postgres have foreign keys pointing at them and go
    // when the auth user does; objects in a bucket have nothing pointing at
    // them, so a deleted account would leave its photos behind forever.
    //
    // Best effort per bucket: a bucket that does not exist, or a listing that
    // fails, must not stop the account being deleted. Someone who asked to
    // leave should not be kept because a photo would not delete.
    await removeFolder(admin, "avatars", userId);
    await removeOwnedImages(admin, userId);

    // Then the auth user. Everything else hangs off `public.users` — posts,
    // comments, likes, saves, follows, meals, daily logs, water, weight, group
    // memberships, blocks — so one delete takes the row that every other row
    // points at.
    //
    // That only holds while the foreign keys say `on delete cascade`, and the
    // tables predating this repository did not. `supabase/account_deletion.sql`
    // is what makes it true; without it this call fails for every account,
    // including an empty one.
    const { error } = await admin.auth.admin.deleteUser(userId);

    if (error) {
      // GoTrue reports every refusal from Postgres as the same five words:
      // "Database error deleting user". No constraint, no table. So ask the
      // database what is actually pointing at this row before giving up —
      // otherwise the next person debugging this starts from nothing, which
      // is where this function spent its first few months.
      const blockers = await describeBlockers(admin);

      console.error("delete-account: deleteUser failed", error, blockers);

      return json(
        {
          error: "delete_failed",
          detail: blockers
            ? `${error.message} — blocked by ${blockers}`
            : error.message,
        },
        500,
      );
    }

    return json({ deleted: true }, 200);
  } catch (error) {
    console.error("delete-account: unexpected", error);
    return json({ error: "delete_failed", detail: `${error}` }, 500);
  }
});

/// Foreign keys that would refuse a `delete from auth.users`, as one line.
///
/// Defined by `supabase/account_deletion.sql`. Null when that migration has
/// not been run — which is itself the likeliest explanation for the failure,
/// and says so rather than reporting nothing.
async function describeBlockers(
  admin: ReturnType<typeof createClient>,
): Promise<string | null> {
  try {
    const { data, error } = await admin.rpc("account_deletion_blockers");

    if (error) {
      return "unknown (run supabase/account_deletion.sql to find out)";
    }

    const rows = (data ?? []) as Array<{
      schema_name: string;
      table_name: string;
      constraint_name: string;
    }>;

    if (!rows.length) return null;

    return rows
      .map((row) =>
        `${row.schema_name}.${row.table_name} (${row.constraint_name})`
      )
      .join(", ");
  } catch (_error) {
    return null;
  }
}

/// Removes everything under `<userId>/` in a bucket.
///
/// The avatars bucket is laid out that way — see `feed_avatars.sql` — so one
/// listing finds every picture the user has ever uploaded, including the
/// superseded ones that upload path deliberately leaves behind.
async function removeFolder(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  try {
    const { data, error } = await admin.storage.from(bucket).list(userId, {
      limit: 1000,
    });

    if (error || !data?.length) return;

    await admin.storage
      .from(bucket)
      .remove(data.map((file) => `${userId}/${file.name}`));
  } catch (error) {
    console.error(`delete-account: could not clear ${bucket}`, error);
  }
}

/// Removes meal and post photos, which are not stored in per-user folders.
///
/// `meal-images` and `post-images` are keyed by the row that owns the image
/// rather than by uploader, so the paths have to be read back out of the URLs
/// the rows carry — before the rows are deleted, which is why this runs first.
async function removeOwnedImages(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const sources: Array<{
    table: string;
    column: string;
    owner: string;
    bucket: string;
  }> = [
    {
      table: "meals",
      column: "image_url",
      owner: "creator_id",
      bucket: "meal-images",
    },
    {
      table: "posts",
      column: "image_url",
      owner: "user_id",
      bucket: "post-images",
    },
  ];

  for (const source of sources) {
    try {
      const { data, error } = await admin
        .from(source.table)
        .select(source.column)
        .eq(source.owner, userId);

      if (error || !data?.length) continue;

      const paths = data
        .map((row: Record<string, unknown>) => `${row[source.column] ?? ""}`)
        .map((url: string) => storagePathFor(url, source.bucket))
        .filter((path: string | null): path is string => path !== null);

      if (paths.length) {
        await admin.storage.from(source.bucket).remove(paths);
      }
    } catch (error) {
      console.error(`delete-account: could not clear ${source.bucket}`, error);
    }
  }
}

/// The object path inside [bucket], out of a public storage URL.
///
/// Mirrors `MealRepository.storagePathFor`. Returns null for anything that is
/// not a URL into this bucket — an empty column, or an avatar still pointing at
/// the OAuth provider that supplied it.
function storagePathFor(url: string, bucket: string): string | null {
  const marker = `/storage/v1/object/public/${bucket}/`;
  const at = url.indexOf(marker);
  if (at === -1) return null;

  const path = url.slice(at + marker.length).split("?")[0];
  return path.length > 0 ? decodeURIComponent(path) : null;
}
