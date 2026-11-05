const q = async (path, params) => { const u = new URL("https://itunes.apple.com/" + path); for (const [k,v] of Object.entries({...params, country: "us"})) u.searchParams.set(k, v); try { const r = await fetch(u); return (await r.json()).results || []; } catch { return []; } };
const norm = s => (s||"").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/\s*[\(\[].*?[\)\]]/g,"").replace(/\s+-\s+(single|ep)$/,"").replace(/&/g,"and").replace(/[^\p{L}\p{N}]/gu,"");
async function findAlbum(artist, album) {
  const a = norm(artist), t = norm(album);
  const match = list => list.find(r => r.collectionId && norm(r.collectionName) === t && norm(r.artistName).includes(a.slice(0,8)))
    || list.find(r => r.collectionId && norm(r.collectionName).startsWith(t.slice(0,10)) && norm(r.artistName).includes(a.slice(0,5)));
  let hit = match(await q("search", { term: `${artist} ${album}`, entity: "album", limit: 15 }));
  if (hit) return [hit.collectionId, "album search"];
  const artists = await q("search", { term: artist, entity: "musicArtist", limit: 5 });
  const ar = artists.find(x => norm(x.artistName) === a) || artists[0];
  if (ar) { hit = match(await q("lookup", { id: ar.artistId, entity: "album", limit: 200, sort: "recent" })); if (hit) return [hit.collectionId, "artist lookup"]; }
  return [null, "none"];
}
async function findSong(artist, song, albumId) {
  const s = norm(song);
  if (albumId) { const tr = (await q("lookup", { id: albumId, entity: "song" })).filter(x => x.wrapperType === "track"); const t = tr.find(x => norm(x.trackName) === s) || tr.find(x => norm(x.trackName).startsWith(s.slice(0,10))); if (t) return [t.trackId, "album tracks"]; }
  const res = await q("search", { term: `${artist} ${song}`, entity: "song", limit: 25 });
  const t = res.find(x => norm(x.trackName) === s && norm(x.artistName).includes(norm(artist).slice(0,6)));
  return t ? [t.trackId, "song search"] : [null, "none"];
}
for (const [artist, album, song] of [["The Avalanches","No Bad Memories","Every Single Weekend"],["Queens of the Stone Age","Perfecth","Easy Street"],["PISS","you made me / skin on linen",null],["Nick Lutsko","Ends",null],["DIIV","ZIRP!",null],["Kali Malone","Burning Song",null],["Everything Everything","Poison Pop","Poison Pop"]]) {
  const [id, how] = await findAlbum(artist, album);
  let line = `${artist} – ${album}: ${id ?? "NO MATCH"} (${how})`;
  if (song) { const [sid, shw] = await findSong(artist, song, id); line += ` | "${song}": ${sid ?? "NO MATCH"} (${shw})`; }
  console.log(line);
}
