Linux
=====

`pin.tcl` is the same idea for X11: one borderless window, above everything, drag it
anywhere, wheel to resize, right click for options, Esc to unpin.

    wish pin.tcl photo.jpg
    wish pin.tcl photo.jpg -size 500 -pos 120 80 -mode fit

Needs `wish` (Tk) and ImageMagick's `convert`. Nothing to compile, no SDK, no runtime
download. On Debian or Ubuntu that is:

    sudo apt install tk imagemagick

Why wish and not C
------------------

`overrideredirect` removes the titlebar, so the window manager has no caption to grab:
it cannot be dragged into a snap zone, and there is nothing for a keyboard shortcut to
maximise either. `wm attributes -topmost` and `-alpha` are supported on X11, PNG loads
natively, and the mouse wheel arrives as buttons 4 and 5. That is every behaviour the
Windows version has, in one script, with no build step. C with Xlib would produce a
smaller binary and about three times the code, and would need `libx11-dev` and a
compiler to get there.

The one thing missing
---------------------

Click-through. Telling X to ignore all input for a window is an `XShapeInput` call on
the input region, which no Tcl or Tk binding exposes. If that feature matters, the port
needs libX11 through a C extension, or LuaJIT FFI, and then it is no longer zero-build.
`T` toggles topmost, `O`-style opacity is in the menu, and unpinning with Esc always works.

Wayland
-------

There is no always-on-top for ordinary clients on Wayland. A window cannot raise itself
above another window; that is the compositor's job by design, and it is not a missing
feature that a flag can turn on. The script detects it and says so instead of pretending.
To get a pinned image on Wayland you need a layer-shell client (`gtk-layer-shell`, or a
compositor-specific keybinding), which means GTK and a build step.

What is checked before shipping
------------------------------

No Linux box here, so `pin.tcl` has not been run. What was verified:

    python selfcheck_tcl.py     # the checker detects broken Tcl
    python check_tcl.py pin.tcl # 0 issues: braces, brackets and argument splices balance

That catches syntax-level breakage only. Whether the wheel feels right, whether the
menu geometry behaves, and whether `convert` handles a given file all need a machine
with Tk on it. If something is off, `wish pin.tcl x.png -size 400` and the traceback
will say where.

State
-----

`$XDG_STATE_HOME/pin.state`, falling back to `~/.local/state/pin.state`. Image, size,
crop mode, opacity, topmost and position. Arguments on the command line beat the saved
values, so `pin.tcl other.jpg` does what you typed.
