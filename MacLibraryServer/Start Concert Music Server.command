#!/bin/zsh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VENV="$ROOT/.concert-server-venv"

# A virtual environment is tied to the Python installation that created it.
# If the repo was moved to another Mac (or Python was upgraded), its symlinks
# can exist but point to a missing interpreter. Check that it actually starts.
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" --version >/dev/null 2>&1; then
    echo "Preparing Concert's music server environment..."
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Python 3 is required. Install it from python.org, then run this file again."
        read -r "?Press Return to close..."
        exit 1
    fi
    python3 -m venv --clear "$VENV" || {
        echo "Could not create the Python environment. Install Python 3 from python.org and try again."
        read -r "?Press Return to close..."
        exit 1
    }
fi

"$VENV/bin/python" -m pip install --disable-pip-version-check -q -r "$ROOT/MacLibraryServer/requirements.txt" || {
    echo "Could not install the server's audio-tagging dependency. Check your internet connection and try again."
    read -r "?Press Return to close..."
    exit 1
}
exec "$VENV/bin/python" "$ROOT/MacLibraryServer/serve.py" --library "$ROOT/Concert/Songs"
