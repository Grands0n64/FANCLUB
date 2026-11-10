"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type CreatorRate = { user_id:string; rate_30_min:number; rate_hour:number; rate_half_day:number; rate_overnight:number; currency:string; meetup_options:string[]; enabled:boolean; profiles?:{username:string;display_name:string;bio?:string}|null };
type Booking = { id:string; booking_code:string; creator_id:string; starts_at:string; duration_minutes:number; meetup_option:string; total_amount:number; currency:string; status:string; created_at:string };
const OPTIONS=["Coffee meetup","Lunch or dinner","Public event","Creator meet-and-greet","Video call","Photography session"];
const DURATIONS=[30,60,90,120,150,180,210,240,300,360,420,480,540,600,660,720,780,840,900,960,1020,1080,1140,1200,1260,1320,1380,1440];
const money=(n:number,c:string)=>new Intl.NumberFormat("en-US",{style:"currency",currency:c||"USD",maximumFractionDigits:2}).format(n);
export default function MeetupBookings({profileId}:{profileId:string}){
 const [rates,setRates]=useState<CreatorRate[]>([]);
 const [mine,setMine]=useState<CreatorRate|null>(null);
 const [bookings,setBookings]=useState<Booking[]>([]);
 const [selected,setSelected]=useState<CreatorRate|null>(null);
 const [duration,setDuration]=useState(30);
 const [option,setOption]=useState(OPTIONS[0]);
 const [date,setDate]=useState("");
 const [time,setTime]=useState("12:00");
 const [rate30,setRate30]=useState("25");
 const [rateHour,setRateHour]=useState("40");
 const [rateHalf,setRateHalf]=useState("120");
 const [rateOvernight,setRateOvernight]=useState("200");
 const [currency,setCurrency]=useState("USD");
 const [enabled,setEnabled]=useState(false);
 const [saving,setSaving]=useState(false);
 const [notice,setNotice]=useState("");
 const [receipt,setReceipt]=useState<Booking|null>(null);
 const sb=createClient();
 async function load(){
  if(!sb)return;
  const [{data:rows},{data:own},{data:mineBookings}]=await Promise.all([
   sb.from("meetup_booking_profiles").select("user_id,rate_30_min,rate_hour,rate_half_day,rate_overnight,currency,meetup_options,enabled,profiles:profiles!meetup_booking_profiles_user_id_fkey(username,display_name,bio)").eq("enabled",true).order("created_at",{ascending:false}),
   sb.from("meetup_booking_profiles").select("user_id,rate_30_min,rate_hour,rate_half_day,rate_overnight,currency,meetup_options,enabled").eq("user_id",profileId).maybeSingle(),
   sb.from("meetup_bookings").select("id,booking_code,creator_id,starts_at,duration_minutes,meetup_option,total_amount,currency,status,created_at").or("customer_id.eq."+profileId+",creator_id.eq."+profileId).order("created_at",{ascending:false}).limit(30)
  ]);
  setRates((rows||[]) as unknown as CreatorRate[]);
  if(own){const o=own as unknown as CreatorRate;setMine(o);setRate30(String(o.rate_30_min));setRateHour(String(o.rate_hour));setRateHalf(String(o.rate_half_day));setRateOvernight(String(o.rate_overnight));setCurrency(o.currency);setEnabled(o.enabled);}
  setBookings((mineBookings||[]) as Booking[]);
 }
 useEffect(()=>{void load();},[profileId]);
 const price=useMemo(()=>{const c=selected;if(!c)return 0;const half=c.rate_half_day;const hour=c.rate_hour;if(duration===240)return half;if(duration<240){const hours=Math.floor(duration/60),halves=(duration%60)/30;return hours*hour+halves*c.rate_30_min;}if(duration===720)return c.rate_overnight;if(duration<720)return half+Math.ceil((duration-240)/60)*hour;return c.rate_overnight+Math.ceil((duration-720)/60)*hour;},[selected,duration]);
 async function saveRates(e:React.FormEvent){e.preventDefault();if(!sb)return;const a=Number(rate30),b=Number(rateHour),c=Number(rateHalf),d=Number(rateOvernight);if([a,b,c,d].some(x=>!Number.isFinite(x)||x<=0)){setNotice("Enter valid prices for all three booking options.");return;}setSaving(true);const payload={user_id:profileId,rate_30_min:a,rate_hour:b,rate_half_day:c,rate_overnight:d,currency,meetup_options:OPTIONS,enabled,updated_at:new Date().toISOString()};const {error}=await sb.from("meetup_booking_profiles").upsert(payload,{onConflict:"user_id"});setNotice(error?"Could not save rates: "+error.message:"Your meetup booking options have been saved.");setSaving(false);await load();}
 async function reserve(){if(!sb||!selected||!date||!time)return;const starts=new Date(date+"T"+time);if(Number.isNaN(starts.getTime())||starts.getTime()<=Date.now()){setNotice("Choose a future date and time.");return;}setSaving(true);const {data,error}=await sb.rpc("create_meetup_booking",{p_creator_id:selected.user_id,p_starts_at:starts.toISOString(),p_duration_minutes:duration,p_meetup_option:option});const created=Array.isArray(data)?data[0]:data;if(error||!created){setNotice("Booking request failed: "+(error?.message||"No booking reference returned."));}else{const booking=created as Booking;setReceipt(booking);setBookings(old=>[booking,...old]);setNotice("Your booking reference is ready. Payment is not connected yet, so this is not a paid confirmation.");}setSaving(false);}
 return <div className="meetup-booking-page">
  <section className="meetup-hero"><span className="eyebrow">FANCLUB MEETUPS</span><h2>Make time to meet.</h2><p>Book creator meet-and-greets and social appointments with clear prices, chosen options and a scheduled time.</p><div className="meetup-hero-tags"><span>30-minute sessions</span><span>Set your own rates</span><span>Booking reference</span></div></section>
  {notice&&<div className="meetup-notice">{notice}</div>}
  <div className="meetup-columns">
   <section className="meetup-panel"><div className="meetup-panel-title"><div><span className="eyebrow">FOR CREATORS</span><h3>Your meetup rates</h3></div><span className="meetup-mini-icon">＋</span></div><p className="meetup-muted">Set prices for social meetups and creator appearances. You control when your listing is available.</p>
    <form onSubmit={saveRates} className="meetup-rate-form"><div className="meetup-rate-grid"><label>30 minutes<input type="number" min="1" step="0.01" value={rate30} onChange={e=>setRate30(e.target.value)}/></label><label>1 hour<input type="number" min="1" step="0.01" value={rateHour} onChange={e=>setRateHour(e.target.value)}/></label><label>Half day (4 hours)<input type="number" min="1" step="0.01" value={rateHalf} onChange={e=>setRateHalf(e.target.value)}/></label><label>Overnight (12 hours)<input type="number" min="1" step="0.01" value={rateOvernight} onChange={e=>setRateOvernight(e.target.value)}/></label><label>Currency<select value={currency} onChange={e=>setCurrency(e.target.value)}><option value="USD">USD ($)</option><option value="NGN">NGN (₦)</option><option value="GBP">GBP (£)</option><option value="EUR">EUR (€)</option></select></label></div><label className="meetup-enable"><input type="checkbox" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/> Show my meetup listing to members</label><button className="button" disabled={saving}>{saving?"Saving…":"Save meetup rates"}</button></form>
   </section>
   <section className="meetup-panel"><div className="meetup-panel-title"><div><span className="eyebrow">DISCOVER</span><h3>Book a meetup</h3></div><span className="meetup-mini-icon">⌕</span></div>{rates.length===0?<div className="meetup-empty">No creators have opened meetup bookings yet. Be the first to publish your rates.</div>:<div className="meetup-creator-list">{rates.map(r=><button className={selected?.user_id===r.user_id?"meetup-creator selected":"meetup-creator"} key={r.user_id} onClick={()=>{setSelected(r);setOption(r.meetup_options?.[0]||OPTIONS[0]);}}><span className="meetup-avatar">{(r.profiles?.display_name||r.profiles?.username||"F").slice(0,1).toUpperCase()}</span><span className="meetup-creator-info"><strong>{r.profiles?.display_name||r.profiles?.username||"Creator"}</strong><small>@{r.profiles?.username||"member"}</small></span><span className="meetup-start-price">{money(r.rate_30_min,r.currency)}<small>/30 min</small></span></button>)}</div>}
    {selected&&<div className="meetup-checkout"><h4>Choose your appointment</h4><label>What would you like to book?<select value={option} onChange={e=>setOption(e.target.value)}>{(selected.meetup_options?.length?selected.meetup_options:OPTIONS).map(x=><option key={x}>{x}</option>)}</select></label><label>Duration<select value={duration} onChange={e=>setDuration(Number(e.target.value))}>{DURATIONS.map(x=><option key={x} value={x}>{x<60?x+" minutes":x===240?"Half day · 4 hours":x===720?"Overnight · 12 hours":x%60===0?(x/60)+" hours":Math.floor(x/60)+"h "+(x%60)+"m"}</option>)}</select></label><div className="meetup-date-row"><label>Date<input type="date" min={new Date().toISOString().slice(0,10)} value={date} onChange={e=>setDate(e.target.value)}/></label><label>Start time<input type="time" value={time} onChange={e=>setTime(e.target.value)}/></label></div><div className="meetup-total"><span>Estimated total</span><strong>{money(price,selected.currency)}</strong></div><button className="button" disabled={saving||!date||!time} onClick={()=>void reserve()}>{saving?"Preparing…":"Request this booking"}</button><small className="meetup-payment-note">Payment checkout is not connected yet. A request here does not reserve a confirmed paid slot.</small></div>}
   </section>
  </div>
  {receipt&&<section className="meetup-receipt"><span className="eyebrow">BOOKING REFERENCE</span><h3>Request received</h3><strong className="meetup-code">{receipt.booking_code}</strong><p>{receipt.meetup_option} · {receipt.duration_minutes} minutes</p><p>{new Date(receipt.starts_at).toLocaleString()}</p><p>{money(receipt.total_amount,receipt.currency)} · <b>Awaiting payment</b></p><small>This is a booking request reference, not a paid receipt.</small></section>}
  <section className="meetup-panel meetup-bookings-history"><div className="meetup-panel-title"><div><span className="eyebrow">YOUR ACTIVITY</span><h3>Booking history</h3></div></div>{bookings.length===0?<p className="meetup-muted">Your booking requests will appear here.</p>:bookings.map(b=><div className="meetup-history-row" key={b.id}><div><strong>{b.booking_code}</strong><small>{b.meetup_option} · {b.duration_minutes} min · {new Date(b.starts_at).toLocaleString()}</small></div><span className={"meetup-status "+b.status}>{b.status.replaceAll("_"," ")}</span></div>)}</section>
 </div>;
}
