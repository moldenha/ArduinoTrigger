
%% 1. SETUP
% Edit these parameters before running.

clearvars;
clc;

% Trigger parameters




% Arduino parameters
arduinoBaudRate = 115200;
arduinoTimeoutSeconds = 2;

% StimJim parameters
stimJimPortName = "";
stimJimBaudRate = 115200;
stimJimTimeoutSeconds = 0.25;


% Output settings
outputDirectory = '';

fileTimestamp = string(datetime('now', ...
    'Format', 'yyyyMMdd_HHmmss'));

outputFile = fullfile(outputDirectory, ...
    "Arduino_Triggers_" + fileTimestamp + ".csv");


%% 2. CONNECT

% First going to connect to the arduino
% Automatically scan serial ports and connect.

controller = ArduinoController([], arduinoBaudRate, arduinoTimeoutSeconds);
fprintf("Finished making controller");

% Close connection automatically if script exits
cleanupObject = onCleanup(@() delete(controller));
fprintf("Made cleanup object");
pause(1);

fprintf("Now verifying...");
% Verify Arduino identity
if ~controller.verify_setup()
    error('Arduino verification failed.');
end

fprintf('\nArduino successfully connected!\n');
fprintf('Connected port: %s\n', controller.Port);

% Now going to connect to the stimjim
% This scans ports using the firmware's non-stimulation D query.
stimjim = StimJimController(StimJimPortName, stimJimBaudRate, stimJimTimeoutSeconds);

% Keep this cleanup object in the workspace while using the connection.
stimjimCleanup = onCleanup(@() delete(stimjim));




% Now initialize logging
% Logging is handled by ArduinoController itself.

controller.start_logging(outputFile);

fprintf('\nLogging initialized.\n');

%% 3. CONFIGURE

% This is the settings of both the arduino and the stim jim

% Arduino Settings
arduino_trigger_time = 50;       % Number of ms for trigger to be active


% StimJim parameters
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




% This is to set the parameters on the arduino and the stim jim
controller.set_on_time(arduino_trigger_time);


% Build configuration and send it to the StimJim
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
% Make sure that the pulse from the arduino is configured for the stimjim
pause(0.5);
stimjim.sendQuery('R0,0');
controller.stimjim_cfg = cfg;


%% 4. RUN TRIGGER LOOP
% MATLAB controls the loop.
% Every trigger is sent individually.
% ArduinoController.loop() is NOT used.

fprintf('\nStarting trigger sequence...\n');

runClock = tic;
numTriggers = 20;        % Number of triggers
intervalSeconds = 5;     % Seconds between triggers

try

    for k = 1:numTriggers

        % Schedule relative to the original start time
        targetTime = (k - 1) * intervalSeconds;

        while toc(runClock) < targetTime

            remaining = targetTime - toc(runClock);

            pause(min(0.01, remaining));

        end

        % Send trigger
        controller.trigger();

        fprintf('Trigger %d/%d sent | Elapsed: %.6f seconds\n', ...
            k, numTriggers, toc(runClock));

    end

    fprintf('\nTrigger sequence complete!\n');
    controller.save_log(); % Make sure the log is saved at the end

catch ME

    % Save any triggers already recorded
    controller.save_log();

    rethrow(ME);

end

%% 5. SEND SINGLE TRIGGER

controller.trigger();
controller.save_log(); % Make sure that the log is saved at the end

%% 6. SAVE DATA

controller.save_log();

fprintf('\nExperiment finished.\n');


%% 7. DISCONNECT
% Release Arduino serial connection.

clear cleanupObject;
clear stimjimCleanup;

fprintf('Arduino and StimJim disconnected.\n');

