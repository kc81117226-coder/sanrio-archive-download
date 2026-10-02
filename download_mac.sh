#!/usr/bin/env bash
# Save password-protected Vimeo videos as local MP4 files (yt-dlp + ffmpeg).
# Run:  bash download_mac.sh     (also works on Linux)
# Tools go into ./tools, videos into ./videos. Compatible with macOS bash 3.2.

cd "$(dirname "$0")" || exit 1
TOOLS="$PWD/tools"
OUT="$PWD/videos"
mkdir -p "$TOOLS" "$OUT"

os="$(uname -s)"
arch="$(uname -m)"

echo "============================================================"
echo " Vimeo ダウンローダー (yt-dlp + ffmpeg)"
echo "============================================================"

# --- yt-dlp -----------------------------------------------------------------
case "$os" in
  Darwin) asset=yt-dlp_macos ;;
  Linux)
    asset=yt-dlp_linux
    [ "$arch" = aarch64 ] && asset=yt-dlp_linux_aarch64
    ;;
  *) echo "未対応のOSです: $os"; exit 1 ;;
esac

if [ ! -x "$TOOLS/yt-dlp" ]; then
  echo "[1/3] yt-dlp をダウンロード中..."
  if ! curl -fL --progress-bar -o "$TOOLS/yt-dlp" \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$asset"; then
    echo "*** yt-dlp のダウンロードに失敗しました。ネット接続を確認して再実行してください。"
    exit 1
  fi
  chmod +x "$TOOLS/yt-dlp"
else
  echo "[1/3] yt-dlp を更新中..."
  "$TOOLS/yt-dlp" -U || true
fi

# --- ffmpeg (needed to join the separate video and audio streams) -----------
ffmpeg_dir=""
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg_dir="$(dirname "$(command -v ffmpeg)")"
elif [ -x "$TOOLS/ffmpeg" ]; then
  ffmpeg_dir="$TOOLS"
elif [ "$os" = Darwin ]; then
  echo "[2/3] ffmpeg をダウンロード中..."
  a=arm64
  [ "$arch" = x86_64 ] && a=amd64
  if curl -fL --progress-bar -o "$TOOLS/ffmpeg.zip" \
        "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$a/release/ffmpeg.zip" \
     || { [ "$arch" = x86_64 ] && curl -fL --progress-bar -o "$TOOLS/ffmpeg.zip" \
        "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"; }; then
    unzip -o -q "$TOOLS/ffmpeg.zip" -d "$TOOLS/ffmpeg_unzip"
    found="$(find "$TOOLS/ffmpeg_unzip" -type f -name ffmpeg | head -n 1)"
    if [ -n "$found" ]; then
      mv "$found" "$TOOLS/ffmpeg"
      chmod +x "$TOOLS/ffmpeg"
      ffmpeg_dir="$TOOLS"
    fi
    rm -rf "$TOOLS/ffmpeg.zip" "$TOOLS/ffmpeg_unzip"
  fi
  if [ -z "$ffmpeg_dir" ] && command -v brew >/dev/null 2>&1; then
    echo "Homebrew で ffmpeg を入れます（数分かかります）..."
    brew install ffmpeg && ffmpeg_dir="$(dirname "$(command -v ffmpeg)")"
  fi
fi

if [ -n "$ffmpeg_dir" ]; then
  echo "[2/3] ffmpeg OK: $ffmpeg_dir"
  fmt_args=(--ffmpeg-location "$ffmpeg_dir" -S "res:1080,vcodec:h264,acodec:aac" --merge-output-format mp4)
else
  echo "!!! ffmpeg が用意できませんでした。音声付きの単一ファイル形式で保存を試みます。"
  echo "!!! (Linux なら: sudo apt install ffmpeg で入れてから再実行するのがおすすめ)"
  fmt_args=(-f "b/bv*+ba")
fi

# --- ask for URLs and password ---------------------------------------------
# Sets PLAYER to the embed player URL and WEB to the vimeo.com page URL.
# Logged out, yt-dlp can only read the player URL, and the player refuses
# embed-restricted videos unless the Referer is the vimeo.com page (WEB).
# With cookies.txt (logged in), yt-dlp reads the WEB page directly.
vimeo_urls() {
  local re_web='^https?://(www\.)?vimeo\.com/([0-9]+)(/([0-9a-f]{10}))?/?([?#].*)?$'
  local re_player='^https?://player\.vimeo\.com/video/([0-9]+)'
  PLAYER="$1"
  WEB="$1"
  if [[ $1 =~ $re_web ]]; then
    if [ -n "${BASH_REMATCH[4]}" ]; then
      PLAYER="https://player.vimeo.com/video/${BASH_REMATCH[2]}?h=${BASH_REMATCH[4]}"
      WEB="https://vimeo.com/${BASH_REMATCH[2]}/${BASH_REMATCH[4]}"
    else
      PLAYER="https://player.vimeo.com/video/${BASH_REMATCH[2]}"
      WEB="https://vimeo.com/${BASH_REMATCH[2]}"
    fi
  elif [[ $1 =~ $re_player ]]; then
    WEB="https://vimeo.com/${BASH_REMATCH[1]}"
  fi
}

echo
echo "保存したい Vimeo の URL を 1 行ずつ貼り付けて Enter。"
echo "全部入れたら、何も入力せずに Enter を押してください。"
urls=()
webs=()
while :; do
  read -r -p "URL $(( ${#urls[@]} + 1 )): " u </dev/tty || break
  u="${u//[[:space:]]/}"
  [ -z "$u" ] && break
  vimeo_urls "$u"
  echo "    = $PLAYER"
  urls+=("$PLAYER")
  webs+=("$WEB")
done

if [ ${#urls[@]} -eq 0 ]; then
  echo "URL が入力されませんでした。"
  exit 1
fi

read -r -p "Vimeo のパスワード（無ければ空のまま Enter）: " pw </dev/tty

# --- download ----------------------------------------------------------------
cookies="$PWD/cookies.txt"
failed=0
i=0
while [ "$i" -lt "${#urls[@]}" ]; do
  url="${urls[$i]}"
  web="${webs[$i]}"
  i=$((i + 1))
  out="$OUT/$i - %(title)s [%(id)s].%(ext)s"
  echo
  echo "[3/3] ${i}/${#urls[@]} 本目をダウンロード中..."
  if "$TOOLS/yt-dlp" "${fmt_args[@]}" --video-password "$pw" \
       --add-headers "Referer:$web" \
       -N 4 --retries 30 --fragment-retries 100 -o "$out" "$url"; then
    continue
  fi
  if [ -f "$cookies" ]; then
    echo
    echo "cookies.txt（Vimeo にログインした状態）で再試行します..."
    if "$TOOLS/yt-dlp" "${fmt_args[@]}" --video-password "$pw" \
         --cookies "$cookies" \
         -N 4 --retries 30 --fragment-retries 100 -o "$out" "$web"; then
      continue
    fi
  fi
  failed=1
done

echo
if [ "$failed" -ne 0 ]; then
  echo "*** 失敗したものがあります。"
  echo "*** 次の手: cookies.txt をこのスクリプトと同じ場所に置いて再実行（README.md 参照）。"
  echo "*** それでもダメなら README.md の「画面録画」の手順を使ってください。"
else
  echo "完了しました。保存先: $OUT"
fi
[ "$os" = Darwin ] && open "$OUT"
exit "$failed"
