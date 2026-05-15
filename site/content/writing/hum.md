---
title: "Building an Audio Fingerprinting Service"
date: 2026-05-15
excerpt: "On building a shazam-like audio matching service"
tags: ["engineering"]
image: "/hum-result.png"
---
﻿I read Avery Wang's [2003 paper on audio fingerprinting](https://www.ee.columbia.edu/~dpwe/papers/Wang03-shazam.pdf) and wanted to try it myself. Wang was one of Shazam's founders; the paper describes the core algorithm still running in the app today. I just wanted to see how much of it I could build from scratch.

And so, I wrote a small service that ingests WAV files, generates fingerprints, and identifies songs from microphone recordings.


The obvious approach to matching audio is to compare two recordings point by point. However, this breaks immediately once there's any noise. Room echo, someone talking nearby, etc: any of it shifts the audio to kill the comparison.

The paper's approach is to stop comparing the raw audio and build a map instead. You turn the recording into something like a heat map: time on one axis, pitch on the other and brightness showing how loud each pitch is at each moment. Then you throw away almost everything except the brightest spots, the pitches that are loudest relative to their immediate neighborhood. These are the dominant notes, the ones that cut through everything else.

You then connect pairs of those peaks, anchor one, find nearby ones, record their pitches and the time gap between them, and you get a fingerprint. This fingerprint is a sparse set of relationships between its loudest moments. Those ones go into a database.

To identify a recording, you generate the same fingerprint from the mic audio and look up the hashes. If enough of them agree on the same time offset relative to some stored song, it's a match.

Why does this survive noise? Those dominant peaks are hard to destroy. For instance, a rap beat played through a laptop speaker into a phone mic still puts energy in roughly the same pitches. The loudest moments will make it through. The fingerprint matches. And because you're only tracking a sparse set of peaks, different songs rarely produce the same fingerprint, but a 10-second clip still generates enough matching points to be confident.


The [DSP](https://en.wikipedia.org/wiki/Digital_signal_processing) pipeline runs entirely server-side, fingerprint generation, storage and matching. I made the client a simple Blazor WASM with two pages: one to ingest audio files and another for live identification. Audio capture is JavaScript via the [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API).

The fingerprint hash packs three values into a 32-bit unsigned integer:

```csharp
/*
 * Hash bit layout (32-bit unsigned):
 *   bits 31-22: anchor frequency bin (10 bits, range 0-1023)
 *   bits 21-12: target frequency bin (10 bits, range 0-1023)
 *   bits 11-0:  time delta (12 bits, range 0-4095)
 */
uint hash = ((uint)anchor.FrequencyBin & 0x3FF) << 22
          | ((uint)target.FrequencyBin & 0x3FF) << 12
          | ((uint)delta & 0xFFF);
```

This makes it fast to compute, and the 32-bit key indexes directly in SQLite: which I used as a database.

## The Pipeline

The browser captures audio and sends a WAV file to the server. From there it's a chain: resample to the expected rate, build a spectrogram, pick the dominant peaks, hash them into fingerprints, and look up matches. Here's what each stage does.

**Audio capture** was the first decision. The obvious Web API is MediaRecorder. It works in every browser, it's simple, you get a Blob. The problem was that: [`MediaRecorder`](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder) outputs [WebM](https://en.wikipedia.org/wiki/WebM) with [Opus](https://en.wikipedia.org/wiki/Opus_(audio_format)) audio in Chrome, and my server's WAV decoder has no idea what to do with that. 

I could've pulled in a full demuxer library, but I didn't want the dependency. Instead I used `AudioContext` with `ScriptProcessorNode`: the `onaudioprocess` callback fires with raw float32 [PCM](https://en.wikipedia.org/wiki/Pulse-code_modulation) samples, which I pack into a WAV manually in JavaScript.

```javascript
writeString(8, 'WAVE');
writeString(12, 'fmt ');
view.setUint32(16, 16, true);        // fmt chunk size
view.setUint16(20, 1, true);         // PCM = 1
view.setUint16(22, 1, true);         // mono
view.setUint32(24, actualSampleRate, true);
```

Now writing a WAV header in JavaScript at midnight is exactly as tedious as it sounds, but it works and it's deterministic. So lets keep it at that.

**Resampling** came up immediately. I asked the browser to record at 44100 samples per second, but apparently Chrome on most hardware ignores that hint and records at 48000 instead. That matters because my fingerprinting code identifies pitches by their position in a fixed grid, if the recording speed doesn't match what the code expects, every pitch lands in the wrong slot and the fingerprint comes out wrong. A resampler on the server converts the 48000 recording down to 44100 before fingerprinting starts. It's not perfect, a bit of quality gets lost in the conversion, but the dominant peaks survive intact.

**SpectrogramBuilder** applies a [Hamming window](https://en.wikipedia.org/wiki/Window_function#Hann_and_Hamming_windows) to each frame before the [FFT](https://en.wikipedia.org/wiki/Fast_Fourier_transform), which reduces [spectral leakage](https://en.wikipedia.org/wiki/Spectral_leakage). FFT size 1024 with a hop size of 512 means roughly 86 frames per second at 44100 Hz. Each frame produces 512 magnitude bins. The magnitudes aren't normalized by FFT size, which matters for the peak detection threshold downstream.

**PeakPicker** scans every time-frequency cell and checks whether it's the maximum value in its 20×20 neighbourhood. If it is, and it's above a magnitude threshold, it's a peak. A configurable `MaxPeaksPerSecond` parameter caps the total count; when there are more candidates than allowed, it keeps the highest-magnitude ones. A boundary exclusion of 5 frames at each end prevents window edge artifacts from becoming false peaks.

**FingerprintGenerator** iterates over the sorted peaks. For each anchor, it scans forward in time and pairs it with up to 5 targets within the configured time delta window. The time delta is encoded in the hash, anchoring the spatial relationship between peaks.

**MatcherService** finally looks up every query hash in SQLite and accumulates a histogram: for each `(songId, timeDelta)` pair, how many query hashes point there? The timeDelta here is `dbOffset - queryOffset`, the shift in frame position between where the anchor appears in the stored song and where it appears in the query. A consistent delta across many hashes means the query audio overlaps with the stored audio at a specific time position.

## Some Difficulties I Came Across

**Wrong Filename** The database library I used treats its connection string as a literal file path, not a formatted key-value string like most database drivers do. Passing `"Data Source=hum.db"` didn't open a database called `hum.db`; it created a file named `Data Source=hum.db`. I found this because `git status` showed an untracked file with that exact name sitting in the project directory. Anyway, this cost me an embarrassing amount of time.

**UI freeze.** Uploading a WAV file used to lock the entire interface. Click "choose file," pick something, and the browser would go unresponsive for several seconds. The app runs on a single thread, it can't repaint the UI while it's busy reading a large file. The fix was to force a repaint *before* the blocking work starts, not after:

```csharp
_readingFile = true;
StateHasChanged();           // forces a repaint NOW, before blocking
await stream.CopyToAsync(ms);
_wavBase64 = Convert.ToBase64String(ms.ToArray());
_readingFile = false;
StateHasChanged();
```

Without that first call, the "Reading file..." indicator never appears and the button never disables.

**HTTP 413 Error.** Base64 encoding adds 33% overhead. A 37MB WAV becomes roughly 50MB once encoded. The server's default body size limit is 35MB, so the upload gets rejected. The error came back as HTTP 413, but the client then tried to parse the HTML error page as JSON and logged `'M' is an invalid start of a value`, which told me nothing until I looked at the raw response. I then raised the limit to 100MB.

**Zero peaks from the microphone.** This one took the most debugging. Everything was wired up and running, but identifications returned no match. Logs showed 0 peaks found, 0 fingerprints generated. My mic was recording fine, 217,000 samples, but the signal was at 1.75% of full scale. The peak detection threshold is absolute, so a quiet recording produces nothing. The fix was to normalize the audio before analysis:

```csharp
float maxAmp = samples.Max(Math.Abs);
if (maxAmp > 1e-6f)
{
    float scale = 1.0f / maxAmp;
    for (int i = 0; i < samples.Length; i++)
        samples[i] *= scale;
}
```

Laptop microphones recording laptop speakers at moderate volume produce a quiet signal. The threshold needs to be relative to the input, not some fixed reference level.


The algorithm works. A laptop mic picking up a laptop speaker from half a meter away with background noise still produces a correct match. The dominant peaks survives and the fingerprint holds: the whole thing even runs in under a second.

I just wanted to see how it would look to build this from scratch, and I got exactly that.

The source code can be found  [here](https://github.com/thesarfo/hum).
