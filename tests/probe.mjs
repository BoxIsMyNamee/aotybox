// One-off: print markup around rating distribution rows and user names on an archived user-reviews page.
const urls = ["https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/album/2915-outkast-aquemini/user-reviews/",
  "https://web.archive.org/web/2025id_/https://www.albumoftheyear.org/album/1998-kanye-west-my-beautiful-dark-twisted-fantasy/user-reviews/"];
for (const u of urls) {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(u); const h = await r.text();
      const k = h.indexOf("distRow");
      console.log("==", u, r.status, h.length);
      console.log(h.slice(Math.max(0, k - 600), k + 1500));
      const n = h.indexOf("userReviewName");
      console.log("-- name:", h.slice(n - 100, n + 400));
      break;
    } catch (e) { console.log("retry", e.message); await new Promise(r => setTimeout(r, 4000)); }
  }
}
