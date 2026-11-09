# Fanclub — Project Instructions

You are working on Fanclub, a global social networking and creator-subscription platform.

## Product direction
- Brand: FANCLUB
- Tagline: Connect. Create. Earn.
- Audience: adults aged 18+ worldwide.
- Core experience: social profiles, follows, feed, posts, stories, discovery, private messaging, creator subscriptions, exclusive paid posts, tips, gifts, livestreams, and creator earnings.
- Verification levels: Noble (silver), Royal (blue), Sovereign (yellow), Imperial Elite (owner-awarded only).
- Creator revenue share: 80% creator / 20% platform, clearly disclosed. Payment processing fees, refunds and chargebacks must be shown transparently.
- Public pages may show safe previews. Age-restricted content must never be publicly accessible and must be protected by server-side authorization and age/identity/consent checks.
- Adult content must be limited to verified adults and comply with applicable laws, platform policies, consent requirements, and payment/hosting provider terms. Never support minors, coercion, non-consensual imagery, or deceptive impersonation.

## Engineering rules
- Preserve existing work. Inspect files before changing them.
- Prefer small, reviewable changes and explain what changed.
- Never hardcode secrets, API keys, service-role keys, or payment credentials. Use environment variables and provide an .env.example with placeholders only.
- Validate all user input on the server. Enforce access control on the server/database, not only in the UI.
- Do not invent payment, verification, moderation, or analytics success states. Use explicit demo states until real providers are configured and approved.
- Never create fake followers, bots, fabricated engagement, or guaranteed follower counts. Promotion tools must reach real users and report actual metrics.
- Do not claim production readiness without running checks and verifying integrations.
- Keep accessibility, responsive layouts, privacy, security, and clear error states in scope.
- Use TypeScript strict mode. Keep components readable and avoid unnecessary dependencies.
- Before finishing a change, run available lint/typecheck/build commands when the environment allows. Report any checks that could not be run.
