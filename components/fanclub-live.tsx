"use client";

import { useEffect, useRef, useState } from "react";
import { Room, RoomEvent, type Participant, type Track } from "livekit-client";
import { LiveKitRoom, VideoConference, RoomAudioRenderer } from "@livekit/components-react";
import "@livekit/components-styles";

type Props = { displayName: string };
export default function FanclubLive({ displayName }: Props) {
  const [roomName, setRoomName] = useState("");
  const [activeRoom, setActiveRoom] = useState("");
  const [token, setToken] = useState("");
  const [serverUrl, setServerUrl] = useState("");
  const [mode, setMode] = useState<"host" | "viewer">("host");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [ended, setEnded] = useState(false);

  async function enterLive(nextMode: "host" | "viewer") {
    const name = roomName.trim();
    if (!/^[a-zA-Z0-9_-]{3,64}$/.test(name)) {
      setError("Use a room name with 3–64 letters, numbers, dashes or underscores.");
      return;
    }
    setBusy(true); setError("");
    try {
      const { createClient } = await import("@/lib/supabase/client");
      const supabase = createClient();
      const { data: { session } } = await supabase?.auth.getSession() || { data: { session: null } };
      if (!session?.access_token) throw new Error("Please sign in again.");
      const response = await fetch("/api/livekit/token", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + session.access_token },
        body: JSON.stringify({ roomName: name, mode: nextMode }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Unable to join live room.");
      setToken(data.token); setServerUrl(data.serverUrl); setActiveRoom(name); setMode(nextMode); setEnded(false);
    } catch (e) { setError(e instanceof Error ? e.message : "Unable to join live room."); }
    finally { setBusy(false); }
  }

  if (token && activeRoom) return <div className="fanclub-live-stage">
    <div className="fanclub-live-bar"><div><strong>{mode === "host" ? "You are live" : "Watching live"} · {activeRoom}</strong><small>{mode === "host" ? "Share this room name so viewers can join." : "You joined this live room."}</small></div><button className="button small" onClick={() => { setToken(""); setActiveRoom(""); setEnded(true); }}>Leave live</button></div>
    <LiveKitRoom token={token} serverUrl={serverUrl} connect={true} audio={mode === "host"} video={mode === "host"} onDisconnected={() => { setToken(""); setActiveRoom(""); }}>
      <VideoConference />
      <RoomAudioRenderer />
    </LiveKitRoom>
  </div>;

  return <div className="workspace-card">
    <span className="eyebrow">FANCLUB LIVE</span>
    <h2>Go live with your community</h2>
    <p>Start a live video or join a creator using their room name. Allow camera and microphone access when your browser asks.</p>
    <label className="live-room-label">Live room name<input value={roomName} onChange={e => setRoomName(e.target.value)} placeholder="e.g. victor-live" maxLength={64} /></label>
    <div className="live-actions"><button className="button" disabled={busy} onClick={() => void enterLive("host")}>{busy && mode === "host" ? "Connecting…" : "Start broadcasting"}</button><button className="button live-secondary" disabled={busy} onClick={() => void enterLive("viewer")}>Join as viewer</button></div>
    {error && <p className="live-error" role="alert">{error}</p>}
    {ended && <p className="muted">You left the live room.</p>}
    <p className="muted">Only share room names with people you want to invite. Live rooms are not yet listed in a public directory.</p>
  </div>;
}