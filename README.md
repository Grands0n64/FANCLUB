# FANCLUB

**Connect. Create. Earn.**

Fanclub is a global social and creator community for adults aged 18+.

## Included in this repository
- Next.js 15 / React 19 / TypeScript application foundation
- Responsive public landing page
- Supabase email/password sign-up and login UI
- Profile creation trigger and member profile editing
- Signed-in home feed, text posts, discovery search, follow/unfollow and likes
- Creator workspace placeholder with the planned 80% creator / 20% platform split
- Verification hierarchy: Noble, Royal, Sovereign and owner-awarded Imperial Elite
- Supabase schema with row-level security policies
- GitHub Actions typecheck and production build workflow

## Run locally
1. Install Node.js 20 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local`.
4. Add your Supabase project URL and anon key.
5. In Supabase SQL Editor, run `supabase/schema.sql`.
6. Run `npm run dev` and open `http://localhost:3000`.

## Profile promotions

After applying the base schema and creator payment setup, run `supabase/promotions_setup.sql` in Supabase SQL Editor. This adds private self-declared gender eligibility, Royal-or-higher campaign enforcement, $2 per 1,000 genuine member impressions, BTC/USDT manual payment review, campaign delivery and unique signed-in member impression tracking. Campaigns stop when their reach target is met and are excluded from delivery after their 30-day deadline. Owner approval activates a campaign; no payment is auto-confirmed.

Promote is available in the signed-in app only to members who privately select Female and hold Royal, Sovereign or Imperial Elite verification. This is a self-declared eligibility field, not identity verification. Promoted reach is not a guaranteed follower count.

## Owner access
After creating your own Fanclub account, grant that account owner moderation access in Supabase SQL Editor (replace the email with the account email you registered with):

```sql
insert into public.admin_roles (user_id)
select id from auth.users where email = 'YOUR_LOGIN_EMAIL'
on conflict (user_id) do nothing;
```

Then visit `/admin` to review pending public text posts. Never grant admin access to another person unless you trust them with moderation powers.

## Environment
- `NEXT_PUBLIC_SUPABASE_URL`: Supabase project URL.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: Supabase publishable/anon key.
- Never expose the Supabase service-role key in browser code or commit it.

## Important production gates
- The age checkbox is only a declaration, not age verification. Adult/restricted features remain disabled until reliable age and identity checks, consent review, moderation and private media authorization are implemented.
- Payment processing and payouts are not connected. Do not accept real payments until a processor has explicitly approved the business model and supported markets.
- Calls, livestreams, paid media delivery, creator subscriptions, tips, messaging, admin moderation and the complete creator earnings ledger are not live yet.
- Vercel Hobby is for personal, non-commercial use; move to an appropriate commercial hosting plan before operating Fanclub as a paid business.
- Never implement fake followers, bot engagement or fabricated metrics. Promotion must reach real users and report actual results.

## Creator revenue model
The planned split is 80% creator / 20% platform on eligible creator sales. Processing fees, refunds and chargebacks must be separately disclosed and handled transparently.

## Security
Access is enforced with Supabase Row Level Security. Verification and creator privileges must only be granted by trusted server/admin workflows, never by client-side profile updates. Keep all secrets in server-side environment variables.
