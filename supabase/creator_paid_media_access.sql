-- Allow a buyer to read a paid media object only after admin confirms
-- a payment for that exact post. The bucket stays private.
drop policy if exists "Buyers read paid post media after approval" on storage.objects;
create policy "Buyers read paid post media after approval"
on storage.objects for select to authenticated
using (
  bucket_id='fanclub-paid-media'
  and exists (
    select 1
    from public.posts p
    join public.creator_payment_submissions s on s.post_id=p.id
    where p.media_path=storage.objects.name
      and p.creator_id=s.creator_id
      and s.buyer_id=auth.uid()
      and s.status='confirmed'
  )
);
