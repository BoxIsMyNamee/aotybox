// parser rev 2026-11-11d
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

// "16h ago", "3 days ago", "Nov 2", "Oct 17, 2025", "Jul 2024"
function aotyLooksLikeDate(t) {
  t = (t || "").trim();
  return /^\d+\s*(s|m|min|mins|h|hr|hrs|d|w|mo|y|second|minute|hour|day|week|month|year)s?\s+ago$/i.test(t) ||
    /^(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(,?\s+\d{4})?$/i.test(t) ||
    /^(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{4}$/i.test(t) ||
    /^\d{4}-\d{2}-\d{2}/.test(t);
}
function aotyFindDate(root) {
  var els = root.querySelectorAll("*");
  for (var i = 0; i < els.length; i++) {
    if (els[i].children.length) continue;
    var ti = els[i].getAttribute("title") || "";
    if (aotyLooksLikeDate(ti)) return ti;
    var t = aotyTxt(els[i]);
    if (aotyLooksLikeDate(t)) return t;
  }
  return null;
}

// --- Album cards (.albumBlock): releases, upcoming, this-week, similar ---
function aotyAlbumBlocks(root) {
  var out = [];
  var blocks = root.querySelectorAll(".albumBlock");
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    // Signed in, the cover box starts with a "…" menu link (href="#"), so look for the album link itself.
    var a = b.querySelector(".image a[href*='/album/']") || b.querySelector("a[href*='/album/']");
    var img = b.querySelector(".image img");
    var wrap = b.querySelector(".image");
    var critic = null, criticCount = null, user = null, userCount = null, mine = null, ratedDate = null;
    var rows = b.querySelectorAll(".ratingRow, .ratingRowContainer");
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r];
      var val = aotyTxt(row.querySelector(".rating"));
      var bar = row.querySelector(".ratingBar [style*='width'], .ratingBar[style*='width']");
      var bw = bar ? (bar.getAttribute("style") || "").match(/width:\s*([\d.]+)%/) : null;
      if (bw) val = String(Math.round(parseFloat(bw[1])));
      else if (aotyNum(val) > 100) val = "";   // never guess: no score beats a wrong one
      var texts = Array.prototype.map.call(row.querySelectorAll(".ratingText"), aotyTxt);
      var label = (texts[0] || "").toLowerCase();
      var cnt = null;
      for (var k = 0; k < texts.length; k++) if (texts[k].charAt(0) === "(") cnt = texts[k];
      if (label.indexOf("critic") >= 0) { critic = aotyNum(val); criticCount = aotyCount(cnt); }
      else if (label.indexOf("user") >= 0) { user = aotyNum(val); userCount = aotyCount(cnt); }
      else if (val) {
        mine = aotyNum(val);
        var dEls = row.querySelectorAll(".ratingText, .date, [title]");
        for (var dd = 0; dd < dEls.length && !ratedDate; dd++) {
          var tt = aotyTxt(dEls[dd]), ti = dEls[dd].getAttribute("title") || "";
          if (aotyLooksLikeDate(ti)) ratedDate = ti;
          else if (aotyLooksLikeDate(tt)) ratedDate = tt;
        }
      }
    }
    if (!ratedDate) ratedDate = aotyFindDate(b);
    if (mine == null && !rows.length) mine = aotyNum(aotyTxt(b.querySelector(".rating")));
    var item = {
      url: aotyAbs(a && a.getAttribute("href")),
      artist: aotyTxt(b.querySelector(".artistTitle")),
      title: aotyTxt(b.querySelector(".albumTitle")),
      cover: aotyCleanImg(aotyImgSrc(img)),
      mediaType: b.getAttribute("data-type") || null,
      releaseDate: aotyTxt(b.querySelector(".type")) || null,
      criticScore: critic, criticCount: criticCount,
      userScore: user, userCount: userCount, rating: mine, ratedDate: ratedDate,
      mustHear: !!b.querySelector(".mustHear") || !!(wrap && /\bmustHear\b/.test(wrap.getAttribute("class") || ""))
    };
    if (item.url.indexOf("/album/") >= 0 && item.title) out.push(item);
  }
  return out;
}

// --- Fallback for album cards when the page layout differs (e.g. signed-in users) ---
// Find every album link that wraps a cover image, take the smallest ancestor that holds
// only that album, and read title/artist/scores from its text.
function aotyGenericBlocks(doc) {
  var out = [], seen = {};
  var links = doc.querySelectorAll("a[href*='/album/']");
  for (var i = 0; i < links.length; i++) {
    var a = links[i];
    var href = a.getAttribute("href") || "";
    if (!/\/album\/\d+[^\/]*\.php/.test(href)) continue;
    var url = aotyAbs(href).split("#")[0];
    if (seen[url]) continue;
    var img = a.querySelector("img");
    if (!img) continue;
    // Climb while the parent still only contains this one album.
    var box = a;
    for (var d = 0; d < 6 && box.parentElement; d++) {
      var p = box.parentElement;
      var hrefs = {};
      var inner = p.querySelectorAll("a[href*='/album/']");
      for (var k = 0; k < inner.length; k++) hrefs[(inner[k].getAttribute("href") || "").split("#")[0]] = 1;
      if (Object.keys(hrefs).length > 1) break;
      box = p;
    }
    seen[url] = 1;
    var alt = (img.getAttribute("alt") || "").trim();
    var dash = alt.indexOf(" - ");
    var artistEl = box.querySelector(".artistTitle") || box.querySelector("a[href*='/artist/']");
    var titleEl = box.querySelector(".albumTitle");
    var text = (box.textContent || "").replace(/\s+/g, " ");
    var cm = text.match(/(\d{1,3})\s*critic score\s*\(?([\d,.]+[KkMm]?)?\)?/i);
    var um = text.match(/(\d{1,3})\s*user score\s*\(?([\d,.]+[KkMm]?)?\)?/i);
    var title = aotyTxt(titleEl) || (dash > -1 ? alt.slice(dash + 3) : alt);
    var artist = aotyTxt(artistEl) || (dash > -1 ? alt.slice(0, dash) : "");
    if (!title) continue;
    out.push({
      url: url, artist: artist, title: title,
      cover: aotyCleanImg(aotyImgSrc(img)),
      mediaType: null,
      releaseDate: aotyTxt(box.querySelector(".type")) || null,
      criticScore: cm ? Number(cm[1]) : null, criticCount: cm ? aotyCount(cm[2]) : null,
      userScore: um ? Number(um[1]) : null, userCount: um ? aotyCount(um[2]) : null,
      rating: (!cm && !um) ? aotyNum(aotyTxt(box.querySelector(".rating"))) : null,
      ratedDate: (!cm && !um) ? aotyFindDate(box) : null,
      mustHear: !!box.querySelector(".mustHear")
    });
  }
  return out;
}

/** Short sample of the markup around the first album card, for Diagnostics. */
function aotySample(doc) {
  var a = doc.querySelector("a[href*='/album/'] img");
  if (!a) return "(no album links with images found)";
  var el = a;
  for (var i = 0; i < 4 && el.parentElement; i++) el = el.parentElement;
  return el.outerHTML.replace(/\s+/g, " ").slice(0, 1500);
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

// --- User review rows (album page + user-reviews page) ---
function aotyUserReview(el) {
  var nameEl = el.querySelector(".userReviewName a");
  if (!nameEl) return null;
  var idm = (el.getAttribute("id") || "").match(/(\d+)/);
  var textEl = el.querySelector(".albumReviewText.user") || el.querySelector(".albumReviewText");
  var raw = aotyTxt(textEl);
  var avatarImg = el.querySelector(".userReviewImage img");
  var revLink = null;
  var links = el.querySelectorAll("a[href*='/user/']");
  for (var i = 0; i < links.length; i++) {
    var h = links[i].getAttribute("href") || "";
    if (h.indexOf("/album/") >= 0 || h.indexOf("/review/") >= 0) { revLink = h; break; }
  }
  return {
    reviewId: idm ? parseInt(idm[1], 10) : null,
    username: aotyTxt(nameEl),
    userSlug: ((nameEl.getAttribute("href") || "").match(/\/user\/([^\/?#]+)/) || [])[1] || null,
    nameColor: aotyNameColor(nameEl),
    avatar: avatarImg ? (aotyImgSrc(avatarImg) || null) : null,
    rating: aotyNum(aotyTxt(el.querySelector(".rating"))),
    text: raw.replace(/\s*(\.\.\.|…)?\s*read more\s*$/i, "").trim(),
    isTruncated: /read more\s*$/i.test(raw),
    url: revLink ? aotyAbs(revLink) : null,
    likes: aotyCount(aotyTxt(el.querySelector(".review_likes"))),
    liked: !!el.querySelector(".review_like.liked, .heartLiked"),
    commentCount: aotyCount(aotyTxt(el.querySelector(".comment_count"))),
    date: aotyTxt(el.querySelector(".review_date")).replace(/\*$/, "").trim() || null
  };
}

// Donor / staff name color AOTY puts on a username link: style="color: #921591".
function aotyNameColor(el) {
  for (var e = el, n = 0; e && n < 3; e = e.parentElement, n++) {
    var m = (e.getAttribute && e.getAttribute("style") || "").match(/color:\s*(#[0-9a-f]{3,8})/i);
    if (m) return m[1];
    var inner = e.querySelector && e.querySelector("[style*='color']");
    if (inner) { var m2 = (inner.getAttribute("style") || "").match(/color:\s*(#[0-9a-f]{3,8})/i); if (m2) return m2[1]; }
  }
  return null;
}

// "4y", "2d", "Mar 3, 2025" — whatever date-ish text a review row carries.
function aotyReviewDate(el) {
  var cands = el.querySelectorAll(".review_date, .reviewDate, .date, time, [class*='date']");
  for (var i = 0; i < cands.length; i++) {
    var t = aotyTxt(cands[i]).replace(/\*$/, "").trim();
    if (t && t.length < 30) return t;
  }
  return null;
}

function aotyUserReviewsPage(doc, html) {
  var reviews = [];
  var rows = doc.querySelectorAll(".albumReviewRow");
  for (var i = 0; i < rows.length; i++) {
    var r = aotyUserReview(rows[i]);
    if (r) reviews.push(r);
  }
  var tm = html.match(/showing\s+\d+\s*-\s*(\d+)\s*of\s*([\d,]+)\s*user reviews/i);
  var total = tm ? parseInt(tm[2].replace(/,/g, ""), 10) : reviews.length;
  var perPage = tm ? Math.max(1, parseInt(tm[1], 10)) : 25;
  var maxPage = 1;
  var pageLinks = doc.querySelectorAll("a[href*='p=']");
  for (var j = 0; j < pageLinks.length; j++) {
    var pm = (pageLinks[j].getAttribute("href") || "").match(/[?&]p=(\d+)/);
    if (pm) maxPage = Math.max(maxPage, parseInt(pm[1], 10));
  }
  var distribution = [];
  var drows = doc.querySelectorAll("tr.distRow");
  for (var d = 0; d < drows.length; d++) {
    var label = aotyTxt(drows[d].querySelector(".distLabel"));
    var count = aotyCount(aotyTxt(drows[d].querySelector(".distCount")));
    if (label) distribution.push({ label: label, count: count || 0 });
  }
  return {
    reviews: reviews,
    total: total,
    totalPages: Math.max(maxPage, Math.ceil(total / (perPage < 10 ? 25 : perPage))),
    distribution: distribution
  };
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

// Your own box on an album page (signed in): listened / liked / saved, your score and review.
function aotyMyAlbumBox(doc) {
  var actions = doc.querySelector(".albumActions");
  var rateBtn = doc.querySelector(".insertRating, .insertReview");
  if (!actions && !rateBtn) return null;                          // signed out
  var idEl = doc.querySelector(".albumActions [data-album-id], .insertRating, .insertReview");
  var albumID = idEl ? parseInt(idEl.getAttribute("data-album-id") || idEl.getAttribute("id"), 10) : null;
  function shown(sel) {
    var el = doc.querySelector(sel);
    return !!el && !/display:\s*none/i.test(el.getAttribute("style") || "");
  }
  var idS = albumID ? String(albumID) : "";
  var ratingEl = doc.querySelector("#currentRatingBlock .ratingValue, #currentRatingBlock .rating");
  var rating = ratingEl ? aotyNum(aotyTxt(ratingEl)) : null;
  // The box holding your avatar/name (and your review once posted).
  var box = actions ? (actions.closest(".content") || actions.parentElement) : null;
  var nameA = box ? box.querySelector(".userReviewName a") : null;
  var img = box ? box.querySelector(".userReviewImage img") : null;
  var reviewEl = doc.querySelector("#currentReviewBlock .albumReviewText, #currentReviewBlock .userReviewText, #currentReviewBlock");
  var review = null;
  if (reviewEl && !reviewEl.querySelector("textarea")) {
    var t = aotyBlockText(reviewEl).replace(/\s*(Edit|Delete|Update|Cancel)\s*/g, " ").trim();
    if (t.length > 2) review = t;
  }
  // AOTY cuts long reviews with "... read more". Prefer the full text if the page holds it (edit box),
  // and keep the link to your review page so the app can fetch the rest.
  var ta = doc.querySelector("#reviewBlock textarea, textarea#text");
  var full = ta ? String(ta.value || ta.textContent || "").trim() : "";
  if (review && full.length > 2 && full.length >= review.replace(/\s*(\.\.\.|…)?\s*read more\s*$/i, "").length - 5) review = full;
  var moreA = null;
  if (reviewEl) {
    var as = reviewEl.querySelectorAll('a[href*="/user/"]');
    for (var k = 0; k < as.length; k++) { if (/album\//.test(as[k].getAttribute("href") || "")) { moreA = as[k]; break; } }
  }
  var userHref = nameA ? (nameA.getAttribute("href") || "") : "";
  var um = userHref.match(/\/user\/([^\/?#]+)/);
  return {
    albumID: albumID,
    listened: idS ? shown("#notListenedContainer_" + idS) : false,
    liked: idS ? shown("#unlikeAlbumContainer_" + idS) : false,
    saved: shown("#removeSpinList"),
    rating: rating != null && rating >= 0 && rating <= 100 ? rating : null,
    review: review,
    canReview: !!doc.querySelector("#reviewBlock textarea, textarea#text"),
    name: nameA ? aotyTxt(nameA) : null,
    nameColor: nameA ? aotyNameColor(nameA) : null,
    avatar: img ? aotyImgSrc(img) : null,
    userSlug: um ? um[1] : null,
    reviewURL: moreA ? moreA.getAttribute("href") : null
  };
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
    var logo = row.querySelector(".albumReviewImage img");
    reviews.push({
      image: logo ? (aotyImgSrc(logo) || null) : null,
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
      var ur = aotyUserReview(el);
      if (!ur) continue;
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
    me: aotyMyAlbumBox(doc),
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

// --- Signed-in user (from the site header) ---
// Only trust the header/nav area. Review rows, comments and album cards are full of other
// users' avatars, so anything inside them is ignored.
var AOTY_CONTENT = ".albumReviewRow, .albumBlock, .albumListRow, .commentRow, .comment, .commentsContainer, .userReview, .listBlock, .newsBlock, .reviewRow, .userBlock, .rightBox, .sideBox, #comments, .sectionHeading";

function aotySlugFromAvatar(src) {
  var m = (src || "").match(/\/user\/(?:thumbs\/)?([^\/?#]+?)_\d+\.[a-z]+/i);
  return m ? m[1].toLowerCase() : null;
}

// The header bell: where it links and the unread count on its badge (if any).
function aotyNotifications(doc) {
  // Unread: AOTY puts a small teal ".alertNotification" dot in the header (next to your avatar).
  var alert = null, alerts = doc.querySelectorAll(".alertNotification");
  for (var i = 0; i < alerts.length; i++) { if (!alerts[i].closest(".notificationRow")) { alert = alerts[i]; break; } }
  var count = 0;
  if (alert) { var m = aotyTxt(alert).match(/\d+/); count = m ? parseInt(m[0], 10) : 1; }
  var a = doc.querySelector("a[href*='/notifications']");
  return { href: a ? a.getAttribute("href") : "/notifications/", count: count };
}

// The notifications page: one ".notificationRow" each. A teal <i> dot in the row marks it unread.
function aotyNotificationList(doc) {
  var rows = doc.querySelectorAll(".notificationRow"), items = [];
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    var img = r.querySelector("img");
    var links = r.querySelectorAll("a[href]");
    var userA = r.querySelector("strong a[href^='/user/']") || r.querySelector("a[href^='/user/'][title]") || r.querySelector("a[href^='/user/']");
    var target = null;
    for (var k = links.length - 1; k >= 0; k--) {
      var h = links[k].getAttribute("href") || "";
      if (!/^\/user\/[^\/]+\/?$/.test(h)) { target = h; break; }
    }
    var time = aotyTxt(r.querySelector(".gray-font"));
    var clone = r.cloneNode(true);
    clone.querySelectorAll(".gray-font").forEach(function (x) { x.remove(); });
    var strongs = r.querySelectorAll("strong");
    items.push({
      id: i,
      user: userA ? (userA.getAttribute("title") || aotyTxt(userA)) : null,
      userSlug: userA ? (((userA.getAttribute("href") || "").match(/\/user\/([^\/?#]+)/) || [])[1] || null) : null,
      avatar: img ? aotyImgSrc(img) : null,
      text: aotyTxt(clone),
      subject: strongs.length > 1 ? aotyTxt(strongs[strongs.length - 1]) : null,
      href: target ? aotyAbs(target) : null,
      time: time || null,
      unread: !!r.querySelector(":scope > i, i.fa-circle, i[class*='circle']")
    });
  }
  return { items: items };
}

function aotyMe(doc) {
  function inContent(el) { return !!(el.closest && el.closest(AOTY_CONTENT)); }
  function userFromLink(a) {
    var href = (a.getAttribute("href") || "").replace(/^https?:\/\/[^/]+/, "");
    var m = href.match(/^\/user\/([^\/?#]+)\/?$/);
    return m ? decodeURIComponent(m[1]) : null;
  }
  // 1. Header / nav regions.
  var regions = doc.querySelectorAll("header, nav, #header, .header, .headerContainer, .topBar, .navBar, .menu, [class*='header'], [class*='Header'], [id*='header'], [class*='nav'], [class*='Nav'], [class*='account'], [class*='Account']");
  for (var r = 0; r < regions.length; r++) {
    var reg = regions[r];
    if (inContent(reg)) continue;
    var imgs = reg.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) {
      var src = aotyImgSrc(imgs[i]);
      if (src.indexOf("/user/") < 0) continue;
      var a = imgs[i].closest("a");
      var name = (a && userFromLink(a)) || aotySlugFromAvatar(src);
      if (name) return { username: name, avatar: src };
    }
    var links = reg.querySelectorAll("a[href*='/user/']");
    for (var k = 0; k < links.length; k++) {
      var t = aotyTxt(links[k]).toLowerCase();
      var u = userFromLink(links[k]);
      if (u && (t === "profile" || t === "my profile" || t === "view profile")) return { username: u, avatar: null };
    }
  }
  // 2. Links labelled "Profile" anywhere outside content.
  var all = doc.querySelectorAll("a[href*='/user/']");
  for (var n = 0; n < all.length; n++) {
    if (inContent(all[n])) continue;
    var label = aotyTxt(all[n]).toLowerCase();
    if (label === "profile" || label === "my profile" || label === "view profile") {
      var uu = userFromLink(all[n]);
      if (uu) return { username: uu, avatar: null };
    }
  }
  // 3. The first user avatar on the page, but only if it appears before any content block.
  var seq = doc.querySelectorAll("img, " + AOTY_CONTENT);
  for (var q = 0; q < seq.length; q++) {
    var el = seq[q];
    if (el.tagName.toLowerCase() !== "img") break;          // hit content first: give up
    var s2 = aotyImgSrc(el);
    if (s2.indexOf("/user/") >= 0 && !inContent(el)) {
      var slug = aotySlugFromAvatar(s2);
      var la = el.closest("a");
      var nm = (la && userFromLink(la)) || slug;
      if (nm) return { username: nm, avatar: s2 };
    }
  }
  return { username: null, avatar: null };
}

// --- Profile page (best effort, layout-independent) ---
function aotyProfile(doc, html, pageURL) {
  var text = (doc.body ? doc.body.textContent : "").replace(/\s+/g, " ");
  var stats = [];
  var labels = ["Ratings", "Reviews", "Lists", "Followers", "Following"];
  for (var i = 0; i < labels.length; i++) {
    var re = new RegExp("([\\d,.]+[KkMm]?)\\s*" + labels[i] + "\\b", "i");
    var m = text.match(re);
    if (m) stats.push({ label: labels[i], value: m[1] });
  }
  var userPath = (pageURL || "").replace(/^https?:\/\/[^/]+/, "");
  var um = userPath.match(/\/user\/([^\/?#]+)/);
  var username = um ? decodeURIComponent(um[1]) : "";
  var avatar = null;
  var imgs = doc.querySelectorAll("img");
  for (var k = 0; k < imgs.length; k++) {
    var src = aotyImgSrc(imgs[k]);
    var alt = (imgs[k].getAttribute("alt") || "").toLowerCase();
    if (src.indexOf("/user/") >= 0 && (alt === username.toLowerCase() || alt.replace(/[-_]/g, "") === username.toLowerCase().replace(/[-_]/g, ""))) { avatar = src; break; }
  }
  if (!avatar) { var og = doc.querySelector('meta[property="og:image"]'); if (og && /\/user\//.test(og.getAttribute("content") || "")) avatar = og.getAttribute("content"); }
  var nameEl = doc.querySelector("h1") || doc.querySelector(".profileName");
  var albums = aotyAlbumBlocks(doc);
  if (!albums.length) albums = aotyGenericBlocks(doc);
  var about = aotyTxt(doc.querySelector(".aboutUser, .profileAbout, .userAbout"));

  // Sections, sliced by heading like AOTY-api does: Recently Rated (mixed albums + singles,
  // in AOTY's own order), Recent Reviews, and the Following preview box.
  var recentChunk = aotySlice(html, ["Recently Rated", "Recently Listened"]);
  var recent = [];
  var viewAll = null;
  if (recentChunk) {
    var rd = new DOMParser().parseFromString(recentChunk, "text/html");
    recent = aotyAlbumBlocks(rd);
    if (!recent.length) recent = aotyGenericBlocks(rd);
    var vas = rd.querySelectorAll("a");
    for (var v = 0; v < vas.length; v++) if (/view all/i.test(aotyTxt(vas[v]))) { viewAll = (vas[v].getAttribute("href") || "").replace(/^https?:\/\/[^/]+/, ""); break; }
  }
  var reviews = [];
  var revChunk = aotySlice(html, ["Recent Reviews"]);
  if (revChunk) reviews = aotyProfileReviewRows(new DOMParser().parseFromString(revChunk, "text/html")).slice(0, 10);

  var following = [];
  var fi = html.indexOf("Following (");
  if (fi >= 0) {
    var end = html.indexOf('<div class="rightBox">', fi + 12);
    var nh = html.indexOf('<h2 class="sectionHeading">', fi + 12);
    if (end < 0 || (nh >= 0 && nh < end)) end = nh;
    var box = html.slice(fi, end > 0 ? end : fi + 8000);
    following = aotyFollows(new DOMParser().parseFromString(box, "text/html"), true).users;
  }
  following = following.filter(function (f) { return f.username.toLowerCase() !== username.toLowerCase(); });

  var nameColor = nameEl ? aotyNameColor(nameEl) : null;
  return { username: username, nameColor: nameColor, displayName: aotyTxt(nameEl) || username, avatar: avatar, stats: stats, about: about || null,
           albums: albums.slice(0, 30), recent: recent, ratingsPath: viewAll, reviews: reviews, following: following };
}

function aotySlice(html, headings) {
  for (var i = 0; i < headings.length; i++) {
    var start = html.indexOf(headings[i]);
    if (start < 0) continue;
    var next = html.indexOf('<h2 class="sectionHeading">', start + headings[i].length);
    return html.slice(start, next >= 0 ? next : start + 60000);
  }
  return "";
}

// Review rows on a user's profile / reviews page: album info + their score + text.
function aotyProfileReviewRows(doc) {
  var out = [];
  var rows = doc.querySelectorAll(".albumReviewRow");
  for (var i = 0; i < rows.length; i++) {
    var el = rows[i];
    var albumLink = null, reviewLink = null;
    var links = el.querySelectorAll("a[href*='/album/']");
    for (var k = 0; k < links.length; k++) {
      var h = links[k].getAttribute("href") || "";
      if (/\/user\/[^/]+\/album\//.test(h)) { if (!reviewLink) reviewLink = h; }
      else if (!albumLink) albumLink = h;
    }
    var img = el.querySelector(".userReviewImage img, .albumReviewImage img, img");
    var textEl = el.querySelector(".albumReviewText.user") || el.querySelector(".albumReviewText");
    var raw = aotyTxt(textEl);
    var idm = (el.getAttribute("id") || "").match(/(\d+)/);
    var item = {
      id: idm ? idm[1] : String(i) + (albumLink || ""),
      albumUrl: albumLink ? aotyAbs(albumLink) : null,
      artist: aotyTxt(el.querySelector(".artistTitle")),
      album: aotyTxt(el.querySelector(".albumTitle")),
      cover: img ? (aotyCleanImg(aotyImgSrc(img)) || null) : null,
      rating: aotyNum(aotyTxt(el.querySelector(".rating"))),
      text: raw.replace(/\s*(\.\.\.|…)?\s*read more\s*$/i, "").trim(),
      isTruncated: /read more\s*$/i.test(raw),
      url: reviewLink ? aotyAbs(reviewLink) : null,
      likes: aotyCount(aotyTxt(el.querySelector(".review_likes"))),
      liked: !!el.querySelector(".review_like.liked, .heartLiked"),
      commentCount: aotyCount(aotyTxt(el.querySelector(".comment_count"))),
      reviewId: (function () { var b = el.querySelector("[data-review-id]"); return b ? parseInt(b.getAttribute("data-review-id"), 10) : (idm ? parseInt(idm[1], 10) : null); })(),
      date: aotyReviewDate(el)
    };
    if (item.album || item.text) out.push(item);
  }
  return out;
}

// --- Following / followers list ---
// Rows are found by their "N Followers / Following N" line, so the logged-in user's header
// avatar and any sidebars are ignored. `loose` (for small preview boxes) accepts any avatar link.
function aotyFollows(doc, loose) {
  var out = [], seen = {};
  function add(href, name, img, el) {
    var m = (href || "").replace(/^https?:\/\/[^/]+/, "").match(/^\/user\/([^\/?#]+)\/?$/);
    if (!m) return;
    var u = decodeURIComponent(m[1]);
    if (seen[u.toLowerCase()]) return;
    seen[u.toLowerCase()] = 1;
    out.push({ username: u, name: (name || u).trim(), avatar: img || null, nameColor: el ? aotyNameColor(el) : null });
  }
  function distinctUsers(box) {
    var set = {}, n = 0, links = box.querySelectorAll("a[href*='/user/']");
    for (var q = 0; q < links.length; q++) {
      var h = (links[q].getAttribute("href") || "").split("?")[0];
      if (!set[h]) { set[h] = 1; n++; }
    }
    return n;
  }
  // Smallest ancestor with an avatar and exactly one user; stop before it spans two users.
  function rowFor(el) {
    var box = el;
    for (var d = 0; d < 6 && box; d++) {
      var n = distinctUsers(box);
      if (n > 1) return null;
      if (n === 1 && box.querySelector("img")) return box;
      box = box.parentElement;
    }
    return null;
  }
  // 1. Rows carrying the follower-count line.
  var all = doc.querySelectorAll("*");
  for (var i = 0; i < all.length; i++) {
    var e = all[i];
    if (e.children.length > 2) continue;
    if (!/\d[\d,.]*\s*Followers?\s*\/\s*Following\s*\d/i.test(e.textContent || "")) continue;
    var row = rowFor(e);
    if (!row) continue;
    var a = row.querySelector("a[href*='/user/']");
    var img = row.querySelector("img");
    var nameEl = row.querySelector(".userName") || a;
    var nm = aotyTxt(nameEl).replace(/follows you/i, "").trim();
    add(a && a.getAttribute("href"), nm, img ? aotyImgSrc(img) : null, a);
  }
  // 2. AOTY-api's known row class.
  if (!out.length) {
    var rows = doc.querySelectorAll(".listRow.users");
    for (var r = 0; r < rows.length; r++) {
      var ra = rows[r].querySelector("a[href*='/user/']");
      var ri = rows[r].querySelector(".profilePic img, img");
      add(ra && ra.getAttribute("href"), aotyTxt(rows[r].querySelector(".userName")) || aotyTxt(ra), ri ? aotyImgSrc(ri) : null, rows[r].querySelector(".userName") || ra);
    }
  }
  // 3. Loose: any user link wrapping an avatar (preview boxes only).
  if (!out.length && loose) {
    var links2 = doc.querySelectorAll("a[href*='/user/']");
    for (var k = 0; k < links2.length; k++) {
      var im = links2[k].querySelector("img");
      if (!im) continue;
      add(links2[k].getAttribute("href"), im.getAttribute("alt") || links2[k].getAttribute("title") || "", aotyImgSrc(im));
    }
  }
  return { users: out };
}

// A real Cloudflare challenge page, not a normal page that merely loads Cloudflare's
// background bot script (/cdn-cgi/challenge-platform/…), which AOTY includes on some pages.
function aotyIsChallenge(html, status) {
  var head = html.slice(0, 40000);
  if (/<title>\s*(Just a moment|Attention Required|Please Wait)/i.test(head)) return true;
  if (/window\._cf_chl_opt|id="challenge-form"|class="cf-turnstile"|cf-browser-verification/i.test(head)) return true;
  if ((status === 403 || status === 503) && /cloudflare/i.test(head)) return true;
  return false;
}

// Text of every "deepest substantial" block on a page (one with 120+ chars where no child holds
// 90%+ of its text). Swift picks the block that contains a review preview → the full review.
function aotyBlockText(el) {
  var c = el.cloneNode(true);
  c.querySelectorAll("script,style").forEach(function (x) { x.remove(); });
  c.querySelectorAll("br").forEach(function (b) { b.replaceWith("\n"); });
  c.querySelectorAll("p,div,li").forEach(function (p) { p.append("\n\n"); });
  return c.textContent.split("\n").map(function (l) { return l.replace(/[ \t\u00a0]+/g, " ").trim(); })
    .join("\n").replace(/\n{3,}/g, "\n\n").trim();
}
function aotyTextBlocks(doc) {
  var norm = function (s) { return (s || "").replace(/\s+/g, " ").trim(); };
  var out = [];
  var els = doc.body ? doc.body.querySelectorAll("div,p,section,article,td,span,blockquote") : [];
  for (var i = 0; i < els.length && out.length < 80; i++) {
    var el = els[i];
    if (el.closest("script,style,nav,header,footer")) continue;
    var len = norm(el.textContent).length;
    if (len < 120) continue;
    var big = false;
    for (var k = 0; k < el.children.length; k++) {
      if (norm(el.children[k].textContent).length >= len * 0.9) { big = true; break; }
    }
    if (!big) out.push(aotyBlockText(el));
  }
  var preferred = [];
  var pe = doc.querySelectorAll(".albumReviewText, .userReviewText, [itemprop=reviewBody], [class*='reviewText'], [class*='ReviewText']");
  for (var j = 0; j < pe.length; j++) { var t = aotyBlockText(pe[j]); if (t.length > 40) preferred.push(t); }
  return { preferred: preferred, blocks: out };
}

// Artist page: name, photo, and the discography as album blocks (grouped by type in Swift).
function aotyArtist(doc, pageURL) {
  var h1 = doc.querySelector(".artistHeadline h1, h1.artistHeadline, .artistHeadline, h1");
  var name = aotyTxt(h1).replace(/\s+Albums.*$/i, "").trim();
  var img = doc.querySelector(".artistImage img, .artistTopBox img");
  var og = doc.querySelector("meta[property='og:image']");
  var image = img ? aotyCleanImg(aotyImgSrc(img)) : (og ? og.getAttribute("content") : null);
  var albums = aotyAlbumBlocks(doc);
  if (!albums.length) albums = aotyGenericBlocks(doc);
  // Section headings ("LP", "EP", "Singles", …) give the type when blocks don't carry data-type.
  var blocks = doc.querySelectorAll(".albumBlock");
  for (var i = 0; i < blocks.length && i < albums.length; i++) {
    if (albums[i].mediaType) continue;
    var el = blocks[i], heading = null;
    for (var up = el; up && !heading; up = up.parentElement) {
      for (var sib = up.previousElementSibling; sib && !heading; sib = sib.previousElementSibling) {
        if (/sectionHeading|facetTitle|discographyHeading/.test(sib.className || "") || /^H[23]$/.test(sib.tagName)) heading = aotyTxt(sib);
      }
    }
    if (heading) albums[i].mediaType = heading;
  }
  for (var j = 0; j < albums.length; j++) if (!albums[j].artist) albums[j].artist = name;
  function box(sel) {
    var b = doc.querySelector(sel);
    if (!b) return [null, null];
    var v = aotyNum(aotyTxt(b.querySelector(".artistCriticScore, .artistUserScore")));
    var st = b.querySelector(".text strong");
    return [v, st ? aotyCount(aotyTxt(st)) : null];
  }
  var c = box(".artistCriticScoreBox"), u = box(".artistUserScoreBox");
  var fc = aotyTxt(doc.querySelector(".followCount"));
  var details = [];
  var rows = doc.querySelectorAll(".artistTopBox.info .detailRow, .detailRow");
  for (var d = 0; d < rows.length; d++) {
    var row = rows[d], span = row.querySelector(":scope > span");
    var label = span ? aotyTxt(span).replace(/^\/\s*/, "").trim() : "";
    var clone = row.cloneNode(true);
    clone.querySelectorAll(":scope > span, button").forEach(function (x) { x.remove(); });
    var value = aotyTxt(clone).replace(/,\s*$/, "").trim();
    var links = [];
    clone.querySelectorAll("a[href]").forEach(function (a) { links.push({ text: aotyTxt(a), href: a.getAttribute("href") }); });
    if (label && value) details.push({ label: label, value: value, links: links });
  }
  var fBtn = doc.querySelector(".followArtist[data-artist-id], .unfollowArtist[data-artist-id]");
  // Release types AOTY offers for this artist (its own type links, e.g. "?type=soundtrack").
  var types = [], seenT = {};
  doc.querySelectorAll("a[href*='?type='], a[href*='&type='], option[value*='type=']").forEach(function (el) {
    var h = el.getAttribute("href") || el.getAttribute("value") || "";
    // Sort links (&s=…), "listened" filters and Clear/Featured aren't release types.
    if (/[?&](s|filter)=/.test(h)) return;
    var tm = h.match(/[?&]type=([a-z0-9_+%-]+)/i);   // multi-word types use "+": dj+mix, music+video
    if (!tm || /^(all|featured)$/i.test(tm[1]) || seenT[tm[1].toLowerCase()]) return;
    var lbl = aotyTxt(el).replace(/\s*\(?\d+\)?\s*$/, "").trim();
    seenT[tm[1].toLowerCase()] = 1;
    types.push({ type: tm[1].toLowerCase(), label: lbl || tm[1] });
  });
  return { name: name, image: image, score: c[0],
           criticScore: c[0], criticCount: c[1], userScore: u[0], userCount: u[1],
           followers: fc || null, details: details, albums: albums,
           artistID: fBtn ? (parseInt(fBtn.getAttribute("data-artist-id"), 10) || null) : null,
           following: fBtn ? /unfollowArtist/.test(fBtn.className || "") : null,
           types: types };
}

function aotyExtract(kind, html, pageURL) {
  var doc = new DOMParser().parseFromString(html, "text/html");
  if (kind === "blocks") {
    var albums = aotyAlbumBlocks(doc);
    if (!albums.length) albums = aotyGenericBlocks(doc);
    return { page: null, albums: albums };
  }
  if (kind === "chart") return aotyChart(doc);
  if (kind === "album") return aotyAlbum(doc, html, pageURL);
  if (kind === "userReviews") return aotyUserReviewsPage(doc, html);
  if (kind === "me") { var me = aotyMe(doc) || {}; me.notifications = aotyNotifications(doc); return me; }
  if (kind === "profile") return aotyProfile(doc, html, pageURL);
  if (kind === "follows") return aotyFollows(doc, false);
  if (kind === "textBlocks") return aotyTextBlocks(doc);
  if (kind === "artist") return aotyArtist(doc, pageURL);
  if (kind === "notifications") return aotyNotificationList(doc);
  if (kind === "artistSearch") {
    var links = doc.querySelectorAll("a[href^='/artist/'], a[href*='albumoftheyear.org/artist/']");
    var paths = [];
    for (var q = 0; q < links.length; q++) {
      var m = (links[q].getAttribute("href") || "").match(/\/artist\/\d+[^\/?#]*\/?/);
      if (m && paths.indexOf(m[0]) < 0) paths.push(m[0]);
    }
    // Names and pictures too, for the in-app search results.
    var artists = [];
    for (var pi = 0; pi < paths.length && artists.length < 20; pi++) {
      var as = doc.querySelectorAll("a[href*='" + paths[pi] + "']"), nm = "", im = null;
      for (var ai = 0; ai < as.length; ai++) {
        var t = aotyTxt(as[ai]); if (t && t.length > nm.length && t.length < 80) nm = t;
        var ig = as[ai].querySelector("img"); if (ig && !im) im = aotyImgSrc(ig);
        if (!im) {
          var box = as[ai].closest("div"); var ig2 = box && box.querySelector("img");
          if (ig2) im = aotyImgSrc(ig2);
        }
      }
      if (nm) artists.push({ path: paths[pi], name: nm, image: im ? aotyCleanImg(im) : null });
    }
    return { paths: paths.slice(0, 5), artists: artists };
  }
  if (kind === "userReviewList") {
    var rv = aotyProfileReviewRows(doc);
    return { reviews: rv };
  }
  throw new Error("unknown kind " + kind);
}

if (typeof module !== "undefined") module.exports = { aotyExtract: aotyExtract, aotyIsChallenge: aotyIsChallenge, aotyGenericBlocks: aotyGenericBlocks, aotySample: aotySample };
