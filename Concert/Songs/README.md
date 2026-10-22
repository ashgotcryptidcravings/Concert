# Concert song library

Put albums inside one of the quality folders. A normal album can contain all
its tracks directly, or separate them into numbered disc folders:

```text
Songs/
  Standard/
    Glass Animals - Dreamland/
      01. Dreamland.mp3
      02. Tangerine.mp3
      cover.jpg
    Persona 5 Original Soundtrack/
      cover.jpg
      Disc 1/
        01. Wake Up, Get Up, Get Out There.mp3
        02. Phantom.mp3
      Disc 2/
        01. Tokyo Daylight.mp3
  Standard Lossless/
  Full Spatial Lossless/
```

Concert treats the album folder as one album, recognizes `Disc`, `Disk`, or
`CD` folders with a number, and sorts tracks by disc then their leading track
number. It also supports the original single-song folder format, with one
audio file and optional cover image in each song folder.

Title, artist, album, and embedded artwork are read from audio metadata when
available. Otherwise, track names come from filenames, album names from the
album folder, and artist is shown as "Unknown Artist". A `cover.jpg` or
`cover.png` in the album or disc folder is used as artwork when available.

Add folders inside this `Songs` folder on the Mac. Concert reads the library
from the Mac music server and downloads a track to the iPhone the first time it
is played. The audio files are kept out of the iPhone app bundle. Audio formats scanned:
M4A, MP3, AAC, WAV, AIFF, CAF, ALAC, and FLAC. Playback support depends on the
iOS audio decoder.

To start the server, open `MacLibraryServer/Start Concert Music Server.command`
from this repository on the Mac. The first launch prepares a small Python
environment. Keep its Terminal window open while listening. It prints the
Mac’s local address; paste that address into Concert’s Settings and tap
Connect. Both devices must be on the same Wi-Fi network.
