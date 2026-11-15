#!/usr/bin/env python3
"""Write a raw 16-bit LE stereo 44.1 kHz 1 kHz sine (raop_play input format).
usage: make_fixture.py <out> [seconds]"""
import sys
import numpy as np

secs = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
t = np.arange(int(44100 * secs)) / 44100
s = (0.5 * 32767 * np.sin(2 * np.pi * 1000 * t)).astype("<i2")
np.column_stack((s, s)).tofile(sys.argv[1])
