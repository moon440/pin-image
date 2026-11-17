pin-image
=========

Keeps one image on top of every other window on Windows. Drag it where you want, size
it however you want, it stays there and never gets maximised or snapped to an edge by
the shell.

No installer, no dependencies. PowerShell 5.1 and WPF are already on the machine.

No screenshot. Every capture I took of this running was a picture of someone's actual
desktop, and a README image is a bad place to put that.

X11 and Wayland: read `linux/README.md`. The X11 port is a Tcl script; Wayland cannot
do this at all, and that file says why.

Usage
-----

    powershell -ExecutionPolicy Bypass -File pin_image.ps1 photo.jpg
    powershell -ExecutionPolicy Bypass -File pin_image.ps1 photo.jpg -Width 400
    powershell -ExecutionPolicy Bypass -File pin_image.ps1 photo.jpg -Crop width -Width 600 -NoTaskbar

Run it with no arguments and it reopens the picture you last unpinned, at the size and
spot it was.

Right click the image for the menu: crop mode, sizes, opacity, recent images, unpin.
Drop a file on the image to swap it.

Keys:

| | |
|---|---|
| drag | move |
| wheel | resize, anchored under the cursor |
| `[` `]` | resize by key |
| `T` | topmost on, off |
| `O` | opacity: 100, 85, 65, 45, 28 % |
| `C` | ignore the mouse entirely. `Ctrl+Alt+L` gives the mouse back and it is the only thing that will, so read this line before you press `C` |
| `R` | back to 320 px |
| `Esc` | unpin |

Switches:

```
-Image <file>          what to show
-Width -Height         size in pixels
-Crop square|fit|stretch|width|height
-Radius <n>            rounded corners
-X -Y                  start position
-NoTopmost -NoTaskbar  be less aggressive
-ClickThrough          start out ignoring the mouse
-Forget                do not read or write the saved state
```

`square` is the default: a square window, the picture filling it, the overflow cropped.
`fit` keeps the whole picture and lets the window take the image's aspect ratio.
`stretch` does what it says. `width` and `height` follow the picture's aspect from the
one dimension you give.

Why it does not snap
--------------------

This is the part that took the most tinkering, so it is written down once here.

A borderless layered window does most of it. `WindowStyle = None` leaves the shell no
caption to grab on a drag, and `AllowsTransparency` makes Windows decline to Aero-Snap
the window. `WM_SYSCOMMAND` is hooked to refuse `SC_MAXIMIZE` and `SC_MINIMIZE`, which
is what Win+Up and Win+arrow send. If the size changes anyway without the app asking,
the next frame puts it back. Position is clamped into the work area, so the image can be
moved out of the way but never pushed off screen where you cannot find it.

Dragging is done by hand with mouse capture instead of `Window.DragMove()`. `DragMove`
silently does nothing on layered windows in some WPF builds. Nothing errors, the window
just refuses to move, which is an unpleasant thing to bisect.

`powershell.exe` is DPI unaware, and that matters here: its screen coordinates come back
virtualised, and mixing them with WPF's DIP coordinates made the window drift and grow a
few pixels every launch until `SetProcessDpiAwarenessContext` was called before any
window existed.

Desktop shortcut
----------------

    powershell -File make_shortcut.ps1              # Pin Image on the Desktop
    powershell -File make_shortcut.ps1 -AtStartup   # and start it at login

It writes a small `.vbs` beside the script and points the shortcut at it, because every
other way of starting PowerShell flashes a console window first. Then drag an image file
onto the shortcut to pin it.

Compiling it
------------

There is no build step, which is the point: the script runs on what Windows already has.
If you want a binary anyway, port the ~450 lines of WPF to C# (it is nearly the same code)
and use the compiler that ships with the .NET Framework, no SDK and no Visual Studio:

    %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /out:pin.exe pin.cs

State
-----

`%LOCALAPPDATA%\pinimage.json`, one line: image path, size, position, crop mode, radius,
opacity, the last eight images. `-Forget` skips reading and writing it. Delete the file to
start clean.

Not implemented
---------------

- more than one image at a time. Would need one runspace per window, or a rewrite
- snapping to a corner on a key press
- a tray icon
- surviving a resolution change while the monitor is switched off

Testing
-------

Nothing here is a test suite. Two things were checked, and what they cannot tell you:

- `pin_image.ps1` was run on Windows 11 while real mouse input was injected at it:
  dragged, resized with the wheel, swapped by dropping a file on it, closed with Esc.
- The Tk port was never executed. It was only parsed by `linux/check_tcl.py`, and that
  checker was first proven against five deliberately broken files (`linux/selfcheck_tcl.py`).
  Syntax clean does not mean the wheel feels right or that `convert` handles your file.

License
-------

GPL v3, see `LICENSE`.
