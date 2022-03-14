#pragma rtGlobals=3		// Use modern global access method and strict wave access.

function start_ramp(start, finish, duration, stepsize, [wait])
variable start, finish, duration, stepsize, wait
variable MAX_RAMP_RATE = 4e-3

if(finish > 10 || finish < 0)
	print "DONT SET PRESSURE> 10"
	return 1
endif
if(start > 10 || start < 0)
	print "DONT SET PRESSURE> 10"
	return 1
endif
variable ramp_rate
ramp_rate = (finish - start) / duration 

if(abs(ramp_rate) > MAX_RAMP_RATE)
	print "YOU WILL EXCEED RAMP RATE"
	return 1
endif

string savedDataFolder = GetDataFolder(1)	// Save
SetDataFolder root:

variable pnts = abs((finish-start)/stepsize) + 1

make/n=(pnts)/o/d rampy
if (finish < start)
	stepsize *= -1
endif
rampy = start + p * stepsize

// batch mode won't continue if there is anything in the statemon
// showstatemon()
if (paramisdefault(wait))
    wait=1
endif
if(wait)
    appendstatemon("mr_rampy")
endif

variable now = datetime
setscale/I x, now, now + duration, rampy
ctrlnamedbackground mr_rampy, proc=mr_rampy_func, start, period=120

SetDataFolder savedDataFolder
end

function stop_ramp()
ctrlnamedbackground mr_rampy, kill=1
statemonclear("mr_rampy")
end

Function mr_rampy_func(s)
	STRUCT WMBackgroundStruct &s
	variable now = datetime
	wave rampy = root:rampy
	variable row = x2pnt(rampy, now)
	if (row >= numpnts(rampy) - 1)
		rampy_command(rampy[numpnts(rampy) - 1])
		statemonclear("mr_rampy")
		print time(), "Ramp complete"
		return 1
	else
		rampy_command(rampy[row])
	endif
	return 0
End

Function rampy_command(val)
variable val
string cmd = ""
sprintf cmd, "hset /sample/power_supply/volts %f", val
// print time(), cmd
sics_cmd_interest(cmd)
End