import instaloader  # pyright: ignore[reportMissingImports]
import os
import time
import glob
import subprocess
import uuid
import traceback
#import pyktok as pyk # pyright: ignore[reportMissingImports]

def download_tiktok_video(url, target_dir="downloads"):
    """Download a TikTok video using @tobyg74/tiktok-api-dl.
    Returns (video_path, creator_name) on success, or None on failure.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    script_path = os.path.join(script_dir, "download_tiktok.js")
    #metadata = pyk.get_tiktok_json(url)
    #author = metadata.get('author', {}).get('nickname', '')
    if not os.path.isfile(script_path):
        print("❌ download_tiktok.js not found")
        return None
    os.makedirs(target_dir, exist_ok=True)
    out_name = f"tiktok_{uuid.uuid4().hex[:12]}.mp4"
    out_path = os.path.join(target_dir, out_name)
    creator_name = ""
    try:
        result = subprocess.run(
            ["node", script_path, url, os.path.abspath(out_path)],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=script_dir,
        )
        if result.returncode != 0:
            print(f"❌ TikTok download failed: {result.stderr or result.stdout}")
            return None
        # Parse creator from JS output line like: CREATOR_NAME:<name>
        if result.stdout:
            for line in result.stdout.splitlines():
                if line.startswith("CREATOR_NAME:"):
                    creator_name = line.split("CREATOR_NAME:", 1)[1].strip()
                    break
        if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
            return out_path, creator_name
        return None
    except subprocess.TimeoutExpired:
        print("❌ TikTok download timed out")
        return None
    except FileNotFoundError:
        print("❌ Node.js not found. Install Node and run: npm install")
        return None
    except Exception as e:
        print(f"❌ Error in download_tiktok_video: {e}")
        traceback.print_exc()
        return None


def download_instagram_reel(url, target_dir="downloads"):
    L = instaloader.Instaloader(
    save_metadata=False,
    download_pictures=False,
    download_videos=True,
    download_video_thumbnails=False,
    download_geotags=False,
    post_metadata_txt_pattern=None
)
    # Optional: Login if the reel is private or restricted
    # L.login("YOUR_USERNAME", "YOUR_PASSWORD") 
    try:
        # Extract the 'shortcode' from the URL (e.g., 'C12345' from /reels/C12345/)
        shortcode = url.split("/")[-2]
        post = instaloader.Post.from_shortcode(L.context, shortcode)
        author = post.owner_profile.full_name
        print(shortcode)
        # Download the reel
        L.download_post(post, target=target_dir)
        time.sleep(1)
        files = glob.glob(os.path.join(target_dir, "*.mp4"))
        if not files:
            return None
        old_file = max(files, key=os.path.getctime)
        new_file = os.path.join(target_dir, f"{shortcode}.mp4")
        if os.path.exists(new_file):
            os.remove(new_file)
        os.rename(old_file, new_file)
        return new_file, author
    except Exception as e:
        print(f"❌ Error in download_instagram_reel: {e}")
        traceback.print_exc()
        return None