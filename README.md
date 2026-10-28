# Trigger Arduino Controller (Python + MATLAB)

This package contains:
- `arduino_pulse_ctrl` — Arduino package to upload to an arduino so you can easily control it using a python/matlab interface
- `trigger_control.py` — the original Python controller.
- `ArduinoController.m` — MATLAB class plus `scan_serial_ports()` helper.
- This README — setup and usage for both languages.

## What the controller does

Both versions send newline-terminated text commands at **115200 baud** to a custom Arduino firmware. The commands are taken from the original Python source:

| Method | Command sent | Meaning |
|---|---|---|
| `verify_setup()` | `S` | Ask the device to identify itself |
| `trigger()` | `T` | Send a trigger command |
| `turn_on()` | `O` | Turn output on |
| `turn_off()` | `F` | Turn output off |
| `set_on_time(ms)` | `C;<ms>` | Set on-time in milliseconds |
| `loop(on, off, loops)` | `L;<on>;<off>;<loops>` | Request repeated on/off timing |

The identity check expects exactly: `This is a custom trigger arduino!`

A `loops` value of `-1` is passed through as in the Python implementation and is intended by that implementation to mean indefinite repetition. Confirm that interpretation against your Arduino firmware.

## Hardware and safety notes

- Connect the Arduino to the computer and identify its serial port if automatic scanning does not work.
- Only one program can normally own a serial port at a time. Close Arduino Serial Monitor, MATLAB, Python, or other software that may already have the port open before connecting.
- The scan sends `S` to every available serial port at 115200 baud. Use it only when probing available ports is acceptable; if unsure, connect directly using a known port.
- Commands such as `T`, `O`, and `L` may operate connected hardware. Test with the controlled equipment disconnected or in a safe, approved configuration first. This software does not provide an emergency stop or independently verify hardware state.
- The MATLAB version uses `serialport`, available in modern MATLAB releases (R2019b or later). If `serialport` is unavailable, update MATLAB or adapt the code for your installed release.

---

# Arduino Configurations

The only configuration that has to be pre-set before uploading to the arduino is the digital output pin the trigger comes from

```C++
// This line exists inside of arduino_pulse_ctrl/arduino_pulse_ctrl.ino
// Can be set to whatever pin you want, by default is 10
const int TRIGGER_PIN = 10;
```

# Python version

## 1. Install Python and the dependency

Use Python 3. Install pySerial:

```bash
python -m pip install pyserial
```

Save `trigger_control.py` in your project directory.

## 2. Find the Arduino

Run:

```bash
python trigger_control.py
```

The script scans available serial ports and prints whether it finds the expected identity response. It does not retain a controller object after scanning.

Alternatively, use the module from a separate Python script:

```python
from trigger_control import scan_serial_ports, arduino_controller

device = scan_serial_ports()
if device is None:
    raise RuntimeError("Trigger Arduino not found")

controller = arduino_controller(device)
try:
    print("Verified:", controller.verify_setup())
finally:
    del controller
```

## 3. Use the controller

Example script:

```python
from trigger_control import make

controller = make()
if controller is None:
    raise RuntimeError("Trigger Arduino not found")

try:
    if not controller.verify_setup():
        raise RuntimeError("Unexpected device identity")

    # Choose the command appropriate to your setup:
    controller.set_on_time(100)  # 100 ms; configure only when appropriate
    # controller.trigger()
    # controller.turn_on()
    # controller.turn_off()
    # controller.loop(on_time=100, off_time=900, loops=5)
finally:
    del controller
```

Uncomment only the command(s) you intend to test. The numbers are illustrative, not a recommendation for connected hardware.

### Python methods

- `scan_serial_ports()` returns the matching port string or `None`.
- `make()` scans and returns an `arduino_controller`, or `None`.
- `arduino_controller(device, baud=115200, timeout=2, write_timeout=2)` opens a known port.
- `verify_setup()` returns `True` if the expected identity line is received; otherwise it returns `None` in the original code.
- `trigger()`, `turn_on()`, and `turn_off()` send commands without waiting for a reply.
- `set_on_time(ms_time)` requires a positive integer.
- `loop(on_time, off_time, loops=None)` requires positive integer on/off times. `loops=None` is sent as `-1`.

The original Python class closes the port in `__del__`; explicit `close()` in a `finally` block is more predictable.

---

# MATLAB version

## 1. Install/prepare MATLAB files

Put `ArduinoController.m` in your current MATLAB folder or on the MATLAB path. The file contains:
- The `ArduinoController` class.
- The `scan_serial_ports()` helper function.

Connect the Arduino and close any other application using its serial port.

## 2. Scan for the Arduino

In the MATLAB Command Window:

```matlab
device = scan_serial_ports();
```

If found, `device` is a string such as `"COM4"` or `"/dev/ttyACM0"`. If no matching device is found, it is `""`.

If automatic scanning is not appropriate or does not work, list ports and choose the known Arduino port:

```matlab
serialportlist("available")
device = "COM4";  % Replace with your actual port
```

## 3. Connect and verify

```matlab
controller = ArduinoController(device);

if ~controller.verify_setup()
    delete(controller);
    error("Unexpected device identity or no response.");
end
```

Keep the `controller` variable alive while using the connection. To close it when finished:

```matlab
delete(controller);
clear controller
```

## 4. Send commands

```matlab
controller.set_on_time(100);       % 100 ms; illustrative only
% controller.trigger();
% controller.turn_on();
% controller.turn_off();
% controller.loop(100, 900, 5);    % on ms, off ms, loop count
```

Uncomment only the command(s) appropriate to your approved setup. The MATLAB methods use the same command strings as the Python version.

### MATLAB methods

- `scan_serial_ports()` returns the matching port name or `""`.
- `ArduinoController(port)` opens a serial connection at 115200 baud with a 2-second read timeout.
- `verify_setup()` returns logical `true` when the expected identity line is received, otherwise `false`.
- `trigger()`, `turn_on()`, and `turn_off()` send commands without waiting for a response.
- `set_on_time(ms_time)` requires a positive integer number of milliseconds.
- `loop(on_time, off_time, loops)` requires positive integer times and an integer loop count. Omitting `loops` or passing `[]` uses `-1`.

## Troubleshooting

- **No ports listed:** check the USB cable, driver, permissions, and operating-system port list.
- **Port busy / cannot open:** close Serial Monitor and other serial clients.
- **Port opens but identity check fails:** verify the firmware sends the exact identity text in response to `S` and uses newline-delimited commands. The scan may also encounter unrelated serial devices; do not probe ports if that is undesirable.
- **Read timeout:** the device may not answer `S`, may reset slowly, or may use a different line ending or baud rate.
- **MATLAB cannot find `ArduinoController`:** ensure `ArduinoController.m` is in the current folder or on the MATLAB path. MATLAB requires the class name and file name to match.
