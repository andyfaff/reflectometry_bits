#!/usr/bin/python

from __future__ import print_function, division

import time
import datetime
import glob
import os.path

import numpy as np
import matplotlib.pyplot as plt

fig = plt.figure()
ax1 = fig.add_subplot(121)
ax2 = fig.add_subplot(122)

#plt.axis()# [0, 1000, 0, 1])
plt.ion()
plt.show()
ax1.set_ylim(270, 450)

logdir = r"V:\data\current\2015\control.t1s3"

lastline = ''
history_time = []
history_temp = []

label_avg = fig.text(0.05, 0.92, "")
label_curr = fig.text(0.05, 0.95, "")

while True:
    logfiles = sorted(glob.glob(os.path.join(logdir, '*.log')))
    tlogfile = logfiles[-1]
    
    with open(tlogfile) as fh:
        lines = fh.readlines()
        line = lines[-1]
        if lastline != line:
            lastline = line
            
            timestamp, temperature = line.split()
            temp_cel = float(temperature)
            print("%s\t%s\t%5.1f" % (timestamp, temperature, temp_cel))

            ts = datetime.datetime.strptime(timestamp, '%H:%M:%S')
            tst = ts.time()
            secs = tst.hour * 3600 + tst.minute * 60 + tst.second

            history_temp.append(temp_cel)
            history_time.append(secs)
            
            ax1.scatter(secs/3600, temp_cel)
            #plt.draw()
            ax2.scatter(secs/3600, temp_cel)
            tmin = (secs - 1800)/3600
            tmax = secs/3600
            ax2.set_xlim(tmin, tmax)
            
            temp_range = [T for t, T in zip(history_time, history_temp) if t > secs - 1800]
            temp_min = min(temp_range)
            temp_max = max(temp_range)
            #if temp_max - temp_min < 1:
            #    temp_min = temp_cel - 0.5
            #    temp_max = temp_cel + 0.5
            #else:
            temp_min -= 0.5
            temp_max += 0.5
              
            ax2.set_ylim(temp_min, temp_max)
            
            temp_range = [T for t, T in zip(history_time, history_temp) if t > secs - 300]
            t_roll = sum(temp_range) / len(temp_range)
            
            label_avg.set_text("5min avg: %5.1f" % t_roll)
            label_curr.set_text("Latest: %5.1f" % temp_cel)

            plt.pause(0.05)
                    
    plt.pause(1.0)
