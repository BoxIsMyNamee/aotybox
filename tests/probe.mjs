const h = await (await fetch("https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/artist/183-kanye-west/")).text();
let k = h.indexOf("artistCreditList", h.indexOf("<script"));
const all = [...h.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).filter(t => /CreditList|albumOutput|post\(/i.test(t));
all.forEach(t => console.log("INLINE:", t.slice(0, 2500).replace(/\n/g, " ")));
const srcs = [...h.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
console.log("SRCS:", srcs.join(" "));
