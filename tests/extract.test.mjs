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
  ["artist", "/artist/183-kanye-west/"],
  ["artist", "/artist/183-kanye-west/?type=single"],
  ["artist", "/artist/183-kanye-west/?type=reissue"],
  ["artist", "/artist/183-kanye-west/?type=ep"],
  ["artist", "/artist/2049-outkast/"],
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
  } else if (kind === "artist") {
    const types = {};
    out.albums.forEach(a => { types[a.mediaType || "?"] = (types[a.mediaType || "?"] || 0) + 1; });
    console.log(`  name ${JSON.stringify(out.name)}, image ${out.image ? "yes" : "no"}, ${out.albums.length} albums, types ${JSON.stringify(types)}`);
    console.log("  first:", JSON.stringify(out.albums[0]));
    check(out.name && out.name.length < 60, "artist name");
    check(out.albums.length >= 1, "artist discography");
    console.log("  sample:", JSON.stringify(out.albums.slice(0, 3).map(a => [a.title, a.url, a.mediaType, a.cover ? "cover" : "NOCOVER"])));
    console.log("  info:", JSON.stringify({ c: out.criticScore, cc: out.criticCount, u: out.userScore, uc: out.userCount, f: out.followers, d: out.details }).slice(0, 600));
    check(out.criticScore > 0 && out.userCount > 1000, "artist score box");
    check((out.details || []).some(d => /genre/i.test(d.label)), "artist details");
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

// Challenge detection: background bot script must not count as a challenge
{
  const normal = '<html><head><title>harbor - Following - Album of The Year</title><script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script></head><body><div class="listRow users"></div></body></html>';
  const real = '<html><head><title>Just a moment...</title></head><body><script>window._cf_chl_opt={}</script></body></html>';
  check(!aotyIsChallenge(normal, 200), "normal page with bot script is not a challenge");
  check(aotyIsChallenge(real, 403), "real challenge detected");
  console.log("\n=== challenge detection ok");
}

// Rated date + follows (synthetic markup mirroring AOTY's classes)
{
  console.log("\n=== rated dates + follows (synthetic)");
  const blocks = '<div class="albumBlock" data-type="single"><div class="image"><a href="/album/6817412130-everything-everything-poison-pop.php"><img src="https://cdn2.albumoftheyear.org/album/x.jpg"></a></div>' +
    '<div class="artistTitle">Everything Everything</div><div class="albumTitle">Poison Pop</div><div class="type">2026 • Single</div>' +
    '<div class="ratingRowContainer"><div class="ratingBlock"><div class="rating">90</div></div><div class="ratingText">16h ago</div></div></div>' +
    '<div class="albumBlock" data-type="lp"><div class="image"><a href="/album/1-nick-lutsko-ends.php"><img src="https://cdn2.albumoftheyear.org/album/y.jpg"></a></div>' +
    '<div class="artistTitle">Nick Lutsko</div><div class="albumTitle">Ends</div><div class="ratingRow"><div class="ratingBlock"><div class="rating">80</div></div><div class="ratingText">Nov 2</div></div></div>';
  const out = aotyExtract("blocks", "<html><body>" + blocks + "</body></html>", "https://www.albumoftheyear.org/user/x/ratings/");
  console.log("  ", JSON.stringify(out.albums.map(a => [a.title, a.rating, a.ratedDate, a.mediaType])));
  check(out.albums[0].rating === 90 && out.albums[0].ratedDate === "16h ago", "relative rated date");
  check(out.albums[1].rating === 80 && out.albums[1].ratedDate === "Nov 2", "month-day rated date");
  const follows = '<div class="listRow users"><div class="profilePic"><a href="/user/kidwithguns/"><img src="https://cdn.albumoftheyear.org/user/thumbs/kidwithguns_1.jpg"></a></div><div class="userName"><a href="/user/kidwithguns/">KidWithGuns</a></div></div>' +
    '<div class="listRow users"><div class="profilePic"><a href="/user/amaana/"><img src="https://cdn.albumoftheyear.org/user/thumbs/amaana_2.jpg"></a></div><div class="userName"><a href="/user/amaana/">amaana</a></div></div>';
  const followsReal = '<header><a href="/user/harperseemscool/"><img src="https://cdn.albumoftheyear.org/user/thumbs/harperseemscool_9.jpg"></a></header>' +
    '<div class="followRow"><a href="/user/kidwithguns/"><img src="https://cdn.albumoftheyear.org/user/thumbs/kidwithguns_1.jpg"></a><div><a class="name" href="/user/kidwithguns/">KidWithGuns</a><span>FOLLOWS YOU</span><div>1 Followers / Following 2</div></div></div>' +
    '<div class="followRow"><a href="/user/amaana/"><img src="https://cdn.albumoftheyear.org/user/thumbs/amaana_2.jpg"></a><div><a class="name" href="/user/amaana/">amaana</a><div>5 Followers / Following 2</div></div></div>';
  const f2 = aotyExtract("follows", "<html><body>" + followsReal + "</body></html>", "");
  console.log("   count-line rows:", JSON.stringify(f2.users.map(u => u.username)));
  check(f2.users.length === 2 && !f2.users.some(u => u.username === "harperseemscool"), "follows ignores header avatar");
  const f = aotyExtract("follows", "<html><body>" + follows + "</body></html>", "");
  console.log("  ", JSON.stringify(f));
  check(f.users.length === 2 && f.users[0].username === "kidwithguns" && f.users[0].name === "KidWithGuns" && f.users[0].avatar, "follows list");
}

// Profile sections (synthetic, mirroring AOTY's headings)
{
  const page = '<html><body><h1>harbor</h1>' +
    '<h2 class="sectionHeading">Recently Rated <a href="/user/harperseemscool/ratings/">View All</a></h2>' +
    '<div class="albumBlock" data-type="single"><div class="image"><a href="/album/2-ee-poison-pop.php"><img src="https://cdn2.albumoftheyear.org/album/a.jpg"></a></div><div class="artistTitle">Everything Everything</div><div class="albumTitle">Poison Pop</div><div class="ratingRowContainer"><div class="ratingBlock"><div class="rating">90</div></div><div class="ratingText">16h ago</div></div></div>' +
    '<div class="albumBlock" data-type="lp"><div class="image"><a href="/album/1-nick-lutsko-ends.php"><img src="https://cdn2.albumoftheyear.org/album/b.jpg"></a></div><div class="artistTitle">Nick Lutsko</div><div class="albumTitle">Ends</div><div class="ratingRowContainer"><div class="ratingBlock"><div class="rating">80</div></div><div class="ratingText">Nov 2</div></div></div>' +
    '<h2 class="sectionHeading">Recent Reviews</h2>' +
    '<div class="albumReviewRow" id="review_55"><div class="userReviewImage"><a href="/user/harperseemscool/album/1-nick-lutsko-ends/"><img src="https://cdn2.albumoftheyear.org/album/b.jpg"></a></div><div class="artistTitle"><a href="/artist/9-nick-lutsko/">Nick Lutsko</a></div><div class="albumTitle"><a href="/album/1-nick-lutsko-ends.php">Ends</a></div><div class="rating">80</div><div class="albumReviewText user"><p>Great record. read more</p></div><div class="review_date">Nov 2</div></div>' +
    '<h2 class="sectionHeading">Lists</h2>' +
    '<div class="rightBox"><div class="sectionHeading">Following (3)</div><a href="/user/lilyp/"><img alt="LilyP" src="https://cdn.albumoftheyear.org/user/thumbs/lilyp_1.jpg"></a><a href="/user/wojack/"><img alt="Wojack" src="https://cdn.albumoftheyear.org/user/thumbs/wojack_1.jpg"></a><a href="/user/harperseemscool/"><img alt="me" src="x.jpg"></a></div><div class="rightBox">x</div>' +
    '</body></html>';
  const pr = aotyExtract("profile", page, "https://www.albumoftheyear.org/user/harperseemscool/");
  console.log("\n=== profile sections:", JSON.stringify({ recent: pr.recent.map(a => a.title), ratingsPath: pr.ratingsPath, reviews: pr.reviews.map(r => [r.album, r.rating, r.text, r.isTruncated, r.url]), following: pr.following.map(f => f.username) }));
  check(pr.recent.length === 2 && pr.recent[0].title === "Poison Pop", "recently rated in page order");
  check(pr.ratingsPath === "/user/harperseemscool/ratings/", "view-all path");
  check(pr.reviews.length === 1 && pr.reviews[0].album === "Ends" && pr.reviews[0].isTruncated && pr.reviews[0].text === "Great record.", "recent reviews");
  check(pr.following.length === 2 && !pr.following.some(f => f.username === "harperseemscool"), "following preview excludes owner");
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

// Full review text from a review page (synthetic)
{
  console.log("\n=== textBlocks (synthetic review page)");
  const p1 = "i'm a huge sucker for the avalanches. and i'm a huge sucker for tech, especially dated tech. if i could give this a 200 i would.";
  const p2 = "also my signed vinyl showed up today and the 'reception' interlude hits even harder on wax. absolutely incredible work.";
  const html = `<html><body><nav>${"menu ".repeat(40)}</nav><div class="wrap"><div class="userReviewHeader">harperseemscool · 100</div>
    <div class="userReviewText"><p>${p1}</p><p>${p2}</p></div><div class="likes">3 likes</div></div>
    <div class="sidebar">${"Other reviews and things to read on the side. ".repeat(6)}</div></body></html>`;
  const out = aotyExtract("textBlocks", html, "https://www.albumoftheyear.org/user/x/album/1-a-b/");
  const key = s => s.toLowerCase().replace(/[^a-z0-9]/g, "");
  const probe = key(p1).slice(0, 80);
  const hit = (out.preferred || []).filter(b => key(b).includes(probe)).sort((a, b) => b.length - a.length)[0]
    || out.blocks.filter(b => key(b).startsWith(probe)).sort((a, b) => b.length - a.length)[0] || "";
  // also check the fallback alone (no AOTY class)
  const out2 = aotyExtract("textBlocks", html.replace('class="userReviewText"', 'class="x"'), "x");
  const hit2 = out2.blocks.filter(b => key(b).startsWith(probe)).sort((a, b) => b.length - a.length)[0] || "";
  check(hit2.includes(p1) && hit2.includes(p2) && !hit2.includes("harperseemscool"), "fallback picks review body");
  console.log("  blocks:", out.blocks.length, "pick:", JSON.stringify(hit.slice(0, 80)), "…", hit.length, "chars");
  check(hit.includes(p1) && hit.includes(p2), "full review picked");
  check(hit.includes("\n\n"), "paragraph break kept");
  check(!hit.includes("menu menu"), "nav excluded");
}

// Your album box (from the user's signed-in capture)
{
  const rated = `<html><body><div class="content"><div class="albumActions"><span id="notListenedContainer_2114076"><span class="action removeListened" data-album-id="2114076"><div class="listenAlbum listened">Listened</div></span></span><span id="listenedContainer_2114076" style="display: none;"></span><span id="likeAlbumContainer_2114076"><span class="action addAlbumLike" data-album-id="2114076"></span></span><span id="unlikeAlbumContainer_2114076" style="display: none;"></span><span id="addSpinList"></span><span id="removeSpinList" style="display:none;"></span></div><div class="userReviewImage"><a href="/user/harperseemscool/"><img src="https://cdn.albumoftheyear.org/user/thumbs/boxismyname_1.jpg"></a></div><div class="userReviewName"><a href="/user/harperseemscool/" style="color: #7CFC00;">HarperSeemsCool</a></div></div>
    <div id="ratingContainer"><div id="ratingBlock" style="display:none;"><input id="value"><button class="insertRating" id="2114076">Rate</button></div><div id="currentRatingBlock" class="ratingBlock yourOwn"><div class="rating"><div class="ratingValue">55</div></div></div></div></body></html>`;
  const m = aotyExtract("album", rated, "https://www.albumoftheyear.org/album/2114076-x.php").me;
  console.log("\n=== my album box (rated)", JSON.stringify(m));
  check(m && m.albumID === 2114076 && m.listened === true && m.liked === false && m.saved === false && m.rating === 55, "rated box");
  check(m.name === "HarperSeemsCool" && m.nameColor === "#7CFC00", "my name + color");
  const other = `<html><body><div class="content"><div class="albumActions"><span id="listenedContainer_5361"></span><span id="notListenedContainer_5361" style="display: none;"></span><span id="likeAlbumContainer_5361"></span><span id="unlikeAlbumContainer_5361" style="display: none;"></span><span id="addSpinList"></span><span id="removeSpinList" style="display:none;"></span></div></div>
    <div id="ratingContainer"><div id="ratingBlock" style="display:inline-block;"><button class="insertRating" id="5361">Rate</button></div></div><div id="reviewBlock"><textarea id="text"></textarea></div><button class="insertReview" id="5361">Post</button></body></html>`;
  const o = aotyExtract("album", other, "x").me;
  console.log("=== my album box (unrated)", JSON.stringify(o));
  check(o && o.albumID === 5361 && !o.listened && o.rating === null && o.canReview === true, "unrated box");
}

// Header bell (synthetic)
{
  const html = `<html><body><header><a href="/notifications/"><i class="fas fa-bell"></i><span class="notifCount">3</span></a>
    <a href="/user/harbor/"><img src="https://cdn.albumoftheyear.org/user/thumbs/harbor_1.jpg"></a></header></body></html>`;
  const me = aotyExtract("me", html, "x");
  console.log("\n=== bell (synthetic)", JSON.stringify(me.notifications));
  check(me.notifications && me.notifications.count === 3 && me.notifications.href === "/notifications/", "bell count + link");
}

// Signed-in review markup (from the user's capture): liked state and review id
{
  console.log("\n=== review like markup (synthetic)");
  const html = `<html><body><div class="albumReviewRow" id="review_997831"><div class="userReviewName"><a href="/user/rollo-p/">Rollo_P</a></div>
    <div class="rating">99</div><div class="albumReviewText user"><p>Great.</p></div>
    <div class="albumReviewLinks user"><div class="actionContainer"><div class="review_like liked" id="review_like_997831"><button class="likeUserReview" data-review-id="997831"><span class="heartLiked"><i class="fas fa-heart"></i></span></button></div>
    <div class="review_likes_container" id="review_likes_997831"><div class="review_likes"><button class="showUserReviewLikes" data-review-id="997831">185</button></div></div></div></div></div></body></html>`;
  const out = aotyExtract("userReviews", html, "x");
  const r = out.reviews[0] || {};
  console.log("  ", JSON.stringify({ id: r.reviewId, liked: r.liked, likes: r.likes, slug: r.userSlug }));
  check(r.reviewId === 997831 && r.liked === true && r.likes === 185 && r.userSlug === "rollo-p", "liked + id + count + slug");
  const s2 = aotyExtract("artistSearch", `<a href="/artist/183-kanye-west/">Kanye West</a><a href="/artist/183-kanye-west/">x</a><a href="/artist/9-other/">y</a>`, "x");
  check(s2.paths[0] === "/artist/183-kanye-west/" && s2.paths.length === 2, "artist search paths");
  const fa = aotyExtract("artist", `<h1 class="artistHeadline">underscores</h1><div class="followRow"><span id="followContainer_105779"><button class="followArtist" data-artist-id="105779"><div id="followButton_105779" class="follow noFloat">Follow</div></button></span></div>`, "x");
  check(fa.artistID === 105779 && fa.following === false, "artist follow button");
  const fb = aotyExtract("artist", `<h1 class="artistHeadline">x</h1><span id="followContainer_9"><button class="unfollowArtist" data-artist-id="9"><div id="unfollowButton_9">Following</div></button></span>`, "x");
  check(fb.artistID === 9 && fb.following === true, "artist unfollow button");
  const sb = aotyExtract("artist", `<div class="albumBlock small" data-type=""><div class="image mustHear user"><div class="menu"><div class="dotDropMenuContainer"><div class="dotDropMenuButtonBlock"><a class="albumMenuToggle" href="#" id="album_651837" data-album-id="651837"><i class="far fa-ellipsis-h"></i></a></div><div class="dotDropMenu block" id="album_menu_651837"><div class="row" style="text-align: center;"><i class="fas fa-spinner fa-pulse"></i></div></div></div></div><a href="/album/651837-underscores-wallsocket.php"><div class="mustHear"><i class="fas fa-star"></i></div><img src="https://cdn2.albumoftheyear.org/200x0/album/651837-wallsocket_1202.jpg" alt="underscores - Wallsocket" srcset="https://cdn2.albumoftheyear.org/400x0/album/651837-wallsocket_1202.jpg 2x" loading="lazy"></a></div><a href="/album/651837-underscores-wallsocket.php"><div class="albumTitle normal">Wallsocket</div></a><div class="type">2023</div><div class="ratingRowContainer"><div class="ratingRow"><div class="ratingBlock"><div class="rating">82</div><div class="ratingBar green"><div class="green" style="width:82%;"></div></div></div><div class="ratingText">critic score</div> <div class="ratingText">(6)</div> </div><div class="ratingRow"><div class="ratingBlock"><div class="rating">83</div><div class="ratingBar green"><div class="green" style="width:83%;"></div></div></div><div class="ratingText">user score</div> <div class="ratingText">(10.6K)</div> </div></div></div>`, "x");
  check(sb.albums.length === 1 && sb.albums[0].criticScore === 82 && sb.albums[0].userScore === 83 && sb.albums[0].userCount === 10600, "signed-in artist block: both scores");
}

console.log(`\n${failures} failure(s)`);
process.exit(failures ? 1 : 0);
