#include <limits.h>

const int TRIGGER_PIN = 10;
const int BUFFER_SIZE = 1000;

char comBuf[BUFFER_SIZE];
int bytesRecvd = 0;

int on_clock = 1000;

// Trigger states
enum TriggerMode {
  IDLE,
  MANUAL_ON,
  SINGLE_PULSE,
  LOOPING
};

TriggerMode mode = IDLE;

bool on = false;
bool pulseHigh = false;

unsigned long phaseStart = 0;

int loopOnDelay = 0;
int loopOffDelay = 0;
int loopCount = 0;       // -1 means infinite
int completedPulses = 0;

void setTrigger(bool state) {
  digitalWrite(TRIGGER_PIN, state ? HIGH : LOW);
  on = state;
}

void stopTrigger() {
  mode = IDLE;
  pulseHigh = false;
  setTrigger(false);
}

void startPulse() {
  setTrigger(true);
  pulseHigh = true;
  phaseStart = millis(); // Potential bug: will loop over after 49.7 days, will also check if it is less than the phase start
}

void startLoop(int onDelay, int offDelay, int num) {
  if (onDelay < 0 || offDelay < 0 ||
      (num != -1 && num <= 0)) {
    Serial.println("Invalid loop parameters");
    return;
  }

  loopOnDelay = onDelay;
  loopOffDelay = offDelay;
  loopCount = num;
  completedPulses = 0;
  mode = LOOPING;

  // Start the first pulse immediately.
  startPulse();
}

void updateTrigger() {
  unsigned long now = millis();
  unsigned long phaseStart_ = phaseStart;
  if(now < phaseStart){
    // very specific edge case where the device has been on for 49.7 days
    unsigned long remaining = ULONG_MAX - phaseStart;
    phaseStart_ = 0;
    now += remaining;
  }
  if (mode == SINGLE_PULSE) {
    if (now - phaseStart_ >= (unsigned long)on_clock) {
      stopTrigger();
    }
  }

  else if (mode == LOOPING) {
    if (pulseHigh) {
      // end the current high pulse.
      if (now - phaseStart_ >= (unsigned long)loopOnDelay) {
        setTrigger(false);
        pulseHigh = false;
        phaseStart = now;
        completedPulses++;

        // dtop after the requested number of pulses.
        if (loopCount != -1 &&
            completedPulses >= loopCount) {
          mode = IDLE;
        }
      }
    }
    else {
      // wait for the off interval before the next pulse.
      if (now - phaseStart_ >= (unsigned long)loopOffDelay) {
        startPulse();
      }
    }
  }
  // SINGLE_PULSE and MANUAL_ON stay
}

void processCommand(char *cmd) {
  if (cmd[0] == 'S') {
    Serial.println("This is a custom trigger arduino!");
  }

  else if (cmd[0] == 'T' && mode == IDLE) {
    mode = SINGLE_PULSE;
    startPulse();
  }

  else if (cmd[0] == 'O' && mode == IDLE) {
    mode = MANUAL_ON;
    setTrigger(true);
  }

  else if (cmd[0] == 'F') {
    stopTrigger();
  }

  else if (cmd[0] == 'C') {
    int value;

    if (sscanf(cmd + 1, ";%d", &value) == 1 &&
        value >= 0) {
      on_clock = value;
    }
  }

  else if (cmd[0] == 'L' && mode == IDLE) {
    int onDelay, offDelay, num;

    if (sscanf(cmd + 1, ";%d;%d;%d",
               &onDelay, &offDelay, &num) == 3) {
      startLoop(onDelay, offDelay, num);
    }
    else {
      Serial.println("Invalid L command");
    }
  }
}


void setup() {
  Serial.begin(115200);

  pinMode(TRIGGER_PIN, OUTPUT);
  setTrigger(false);
}

/* Commands:
 * S - Setup (this command just confirms that everything is running
 * T - Triggers pin on high for specified "on_time" variable
 * O - Turns pin on high
 * F - Turns pin off
 * C - Change the on clock (how long the pin will be on high ex: [C;1000] will make every trigger last 1000 ms
 * L - Loop the triggers (ex: [L;1000;2000;3] - will loop where the pin is on for 1000 ms, every 2000 ms, for 3 loops)
 *                      - if instead of 3, you get -1, then the loop will run infinitely until the F command is called
 */

void loop() {
  // keep the pulse sequence progressing.
  updateTrigger();
  // Read serial input without blocking.
  if(Serial.available() > 0){
    Serial.readBytes(comBuf + bytesRecvd, 1); // read one byte into the buffer
    ++bytesRecvd;
    if (comBuf[bytesRecvd - 1] == '\n') {
      comBuf[bytesRecvd - 1] = '\0';

      // Support both LF and CRLF line endings.
      if (bytesRecvd > 0 &&
          comBuf[bytesRecvd - 2] == '\r') {
        comBuf[bytesRecvd - 2] = '\0';
      }

      if (bytesRecvd > 0) {
        processCommand(comBuf);
      }

      bytesRecvd = 0;
    }
  }
}

