#!/usr/bin/env wish
# pin.tcl - keep an image on top of every window, X11.
#
#   wish pin.tcl photo.jpg
#   wish pin.tcl photo.jpg -size 500 -pos 120 80 -mode fit
#
# Same shape as the Windows version: one borderless window, above everything,
# drag it anywhere, wheel to resize, right click for options, Esc to unpin.
#
# Needs wish (Tk) and ImageMagick's convert. Nothing to compile, nothing to
# install beyond those two.

package require Tk

if {[info exists env(XDG_SESSION_TYPE)] && $env(XDG_SESSION_TYPE) eq "wayland"} {
  puts stderr "pin: this is Wayland. Ordinary clients cannot raise themselves above
       other windows there, so an always-on-top image needs a layer-shell client.
       On X11 it works: switch the session, or use the feh/xprop route."
  exit 1
}

set opts(file)  ""
set opts(size)  320
set opts(x)     -1
set opts(y)     -1
set opts(mode)  square        ;# square | fit | stretch
set opts(alpha) 1.0
set opts(topmost) 1
set opts(state) [file join /tmp pin-[pid].state]
if {[info exists env(XDG_STATE_HOME)]} {
  set opts(state) [file join $env(XDG_STATE_HOME) pin.state]
} elseif {[info exists env(HOME)]} {
  set opts(state) [file join $env(HOME) .local state pin.state]
  catch {file mkdir [file dirname $opts(state)]}
}

proc parse_args {argv} {
  global opts
  set i 0
  while {$i < [llength $argv]} {
    set a [lindex $argv $i]
    switch -- $a {
      -size  { incr i; set opts(size) [lindex $argv $i] }
      -pos   { incr i; set opts(x) [lindex $argv $i]
               incr i; set opts(y) [lindex $argv $i] }
      -mode  { incr i; set opts(mode) [lindex $argv $i] }
      -alpha { incr i; set opts(alpha) [lindex $argv $i] }
      -state { incr i; set opts(state) [lindex $argv $i] }
      default { if {![string match -* $a]} { set opts(file) $a } }
    }
    incr i
  }
}

# arguments win over whatever was saved last time
proc load_state {} {
  global opts argv
  set given [list]
  foreach a $argv { if {[string match -* $a]} { lappend given [string range $a 1 end] } }
  if {![file readable $opts(state)]} return
  set f [open $opts(state) r]
  while {[gets $f line] >= 0} {
    if {![regexp {^(\w+)=(.*)$} $line -> k v]} continue
    if {$k in $given} continue
    if {$k eq "file"} {
      if {$opts(file) eq "" && [file readable $v]} { set opts(file) $v }
    } elseif {[info exists opts($k)]} {
      set opts($k) $v
    }
  }
  close $f
}

proc save_state {} {
  global opts
  if {[catch {open $opts(state) w} f]} return
  puts $f "file=$opts(file)"
  puts $f "size=$opts(size)"
  puts $f "mode=$opts(mode)"
  puts $f "alpha=$opts(alpha)"
  puts $f "topmost=$opts(topmost)"
  if {[regexp {^[0-9]+x[0-9]+\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry .] -> x y]} {
    puts $f "x=$x"
    puts $f "y=$y"
  }
  close $f
}

# Tk photo images cannot be rescaled in place, so ImageMagick renders the exact
# crop we want into a temp file. Only runs once the wheel settles.
proc render {} {
  global opts img cv
  if {$opts(file) eq "" || ![file readable $opts(file)]} return

  set s [expr {int($opts(size))}]
  if {$s < 24}   { set s 24 }
  if {$s > 4000} { set s 4000 }

  switch -- $opts(mode) {
    square  { set geom "${s}x${s}^"; set extra [list -gravity center -extent "${s}x${s}"] }
    fit     { set geom "${s}x${s}";  set extra [list] }
    default { set geom "${s}x${s}!"; set extra [list] }
  }

  set tmp [file join /tmp pin-[pid].png]
  set cmd [list convert $opts(file) -auto-orient -resize $geom {*}$extra $tmp]
  if {[catch {exec {*}$cmd 2>@ /dev/null} err]} {
    puts stderr "pin: convert failed: $err"
    return
  }
  if {[info exists img]} { image delete $img }
  set img [image create photo -file $tmp]
  file delete -force $tmp

  $cv itemconfigure 1 -image $img
  fit_window
}

proc fit_window {} {
  global opts img cv
  set w [image width $img]
  set h [image height $img]
  if {$opts(x) >= 0 && $opts(y) >= 0} {
    wm geometry . ${w}x${h}+$opts(x)+$opts(y)
  } else {
    wm geometry . ${w}x${h}
  }
  $cv configure -width $w -height $h
  $cv coords 1 [expr {$w/2}] [expr {$h/2}]
}

proc zoom {k} {
  global opts pending
  set opts(size) [expr {int($opts(size) * $k)}]
  if {$pending ne ""} { after cancel $pending }
  set pending [after 90 render_and_keep]
}

proc render_and_keep {} {
  global pending
  set pending ""
  render
  save_state
}

proc keep_inside {} {
  global opts
  set w [winfo width .];  set h [winfo height .]
  set x [winfo rootx .];  set y [winfo rooty .]
  set mw [expr {[winfo screenwidth .]  - $w}]
  set mh [expr {[winfo screenheight .] - $h}]
  set nx [expr {max(0, min($mw, $x))}]
  set ny [expr {max(0, min($mh, $y))}]
  if {$nx != $x || $ny != $y} { wm geometry . +$nx+$ny }
  set opts(x) $nx; set opts(y) $ny
}

# ------------------------------------------------------------------ start up
parse_args $argv
load_state

if {$opts(file) eq "" || ![file readable $opts(file)]} {
  puts stderr "pin: no readable image.  usage: wish pin.tcl photo.jpg \[-size 500\] \[-pos x y\] \[-mode square|fit|stretch\]"
  exit 1
}

wm title . "pinned image"
# no titlebar: the window manager has no caption to grab, so it cannot be
# maximised or half-snapped to an edge, and it stays out of the taskbar too
wm overrideredirect . 1
catch {wm attributes . -topmost $opts(topmost)}
catch {wm attributes . -alpha $opts(alpha)}

canvas .cv -highlightthickness 0 -borderwidth 0 -background gray20
pack .cv -fill both -expand 1
set cv .cv
$cv create image 0 0 -anchor center
set img ""
set pending ""

render

# ------------------------------------------------------------------ input
bind . <ButtonPress-1> {
  set ::dragx [expr {[winfo pointerx .] - [winfo rootx .]}]
  set ::dragy [expr {[winfo pointery .] - [winfo rooty .]}]
}
bind . <B1-Motion> {
  wm geometry . +[expr {[winfo pointerx .] - $::dragx}]+[expr {[winfo pointery .] - $::dragy}]
}
bind . <ButtonRelease-1> { save_state }

# X11 hands the wheel over as buttons 4 and 5
bind . <Button-4> { zoom 1.06 }
bind . <Button-5> { zoom [expr {1.0/1.06}] }

set alphas {1.0 0.85 0.65 0.45 0.28}
menu .m -tearoff 0
.m add command -label "bigger"    -command { zoom 1.15 }
.m add command -label "smaller"   -command { zoom [expr {1/1.15}] }
.m add command -label "reset size" -command { set opts(size) 320; render_and_keep }
.m add separator
foreach mo {square fit stretch} {
  .m add radiobutton -label "crop: $mo" -variable opts(mode) -value $mo -command render_and_keep
}
.m add separator
foreach a $alphas {
  .m add radiobutton -label "[expr {int($a*100)}]% opaque" -variable opts(alpha) -value $a \
    -command "catch {wm attributes . -alpha \$opts(alpha)}; save_state"
}
.m add separator
.m add checkbutton -label "stay on top" -variable opts(topmost) \
  -command "catch {wm attributes . -topmost \$opts(topmost)}; save_state"
.m add command -label "swap image" -command {
  set f [tk_getOpenFile -filetypes {{{Images} {.png .jpg .jpeg .gif .bmp .webp}} {{All} *}}]
  if {$f ne ""} { set opts(file) $f; render; save_state }
}
.m add command -label "unpin" -command { save_state; exit }

bind . <ButtonPress-3> { tk_popup .m %X %Y }
bind . <Escape> { save_state; exit }
bind . <Key-t> {
  set opts(topmost) [expr {!$opts(topmost)}]
  catch {wm attributes . -topmost $opts(topmost)}
  save_state
}
bind . <Configure> { after 120 keep_inside }
wm protocol . WM_DELETE_WINDOW { save_state; exit }
