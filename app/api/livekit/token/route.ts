import { NextRequest, NextResponse } from "next/server";
import { AccessToken } from "livekit-server-sdk";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const authorization = request.headers.get("authorization") || "";
    const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!accessToken) return NextResponse.json({ error: "Sign in to use Fanclub Live." }, { status: 401 });

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    const livekitUrl = process.env.LIVEKIT_URL;
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    if (!supabaseUrl || !supabaseAnonKey || !livekitUrl || !apiKey || !apiSecret) {
      return NextResponse.json({ error: "Live streaming is not configured on the server." }, { status: 503 });
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, { auth: { persistSession: false } });
    const { data: { user }, error } = await supabase.auth.getUser(accessToken);
    if (error || !user) return NextResponse.json({ error: "Your session is invalid. Sign in again." }, { status: 401 });

    const body = await request.json();
    const roomName = typeof body.roomName === "string" ? body.roomName.trim() : "";
    const mode = body.mode === "host" ? "host" : "viewer";
    if (!/^[a-zA-Z0-9_-]{3,64}$/.test(roomName)) {
      return NextResponse.json({ error: "Room name must be 3–64 letters, numbers, dashes or underscores." }, { status: 400 });
    }

    const token = new AccessToken(apiKey, apiSecret, {
      identity: user.id,
      name: (user.user_metadata?.display_name || user.email || "Fanclub member").toString().slice(0, 80),
      ttl: "2h",
    });
    token.addGrant({ roomJoin: true, room: roomName, canPublish: mode === "host", canSubscribe: true, canPublishData: true });
    return NextResponse.json({ token: await token.toJwt(), serverUrl: livekitUrl, roomName });
  } catch {
    return NextResponse.json({ error: "Could not create a live session token." }, { status: 500 });
  }
}