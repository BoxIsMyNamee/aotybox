// AOTY page extractors. Run inside the app's hidden WKWebView (same-origin with
// albumoftheyear.org) and in CI under linkedom for tests.
// Selectors ported from edideaur/AOTY-api's scrapers.
//
// Entry point: aotyExtract(kind, html, pageURL) -> plain object matching the
// Swift models (AlbumListResponse, ChartResponse, AlbumDetail).

var AOTY_BASE = "https://www.albumoftheyear.org";

function aotyAbs(u) {
  if (!u) return "";
  if (u.startsWith("http")) return u;
  return AOTY_BASE + (u.startsWith("/") ? "" : "/") + u;
}
function aotyCleanImg(u) {
  if (!u) return u;
  return u.replace(/\/cdn-cgi\/image\/[^/]+\//g, "/").replace(/\/\d+x\d+\//g, "/").replace(/\/sq\//g, "/");
}
function aotyImgSrc(img) {
  if (!img) return "";
  var src = img.getAttribute("src") || "";
  if (!src || src.startsWith("data:")) src = img.getAttribute("data-src") || img.getAttribute("data-lazy-src") || "";
  return aotyAbs(src);
}
function aotyTxt(el) {
  return el ? el.textContent.replace(/\s+/g, " ").trim() : "";
}
function aotyNum(s) {
  if (s == null) return null;
  var t = String(s).replace(/,/g, "").trim();
  if (!t || /^(nr|n\/a|na|—|–|-)$/i.test(t)) return null;
  var m = t.match(/-?\d+(\.\d+)?/);
  return m ? Number(m[0]) : null;
}
function aotyCount(s) {
  if (s == null) return null;
  var t = String(s).replace(/[(),]/g, "").trim();
  var m = t.match(/(\d+(?:\.\d+)?)\s*([KkMm])?/);
  if (!m) return null;
  var n = Number(m[1]);
  if (m[2]) n *= /k/i.test(m[2]) ? 1e3 : 1e6;
  return Math.round(n);
}
function aotyInt(s) {
  var n = aotyNum(s);
  return n == null ? null : Math.round(n);
}

// --- Album cards (.albumBlock): releases, upcoming, this-week, similar ---
function aotyAlbumBlocks(root) {
  var out = [];
  var blocks = root.querySelectorAll(".albumBlock");
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    var a = b.querySelector(".image a") || b.querySelector("a[href*='/album/']");
    var img = b.querySelector(".image img");
    var wrap = b.querySelector(".image");
    var critic = null, criticCount = null, user = null, userCount = null;
    var rows = b.querySelectorAll(".ratingRow");
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r];
      var val = aotyTxt(row.querySelector(".rating"));
      var texts = Array.prototype.map.call(row.querySelectorAll(".ratingText"), aotyTxt);
      var label = (texts[0] || "").toLowerCase();
      var cnt = null;
      for (var k = 0; k < texts.length; k++) if (texts[k].charAt(0) === "(") cnt = texts[k];
      if (label.indexOf("critic") >= 0) { critic = aotyNum(val); criticCount = aotyCount(cnt); }
      else if (label.indexOf("user") >= 0) { user = aotyNum(val); userCount = aotyCount(cnt); }
    }
    var item = {
      url: aotyAbs(a && a.getAttribute("href")),
      artist: aotyTxt(b.querySelector(".artistTitle")),
      title: aotyTxt(b.querySelector(".albumTitle")),
      cover: aotyCleanImg(aotyImgSrc(img)),
      mediaType: b.getAttribute("data-type") || null,
      releaseDate: aotyTxt(b.querySelector(".type")) || null,
      criticScore: critic, criticCount: criticCount,
      userScore: user, userCount: userCount,
      mustHear: !!b.querySelector(".mustHear") || !!(wrap && /\bmustHear\b/.test(wrap.getAttribute("class") || ""))
    };
    if (item.url.indexOf("/album/") >= 0 && item.title) out.push(item);
  }
  return out;
}

// --- Ratings charts (.albumListRow) ---
function aotyChart(doc) {
  var items = [];
  var rows = doc.querySelectorAll(".albumListRow");
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    var a = r.querySelector(".albumListTitle a[itemprop='url']") || r.querySelector(".albumListTitle a");
    var t = aotyTxt(a);
    var d = t.indexOf(" - ");
    var genreBox = r.querySelector(".albumListGenre");
    var genres = [];
    if (genreBox) {
      var links = genreBox.querySelectorAll("a");
      for (var g = 0; g < links.length; g++) {
        if (links[g].closest && links[g].closest(".secondary-genres")) continue;
        var gv = aotyTxt(links[g]).replace(/,$/, "");
        if (gv && genres.indexOf(gv) < 0) genres.push(gv);
      }
    }
    var rank = aotyInt((r.getAttribute("id") || "").replace("rank-", ""));
    var item = {
      rank: rank == null ? i + 1 : rank,
      artist: d > -1 ? t.slice(0, d).trim() : "",
      album: d > -1 ? t.slice(d + 3).trim() : t,
      url: aotyAbs(a && a.getAttribute("href")),
      cover: aotyCleanImg(aotyImgSrc(r.querySelector(".albumListCover img"))) || null,
      date: aotyTxt(r.querySelector(".albumListDate")) || null,
      genres: genres,
      score: aotyNum(aotyTxt(r.querySelector(".scoreValue"))),
      ratingCount: aotyCount(aotyTxt(r.querySelector(".scoreText")).replace(/ratings?/i, "")),
      mustHear: !!r.querySelector(".mustHear")
    };
    if (item.url) items.push(item);
  }
  var totalPages = null;
  var anchors = doc.querySelectorAll("a");
  for (var j = 0; j < anchors.length; j++) {
    var an = anchors[j];
    if (!an.querySelector(".pageSelectSmall")) continue;
    var href = an.getAttribute("href") || "";
    if (href.indexOf("/ratings/") < 0) continue;
    var segs = href.split("/").filter(Boolean);
    var n = parseInt(segs[segs.length - 1], 10);
    if (isFinite(n) && (totalPages == null || n > totalPages)) totalPages = n;
  }
  return { items: items, totalPages: totalPages == null ? 1 : totalPages };
}

// --- Album page ---
function aotyRanking(html, boxClass) {
  var idx = html.indexOf(boxClass);
  if (idx < 0) return null;
  var chunk = html.slice(idx, idx + 2500);
  var m = chunk.match(/(\d{4})\s*Ratings:\s*<strong>\s*<a href="[^"]+">#(\d+)<\/a>\s*<\/strong>(?:\s*\/\s*(\d+))?/i);
  if (!m) return null;
  return { year: parseInt(m[1], 10), rank: parseInt(m[2], 10), total: m[3] ? parseInt(m[3], 10) : null };
}

function aotyTextWithout(el, removeSel) {
  if (!el) return "";
  var c = el.cloneNode(true);
  var kill = c.querySelectorAll(removeSel);
  for (var i = 0; i < kill.length; i++) kill[i].parentNode.removeChild(kill[i]);
  return aotyTxt(c);
}

function aotyAlbum(doc, html, pageURL) {
  var ld = {};
  var scripts = doc.querySelectorAll('script[type="application/ld+json"]');
  for (var i = 0; i < scripts.length; i++) {
    try {
      var j = JSON.parse(scripts[i].textContent);
      if (Array.isArray(j)) j = j[0];
      if (j && (j["@type"] === "MusicAlbum" || j.byArtist)) { ld = j; break; }
    } catch (e) {}
  }
  var byArtist = Array.isArray(ld.byArtist) ? ld.byArtist[0] : ld.byArtist;

  var rows = Array.prototype.map.call(doc.querySelectorAll(".albumTopBox.info .detailRow"), aotyTxt);
  var format = ((rows[1] || "").split(/\/\s*Format/i)[0] || "").trim() || null;
  var labelEl = doc.querySelector(".albumTopBox.info .detailRow a[href*='/label/']");
  var genres = Array.isArray(ld.genre) ? ld.genre : (ld.genre ? [ld.genre] : []);
  if (!genres.length) {
    var gl = doc.querySelectorAll(".albumTopBox.info .detailRow a[href*='/genre/']");
    for (var g = 0; g < gl.length; g++) { var gv = aotyTxt(gl[g]); if (gv && genres.indexOf(gv) < 0) genres.push(gv); }
  }

  // Streaming links
  var streaming = [];
  var sl = doc.querySelectorAll(".albumLinksFlex a");
  for (var s = 0; s < sl.length; s++) {
    var href = sl[s].getAttribute("href") || "";
    if (!href.startsWith("http")) continue;
    var plat = sl[s].getAttribute("title") || aotyTxt(sl[s]);
    if (!plat) { try { plat = new URL(href).hostname.replace(/^www\./, ""); } catch (e) { plat = "Link"; } }
    streaming.push({ platform: plat, url: href });
  }

  // Tracklist
  var tracks = [];
  var trs = doc.querySelectorAll(".trackListTable tr");
  for (var t = 0; t < trs.length; t++) {
    var tr = trs[t];
    var numTxt = aotyTxt(tr.querySelector(".trackNumber"));
    if (!numTxt) continue;
    var titleBox = tr.querySelector(".trackTitle a") || tr.querySelector(".trackTitle");
    var title = aotyTextWithout(titleBox, ".length, .featuredArtists, .trackNotes");
    var feats = Array.prototype.map.call(tr.querySelectorAll(".trackTitle .featuredArtists a"), aotyTxt).filter(Boolean);
    tracks.push({
      number: aotyInt(numTxt) || tracks.length + 1,
      title: title,
      length: aotyTxt(tr.querySelector(".trackTitle .length")) || null,
      rating: aotyNum(aotyTxt(tr.querySelector(".trackRating span"))),
      features: feats
    });
  }

  // Critic reviews (rows with a publication header)
  var reviews = [];
  var rr = doc.querySelectorAll(".albumReviewRow");
  for (var c = 0; c < rr.length; c++) {
    var row = rr[c];
    var pub = row.querySelector(".albumReviewHeader .publication");
    if (!pub) continue;
    var ext = row.querySelector(".albumReviewLinks .extLink a");
    var actions = row.querySelectorAll(".albumReviewLinks .actionContainer");
    reviews.push({
      score: aotyNum(aotyTxt(row.querySelector(".albumReviewRating"))),
      publication: aotyTxt(pub.querySelector("a")) || aotyTxt(pub),
      author: aotyTxt(row.querySelector(".albumReviewHeader .author a")) || aotyTxt(row.querySelector(".albumReviewHeader .author")) || null,
      text: aotyTxt(row.querySelector(".albumReviewText")),
      url: ext ? aotyAbs(ext.getAttribute("href")) : null,
      date: actions[1] ? (actions[1].getAttribute("title") || null) : null
    });
  }

  // Sections in document order: headings + user review rows + album blocks
  var popular = [], recent = [], similar = [], more = [];
  var section = "";
  var nodes = doc.querySelectorAll(".sectionHeading, h2, h3, .albumReviewRow, .albumBlock");
  for (var n = 0; n < nodes.length; n++) {
    var el = nodes[n];
    var cls = el.getAttribute("class") || "";
    if (!/albumReviewRow|albumBlock/.test(cls)) {
      var head = aotyTxt(el).toLowerCase();
      if (head.indexOf("popular user reviews") >= 0) section = "popular";
      else if (head.indexOf("recent user reviews") >= 0) section = "recent";
      else if (head.indexOf("you may also like") >= 0) section = "similar";
      else if (head.indexOf("more albums") >= 0 || head.indexOf("more by") >= 0) section = "more";
      else if (head) section = section === "" ? "" : "other";
      continue;
    }
    if (/albumReviewRow/.test(cls)) {
      var nameEl = el.querySelector(".userReviewName a");
      if (!nameEl) continue;
      var idm = (el.getAttribute("id") || "").match(/(\d+)/);
      var textEl = el.querySelector(".albumReviewText.user") || el.querySelector(".albumReviewText");
      var ur = {
        reviewId: idm ? parseInt(idm[1], 10) : null,
        username: aotyTxt(nameEl),
        rating: aotyNum(aotyTxt(el.querySelector(".rating"))),
        text: aotyTxt(textEl).replace(/read more\s*$/i, "").trim(),
        likes: aotyCount(aotyTxt(el.querySelector(".review_likes"))),
        date: aotyTxt(el.querySelector(".review_date")).replace(/\*$/, "").trim() || null
      };
      if (section === "recent") recent.push(ur); else popular.push(ur);
    } else if (section === "similar" || section === "more") {
      var blk = aotyAlbumBlocks({ querySelectorAll: function () { return [el]; } });
      if (blk.length) (section === "similar" ? similar : more).push(blk[0]);
    }
  }
  // Fallback if headings weren't recognised: treat all page album cards as similar
  if (!similar.length && !more.length) similar = aotyAlbumBlocks(doc).slice(0, 12);

  var crit = aotyTxt(doc.querySelector(".albumCriticScore a")) || aotyTxt(doc.querySelector(".albumCriticScore"));
  var usr = aotyTxt(doc.querySelector(".albumUserScore a")) || aotyTxt(doc.querySelector(".albumUserScore"));
  var titleFallback = aotyTxt(doc.querySelector(".albumTitle")) || aotyTxt(doc.querySelector("h1"));
  var artistFallback = aotyTxt(doc.querySelector(".artist a")) || aotyTxt(doc.querySelector(".artist"));
  var ogImage = doc.querySelector('meta[property="og:image"]');

  return {
    url: pageURL,
    title: String(ld.name || titleFallback || ""),
    artist: String((byArtist && byArtist.name) || artistFallback || ""),
    artistUrl: byArtist && byArtist.url ? aotyAbs(byArtist.url) : null,
    cover: aotyCleanImg(String(ld.image || (ogImage && ogImage.getAttribute("content")) || "")),
    datePublished: ld.datePublished ? String(ld.datePublished) : (rows[0] || null),
    format: format,
    label: labelEl ? aotyTxt(labelEl) : null,
    genres: genres,
    tags: [],
    totalLength: aotyTxt(doc.querySelector(".totalLength")).replace(/^Total Length:\s*/i, "") || null,
    mustHear: !!doc.querySelector(".mustHearButton"),
    criticScore: aotyNum(crit),
    criticCount: aotyCount(aotyTxt(doc.querySelector(".albumCriticScoreBox .text.numReviews"))),
    criticRanking: aotyRanking(html, "albumCriticScoreBox"),
    userScore: aotyNum(usr),
    userCount: aotyCount(aotyTxt(doc.querySelector(".albumUserScoreBox .text.numReviews"))),
    userRanking: aotyRanking(html, "albumUserScoreBox"),
    tracklist: tracks,
    streamingLinks: streaming,
    reviews: reviews,
    popularUserReviews: popular.slice(0, 15),
    similarAlbums: similar.slice(0, 15),
    moreAlbums: more.slice(0, 15)
  };
}

function aotyIsChallenge(html, status) {
  return status === 403 || status === 503 ||
    /<title>\s*Just a moment/i.test(html) || /cf-challenge|challenge-platform|cf_chl_/i.test(html.slice(0, 20000));
}

function aotyExtract(kind, html, pageURL) {
  var doc = new DOMParser().parseFromString(html, "text/html");
  if (kind === "blocks") return { page: null, albums: aotyAlbumBlocks(doc) };
  if (kind === "chart") return aotyChart(doc);
  if (kind === "album") return aotyAlbum(doc, html, pageURL);
  throw new Error("unknown kind " + kind);
}

if (typeof module !== "undefined") module.exports = { aotyExtract: aotyExtract, aotyIsChallenge: aotyIsChallenge };
