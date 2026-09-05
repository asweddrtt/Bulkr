# delete-account

Deletes the calling user's account and everything belonging to it.

## Why it is a function

`auth.users` is not reachable through PostgREST, and deleting a row there needs
the service role. A service role key shipped inside the app would be a service
role key in the hands of anyone who unzips an `.apk`, so the deletion runs
server-side and the app only asks for it.

## What it deletes

1. **Storage**, first — because nothing else will ever find it again.
   - `avatars/<user id>/…`, the whole folder, including superseded uploads.
   - `meal-images` and `post-images` objects referenced by the user's rows.
     Those buckets are keyed by the owning row rather than by uploader, so the
     paths are read back out of the URLs before the rows go.
2. **The auth user.** `public.users.id` references `auth.users(id)` on delete
   cascade, and every other table hangs off `public.users` the same way, so one
   delete takes the profile, posts, comments, likes, saves, follows, meals,
   ingredients, daily logs, water logs, weigh-ins, group memberships and blocks
   with it.

Other people's threads lose the user's replies. That is what "keep nothing"
means, and it is the option that was chosen deliberately over anonymising.

## Whose account

The user id comes from the verified JWT, never from the request body. There is
no parameter for it, which is what stops this being "delete any account you can
name". The platform verifies the caller's token before the function runs.

## Deploy

```
supabase link --project-ref <your project ref>
supabase functions deploy delete-account
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform;
nothing else needs setting.

## Check it

Sign in as a throwaway account, note its id, then from the app's profile screen
delete it. Afterwards, as an admin:

```sql
select count(*) from auth.users where id = '<id>';   -- 0
select count(*) from public.users where id = '<id>'; -- 0
select count(*) from public.posts where user_id = '<id>'; -- 0
```

And in the dashboard's storage browser, that `avatars/<id>/` is gone.
