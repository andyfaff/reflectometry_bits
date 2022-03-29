fileevalglob $cfPath(commands)/commands_common.tcl

namespace eval motor {
# is_homing_list = comma separated list of motors which are safe to send "home"
  variable is_homing_list ""
}

namespace eval beam {
  command attenuator {text=in,out,osc pos} {
    switch $pos {
      "in" {
        bat send oscd=0
      }
      "out" {
        bat send oscd=-1
      }
      "osc" {
        bat send oscd=1
      }
      default {
        return -code error "ERROR: valid values are in, out, osc"
      }
    }
  }
}
::beam::attenuator -addfb text BeamAttenuator

namespace eval exp_mode {
  variable valid_modes
  #guide element for a specific mode
  variable guide_for_mode
  variable c1ht_pos
  #0=polarisation
  #1=mt
  #2=focussing
  #3=DB
  #4=Single
  variable c1ht_pos
  set valid_modes [list SB DB FOC MT POL POLANAL]
  set c1ht_pos [list 1057 806.7 557.1 320 68.9 68.9]
  #need to change all softzero's
  command set_mode "text=[join $valid_modes ,] arg " {
    global ::exp_mode::valid_modes
    if {[lsearch $::exp_mode::valid_modes $arg] == -1} {
      Clientput "Mode is: $::exp_mode::valid_modes - (POL, POLANAL, MT, FOC, DB, SB)"
      return -code error "Mode is: $::exp_mode::valid_modes - (polarisation, polarisation and analysis, mt,focussing,DB,single)"
    } else {
      if { [catch {::exp_mode::set_guide_element $arg} errMsg] } {
        Clientput $errMsg
        return -code error $errMsg
      }
      mode $arg
    }
    omega -1
    twotheta -1
    return -code ok
  }


  proc ::exp_mode::omega_2theta { arg1 arg2 {s1vg 0} {s2vg 0} {s3vg 0} {s4vg 0}} {

  #need to set omega first.  This is because
  #for Single bounce the twotheta positions depend on the angle of incidence
  #   whenever omega_2theta is called, or the mode is changed, the slits should close
  #   this is to save the detector from being overloaded.
  #   the following line does the job.  However, it is duplicated when the mode is set in
  #   set_omega, so it is commented out for now.

    omega $arg1
    twotheta $arg2
    if {![string is double $arg1] || ![string is double $arg2]} {
      return -code error "omega  and two theta should be a proper number"
    }

    statemon start om2th

    if {![string is double $s1vg] || ![string is double $s2vg] || ![string is double $s3vg] || ![string is double $s4vg]} {
      drive ss1u 0 ss1d 0 ss2d 0 ss3u 0 ss4d 0 ss2u 0 ss3d 0 ss4u 0
      return -code error "ERROR: all the slit openings need to be numbers"
    }
    # request fast shutter to close here
    set tempstr [SplitReply [mc1 send MG FSWHAT]]
    broadcast "Fast Shutter:$tempstr"
    drive fs_shutter_request 0

    if {[catch {
      drive ss1u [expr 0.5 * $s1vg] ss1d [expr -0.5 * $s1vg] ss2d [expr -0.5 * $s2vg] ss3u [expr 0.5 * $s3vg] ss4d [expr -0.5*$s4vg] ss2u [expr 0.5 * $s2vg] ss3d [expr -0.5 * $s3vg] ss4u [expr 0.5 * $s4vg]
      ::exp_mode::set_omega $arg1
      ::exp_mode::set_two_theta $arg2
    } errMsg ] } {
      omega -1
      twotheta -1
      drive ss1u 0 ss1d 0 ss2u 0 ss3d 0 ss4u 0 ss2d 0 ss3u 0 ss4d 0
      broadcast ERROR: omega_2theta command did not complete correctly
      broadcast $errMsg

      # request fast shutter to open here
      drive fs_shutter_request 1

      return -code error $errMsg
    }

    # request fast shutter to open here.
    drive fs_shutter_request 1

    statemon stop om2th

    return -code ok
  }
}
publish ::exp_mode::omega_2theta user

##
# @brief Drive c1ht and set guide_element parameter
#
# @param arg is the user mode
proc ::exp_mode::set_guide_element { arg } {
  global ::exp_mode::c1ht_pos
  global ::exp_mode::valid_modes

  #    drive ss1u 0 ss1d 0 ss2d 0 ss3u 0 ss4d 0
  #    drive ss2u 0 ss3d 0 ss4u 0

  # if you're going to single bounce you're probably going from DB (with large slits), so shut them
  set expmode [SplitReply [mode]]
  if {$expmode ne $arg} {
    drive ss1u 0 ss1d 0 ss2d 0 ss3u 0 ss4d 0 ss2u 0 ss3d 0 ss4u 0
  }

  if {[lsearch $::exp_mode::valid_modes $arg] == -1} {
    Clientput "Mode is: $::exp_mode::valid_modes - (polarisation, polarisation and analysis, mt, focussing, DB, single)"
    return -code error "Mode is: $::exp_mode::valid_modes - (polarisation,polarisation and analysis, mt, focussing, DB, single)"
  }

  if {[catch {::exp_mode::checkMotionAndDrive c1ht [lindex $c1ht_pos [lsearch $::exp_mode::valid_modes $arg]]} errMsg]} {
    return -code error $errMsg
  } else {
    guide_element $arg
    return -code ok
  }
}

proc ::exp_mode::set_omega { arg } {
  set expmode [SplitReply [mode]]
  if {[lsearch $::exp_mode::valid_modes $expmode] == -1} {
    Clientput "Please set the mode first"
    return -code error "Please set the mode first"
  }

  #  if {$arg<0} {
  #    return -code error "omega must be greater than 0"
  #  }
  #the modes is set to ensure that the right guide element is in place
  #someone may have changed it by hand.  DO NOT REMOVE THIS FUNCTIONALITY
  #as it also has the effect of closing all the ssXvg gaps for safety.

  if {[catch {::exp_mode::set_guide_element $expmode} errMsg]} {
  #make sure the guide element is moved.
    return -code error $errMsg
  }
  #position in radians
  set argrad [deg2rad $arg]

  switch $expmode {
    SB {
    #checked ARJN on 081231
      drive st4vt 0
      if {[catch {::exp_mode::checkMotionAndDrive m1ro [expr -1.*$arg/2.]} errMsg]} {return -code error $errMsg}

      set d1 [expr [SplitReply [slit3_distance]] - [SplitReply [guide1_distance]]]
      set d2 [expr [SplitReply [sample_distance]] - [SplitReply [guide1_distance]]]
      set h1 [expr -1. * $d1 * tan($argrad)]
      set h2 [expr -1. * $d2 * tan($argrad)]

      if {[catch {isszst4vtsafe sz $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st3vt $h1
        checkMotion sz $h2
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st3vt $h1 sz $h2
    }
    DB {
    #checked ARJN on 081231
      set temp [deg2rad 2.4]
      #offset is the vertical drop from the beam centre onto the middle of the second compound mirror
      # each compound mirror is 600mm long
      # therefore the distance between the place where the beam hits the centre of both mirrors is
      # 2 * 300 * cos(1.2) = 599.868

      # guide2_distance is therefore the distance from the midpoint of the second compound mirror to chopper disc 1.
      # i.e. sample-> midpoint of compound mirror2 = 1546 + 300*cos3.6 = 1845.4

      set offset [expr 599.868*sin($temp)]
      #fixed angle
      set arg 4.8
      set argrad [deg2rad $arg]

      set d1 [expr [SplitReply [slit3_distance]] - [SplitReply [guide2_distance]]]
      set d2 [expr [SplitReply [sample_distance]] - [SplitReply [guide2_distance]]]
      set h1 [expr -1. * $d1 * tan($argrad) - $offset]
      set h2 [expr -1. * $d2 * tan($argrad) - $offset]

      if { [catch {isszst4vtsafe sz $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st3vt $h1
        checkMotion sz $h2
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st3vt $h1 sz $h2
    }
    FOC {
      if { [catch {
        checkMotion sth $arg
        checkMotion st3vt 0
      } errMsg ] } {
        return -code error $errMsg
      }
      run sth $arg st3vt 0
    }
    MT {
      if { [catch {
        checkMotion sth $arg
        checkMotion st3vt 0
      } errMsg ] } {
        return -code error $errMsg
      }
      run sth $arg st3vt 0
    }
    POL {
      if { [catch {
        checkMotion sth $arg
        checkMotion st3vt 0
      } errMsg ] } {
        return -code error $errMsg
      }
      run sth $arg st3vt 0
    }
    POLANAL {
      if { [catch {
        checkMotion sth $arg
        checkMotion st3vt 0
      } errMsg ] } {
        return -code error $errMsg
      }
      run sth $arg st3vt 0
    }
    default {
      return -code error "omega driving not specified for that mode"
    }
  }

  return -code ok
}
publish ::exp_mode::set_omega user

proc ::exp_mode::set_two_theta { arg } {
  set expmode [SplitReply [mode]]
  set expomega [SplitReply [omega]]

  if {[lsearch $::exp_mode::valid_modes $expmode] == -1} {
    return -code error "please set the mode and omega first"
  }
  if {$expomega == "NaN"} {
    return -code error "please set omega first"
  }
  #  if {$arg<0} {
  #    return -code error "two_theta is less than 0"
  #  }

  #2theta position in radians
  set argrad [deg2rad $arg]
  set omegarad [deg2rad $expomega]

  Clientput $expmode
  switch $expmode {
    SB {
    #checked ARJN 081231
      set d1 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [guide1_distance]]]
      #distance if 2theta is zero, i.e. the direct beam
      set h1 [expr -1. * $d2 * tan($omegarad)]
      set b  [expr $d1 / cos($omegarad)]
      set c  [expr $d1 / cos($argrad-$omegarad)]
      #cosine rule
      set h2 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]

      set d3 [expr [SplitReply [dy]]]
      set d4 [expr [SplitReply [dy]] + [SplitReply [sample_distance]] - [SplitReply [guide1_distance]]]
      set h3 [expr -1. * $d4 * tan($omegarad)]
      set b  [expr $d3 / cos($omegarad)]
      set c  [expr $d3 / cos($argrad-$omegarad)]
      set h4 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      if { [catch {isszst4vtsafe st4vt [expr $h2 + $h1]} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt [expr $h2 + $h1]
        checkMotion dz [expr $h3 + $h4]
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st4vt [expr $h2 + $h1] dz [expr $h3 + $h4]
    }
    DB {
    #checked ARJN 081231
      set temp [deg2rad 2.4]
      set offset [expr 599.868*sin($temp)]

      set expomega 4.8
      set omegarad [deg2rad $expomega]

      set d1 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [guide2_distance]]]
      set h1 [expr -1. * $d2 * tan($omegarad) - $offset]
      set b  [expr $d1 / cos($omegarad)]
      set c  [expr $d1 / cos($argrad-$omegarad)]
      set h2 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]

      set d3 [expr [SplitReply [dy]]]
      set d4 [expr [SplitReply [dy]] + [SplitReply [sample_distance]] - [SplitReply [guide2_distance]]]
      set h3 [expr -1. * $d4 * tan($omegarad) - $offset]
      set b  [expr $d3 / cos($omegarad)]
      set c  [expr $d3 / cos($argrad-$omegarad)]
      set h4 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      if { [catch {isszst4vtsafe st4vt [expr $h2 + $h1]} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt [expr $h2 + $h1]
        checkMotion dz [expr $h3 + $h4]
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st4vt [expr $h2 + $h1] dz [expr $h3 + $h4]
    }
    FOC {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]
      if { [catch {isszst4vtsafe st4vt $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt $h2
        checkMotion dz $h1
      }  errMsg]} {
        return -code error $errMsg
      }
      drive st4vt $h2 dz $h1
    }
    MT {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]
      if { [catch {isszst4vtsafe st4vt $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt $h2
        checkMotion dz $h1
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st4vt $h2 dz $h1
    }
    POL {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]
      if { [catch {isszst4vtsafe st4vt $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt $h2
        checkMotion dz $h1
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st4vt $h2 dz $h1 analz -200 analtilt 0
    }
    POLANAL {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d3 [expr [SplitReply [anal_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]
      set h3 [expr $d3 * tan($argrad)]
      set ang1 [expr $arg]
      if { [catch {isszst4vtsafe st4vt $h2} errMsg]} {return -code error $errMsg}
      if  { [catch {
        checkMotion st4vt $h2
        checkMotion dz $h1
        checkMotion analz $h3
        checkMotion analtilt $ang1
      }  errMsg ] } {
        return -code error $errMsg
      }
      drive st4vt $h2 dz $h1 analz $h3 analtilt $ang1
    }
    default {
      return -code error "two_theta not defined for that mode: $expmode"
    }
  }
  return -code ok
}
publish ::exp_mode::set_two_theta user

proc ::exp_mode::checkMotion { scan_variable target } {
  set motor_list [sicslist type motor]

  if {[lsearch $motor_list $scan_variable]==-1} {
    return -code error "you tried to drive a motor that doesn't exist"
  }
  set softzero [SplitReply [$scan_variable softzero]]
  set absoluteTarget [expr $softzero+$target]

  if { [catch {isszst4vtsafe $scan_variable $target} errMsg]} {return -code error $errMsg}

  if {[catch {
    ::scan::check_limit $scan_variable hardlowerlim $absoluteTarget
    ::scan::check_limit $scan_variable hardupperlim $absoluteTarget
    ::scan::check_limit $scan_variable softlowerlim $target
    ::scan::check_limit $scan_variable softupperlim $target
  }]} {
    return -code error $::errorInfo
  }
  return -code ok
}
publish ::exp_mode::checkMotion user

proc ::exp_mode::checkMotionAndDrive { scan_variable target } {
  set motor_list [sicslist type motor]
  #lappend motorlist [sicslist type configurablevirtualmotor]

  set precision [SplitReply [$scan_variable precision]]

  if {[catch {
    ::exp_mode::checkMotion $scan_variable $target
  }]} {
    return -code error $::errorInfo
  } else {
    drive $scan_variable $target
    set position [SplitReply [$scan_variable]]
    if {[expr [expr $position-$target] > abs($precision)]} {
      return -code error "move of: $scan_variable did not reach required precision"
    } else {
      Clientput "New $scan_variable Position: $position"
      Clientput "Driving finished successfully"
    }
    return -code ok
  }
}
publish ::exp_mode::checkMotionAndDrive user

proc ::exp_mode::isszst4vtsafe { scan_variable target } {
  set szsoftzero [SplitReply [sz softzero]]
  set st4vtsoftzero [SplitReply [st4vt softzero]]
  set szPosition [expr [SplitReply [sz]] + $szsoftzero]
  set st4vtPosition [expr [SplitReply [st4vt]] + $st4vtsoftzero]

  set szHardUpperLim [SplitReply [sz hardupperlim]]

  if { [string equal $scan_variable "sz"] || [string equal $scan_variable "st4vt"]} {
    switch $scan_variable {
      sz {
        set szPosition [expr $target + $szsoftzero]
      }
      st4vt {
        set st4vtPosition [expr $target + $st4vtsoftzero]
      }
    }
    set distance [expr $szHardUpperLim - $szPosition + $st4vtPosition ]
    if { $distance < 98. } {
      return -code error "You would have a collision between st4vt and sz if you tried to move $scan_variable to $target"
    }
  }
  return -code ok
}

publish ::exp_mode::isszst4vtsafe user


proc ::exp_mode::deg2rad { arg } {
  set pi 3.1415926535897931
  return [expr $pi * $arg / 180.]
}

proc ::exp_mode::rad2deg { arg } {
  set pi 3.1415926535897931
  return [expr 180. * $arg / $pi]
}


proc ::exp_mode::nomega_2theta { arg1 arg2 {s1vg 0} {s2vg 0} {s3vg 0} {s4vg 0}} {

  # need to set omega first.  This is because
  # for Single bounce the twotheta positions depend on the angle of incidence
  # whenever omega_2theta is called, or the mode is changed, the slits should close
  # this is to save the detector from being overloaded.
  # the following line does the job.  However, it is duplicated when the mode is set in
  # set_omega, so it is commented out for now.

  omega $arg1
  twotheta $arg2
  if {![string is double $arg1] || ![string is double $arg2]} {
    return -code error "omega  and two theta should be a proper number"
  }

  statemon start om2th

  if {![string is double $s1vg] || ![string is double $s2vg] || ![string is double $s3vg] || ![string is double $s4vg]} {
    drive ss1u 0 ss1d 0 ss2d 0 ss3u 0 ss4d 0 ss2u 0 ss3d 0 ss4u 0
    return -code error "ERROR: all the slit openings need to be numbers"
  }

  # request fast shutter to close here
  set tempstr [SplitReply [mc1 send MG FSWHAT]]
  broadcast "Fast Shutter:$tempstr"
  drive fs_shutter_request 0

  # first step is to change the collimation guide according
  # to the mode
  set expmode [SplitReply [mode]]
  if {[lsearch $::exp_mode::valid_modes $expmode] == -1} {
    Clientput "Please set the mode first"
    drive ss1u 0 ss1d 0 ss2u 0 ss2d 0 ss3u 0 ss3d 0 ss4d 0 ss4u 0
    return -code error "Please set the mode first"
  }

  if {[catch {::exp_mode::set_guide_element $expmode} errMsg]} {
    # make sure the guide element is moved.
    return -code error $errMsg
  }

  if {[catch {
    set d1 [::exp_mode::get_omega $arg1]
    set d2 [::exp_mode::get_two_theta $arg2]
    Clientput $d1 $d2
    set d3 "$d1 $d2"
    drive {*}$d3
  
    drive ss1u [expr 0.5 * $s1vg] ss1d [expr -0.5 * $s1vg] ss2d [expr -0.5 * $s2vg] ss3u [expr 0.5 * $s3vg] ss4d [expr -0.5*$s4vg] ss2u [expr 0.5 * $s2vg] ss3d [expr -0.5 * $s3vg] ss4u [expr 0.5 * $s4vg]
  } errMsg ] } {
    omega -1
    twotheta -1
    drive ss1u 0 ss1d 0 ss2u 0 ss3d 0 ss4u 0 ss2d 0 ss3u 0 ss4d 0
    broadcast ERROR: omega_2theta command did not complete correctly
    broadcast $errMsg

    # request fast shutter to open here
    drive fs_shutter_request 1

    return -code error $errMsg
  }

  # request fast shutter to open here.
  drive fs_shutter_request 1

  statemon stop om2th

  return -code ok
}
publish ::exp_mode::nomega_2theta user


proc ::exp_mode::get_omega { arg } {
  # position in radians
  set argrad [deg2rad $arg]
  set expmode [SplitReply [mode]]

  switch $expmode {
    SB {
    #checked ARJN on 081231
      set d1 [expr [SplitReply [slit3_distance]] - [SplitReply [guide1_distance]]]
      set d2 [expr [SplitReply [sample_distance]] - [SplitReply [guide1_distance]]]
      set h1 [expr -1. * $d1 * tan($argrad)]
      set h2 [expr -1. * $d2 * tan($argrad)]
      set m1roh [expr -1.*$arg/2.]

      checkMotion st3vt $h1
      checkMotion sz $h2
      checkmotion m1ro $m1roh
      return "st3vt $h1 sz $h2 m1ro $m1roh"
    }
    DB {
    #checked ARJN on 081231
      set temp [deg2rad 2.4]
      # offset is the vertical drop from the beam centre onto the middle of the second compound mirror
      # each compound mirror is 600mm long
      # therefore the distance between the place where the beam hits the centre of both mirrors is
      # 2 * 300 * cos(1.2) = 599.868

      # guide2_distance is therefore the distance from the midpoint of the second compound mirror to chopper disc 1.
      # i.e. sample-> midpoint of compound mirror2 = 1546 + 300*cos3.6 = 1845.4

      set offset [expr 599.868*sin($temp)]
      # fixed angle
      set arg 4.8
      set argrad [deg2rad $arg]

      set d1 [expr [SplitReply [slit3_distance]] - [SplitReply [guide2_distance]]]
      set d2 [expr [SplitReply [sample_distance]] - [SplitReply [guide2_distance]]]
      set h1 [expr -1. * $d1 * tan($argrad) - $offset]
      set h2 [expr -1. * $d2 * tan($argrad) - $offset]

      checkMotion st3vt $h1
      checkMotion sz $h2
      return "st3vt $h1 sz $h2"
    }
    FOC {
      checkMotion sth $arg
      checkMotion st3vt 0
      return "sth $arg st3vt 0"
    }
    MT {
      checkMotion sth $arg
      checkMotion st3vt 0
      return "sth $arg st3vt 0"
    }
    POL {
      checkMotion sth $arg
      checkMotion st3vt 0
      return "sth $arg st3vt 0"
    }
    POLANAL {
      checkMotion sth $arg
      checkMotion st3vt 0
      return "sth $arg st3vt 0"
    }
    default {
      return -code error "omega driving not specified for that mode"
    }
  }

  return -code ok
}
publish ::exp_mode::get_omega user


proc ::exp_mode::get_two_theta { arg } {
  set expmode [SplitReply [mode]]
  set expomega [SplitReply [omega]]

  if {[lsearch $::exp_mode::valid_modes $expmode] == -1} {
    return -code error "please set the mode and omega first"
  }
  if {$expomega == "NaN"} {
    return -code error "please set omega first"
  }

  #2theta position in radians
  set argrad [deg2rad $arg]
  set omegarad [deg2rad $expomega]

  Clientput $expmode
  switch $expmode {
    SB {
    # checked ARJN 081231
      set d1 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [guide1_distance]]]
      #distance if 2theta is zero, i.e. the direct beam
      set h1 [expr -1. * $d2 * tan($omegarad)]
      set b  [expr $d1 / cos($omegarad)]
      set c  [expr $d1 / cos($argrad-$omegarad)]
      # cosine rule
      set h2 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      set st4vt_overall [expr $h2 + $h1]
      
      set d3 [expr [SplitReply [dy]]]
      set d4 [expr [SplitReply [dy]] + [SplitReply [sample_distance]] - [SplitReply [guide1_distance]]]
      set h3 [expr -1. * $d4 * tan($omegarad)]
      set b  [expr $d3 / cos($omegarad)]
      set c  [expr $d3 / cos($argrad-$omegarad)]
      set h4 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      set dz_overall [expr $h3 + $h4]
	  
      checkMotion st4vt $st4vt_overall
      checkMotion dz $dz_overall
      
      return "st4vt $st4vt_overall dz $dz_overall"
    }
    DB {
    # checked ARJN 081231
      set temp [deg2rad 2.4]
      set offset [expr 599.868*sin($temp)]

      set expomega 4.8
      set omegarad [deg2rad $expomega]

      set d1 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [guide2_distance]]]
      set h1 [expr -1. * $d2 * tan($omegarad) - $offset]
      set b  [expr $d1 / cos($omegarad)]
      set c  [expr $d1 / cos($argrad-$omegarad)]
      set h2 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      set st4vt_overall [expr $h2 + $h1]


      set d3 [expr [SplitReply [dy]]]
      set d4 [expr [SplitReply [dy]] + [SplitReply [sample_distance]] - [SplitReply [guide2_distance]]]
      set h3 [expr -1. * $d4 * tan($omegarad) - $offset]
      set b  [expr $d3 / cos($omegarad)]
      set c  [expr $d3 / cos($argrad-$omegarad)]
      set h4 [expr sqrt(pow($b,2) + pow($c,2) - 2*$b*$c*cos($argrad))]
      set dz_overall [expr $h3 + $h4]

      checkMotion st4vt $st4vt_overall
      checkMotion dz $dz_overall
      
      return "st4vt $st4vt_overall dz $dz_overall"
    }
    FOC {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]

      checkMotion st4vt $h2
      checkMotion dz $h1
      return "st4vt $h2 dz $h1"
    }
    MT {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]

      checkMotion st4vt $h2
      checkMotion dz $h1
      return "st4vt $h2 dz $h1"
    }
    POL {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]

      checkMotion st4vt $h2
      checkMotion dz $h1
      return "st4vt $h2 dz $h1 analz -200 analtilt 0"
    }
    POLANAL {
      set d1 [SplitReply [dy]]
      set d2 [expr [SplitReply [slit4_distance]] - [SplitReply [sample_distance]]]
      set d3 [expr [SplitReply [anal_distance]] - [SplitReply [sample_distance]]]
      set h1 [expr $d1 * tan($argrad)]
      set h2 [expr $d2 * tan($argrad)]
      set h3 [expr $d3 * tan($argrad)]
      set ang1 [expr $arg]

      checkMotion st4vt $h2
      checkMotion dz $h1
      checkMotion analz $h3
      checkMotion analtilt $ang1
      return "st4vt $h2 dz $h1 analz $h3 analtilt $ang1"
    }
    default {
      return -code error "two_theta not defined for that mode: $expmode"
    }
  }
  return -code ok
}
publish ::exp_mode::get_two_theta user

#
# @brief Commands initialisation procedure
proc ::commands::isc_initialize {} {
  ::commands::ic_initialize
}
