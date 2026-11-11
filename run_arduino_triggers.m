
%% 1. CONFIGURATION
% Edit these parameters before running.

clearvars;
clc;

% Trigger parameters
numTriggers = 20;        % Number of triggers
intervalSeconds = 5;     % Seconds between triggers

% Arduino parameters
baudRate = 115200;
timeoutSeconds = 2;

% Output settings
outputDirectory = pwd;

fileTimestamp = string(datetime('now', ...
    'Format', 'yyyyMMdd_HHmmss'));

outputFile = fullfile(outputDirectory, ...
    "Arduino_Triggers_" + fileTimestamp + ".csv");


%% 2. CONNECT TO ARDUINO
% Automatically scan serial ports and connect.

controller = ArduinoController([], baudRate, timeoutSeconds);

% Close connection automatically if script exits
cleanupObject = onCleanup(@() delete(controller));

% Verify Arduino identity
if ~controller.verify_setup()
    error('Arduino verification failed.');
end

fprintf('\nArduino successfully connected!\n');
fprintf('Connected port: %s\n', controller.Port);


%% 3. INITIALIZE LOGGING
% Logging is handled by ArduinoController itself.

controller.start_logging(outputFile);

fprintf('\nLogging initialized.\n');


%% 4. RUN EXPERIMENT
% MATLAB controls the loop.
% Every trigger is sent individually.
% ArduinoController.loop() is NOT used.

fprintf('\nStarting trigger sequence...\n');

runClock = tic;

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

catch ME

    % Save any triggers already recorded
    controller.save_log();

    rethrow(ME);

end


%% 5. SAVE DATA

controller.save_log();

fprintf('\nExperiment finished.\n');


%% 6. DISCONNECT
% Release Arduino serial connection.

clear cleanupObject;

fprintf('Arduino disconnected.\n');

