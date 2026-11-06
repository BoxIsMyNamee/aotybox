const h = await (await fetch("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/artist/183-kanye-west/")).text();
const k = h.indexOf("// Show Credits");
console.log("HANDLER:", h.slice(k, k + 1800).replace(/\n/g, " "));
