-- Supabase Security Advisor: "Public bucket allows listing".
--
-- The broad SELECT policy on storage.objects lets anyone (including signed-out
-- visitors) call the Storage API's list endpoint and get every file name in the
-- `avatars` bucket. File names are `<user id>/<timestamp>.<ext>`, so that is a
-- full list of every user's id.
--
-- It isn't needed: files in a PUBLIC bucket are served at
-- /storage/v1/object/public/avatars/<path> without any SELECT policy, and the
-- app only ever uploads (INSERT policy) and builds public URLs (getPublicUrl).
-- It never lists or downloads through the API.
--
-- Uploads keep working because they use upsert: false. (Upsert would need
-- SELECT and UPDATE policies as well, so if you ever switch the upload to
-- upsert: true, this will need rethinking.)

drop policy if exists "Avatar images are publicly accessible." on storage.objects;
