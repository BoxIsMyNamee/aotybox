const q = async (path, params) => { const u = new URL("https://itunes.apple.com/" + path); for (const [k,v] of Object.entries({...params, country: "us"})) u.searchParams.set(k, v); const r = await fetch(u); return (await r.json()).results; };
const norm = s => (s||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/\s*[\(\[].*?[\)\]]/g,"").replace(/\s+-\s+(single|ep)$/,"").replace(/&/g,"and").replace(/[^\p{L}\p{N}]/gu,"");
for (const [artist, album] of [["The Avalanches","No Bad Memories"],["Queens of the Stone Age","Perfecth"],["PISS","you made me / skin on linen"],["Nick Lutsko","Ends"]]) {
  const res = await q("search", { term: `${artist} ${album}`, entity: "album", limit: 15 });
  const a = norm(artist), t = norm(album);
  const hit = res.find(r => norm(r.collectionName) === t && norm(r.artistName).includes(a.slice(0,8))) || res.find(r => norm(r.collectionName).startsWith(t.slice(0,10)) && norm(r.artistName).includes(a.slice(0,5)));
  console.log(`${artist} – ${album}:`, hit ? `${hit.collectionId} (${hit.collectionName} / ${hit.artistName})` : "NO MATCH", "| top:", res.slice(0,2).map(r=>r.collectionName+" / "+r.artistName).join("; "));
  if (hit && artist === "The Avalanches") {
    const tracks = (await q("lookup", { id: hit.collectionId, entity: "song" })).filter(x => x.wrapperType === "track");
    const s = tracks.find(x => norm(x.trackName) === norm("Every Single Weekend"));
    console.log("  song Every Single Weekend:", s ? `${s.trackId} (${s.trackName})` : "NO MATCH", `| ${tracks.length} tracks`);
  }
}
