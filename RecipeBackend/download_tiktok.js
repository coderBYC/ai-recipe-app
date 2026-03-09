#!/usr/bin/env node
/**
 * Download a TikTok video to a local file using @tobyg74/tiktok-api-dl.
 * Usage: node download_tiktok.js <tiktok_url> <output_path>
 * Exits 0 on success, 1 on failure.
 * @see https://github.com/TobyG74/tiktok-api-dl
 */

const fs = require("fs");
const path = require("path");
const https = require("https");
const http = require("http");

const url = process.argv[2];
const outputPath = process.argv[3];

if (!url || !outputPath) {
  console.error("Usage: node download_tiktok.js <tiktok_url> <output_path>");
  process.exit(1);
}

function getVideoUrl(result) {
  if (!result || result.status !== "success") return null;
  const r = result.result;
  if (!r) return null;
  // v1: result.video.downloadAddr (array or string)
  if (r.video && r.video.downloadAddr) {
    const addr = r.video.downloadAddr;
    if (Array.isArray(addr) && addr[0]) return typeof addr[0] === "string" ? addr[0] : (addr[0].url || addr[0].src);
    if (typeof addr === "string") return addr;
  }
  // v2: result.video.playAddr or result.direct
  if (r.video && r.video.playAddr) return typeof r.video.playAddr === "string" ? r.video.playAddr : (r.video.playAddr.url || r.video.playAddr[0]);
  if (r.direct) return typeof r.direct === "string" ? r.direct : (r.direct.url || r.direct[0]);
  // v3: result.videoHD or result.videoWatermark
  if (r.videoHD) return typeof r.videoHD === "string" ? r.videoHD : (r.videoHD.url || r.videoHD[0]);
  if (r.videoWatermark) return typeof r.videoWatermark === "string" ? r.videoWatermark : (r.videoWatermark.url || r.videoWatermark[0]);
  return null;
}

function ensureStringUrl(value) {
  if (typeof value === "string" && value.length > 0) return value;
  if (Array.isArray(value) && value.length > 0) return ensureStringUrl(value[0]);
  if (value && typeof value === "object" && (value.url || value.src)) return String(value.url || value.src);
  return null;
}

function downloadToFile(fileUrl, destPath) {
  const urlString = ensureStringUrl(fileUrl);
  if (!urlString || typeof urlString !== "string") {
    return Promise.reject(new Error("Invalid video URL"));
  }
  return new Promise((resolve, reject) => {
    const protocol = urlString.startsWith("https") ? https : http;
    const file = fs.createWriteStream(destPath);
    protocol
      .get(urlString, { headers: { "User-Agent": "Mozilla/5.0 (compatible; RecipeBackend/1.0)" } }, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          file.close();
          try { fs.unlinkSync(destPath); } catch (_) {}
          return downloadToFile(res.headers.location, destPath).then(resolve).catch(reject);
        }
        if (res.statusCode !== 200) {
          file.close();
          try { fs.unlinkSync(destPath); } catch (_) {}
          return reject(new Error(`HTTP ${res.statusCode}`));
        }
        res.pipe(file);
        file.on("finish", () => {
          file.close();
          resolve();
        });
      })
      .on("error", (err) => {
        file.close();
        try { fs.unlinkSync(destPath); } catch (_) {}
        reject(err);
      });
  });
}

async function main() {
  let Tiktok;
  try {
    Tiktok = require("@tobyg74/tiktok-api-dl");
  } catch (e) {
    console.error("Missing dependency. Run: npm install");
    process.exit(1);
  }

  try {
    const result = await Tiktok.Downloader(url, { version: "v1" });
    let videoUrl = getVideoUrl(result);
    if (!videoUrl && result.resultNotParsed) {
      const r = result.resultNotParsed;
      if (r && r.result && r.result.video && r.result.video.downloadAddr)
        videoUrl = ensureStringUrl(r.result.video.downloadAddr);
    }
    if (!videoUrl) {
      const v2 = await Tiktok.Downloader(url, { version: "v2" });
      videoUrl = getVideoUrl(v2);
    }
    if (!videoUrl) {
      const v3 = await Tiktok.Downloader(url, { version: "v3" });
      videoUrl = getVideoUrl(v3);
    }
    if (!videoUrl) {
      console.error("Could not get video URL from TikTok API");
      process.exit(1);
    }
    const urlString = ensureStringUrl(videoUrl);
    if (!urlString) {
      console.error("Video URL is not a valid string");
      process.exit(1);
    }
    const dir = path.dirname(outputPath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    await downloadToFile(urlString, outputPath);
    process.exit(0);
  } catch (err) {
    console.error("TikTok download error:", err.message);
    process.exit(1);
  }
}

main();
