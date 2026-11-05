// Genius lyrics parser. Turns the lyrics containers into segments:
//   [{ t: "text with \n", r: referentId | null }]
// Annotated passages are wrapped in <a href="/{referentId}/..."> on genius.com.
function geniusParse(html) {
  var doc = new DOMParser().parseFromString(html, "text/html");
  var containers = doc.querySelectorAll("[data-lyrics-container]");
  var segs = [];
  function push(t, r) {
    if (!t) return;
    var last = segs[segs.length - 1];
    if (last && last.r === r) last.t += t; else segs.push({ t: t, r: r });
  }
  function walk(node, ref) {
    for (var c = node.firstChild; c; c = c.nextSibling) {
      if (c.nodeType === 3) { push(c.nodeValue.replace(/\s+/g, " "), ref); continue; }
      if (c.nodeType !== 1) continue;
      var tag = c.tagName.toLowerCase();
      if (c.getAttribute("data-exclude-from-selection") === "true") continue;
      if (tag === "br") { push("\n", ref); continue; }
      if (tag === "script" || tag === "style" || tag === "button" || tag === "svg") continue;
      if ((c.getAttribute("style") || "").indexOf("position:absolute") >= 0) continue;
      var r = ref;
      if (tag === "a") {
        var m = (c.getAttribute("href") || "").match(/^\/(\d+)\//);
        if (m) r = parseInt(m[1], 10);
      }
      walk(c, r);
    }
  }
  for (var i = 0; i < containers.length; i++) {
    if (i > 0) push("\n", null);
    walk(containers[i], null);
  }
  // Tidy: trim spaces around newlines, collapse 3+ newlines.
  for (var j = 0; j < segs.length; j++) segs[j].t = segs[j].t.replace(/ *\n */g, "\n");
  var meta = doc.querySelector('meta[property="twitter:app:url:iphone"], meta[name="twitter:app:url:iphone"]');
  var idm = meta ? (meta.getAttribute("content") || "").match(/songs\/(\d+)/) : null;
  var instrumental = /This song is an instrumental/i.test(html);
  return { segments: segs, songId: idm ? parseInt(idm[1], 10) : null, instrumental: instrumental };
}
if (typeof module !== "undefined") module.exports = { geniusParse: geniusParse };
