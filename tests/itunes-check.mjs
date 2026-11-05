const q = async (path, params) => { const u = new URL("https://itunes.apple.com/" + path); for (const [k,v] of Object.entries(params)) u.searchParams.set(k, v); const r = await fetch(u); const t = await r.text(); try { return JSON.parse(t).results; } catch { return "ERR " + r.status + " " + t.slice(0,100); } };
const show = (label, res) => console.log(label, Array.isArray(res) ? `${res.length}: ` + res.slice(0,4).map(r => `${r.collectionName||r.trackName||r.artistName} / ${r.artistName} [${r.collectionId||r.artistId}] ${r.releaseDate?.slice(0,10)||""}`).join(" ; ") : res);
show("album term only, us:", await q("search", { term: "No Bad Memories", entity: "album", country: "us" }));
show("artist albums:", await q("search", { term: "The Avalanches", entity: "album", country: "us", limit: 10 }));
const art = await q("search", { term: "The Avalanches", entity: "musicArtist", country: "us", limit: 1 });
show("artist:", art);
if (Array.isArray(art) && art[0]) show("artist lookup albums (sorted recent):", await q("lookup", { id: art[0].artistId, entity: "album", sort: "recent", limit: 10, country: "us" }));
show("song search:", await q("search", { term: "Avalanches Every Single Weekend", entity: "song", country: "us" }));
show("QOTSA albums:", await q("search", { term: "Queens of the Stone Age", entity: "album", country: "us", limit: 6 }));
