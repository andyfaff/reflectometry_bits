#!/usr/bin/python
import sys
import h5py


if __name__ == "__main__":
    files = sys.argv[1:]
    files.extend(sys.stdin.readlines())
    for file in files:
        file = file.strip()

        with h5py.File(file, 'r') as f:
            f['/entry1/instrument/parameters/y_pixels_per_mm'][0] = 0.321
