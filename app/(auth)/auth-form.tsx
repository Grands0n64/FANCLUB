"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Props = { mode: "login" | "signup" };
export default function AuthForm({ mode }: Props) {
  const router = useRouter();
  const [email,setEmail] = useState("");
  const [password,setPassword] = useState("");
  const [username,setUsername] = useState("");
  const [displayName,setDisplayName] = useState("");
  const [adult,setAdult] = useState(false);
  const [gender,setGender] = useState<"boy"|"girl"|"">("");
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState("");
  const isSignup = mode === "signup";
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); setMessage("");
    const supabase = createClient();
    if (!supabase) { setMessage("Supabase is not configured yet. Add the two NEXT_PUBLIC_SUPABASE values in your deployment environment."); return; }
    if (isSignup && !gender) { setMessage("Choose Boy or Girl to create your account."); return; }
    if (isSignup && !adult) { setMessage("You must confirm that you are 18 or older to continue."); return; }
    if (isSignup && (!displayName.trim() || displayName.trim().length > 60)) { setMessage("Enter a display name between 1 and 60 characters."); return; }
    if (isSignup && !/^[A-Za-z0-9_]{3,30}$/.test(username.trim())) { setMessage("Username must be 3–30 letters, numbers or underscores."); return; }
    setBusy(true);
    try {
      if (isSignup) {
        const { data,error } = await supabase.auth.signUp({ email,password,options:{ data:{ username:username.trim().toLowerCase(), display_name:displayName.trim().slice(0,60), gender, age_declared:true } } });
        if (error) throw error;
        setMessage(data.session ? "Your account has been created. Age verification is still required before restricted features are available." : "Check your email to confirm your account. Age verification will still be required.");
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email,password });
        if (error) throw error;
        router.push("/home"); router.refresh();
      }
    } catch (err) { setMessage(err instanceof Error ? err.message : "Something went wrong. Please try again."); }
    finally { setBusy(false); }
  }
  return <form onSubmit={submit} className="auth-form">
    {isSignup && <><label>Display name<input required minLength={1} maxLength={60} value={displayName} onChange={e=>setDisplayName(e.target.value)} placeholder="Your display name"/></label><label>Username<input required minLength={3} maxLength={30} pattern="[A-Za-z0-9_]+" value={username} onChange={e=>setUsername(e.target.value)} placeholder="yourusername"/></label></>}
    <label>Email address<input required type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@example.com"/></label>
    <label>Password<input required type="password" minLength={8} autoComplete={isSignup ? "new-password" : "current-password"} value={password} onChange={e=>setPassword(e.target.value)} placeholder="At least 8 characters"/></label>
    {isSignup && <label>Gender<select required value={gender} onChange={e=>setGender(e.target.value as "boy"|"girl"|"") }><option value="">Choose Boy or Girl</option><option value="boy">Boy</option><option value="girl">Girl</option></select></label>}
    {isSignup && <label className="age-check"><input type="checkbox" checked={adult} onChange={e=>setAdult(e.target.checked)}/> I confirm that I am 18 years of age or older.</label>}
    <button className="button auth-submit" disabled={busy}>{busy ? "Please wait…" : isSignup ? "Create account ↗" : "Log in ↗"}</button>
    {message && <p className="auth-message" role="status">{message}</p>}
    <p className="auth-copy">{isSignup ? "Already a member? " : "New to Fanclub? "}<Link href={isSignup ? "/login" : "/signup"}>{isSignup ? "Log in" : "Create an account"}</Link></p>
    {isSignup && <p className="auth-note">Age declaration is not identity or age verification. Restricted creator features remain unavailable until the required checks and moderation are completed.</p>}
  </form>;
}