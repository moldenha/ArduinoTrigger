%% 1. CONNECTION SETTINGS
% The supplied stimjimPulser firmware uses Serial.begin(112500).
% Leave portName = "" to scan available serial ports automatically.

clearvars;
clc;

portName = "";
baudRate = 112500;
serialTimeout_s = 0.25;


%% 2. CONNECT TO STIMJIM
% This scans ports using the firmware's non-stimulation D query.

stimjim = StimJimController(portName, baudRate, serialTimeout_s);

% Keep this cleanup object in the workspace while using the connection.
stimjimCleanup = onCleanup(@() delete(stimjim));


%% 3. STIMULATION PARAMETERS
% Fill in the values for your approved bench-tested protocol.
%
% channelNumber:
%   0 = output channel 0
%   1 = output channel 1
%
% mode:
%   0 = voltage (amplitude in mV)
%   1 = current (amplitude in uA)
%
% pulseDuration_us:
%   Total duration of one pulse. If bipolar=true, this is split into
%   two sequential phases of approximately equal duration.
%
% bipolar:
%   false = one stage at the specified polarity
%   true  = two stages, +amplitude followed by -amplitude
%
% threshold:
%   [] because the supplied firmware has no analog threshold field.
%   R commands configure a digital rising-edge input, not a threshold.

trainIndex = 0;

channelNumber = 0;
mode = 1;

pulseAmplitude = [];       % mV (mode 0) or uA (mode 1)
threshold = [];            % Not supported by supplied firmware
pulseDuration_us = [];     % Total pulse duration in microseconds

bipolar = false;

numberOfPulses = [];
trainFrequency_Hz = [];


%% 4. BUILD CONFIGURATION AND SEND IT TO STIMJIM
% This configures the pulse train using the S command.
% It DOES NOT start stimulation.

cfg = struct();

cfg.trainIndex = trainIndex;
cfg.channelNumber = channelNumber;
cfg.mode = mode;
cfg.pulseAmplitude = pulseAmplitude;
cfg.threshold = threshold;
cfg.pulseDuration_us = pulseDuration_us;
cfg.bipolar = bipolar;
cfg.numberOfPulses = numberOfPulses;
cfg.trainFrequency_Hz = trainFrequency_Hz;

% Stop here if any required values are still empty.
requiredValues = [pulseAmplitude, pulseDuration_us, ...
                  numberOfPulses, trainFrequency_Hz];

if isempty(requiredValues)
    error(['Enter pulseAmplitude, pulseDuration_us, numberOfPulses, ', ...
           'and trainFrequency_Hz in Section 3 before configuring.']);
end

% Send configuration and print all firmware response lines.
configurationResponse = stimjim.configurePulseTrain(cfg);


%% 5. OPTIONAL: QUERY CALIBRATION OFFSETS
% D prints ADC/current/voltage offset values.
% This does not start a pulse train.

offsetResponse = stimjim.sendQuery("D", 1.0);


%% 6. OPTIONAL: START A CONFIGURED TRAIN -- DELIBERATE ACTION
% This section is intentionally separate.
% Only uncomment the command after verifying the configuration and
% completing the required hardware/bench checks.
%
% startResponse = stimjim.startTrain(trainIndex, 'T');
%
% 'T' uses timer 0; 'U' uses timer 1.
% Do not issue both unless simultaneous trains are intentionally required.


%% 7. DISCONNECT
% Run this section when finished.

stimjim.disconnect();
clear stimjimCleanup;
clear stimjim;
