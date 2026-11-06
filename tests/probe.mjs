const url = "https://web.archive.org/web/2026id_/https://www.albumoftheyear.org/scripts/main.js";
for (let i = 0; i < 3; i++) {
  try {
    const js = await (await fetch(url)).text();
    console.log("LEN", js.length);
    for (const key of ["review_like", "likeReview", "reviewLike", "ajax/like", "like.php", "/scripts/ajax", "type == \"reviewLike", "review_likes_"]) {
      let k = js.indexOf(key), n = 0;
      while (k >= 0 && n < 2) { console.log("KEY", key, ":", js.slice(Math.max(0, k - 400), k + 700).replace(/\n/g, " ")); k = js.indexOf(key, k + 1); n++; }
    }
    break;
  } catch (e) { console.log("retry", e.message); await new Promise(r => setTimeout(r, 4000)); }
}
