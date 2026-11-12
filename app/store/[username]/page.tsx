import MeetupStorefront from "@/components/meetup-storefront";
export default async function CreatorStorePage({params}:{params:Promise<{username:string}>}){const {username}=await params;return <MeetupStorefront username={decodeURIComponent(username)}/>;}
