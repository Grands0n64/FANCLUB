"use client";
import {useState} from "react";
import {createClient} from "@/lib/supabase/client";

const BTC_WALLET="1HxpFiB5fpL2oPoxFcPiGB7JcHFauqzs2o";
const USDT_BEP20_WALLET="0x6588cd478cf2b229e72fa9c81f983d7922d8a840";
type Level="noble"|"royal"|"sovereign";
const PRICES:Record<Level,number>={noble:5,royal:15,sovereign:30};
export default function VerificationPaymentCheckout({level}:{level:Level}){
 const [method,setMethod]=useState<"bitcoin"|"usdt_bep20">("bitcoin");
 const [reference,setReference]=useState("");const [busy,setBusy]=useState(false);const [notice,setNotice]=useState("");const [paymentId,setPaymentId]=useState("");
 const sb=createClient();
 async function submit(e:React.FormEvent){e.preventDefault();if(!sb)return;const {data:{user}}=await sb.auth.getUser();if(!user){setNotice("Sign in to buy verification.");return;}
 if(method==="bitcoin"&&!/^[a-fA-F0-9]{64}$/.test(reference.trim())){setNotice("Enter the full 64-character Bitcoin transaction ID.");return;}
 if(method==="usdt_bep20"&&!/^0x[a-fA-F0-9]{64}$/.test(reference.trim())){setNotice("Enter the full BNB Smart Chain transaction hash.");return;}
 setBusy(true);const {data,error}=await sb.from("verification_payment_submissions").insert({user_id:user.id,verification_level:level,amount_usd:PRICES[level],payment_method:method,transaction_reference:reference.trim(),status:"pending"}).select("id").single();
 if(error)setNotice("Payment submission failed: "+error.message);else{setPaymentId(data.id);setNotice("Payment submitted for admin review. Your verification will be updated after the payment and account review are approved.");setReference("");}setBusy(false);
 }
 const wallet=method==="bitcoin"?BTC_WALLET:USDT_BEP20_WALLET;
 return <section className="workspace-card" style={{marginTop:14,padding:18}}><h3>Pay for {level.charAt(0).toUpperCase()+level.slice(1)} verification</h3><strong style={{fontSize:26}}>${PRICES[level]}.00 USD</strong><form className="profile-edit" onSubmit={submit}><label>Payment method<select value={method} onChange={e=>setMethod(e.target.value as typeof method)}><option value="bitcoin">Bitcoin (BTC)</option><option value="usdt_bep20">USDT · BNB Smart Chain (BEP20)</option></select></label><p>Send exactly the equivalent of ${PRICES[level]} USD using the selected network to this FANCLUB wallet:</p><code style={{display:"block",overflowWrap:"anywhere",padding:12}}>{wallet}</code><label>Transaction hash / reference<input required value={reference} onChange={e=>setReference(e.target.value.trim())} placeholder={method==="bitcoin"?"Paste Bitcoin TXID":"Paste BNB Smart Chain transaction hash"}/></label><button className="button" disabled={busy}>{busy?"Submitting…":"Submit payment for review"}</button></form>{notice&&<p role="status">{notice}</p>}{paymentId&&<small>Payment reference: {paymentId}</small>}<p className="muted">Crypto transfers are checked manually. Do not send funds until you have confirmed the network and amount.</p></section>;
}
