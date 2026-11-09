// Temporary: dump artist-page markup (album blocks, follow button) and the follow script.
const get = async (p) => {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(`https://web.archive.org/web/2026id_/https://www.albumoftheyear.org${p}`, { headers: { "User-Agent": "Mozilla/5.0 aotybox-ci" } });
      if (r.ok) return await r.text();
      console.log("status", r.status, p);
    } catch (e) { console.log("err", e.message); }
    await new Promise(r => setTimeout(r, 10000));
  }
  return "";
};
for (const p of ["/artist/183-kanye-west/", "/artist/105779-underscores/"]) {
  const h = await get(p);
  console.log("\n#### PAGE", p, h.length);
  let i = h.indexOf('class="albumBlock'); let n = 0;
  while (i >= 0 && n < 3) { console.log("BLOCK:", h.slice(i - 20, i + 1600).replace(/\s+/g, " ")); i = h.indexOf('class="albumBlock', i + 10); n++; }
  for (const k of ["followCount", "follow", "Follow"]) {
    let j = h.indexOf(k), c = 0;
    while (j >= 0 && c < 4) { console.log(`CTX ${k}:`, h.slice(j - 500, j + 500).replace(/\s+/g, " ")); j = h.indexOf(k, j + 600); c++; }
  }
  const scripts = [...h.matchAll(/src="(\/scripts\/[^"]+)"/g)].map(m => m[1]);
  console.log("SCRIPTS", scripts);
  if (p.includes("kanye")) for (const s of scripts) {
    const js = await get(s);
    let j = js.search(/[Ff]ollow/), c = 0;
    while (j >= 0 && c < 6) { console.log(`JS ${s}:`, js.slice(j - 300, j + 700)); const nx = js.slice(j + 700).search(/[Ff]ollow/); if (nx < 0) break; j = j + 700 + nx; c++; }
  }
}
