#!/usr/bin/env python3
"""Serve Concert's local Songs folder to the iPhone app over a private LAN."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import re
import shutil
import socket
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import quote, unquote, urlsplit

from mutagen import File as MutagenFile


AUDIO_EXTENSIONS = {"m4a", "mp3", "aac", "wav", "aiff", "aif", "caf", "alac", "flac"}
IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "heic", "tiff", "webp"}
DISC_PATTERN = re.compile(r"^(?:disc|disk|cd)\s*[-_ ]*0*(\d+)\b", re.IGNORECASE)
TRACK_PATTERN = re.compile(r"^\s*0*(\d+)(?:\s*[.\-_)]|\s+)")


def clean_tag(tags, name: str, fallback: str = "") -> str:
    value = tags.get(name) if tags else None
    if isinstance(value, (list, tuple)):
        value = value[0] if value else None
    return str(value).strip() if value is not None and str(value).strip() else fallback


def tag_number(value: Optional[str], fallback: int) -> int:
    if not value:
        return fallback
    match = re.match(r"\s*(\d+)", str(value))
    return int(match.group(1)) if match else fallback


def embedded_artwork(path: Path):
    try:
        audio = MutagenFile(path)
        tags = getattr(audio, "tags", None)
        if not tags:
            return None
        pictures = getattr(audio, "pictures", None)
        if pictures:
            picture = pictures[0]
            return bytes(picture.data), picture.mime or "image/jpeg"
        for key in tags.keys():
            value = tags[key]
            if str(key).upper().startswith("APIC:") and getattr(value, "data", None):
                return bytes(value.data), getattr(value, "mime", "image/jpeg")
        cover = tags.get("covr")
        if cover:
            data = bytes(cover[0])
            mime = "image/png" if data.startswith(b"\x89PNG") else "image/jpeg"
            return data, mime
    except Exception:
        pass
    return None


def file_artwork(path: Path):
    try:
        data = path.read_bytes()
        mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
        return data, mime
    except OSError:
        return None


class ConcertLibrary:
    def __init__(self, songs_root: Path, port: int):
        self.songs_root = songs_root.resolve()
        self.port = port
        self.audio_by_id: dict[str, Path] = {}
        self.artwork_by_id: dict[str, tuple[bytes, str]] = {}
        self._manifest: list[dict] = []
        self._built_at = 0.0
        self._lock = threading.Lock()

    def manifest(self, host: str) -> list[dict]:
        with self._lock:
            if time.monotonic() - self._built_at > 30:
                self._build()
            result = []
            for item in self._manifest:
                item = dict(item)
                item["audioURL"] = f"http://{host}/audio/{item['id']}.{item['extension']}?v={item['version']}"
                item["artworkURL"] = f"http://{host}/artwork/{item['artworkID']}" if item.get("artworkID") else None
                result.append(item)
            return result

    def _build(self):
        self.audio_by_id = {}
        self.artwork_by_id = {}
        self._manifest = []
        if not self.songs_root.is_dir():
            return

        artwork_by_album: dict[str, tuple[str, tuple[bytes, str]]] = {}
        pending = []
        for path in sorted(self.songs_root.rglob("*")):
            if not path.is_file() or path.suffix.lower().lstrip(".") not in AUDIO_EXTENSIONS:
                continue
            relative = path.relative_to(self.songs_root)
            if len(relative.parts) < 3:
                continue

            quality = relative.parts[0]
            album_name = relative.parts[1]
            album_folder = self.songs_root / quality / album_name
            disc_number = 1
            for part in relative.parts[2:-1]:
                match = DISC_PATTERN.match(part)
                if match:
                    disc_number = int(match.group(1))
                    break

            try:
                audio = MutagenFile(path, easy=True)
                tags = getattr(audio, "tags", None)
                duration_seconds = float(getattr(getattr(audio, "info", None), "length", 0) or 0)
            except Exception:
                audio, tags, duration_seconds = None, None, 0

            title_from_name = path.stem
            title_from_name = TRACK_PATTERN.sub("", title_from_name).strip() or path.stem
            title = clean_tag(tags, "title", title_from_name)
            artist = clean_tag(tags, "artist", "Unknown Artist")
            album = clean_tag(tags, "album", album_name)
            album_id = f"{artist.strip().lower()}|{album.strip().lower()}"
            file_number = TRACK_PATTERN.match(path.stem)
            filename_track_number = int(file_number.group(1)) if file_number else len(pending) + 1
            track_number = tag_number(clean_tag(tags, "tracknumber", ""), filename_track_number)
            disc_number = tag_number(clean_tag(tags, "discnumber", ""), disc_number)
            digest = hashlib.sha256(relative.as_posix().encode("utf-8")).hexdigest()[:32]
            version = path.stat().st_mtime_ns
            self.audio_by_id[digest] = path

            artwork = None
            artwork_candidates = [album_folder / name for name in ("cover.jpg", "cover.jpeg", "cover.png", "Cover.jpg", "Cover.png")]
            if len(relative.parts) > 3 and DISC_PATTERN.match(relative.parts[2]):
                disc_folder = album_folder / relative.parts[2]
                artwork_candidates += [disc_folder / name for name in ("cover.jpg", "cover.jpeg", "cover.png", "Cover.jpg", "Cover.png")]
            for candidate in artwork_candidates:
                if candidate.is_file():
                    artwork = file_artwork(candidate)
                    if artwork:
                        break
            if not artwork:
                artwork = embedded_artwork(path)
            if artwork and album_id not in artwork_by_album:
                art_id = hashlib.sha256(album_id.encode("utf-8")).hexdigest()[:32]
                artwork_by_album[album_id] = (art_id, artwork)

            pending.append({
                "id": digest,
                "extension": path.suffix.lower().lstrip("."),
                "version": version,
                "libraryKey": relative.as_posix().lower(),
                "title": title,
                "artist": artist,
                "album": album,
                "duration": f"{int(duration_seconds) // 60}:{int(duration_seconds) % 60:02d}",
                "quality": quality,
                "albumID": album_id,
                "discNumber": disc_number,
                "trackNumber": track_number,
                "artworkID": None,
            })

        for item in pending:
            artwork_entry = artwork_by_album.get(item["albumID"])
            if artwork_entry:
                art_id, artwork = artwork_entry
                item["artworkID"] = art_id
                self.artwork_by_id[art_id] = artwork
        self._manifest = pending
        self._built_at = time.monotonic()

    def audio_file(self, file_id: str) -> Path | None:
        with self._lock:
            if time.monotonic() - self._built_at > 30:
                self._build()
            return self.audio_by_id.get(file_id)

    def artwork(self, artwork_id: str):
        with self._lock:
            if time.monotonic() - self._built_at > 30:
                self._build()
            return self.artwork_by_id.get(artwork_id)


def local_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def make_handler(library: ConcertLibrary):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ConcertLibrary/1.0"

        def log_message(self, fmt, *args):
            print(f"[{datetime.now().strftime('%H:%M:%S')}] {fmt % args}")

        def _write(self, status: int, payload: bytes, content_type: str, headers=None):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            for name, value in (headers or {}).items():
                self.send_header(name, value)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)

        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            host = self.headers.get("Host", f"127.0.0.1:{library.port}")
            if path == "/api/health":
                self._write(200, b'{"status":"ok"}', "application/json; charset=utf-8")
                return
            if path == "/api/library":
                payload = json.dumps(library.manifest(host), ensure_ascii=False).encode("utf-8")
                self._write(200, payload, "application/json; charset=utf-8")
                return
            if path.startswith("/artwork/"):
                artwork = library.artwork(path.rsplit("/", 1)[-1])
                if not artwork:
                    self.send_error(404)
                    return
                self._write(200, artwork[0], artwork[1], {"Cache-Control": "public, max-age=86400"})
                return
            if path.startswith("/audio/"):
                filename = path.rsplit("/", 1)[-1]
                file_id = filename.rsplit(".", 1)[0]
                audio_path = library.audio_file(file_id)
                if not audio_path:
                    self.send_error(404)
                    return
                self._send_audio(audio_path)
                return
            self.send_error(404)

        def do_HEAD(self):
            self.do_GET()

        def _send_audio(self, path: Path):
            size = path.stat().st_size
            range_header = self.headers.get("Range")
            start, end, status = 0, size - 1, 200
            if range_header:
                match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header.strip())
                if not match or (not match.group(1) and not match.group(2)):
                    self.send_error(416)
                    return
                if match.group(1):
                    start = int(match.group(1))
                    end = int(match.group(2)) if match.group(2) else size - 1
                else:
                    suffix_length = int(match.group(2))
                    start = max(0, size - suffix_length)
                if start >= size or end < start:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
                end = min(end, size - 1)
                status = 206

            length = end - start + 1
            content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if self.command == "HEAD":
                return
            with path.open("rb") as stream:
                stream.seek(start)
                shutil.copyfileobj(_LimitedReader(stream, length), self.wfile, length=256 * 1024)

    return Handler


class _LimitedReader:
    def __init__(self, stream, remaining: int):
        self.stream = stream
        self.remaining = remaining

    def read(self, amount=-1):
        if self.remaining <= 0:
            return b""
        if amount < 0 or amount > self.remaining:
            amount = self.remaining
        data = self.stream.read(amount)
        self.remaining -= len(data)
        return data


def main():
    parser = argparse.ArgumentParser(description="Serve local Concert songs to an iPhone on Wi-Fi.")
    parser.add_argument("--library", type=Path, required=True, help="Path to the Concert/Songs folder")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    library = ConcertLibrary(args.library, args.port)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(library))
    print(f"Concert music server ready: http://{local_ip()}:{args.port}")
    print(f"Library folder: {library.songs_root}")
    print("Keep this window open while listening. Press Control-C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping Concert music server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
