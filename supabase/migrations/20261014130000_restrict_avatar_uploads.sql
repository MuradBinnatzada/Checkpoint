-- Avatar uploads: only into your own folder.
--
-- The old policy only checked `bucket_id = 'avatars'`, so any signed-in user
-- could upload any file to any path in this PUBLIC bucket (including into other
-- users' folders). With open sign-ups that is free file hosting on your project.
--
-- The app uploads to `<auth.uid()>/<timestamp>.<ext>` (CheckpointRepository.uploadAvatar),
-- so the first folder of the object name must be the caller's own user id.
--
-- There is no UPDATE or DELETE policy on purpose: uploads use upsert:false.
--
-- ALSO set these on the bucket itself (Storage > avatars > Edit bucket), since a
-- policy can't limit them:
--   - File size limit:       e.g. 2 MB
--   - Allowed MIME types:    image/jpeg, image/png, image/webp, image/gif

drop policy if exists "Users can upload their own avatars." on storage.objects;

create policy "Users can upload their own avatars."
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
