import { NextRequest, NextResponse } from "next/server";
import { RoomServiceClient } from "livekit-server-sdk";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  try {
    const authorization = request.headers.get("authorization") || "";
    const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!accessToken) return NextResponse.json({ error: "Sign in to view live rooms." }, { status: 401 });

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    const livekitUrl = process.env.LIVEKIT_URL;
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    if (!supabaseUrl || !supabaseAnonKey || !livekitUrl || !apiKey || !apiSecret) {
      return NextResponse.json({ error: "Live streaming is not configured." }, { status: 503 });
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, { auth: { persistSession: false } });
    const { data: { user }, error } = await supabase.auth.getUser(accessToken);
    if (error || !user) return NextResponse.json({ error: "Your session is invalid." }, { status: 401 });

    const service = new RoomServiceClient(livekitUrl, apiKey, apiSecret);
    const result = await service.listRooms();
    const activeRooms = (result || []).filter(room => room.numParticipants > 0).slice(0, 50);
    const rooms = await Promise.all(activeRooms.map(async room => {
      try {
        const participants = await service.listParticipants(room.name);
        const host = participants.find(participant => participant.permission?.canPublish !== false) || participants[0];
        return {
          roomName: room.name,
          participantCount: room.numParticipants,
          creatorName: host?.name || "FANCLUB creator",
        };
      } catch {
        return { roomName: room.name, participantCount: room.numParticipants, creatorName: "FANCLUB creator" };
      }
    }));
    return NextResponse.json({ rooms });
  } catch {
    return NextResponse.json({ error: "Could not load live rooms." }, { status: 500 });
  }
}
