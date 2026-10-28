import serial.tools.list_ports
import serial
import time

def scan_serial_ports():
    ports = serial.tools.list_ports.comports()

    if not ports:
        print("No serial ports found.")
        return None

    print(f"Found {len(ports)} serial port(s):")

    for port in ports:
        print(f"\nChecking {port.device}: {port.description}")
        if port.description == "n/a":
           continue

        try:
            with serial.Serial(
                port.device,
                115200,
                timeout=2,
                write_timeout=2
            ) as ser:
                # Allow time for an Arduino reset, if one occurs.
                time.sleep(2)

                ser.reset_input_buffer()
                ser.write(b"S\n")
                ser.flush()

                start = time.monotonic()
                line = ser.readline().decode(
                    "utf-8", errors="replace"
                ).strip()
                elapsed = time.monotonic() - start

                print(f"Response: {line!r}")
                print(f"Read time: {elapsed:.3f} seconds")

                if line == "This is a custom trigger arduino!":
                    print("Found the trigger Arduino!")
                    return port.device

        except (serial.SerialException, OSError) as e:
            print(f"Could not use {port.device}: {e}")

    print("Trigger Arduino not found.")
    return None

class arduino_controller:
    def __init__(self, device, baud = 115200, timeout = 2, write_timeout = 2):
        self.ser = serial.Serial(device, baud, 
                                 timeout = timeout, write_timeout = write_timeout)
        self.ser.reset_input_buffer()

    def __del__(self):
        print("Finished with arduino controller")
        self.ser.close()

    def verify_setup(self):
        self.ser.write(b"S\n")
        self.ser.flush()
        line = self.ser.readline().decode(
            "utf-8", errors="replace"
        ).strip()
        if line == "This is a custom trigger arduino!":
            return True;

    def trigger(self):
        self.ser.write(b"T\n")
        self.ser.flush()

    def turn_on(self):
        self.ser.write(b"O\n")
        self.ser.flush()

    def turn_off(self):
        self.ser.write(b"F\n")
        self.ser.flush()

    def set_on_time(self, ms_time):
        assert type(ms_time) == int, "Error: Expected ms_time for set on time ({ms_time}) to be an integer"
        assert ms_time > 0, "Error: Expected ms_time for set on time ({ms_time}) to be greater than 0"
        self.ser.write(f"C;{ms_time}\n".encode('utf-8'))
        self.ser.flush()
    
    def loop(self, on_time: int, off_time: int, loops: int = None):
        if loops == None:
            loops = -1
        assert type(on_time) == int and type(off_time) == int and type(loops) == int, "Error: Expected all variables for loop to be integers"
        assert on_time > 0 and off_time > 0, f"Error: Expected on_time ({on_time}) and off_time ({off_time}) to be greater than 0"
        self.ser.write(f"L;{on_time};{off_time};{loops}\n".encode('utf-8'))
        self.ser.flush()

def make():
    device = scan_serial_ports()
    if device is None:
        print("No devices found")
        return None
    return arduino_controller(device)

if __name__ == "__main__":
    device = scan_serial_ports()
    assert device is not None, "Error: could not find device!"

