const base = "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/artist/183-kanye-west/";
async function get(u) { for (let i = 0; i < 3; i++) { try { return await (await fetch(u)).text(); } catch (e) { await new Promise(r => setTimeout(r, 4000)); } } return ""; }
const h = await get(base);
const ap = [...h.matchAll(/<a[^>]+href="([^"]*)"[^>]*>\s*(Appears On|Producer|Feature)[^<]*/gi)].map(m => m[1] + " => " + m[2]);
console.log("CREDITS:", ap.join(" | "));
for (const key of ["artistCriticScore", "artistUserScore", "Based on", "Followers", "detailRow"]) {
  const k = h.indexOf(key); console.log("KEY", key, ":", k < 0 ? "none" : h.slice(Math.max(0, k - 300), k + 600).replace(/\n/g, " "));
}
const fk = h.indexOf("facetContent"); console.log("FACETCONTENT:", fk < 0 ? "none" : h.slice(fk - 200, fk + 400));
for (const t of ["reissue", "single", "live"]) {
  const r = await get(base + "?type=" + t);
  console.log("TYPE", t, "len", r.length, "albumBlocks", (r.match(/class="albumBlock/g) || []).length, "title", (r.match(/<title>([^<]*)/) || [])[1]);
  const i = r.indexOf("albumBlock"); console.log("  first:", r.slice(i - 100, i + 300).replace(/\n/g, " "));
}
