for (const f of ["bandScript.js?v=2", "main.js?v=1788984971", "albumScript.js?v=33"]) {
  try {
    const js = await (await fetch("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/scripts/" + f)).text();
    const re = /CreditList|credit/gi; let m, n = 0;
    console.log("FILE", f, js.length);
    while ((m = re.exec(js)) && n < 4) { console.log("HIT:", js.slice(Math.max(0, m.index - 300), m.index + 900).replace(/\n/g, " ")); re.lastIndex = m.index + 900; n++; }
  } catch (e) { console.log("err", e.message); }
}
