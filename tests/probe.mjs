const u = "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/artist/183-kanye-west/";
for (let i = 0; i < 3; i++) {
  try {
    const h = await (await fetch(u)).text();
    const links = [...h.matchAll(/<a[^>]+href="([^"]*)"[^>]*>([^<]{0,40})/g)].filter(m => /type|facet|filter|Reissue|Live|Single|Demo|Compilation/i.test(m[1] + m[2]));
    console.log("FACETS:", links.slice(0, 40).map(m => m[1] + " => " + m[2].trim()).join("\n"));
    const k = h.indexOf("ratingRow");
    console.log("RATING:", h.slice(k - 200, k + 900));
    const f = h.search(/facet|filterContainer|Type<\/div>/i);
    console.log("FILTERBOX:", h.slice(f - 300, f + 1500));
    break;
  } catch (e) { console.log("retry", e.message); await new Promise(r => setTimeout(r, 4000)); }
}
