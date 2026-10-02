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
echo
echo "保存したい Vimeo の URL を 1 行ずつ貼り付けて Enter。"
echo "全部入れたら、何も入力せずに Enter を押してください。"
urls=()
while :; do
  read -r -p "URL $(( ${#urls[@]} + 1 )): " u </dev/tty || break
  u="${u//[[:space:]]/}"
  [ -z "$u" ] && break
  urls+=("$u")
done

if [ ${#urls[@]} -eq 0 ]; then
  echo "URL が入力されませんでした。"
  exit 1
fi

read -r -p "Vimeo のパスワード（無ければ空のまま Enter）: " pw </dev/tty

# --- download ----------------------------------------------------------------
failed=0
i=0
for url in "${urls[@]}"; do
  i=$((i + 1))
  echo
  echo "[3/3] ${i}/${#urls[@]} 本目をダウンロード中..."
  "$TOOLS/yt-dlp" "${fmt_args[@]}" \
    --video-password "$pw" \
    -N 4 --retries 30 --fragment-retries 100 \
    -o "$OUT/$i - %(title)s [%(id)s].%(ext)s" \
    "$url" || failed=1
done

echo
if [ "$failed" -ne 0 ]; then
  echo "*** 失敗したものがあります。もう一度このスクリプトを実行すると途中から再開します。"
  echo "*** 何度やってもダメな場合は README.md の「画面録画」の手順を使ってください。"
else
  echo "完了しました。保存先: $OUT"
fi
[ "$os" = Darwin ] && open "$OUT"
exit "$failed"
