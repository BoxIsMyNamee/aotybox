import { DOMParser } from "linkedom";
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const get = async (u) => { try { const r = await fetch(u, { headers: { "User-Agent": UA, Accept: "*/*" } }); const t = await r.text(); return [r.status, t]; } catch (e) { return [0, String(e)]; } };

console.log("=== Genius search API");
let [st, body] = await get("https://genius.com/api/search/song?q=" + encodeURIComponent("Kendrick Lamar HUMBLE.") + "&per_page=3");
console.log(st, body.slice(0, 300));
let id = null;
try { id = JSON.parse(body).response.sections[0].hits[0].result.id; } catch {}
console.log("song id", id);
if (id) {
  for (const p of [`/api/songs/${id}?text_format=plain`, `/api/referents?song_id=${id}&text_format=plain&per_page=3`, `/api/songs/${id}/comments?text_format=plain&per_page=3`]) {
    [st, body] = await get("https://genius.com" + p);
    console.log("=== " + p, st);
    try {
      const j = JSON.parse(body).response;
      if (j.song) console.log(" keys:", Object.keys(j.song).join(",").slice(0, 500), "\n desc:", JSON.stringify(j.song.description).slice(0, 200), "\n url:", j.song.url, "path:", j.song.path);
      if (j.referents) console.log(" ref0:", JSON.stringify(j.referents[0]).slice(0, 600));
      if (j.comments) console.log(" c0:", JSON.stringify(j.comments[0]).slice(0, 500));
    } catch { console.log(body.slice(0, 200)); }
  }
}
console.log("=== Genius lyrics page (live)");
[st, body] = await get("https://genius.com/Kendrick-lamar-humble-lyrics");
console.log(st, body.length, (body.match(/data-lyrics-container/g) || []).length, "containers");
if (st !== 200 || !/data-lyrics-container/.test(body)) {
  [st, body] = await get("https://web.archive.org/web/2026id_/https://genius.com/Kendrick-lamar-humble-lyrics");
  console.log("archive", st, body.length, (body.match(/data-lyrics-container/g) || []).length, "containers");
}
const doc = new DOMParser().parseFromString(body, "text/html");
const c = doc.querySelector("[data-lyrics-container]");
console.log("container sample:", c ? c.outerHTML.slice(0, 1500) : "none");

console.log("\n=== AOTY profile (archive)");
for (const p of ["/user/rollo_p/", "/user/rollo_p/ratings/"]) {
  [st, body] = await get("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org" + p);
  const d = new DOMParser().parseFromString(body, "text/html");
  console.log("--", p, st, body.length, "title", d.title, "blocks", d.querySelectorAll(".albumBlock").length);
  const og = d.querySelector('meta[property="og:image"]'); console.log(" og:image", og && og.getAttribute("content"));
  const text = d.body ? d.body.textContent.replace(/\s+/g, " ") : "";
  console.log(" stats:", (text.match(/[\d,]+\s*(Ratings|Reviews|Lists|Followers|Following)/gi) || []).slice(0, 10).join(" | "));
  const b = d.querySelector(".albumBlock"); console.log(" block0:", b ? b.outerHTML.replace(/\s+/g, " ").slice(0, 1200) : "none");
  const prof = d.querySelector(".profileHeadLeft, .profileHeader, .userTopBox, .profileTop"); console.log(" head:", prof ? prof.outerHTML.replace(/\s+/g, " ").slice(0, 1500) : "none");
  const sects = [...d.querySelectorAll(".sectionHeading, h2")].map(x => x.textContent.trim()).slice(0, 15); console.log(" sections:", sects.join(" | "));
}
console.log("\n=== AOTY home header (archive) user link sample");
[st, body] = await get("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/");
const hd = new DOMParser().parseFromString(body, "text/html");
const ul = hd.querySelector("a[href*='/user/'] img"); console.log(" logged-out archive, user link img:", ul ? ul.parentElement.outerHTML.slice(0, 300) : "none");
const hdr = hd.querySelector("header, .header, #header, .headerBar"); console.log(" header:", hdr ? hdr.outerHTML.replace(/\s+/g, " ").slice(0, 1200) : "none");
