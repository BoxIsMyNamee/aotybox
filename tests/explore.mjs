import { DOMParser } from "linkedom";
const get = async (u) => { try { const r = await fetch(u, { headers: { "User-Agent": "Mozilla/5.0" } }); return [r.status, await r.text()]; } catch (e) { return [0, String(e)]; } };
let [st, body] = await get("https://web.archive.org/web/2026id_/https://genius.com/Kendrick-lamar-humble-lyrics");
const doc = new DOMParser().parseFromString(body, "text/html");
const cs = doc.querySelectorAll("[data-lyrics-container]");
console.log("containers", cs.length);
const c = cs[0];
// strip header, show first anchors
const hdr = c.querySelector("[data-exclude-from-selection]"); if (hdr) hdr.remove();
console.log("C0:", c.innerHTML.replace(/\s+/g, " ").slice(0, 2500));
const a = c.querySelector("a"); console.log("A0:", a ? a.outerHTML.slice(0, 600) : "none");
// song id + description in page
const m = body.match(/"song_id":(\d+)|songId\\?":(\d+)|"id":(\d+),"_type":"song"/); console.log("songid hint", m && m[0]);
const meta = doc.querySelector('meta[name="newrelic-resource-path"], meta[property="twitter:app:url:iphone"], meta[name="twitter:app:url:iphone"]'); console.log("meta", meta && meta.outerHTML);
const ab = doc.querySelector("[class*='SongDescription'], [class*='About__Container']"); console.log("about:", ab ? ab.textContent.slice(0, 300) : "none");

[st, body] = await get("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/album/2915-outkast-aquemini.php");
const d2 = new DOMParser().parseFromString(body, "text/html");
const links = [...d2.querySelectorAll(".userReviewName a")].slice(0, 5).map(x => x.getAttribute("href"));
console.log("user hrefs:", links.join(" "));
for (const href of links.slice(0, 4)) {
  const path = href.replace(/^https?:\/\/[^/]+/, "").replace(/^\/web\/\d+\w*\/https?:\/\/[^/]+/, "");
  [st, body] = await get("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org" + path);
  const d = new DOMParser().parseFromString(body, "text/html");
  console.log("--", path, st, body.length, "title", d.title, "blocks", d.querySelectorAll(".albumBlock").length);
  if (st !== 200) continue;
  const text = d.body ? d.body.textContent.replace(/\s+/g, " ") : "";
  console.log(" stats:", (text.match(/[\d,.K]+\s*(Ratings|Reviews|Lists|Followers|Following|Listens|Likes)/gi) || []).slice(0, 12).join(" | "));
  const og = d.querySelector('meta[property="og:image"]'); console.log(" og:image", og && og.getAttribute("content"));
  const sects = [...d.querySelectorAll(".sectionHeading, h2, h1")].map(x => x.textContent.trim()).slice(0, 15); console.log(" sections:", sects.join(" | "));
  const b = d.querySelector(".albumBlock"); console.log(" block0:", b ? b.outerHTML.replace(/\s+/g, " ").slice(0, 1400) : "none");
  const stat = [...d.querySelectorAll("*")].find(e => /^\s*Ratings\s*$/i.test(e.textContent) && e.children.length === 0);
  console.log(" ratings label ctx:", stat ? stat.parentElement.parentElement.outerHTML.replace(/\s+/g, " ").slice(0, 900) : "none");
  const av = d.querySelector(".profileImage img, .userImage img, img[src*='/user/']"); console.log(" avatar:", av && av.outerHTML.slice(0, 300));
  break;
}
