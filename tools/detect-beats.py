#!/usr/bin/env python
# Lightweight onset/beat detector (numpy only -- no librosa).
# Reads a mono 16-bit PCM WAV and prints space-separated onset times (seconds) to stdout.
# Used by make-mg.ps1 -Pattern beatpulse to place visual flashes ON the beat (音ハメ).
#
# Usage: py tools/detect-beats.py <mono.wav> [min_gap_sec] [sensitivity]
import sys, wave
import numpy as np

path = sys.argv[1]
min_gap = float(sys.argv[2]) if len(sys.argv) > 2 else 0.28      # min seconds between hits
sens    = float(sys.argv[3]) if len(sys.argv) > 3 else 1.3       # threshold = mean + sens*std

w = wave.open(path, 'rb')
sr, n, ch = w.getframerate(), w.getnframes(), w.getnchannels()
a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32)
w.close()
if ch > 1:
    a = a.reshape(-1, ch).mean(axis=1)
peak = np.abs(a).max()
if peak > 0:
    a /= peak

hop = 512
nf = len(a) // hop
if nf < 4:
    print("")
    sys.exit(0)
# short-time RMS energy envelope
e = np.sqrt(np.array([np.mean(a[i*hop:(i+1)*hop]**2) for i in range(nf)]) + 1e-12)
# spectral-flux-like onset = positive energy increase
d = np.diff(e, prepend=e[:1])
d[d < 0] = 0.0
if d.max() > 0:
    d /= d.max()
thr = d.mean() + sens * d.std()

times, last = [], -10.0
for i, val in enumerate(d):
    t = i * hop / sr
    if val > thr and (t - last) > min_gap:
        times.append(round(t, 3))
        last = t
print(' '.join(str(t) for t in times))
