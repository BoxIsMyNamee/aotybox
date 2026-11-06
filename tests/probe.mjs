for (const u of ["https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/scripts/bandScript.js?v=2",
                 "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/scripts/bandScript.js"]) {
  try {
    const js = await (await fetch(u)).text();
    console.log("LEN", js.length);
    let k = js.indexOf("artistCreditList");
    while (k >= 0) { console.log("CREDIT:", js.slice(Math.max(0, k - 200), k + 1400)); k = js.indexOf("artistCreditList", k + 1400); }
    if (js.includes("artistCreditList")) break;
  } catch (e) { console.log("err", e.message); }
}
