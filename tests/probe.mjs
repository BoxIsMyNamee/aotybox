const base = "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/artist/183-kanye-west/";
async function get(u) { for (let i = 0; i < 3; i++) { try { return await (await fetch(u)).text(); } catch (e) { await new Promise(r => setTimeout(r, 4000)); } } return ""; }
const h = await get(base);
let k = h.indexOf("Appears On"); console.log("APPEARS:", k < 0 ? "none" : h.slice(k - 500, k + 300).replace(/\n/g, " "));
k = h.indexOf("Credits"); console.log("CREDITS:", k < 0 ? "none" : h.slice(k - 100, k + 700).replace(/\n/g, " "));
