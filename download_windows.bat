@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Save password-protected Vimeo videos as local MP4 files (yt-dlp + ffmpeg).
rem Double-click to run. Tools go into .\tools, videos into .\videos.
cd /d "%~dp0"

set "TOOLS=%~dp0tools"
set "OUT=%~dp0videos"
if not exist "%TOOLS%" mkdir "%TOOLS%"
if not exist "%OUT%" mkdir "%OUT%"

echo ============================================================
echo  Vimeo downloader  (yt-dlp + ffmpeg)
echo ============================================================
echo.

if not exist "%TOOLS%\yt-dlp.exe" (
  echo [1/3] Downloading yt-dlp ...
  curl.exe -fL -o "%TOOLS%\yt-dlp.exe" "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
  if errorlevel 1 goto :fail
) else (
  echo [1/3] Updating yt-dlp ...
  "%TOOLS%\yt-dlp.exe" -U
)

if not exist "%TOOLS%\ffmpeg\bin\ffmpeg.exe" (
  echo [2/3] Downloading ffmpeg - about 200 MB ...
  curl.exe -fL -o "%TOOLS%\ffmpeg.zip" "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
  if errorlevel 1 goto :fail
  tar.exe -xf "%TOOLS%\ffmpeg.zip" -C "%TOOLS%"
  if errorlevel 1 goto :fail
  move "%TOOLS%\ffmpeg-master-latest-win64-gpl" "%TOOLS%\ffmpeg" >nul
  del "%TOOLS%\ffmpeg.zip"
) else (
  echo [2/3] ffmpeg is ready.
)

echo.
echo Paste the Vimeo URLs one per line.
echo When you are done, press Enter on an empty line.
set /a N=0
:askurl
set /a NEXT=N+1
set "U="
set /p "U=URL !NEXT!: "
if not defined U goto :askpw
set /a N+=1
set "URL!N!=!U!"
goto :askurl

:askpw
if %N%==0 (
  echo No URL was entered.
  goto :end
)
set "PW="
set /p "PW=Vimeo password - leave empty if none: "

set "FAILED="
for /l %%i in (1,1,%N%) do (
  echo.
  echo [3/3] Downloading video %%i of %N% ...
  "%TOOLS%\yt-dlp.exe" --ffmpeg-location "%TOOLS%\ffmpeg\bin" --video-password "!PW!" -S "res:1080,vcodec:h264,acodec:aac" --merge-output-format mp4 -N 4 --retries 30 --fragment-retries 100 -o "%OUT%\%%i - %%(title)s [%%(id)s].%%(ext)s" "!URL%%i!"
  if errorlevel 1 set "FAILED=1"
)

echo.
if defined FAILED (
  echo *** Some downloads FAILED. Run this file again - it resumes where it stopped.
  echo *** If it keeps failing, see README.md for the screen-recording fallback.
) else (
  echo All done. Saved to: !OUT!
)
start "" "%OUT%"
goto :end

:fail
echo.
echo *** Could not download the tools. Check your internet connection and run again.

:end
echo.
pause
endlocal
