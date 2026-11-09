"use client";

import { useEffect, useState, useRef, type FormEvent } from "react";
import { Track } from "livekit-client";
import { LiveKitRoom, RoomAudioRenderer, useChat, useLocalParticipant, useParticipants, useTracks, VideoTrack } from "@livekit/components-react";
import "@livekit/components-styles";

type Props = { displayName: string };
type LiveRoom = { roomName: string; participantCount: number; creatorName: string };

function LiveExperience({ mode, roomName, onLeave }: { mode: "host" | "viewer"; roomName: string; onLeave: () => void }) {
  const participants = useParticipants();
  const cameraTracks = useTracks([Track.Source.Camera]);
  const { localParticipant } = useLocalParticipant();
  const { chatMessages, send } = useChat();
  const [message, setMessage] = useState("");
  const [torchOn, setTorchOn] = useState(false);
  const [torchSupported, setTorchSupported] = useState(false);
  const [torchNotice, setTorchNotice] = useState("");
  const [torchBusy, setTorchBusy] = useState(false);
  const chatEnd = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const publication = localParticipant.getTrackPublication(Track.Source.Camera);
    const mediaTrack = publication?.track?.mediaStreamTrack;
    const capabilities = mediaTrack?.getCapabilities?.() as MediaTrackCapabilities & { torch?: boolean } | undefined;
    setTorchSupported(Boolean(capabilities?.torch));
  }, [localParticipant]);

  useEffect(() => { chatEnd.current?.scrollIntoView({ behavior: "smooth" }); }, [chatMessages.length]);

  async function toggleTorch() {
    const mediaTrack = localParticipant.getTrackPublication(Track.Source.Camera)?.track?.mediaStreamTrack;
    if (!mediaTrack) { setTorchNotice("Turn on your camera first."); return; }
    const capabilities = mediaTrack.getCapabilities?.() as MediaTrackCapabilities & { torch?: boolean } | undefined;
    if (!capabilities?.torch) { setTorchNotice("This camera does not support browser flashlight control. Most front cameras do not have a flash."); return; }
    setTorchBusy(true);
    try {
      await mediaTrack.applyConstraints({ advanced: [{ torch: !torchOn } as MediaTrackConstraintSet] });
      setTorchOn(!torchOn); setTorchNotice("");
    } catch { setTorchNotice("Flashlight control is not available on this device or browser."); }
    finally { setTorchBusy(false); }
  }

  async function submitMessage(event: FormEvent) {
    event.preventDefault();
    const text = message.trim();
    if (!text) return;
    try { await send(text); setMessage(""); }
    catch { setTorchNotice("Your message could not be sent. Try again."); }
  }

  return <div className="fanclub-live-experience">
    <div className="fanclub-live-video">
      <div className="fanclub-live-video-head"><span className="live-on-dot" /> LIVE <span className="live-viewer-count">◉ {participants.length} {participants.length === 1 ? "person" : "people"} here</span></div>
      {cameraTracks.length ? cameraTracks.map(track => <VideoTrack key={track.publication.trackSid} trackRef={track} />) : <div className="fanclub-live-camera-empty">{mode === "host" ? "Your camera is starting…" : "Waiting for the creator's video…"}</div>}
      <div className="fanclub-live-video-actions">
        {mode === "host" && <button className="button live-secondary small" onClick={() => void toggleTorch()} disabled={torchBusy}>{torchOn ? "Turn flashlight off" : "Flashlight"}</button>}
        <button className="button small" onClick={onLeave}>{mode === "host" ? "End / leave live" : "Leave live"}</button>
      </div>
      {torchNotice && <p className="live-device-note">{torchNotice}</p>}
    </div>
    <aside className="fanclub-live-side">
      <section className="fanclub-live-panel">
        <h3>Live chat</h3>
        <div className="fanclub-live-chat-list">
          {chatMessages.length === 0 && <p className="muted">Say hello to the creator.</p>}
          {chatMessages.map((item, index) => <div className="fanclub-live-chat-message" key={item.timestamp + "-" + index}><strong>{item.from?.name || "Fanclub member"}</strong><span>{item.message}</span></div>)}
          <div ref={chatEnd} />
        </div>
        <form className="fanclub-live-chat-form" onSubmit={submitMessage}><input value={message} onChange={event => setMessage(event.target.value)} maxLength={500} placeholder="Send a message…" /><button className="button small" type="submit" disabled={!message.trim()}>Send</button></form>
      </section>
      <section className="fanclub-live-panel">
        <h3>Top gifters</h3>
        <p className="muted">Gift leaderboard will appear here. Gifts and scores are coming soon.</p>
        <div className="fanclub-gift-placeholder"><span>✦</span><div><strong>Support this creator</strong><small>Gift sending will be available after the gift system is added.</small></div><button className="button small live-secondary" disabled>Gifts soon</button></div>
      </section>
    </aside>
    <RoomAudioRenderer />
  </div>;
}

export default function FanclubLive({ displayName }: Props) {
  const [roomName, setRoomName] = useState("");
  const [activeRoom, setActiveRoom] = useState("");
  const [token, setToken] = useState("");
  const [serverUrl, setServerUrl] = useState("");
  const [mode, setMode] = useState<"host" | "viewer">("host");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [ended, setEnded] = useState(false);
  const [liveRooms, setLiveRooms] = useState<LiveRoom[]>([]);
  const [roomsLoading, setRoomsLoading] = useState(false);
  const [roomTitle, setRoomTitle] = useState("");

  async function refreshLiveRooms() {
    setRoomsLoading(true);
    try {
      const { createClient } = await import("@/lib/supabase/client");
      const supabase = createClient();
      const { data: { session } } = await supabase?.auth.getSession() || { data: { session: null } };
      if (!session?.access_token) throw new Error("Please sign in again.");
      const response = await fetch("/api/livekit/rooms", { headers: { Authorization: "Bearer " + session.access_token }, cache: "no-store" });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Could not load live rooms.");
      setLiveRooms(data.rooms || []);
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load live rooms."); }
    finally { setRoomsLoading(false); }
  }

  useEffect(() => { void refreshLiveRooms(); const timer = window.setInterval(() => void refreshLiveRooms(), 15000); return () => window.clearInterval(timer); }, []);

  async function enterLive(nextMode: "host" | "viewer", selectedRoom?: string) {
    const name = (selectedRoom || roomName).trim();
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
        body: JSON.stringify({ roomName: name, mode: nextMode, title: roomTitle.trim().slice(0,100) }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Unable to join live room.");
      setToken(data.token); setServerUrl(data.serverUrl); setActiveRoom(name); setRoomName(name); setMode(nextMode); setEnded(false);
    } catch (e) { setError(e instanceof Error ? e.message : "Unable to join live room."); }
    finally { setBusy(false); }
  }

  if (token && activeRoom) return <div className="fanclub-live-stage">
    <div className="fanclub-live-bar"><div><strong>{mode === "host" ? "You are live" : "Watching live"} · {activeRoom}</strong><small>{mode === "host" ? "Your viewers can chat with you here." : "Send a message to the creator."}</small></div></div>
    <LiveKitRoom token={token} serverUrl={serverUrl} connect={true} audio={mode === "host"} video={mode === "host"} onDisconnected={() => { setToken(""); setActiveRoom(""); setEnded(true); }}>
      <LiveExperience mode={mode} roomName={activeRoom} onLeave={() => { setToken(""); setActiveRoom(""); setEnded(true); }} />
    </LiveKitRoom>
  </div>;

  return <div className="workspace-card">
    <span className="eyebrow">FANCLUB LIVE</span>
    <h2>Go live with your community</h2>
    <p>Start a broadcast or join a creator who is live right now.</p>
    <label className="live-room-label">Live room name<input value={roomName} onChange={e => setRoomName(e.target.value)} placeholder="e.g. victor-live" maxLength={64} /></label>
    <label className="live-room-label">Live title<input value={roomTitle} onChange={e => setRoomTitle(e.target.value)} placeholder="What are you going live about?" maxLength={100} /></label>
    <div className="live-actions"><button className="button" disabled={busy} onClick={() => void enterLive("host")}>{busy && mode === "host" ? "Connecting…" : "Start broadcasting"}</button><button className="button live-secondary" disabled={busy} onClick={() => void enterLive("viewer")}>Join by room name</button></div>
    {error && <p className="live-error" role="alert">{error}</p>}
    {ended && <p className="muted">You left the live room.</p>}
    <div className="fanclub-live-directory"><div className="fanclub-live-directory-head"><h3>Live now</h3><button className="button live-secondary small" onClick={() => void refreshLiveRooms()} disabled={roomsLoading}>{roomsLoading ? "Refreshing…" : "Refresh"}</button></div>
      {liveRooms.length === 0 ? <p className="muted">No creators are live right now.</p> : liveRooms.map(room => <div className="fanclub-live-room" key={room.roomName}><div><strong>{room.creatorName}</strong><small>{room.roomName} · {room.participantCount} watching</small></div><button className="button small" disabled={busy} onClick={() => void enterLive("viewer", room.roomName)}>Join live</button></div>)}
    </div>
  </div>;
}
