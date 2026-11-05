// Runs Resources/extract.js against archived AOTY pages (Wayback Machine raw HTML).
import { DOMParser } from "linkedom";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
globalThis.DOMParser = DOMParser;
const { aotyExtract, aotyIsChallenge, aotyGenericBlocks } = require("../AOTYClient/Scripts/extract.js");

const pages = [
  ["blocks", "/releases/this-week/"],
  ["blocks", "/releases/"],
  ["blocks", "/upcoming/"],
  ["blocks", "/releases/singles/"],
  ["blocks", "/releases/this-week/singles/"],
  ["chart", "/ratings/6-highest-rated/2025/1"],
  ["chart", "/ratings/user-highest-rated/2025/1"],
  ["album", "/album/2915-outkast-aquemini.php"],
  ["album", "/album/1998-kanye-west-my-beautiful-dark-twisted-fantasy.php"],
  ["userReviews", "/album/2915-outkast-aquemini/user-reviews/"],
  ["userReviews", "/album/1998-kanye-west-my-beautiful-dark-twisted-fantasy/user-reviews/"],
];

let failures = 0;
const check = (cond, msg) => { if (!cond) { failures++; console.log("  FAIL:", msg); } };

for (const [kind, path] of pages) {
  const url = `https://web.archive.org/web/2026id_/https://www.albumoftheyear.org${path}`;
  console.log(`\n=== ${kind} ${path}`);
  let html = "";
  try {
    let r;
    for (let attempt = 0; attempt < 3; attempt++) {
      try { r = await fetch(url, { redirect: "follow", headers: { "User-Agent": "Mozilla/5.0 aotybox-ci" } }); } catch (e) { r = null; }
      if (r && r.status !== 429 && r.status !== 503) break;
      await new Promise(res => setTimeout(res, 15000));
    }
    if (!r) { console.log("  archive unreachable, skipping"); continue; }
    html = await r.text();
    console.log(`  archive HTTP ${r.status}, ${html.length} bytes, final ${r.url.slice(0, 110)}`);
    if (!r.ok || html.length < 5000) { console.log("  (no usable snapshot, skipping)"); continue; }
  } catch (e) { console.log("  fetch error", e.message); continue; }
  if (aotyIsChallenge(html, 200)) { console.log("  snapshot is a Cloudflare page, skipping"); continue; }

  const out = aotyExtract(kind, html, "https://www.albumoftheyear.org" + path);
  if (kind === "blocks") {
    console.log(`  ${out.albums.length} albums`);
    console.log("  first:", JSON.stringify(out.albums[0]));
    check(out.albums.length >= 5, "expected >= 5 album blocks");
    const g = aotyGenericBlocks(new DOMParser().parseFromString(html, "text/html"));
    console.log(`  generic fallback: ${g.length} albums; first: ${JSON.stringify(g[0])}`);
    check(g.length >= out.albums.length * 0.8, "generic fallback finds most albums");
    check(g[0] && g[0].title && g[0].url.includes("/album/"), "generic fallback first item");
    const a = out.albums[0] || {};
    check(a.url && a.url.includes("/album/"), "album url");
    check(a.artist && a.title, "artist + title");
    check(out.albums.filter(x => x.cover && x.cover.startsWith("http")).length >= out.albums.length / 2, "most albums have covers");
  } else if (kind === "chart") {
    console.log(`  ${out.items.length} items, totalPages ${out.totalPages}`);
    console.log("  first:", JSON.stringify(out.items[0]));
    check(out.items.length >= 10, "expected >= 10 chart rows");
    const i = out.items[0] || {};
    check(i.rank === 1, "rank 1 first");
    check(i.artist && i.album, "artist + album split");
    check(typeof i.score === "number", "numeric score");
  } else if (kind === "userReviews") {
    console.log(`  ${out.reviews.length} reviews, total ${out.total}, pages ${out.totalPages}, dist ${out.distribution.length}`);
    console.log("  first:", JSON.stringify(out.reviews[0])?.slice(0, 400));
    console.log("  dist:", JSON.stringify(out.distribution.slice(0, 3)));
    check(out.reviews.length >= 10, "user reviews parsed");
    check(out.reviews.filter(r => r.avatar).length >= out.reviews.length / 2, "most reviews have avatars");
    check(out.total > out.reviews.length && out.totalPages > 1, "pagination");
  } else {
    const s = { ...out, tracklist: out.tracklist.length, reviews: out.reviews.length,
      popularUserReviews: out.popularUserReviews.length, similarAlbums: out.similarAlbums.length, moreAlbums: out.moreAlbums.length };
    console.log("  summary:", JSON.stringify(s));
    console.log("  track1:", JSON.stringify(out.tracklist[0]));
    console.log("  review1:", JSON.stringify(out.reviews[0])?.slice(0, 300));
    console.log("  user1:", JSON.stringify(out.popularUserReviews[0])?.slice(0, 300));
    check(out.title && out.artist, "title + artist");
    check(out.cover && out.cover.startsWith("http"), "cover");
    check(typeof out.criticScore === "number", "critic score");
    check(typeof out.userScore === "number", "user score");
    check(out.tracklist.length >= 5, "tracklist");
    check(out.tracklist[0] && out.tracklist[0].title && !/\d:\d\d/.test(out.tracklist[0].title), "clean track title");
    check(out.reviews.length >= 3, "critic reviews");
    check(out.popularUserReviews.some(r => r.avatar), "user review avatars");
    check(out.reviews.filter(r => r.image && r.image.startsWith("http")).length >= out.reviews.length / 2, "critic logos");
    console.log("  logo:", out.reviews[0] && out.reviews[0].image);
  }
}
// Signed-in user detection must ignore reviewer avatars on a logged-out page
{
  console.log("\n=== me (logged-out homepage)");
  let r, html = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    try { r = await fetch("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/", { headers: { "User-Agent": "Mozilla/5.0" } }); html = await r.text(); }
    catch (e) { r = { ok: false, status: "unreachable" }; html = ""; }
    if (r.status !== 429) break;
    await new Promise(res => setTimeout(res, 25000));
  }
  if (r.ok && html.length > 20000) {
    const out = aotyExtract("me", html, "https://www.albumoftheyear.org/");
    const avatars = (html.match(/\/user\/thumbs\//g) || []).length;
    console.log(`  page has ${avatars} user avatars; detected:`, JSON.stringify(out));
    check(out.username === null, "no username on a logged-out page");
  } else console.log("  no snapshot", r.status);
  // Synthetic signed-in header
  const fake = '<html><body><div class="headerContainer"><a href="/user/harbor/"><img src="https://cdn.albumoftheyear.org/user/thumbs/harbor_1700000000.jpg"></a></div>' +
    '<div class="albumReviewRow"><div class="userReviewImage"><a href="/user/smtcubes/"><img src="https://cdn.albumoftheyear.org/user/thumbs/smtcubes_1.jpg"></a></div></div></body></html>';
  const me = aotyExtract("me", fake, "https://www.albumoftheyear.org/");
  console.log("  synthetic:", JSON.stringify(me));
  check(me.username === "harbor", "header avatar wins over review avatars");
  const fake2 = '<html><body><div class="topRight"><img src="https://cdn.albumoftheyear.org/user/thumbs/harbor_1700000000.jpg"></div><div class="albumBlock"><a href="/album/1-x.php"><img src="a.jpg"></a></div></body></html>';
  const me2 = aotyExtract("me", fake2, "https://www.albumoftheyear.org/");
  console.log("  synthetic (avatar only):", JSON.stringify(me2));
  check(me2.username === "harbor", "slug from avatar filename");
}

// Genius lyrics parser against an archived lyrics page
{
  const { geniusParse } = require("../AOTYClient/Scripts/genius.js");
  console.log("\n=== genius lyrics");
  let r, html = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    try { r = await fetch("https://web.archive.org/web/2026id_/https://genius.com/Kendrick-lamar-humble-lyrics", { headers: { "User-Agent": "Mozilla/5.0" } }); html = await r.text(); }
    catch (e) { r = { ok: false, status: "unreachable" }; html = ""; }
    if (r.status !== 429) break;
    console.log("  archive rate-limited, waiting…");
    await new Promise(res => setTimeout(res, 25000));
  }
  if (r.ok && html.length > 50000) {
    const out = geniusParse(html);
    const text = out.segments.map(s => s.t).join("");
    const refs = out.segments.filter(s => s.r).length;
    console.log(`  songId ${out.songId}, ${out.segments.length} segments, ${refs} annotated, ${text.length} chars`);
    console.log("  start:", JSON.stringify(text.slice(0, 200)));
    console.log("  seg0:", JSON.stringify(out.segments[0]));
    check(out.songId === 3039923, "song id from meta");
    check(text.includes("Nobody pray for me") && text.includes("Sit down"), "lyrics text");
    check(refs >= 10, "annotated segments");
    check(!/Contributors/.test(text.slice(0, 100)), "header excluded");
  } else console.log("  no snapshot", r.status);
}

console.log(`\n${failures} failure(s)`);
process.exit(failures ? 1 : 0);
