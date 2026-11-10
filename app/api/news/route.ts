import { NextRequest, NextResponse } from "next/server";

export const revalidate = 0;
type Story = { title: string; link: string; source: string; published: string; description: string; image?: string };
function decode(s: string) {
  return s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/\s+/g, " ").trim();
}
function parse(xml: string, source: string): Story[] {
  return Array.from(xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)).slice(0, 30).map(m => {
    const block = m[1];
    const get = (tag: string) => {
      const x = block.match(new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)</" + tag + ">", "i"));
      return x ? decode(x[1]) : "";
    };
    const media = block.match(/<(?:media:content|media:thumbnail|enclosure)[^>]*(?:url|href)="([^"]+)"[^>]*\/?>/i);
    return { title: get("title"), link: get("link") || ((block.match(/<link[^>]*href="([^"]+)"/i) || [])[1] || ""), source, published: get("pubDate") || get("published"), description: get("description") || get("summary"), image: media?.[1] };
  }).filter(x => x.title && x.link);
}
const clubs = ["Arsenal", "Chelsea", "Liverpool", "Manchester United", "Manchester City", "Tottenham", "Newcastle United", "Real Madrid", "Barcelona", "Atletico Madrid", "Bayern Munich", "Borussia Dortmund", "Paris Saint-Germain", "Juventus", "Inter Milan", "AC Milan", "Napoli"];
const googleNews = (q: string) => "https://news.google.com/rss/search?q=" + encodeURIComponent(q) + "&hl=en-US&gl=US&ceid=US:en";
async function readFeed(source: string, url: string): Promise<Story[]> {
  try { const r = await fetch(url, { cache: "no-store", headers: { "user-agent": "FANCLUB/1.0 news reader" } }); if (!r.ok) return []; return parse(await r.text(), source); }
  catch { return []; }
}
export async function GET(request: NextRequest) {
  const category = (request.nextUrl.searchParams.get("category") || "world").toLowerCase();
  const club = (request.nextUrl.searchParams.get("club") || "").trim();
  let feeds: [string, string][] = [];
  if (category === "football") feeds = [["BBC Sport Football", "https://feeds.bbci.co.uk/sport/football/rss.xml"], ["Sky Sports Football", "https://www.skysports.com/rss/11095"], ["The Guardian Football", "https://www.theguardian.com/football/rss"]];
  else if (category === "transfers") feeds = [["Transfer News", googleNews("football transfer news OR transfer rumours")], ["BBC Sport Football", "https://feeds.bbci.co.uk/sport/football/rss.xml"], ["Sky Sports Football", "https://www.skysports.com/rss/11095"]];
  else if (category === "adult") feeds = [["Adult Industry News", "https://www.xbiz.com/rss/all.xml"], ["Adult FYI", "https://adultfyi.com/feed.xml"]];\n  else if (category === "clubs") {
    const safe = clubs.find(n => n.toLowerCase() === club.toLowerCase());
    if (!safe) return NextResponse.json({ items: [], updatedAt: new Date().toISOString(), error: "Choose a supported club." }, { headers: { "Cache-Control": "no-store" } });
    feeds = [[safe + " News", googleNews('"' + safe + '" football news')], [safe + " Transfer News", googleNews('"' + safe + '" transfer news')]];
  } else feeds = [["BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml"], ["The Guardian World", "https://www.theguardian.com/world/rss"]];
  const all = await Promise.all(feeds.map(([source, url]) => readFeed(source, url)));
  const items = all.flat().sort((a, b) => new Date(b.published).getTime() - new Date(a.published).getTime()).filter((x, i, a) => a.findIndex(y => y.link === x.link) === i).slice(0, 30);
  return NextResponse.json({ items, updatedAt: new Date().toISOString(), category, club }, { headers: { "Cache-Control": "no-store, max-age=0" } });
}
