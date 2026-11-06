// One-off: how does AOTY's review like button work?
const u = "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/album/2915-outkast-aquemini/user-reviews/";
for (let i = 0; i < 3; i++) {
  try {
    const h = await (await fetch(u)).text();
    const k = h.indexOf("review_likes");
    console.log("LIKES:", h.slice(k - 700, k + 500));
    const scripts = [...h.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
    console.log("SCRIPTS:", scripts.join(" "));
    const fn = h.match(/function\s+\w*[Ll]ike\w*\s*\([^)]*\)\s*\{[\s\S]{0,800}/);
    console.log("INLINE FN:", fn ? fn[0] : "none");
    for (const s of scripts.filter(s => /aoty|main|script|site/i.test(s)).slice(0, 3)) {
      const url = s.startsWith("http") ? s : "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org" + s;
      const js = await (await fetch(url)).text();
      const m = js.match(/.{0,300}[Ll]ike.{0,500}/g) || [];
      console.log("JS", s, m.slice(0, 4).join("\n---\n"));
    }
    break;
  } catch (e) { console.log("retry", e.message); await new Promise(r => setTimeout(r, 4000)); }
}
