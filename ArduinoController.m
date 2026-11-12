classdef ArduinoController < handle
    % ARDUINOCONTROLLER Control custom trigger Arduino over serial.
    %
    % Commands:
    %   S                 Verify identity
    %   T                 Trigger
    %   O                 Output on
    %   F                 Output off
    %   C;<milliseconds>  Set on-time
    %   L;<on>;<off>;<loops>  Arduino-side loop
    %
    % Logging:
    %   start_logging(filename)
    %   trigger()
    %   save_log()
    %
    % Individual triggers are timestamped in MATLAB immediately
    % before their serial commands are sent.

    properties (SetAccess = private)
        Port
        BaudRate
        ArduinoTriggerTime_ms

        % Logging
        LogFile
        LoggingEnabled
        LogTimestamps
        LogElapsedSeconds
        LogArduinoTriggerTime_ms
        LogTriggerNumbers
        LogClock
        LogTrainIndex
        LogChannelNumber
        LogMode
        LogPulseAmplitude
        LogPulseDuration_us
        LogBipolar
        LogNumberOfPulses
        LogTrainFrequency_Hz
        stimjim_cfg
    end

    properties (Access = private)
        SerialObj
    end

    methods

        %% CONSTRUCTOR

        function obj = ArduinoController(port, baudRate, timeoutSeconds)

            if nargin < 1 || isempty(port)
                port = ArduinoController.scan_serial_ports();
            end

            if nargin < 2 || isempty(baudRate)
                baudRate = 115200;
            end

            if nargin < 3 || isempty(timeoutSeconds)
                timeoutSeconds = 2;
            end

            if isempty(port)
                error('ArduinoController:NotFound', ...
                    'Could not find the trigger Arduino.');
            end

            validateattributes(port, {'char','string'}, ...
                {'scalartext'});

            validateattributes(baudRate, {'numeric'}, ...
                {'scalar','integer','positive'});

            validateattributes(timeoutSeconds, {'numeric'}, ...
                {'scalar','positive'});

            obj.Port = char(port);
            obj.BaudRate = baudRate;
            obj.ArduinoTriggerTime_ms = 1000;


            % Initialize logging variables
            obj.LoggingEnabled = false;
            obj.LogFile = "";
            obj.LogTimestamps = strings(0,1);
            obj.LogElapsedSeconds = [];
            obj.LogTriggerNumbers = [];
            obj.LogClock = [];
            obj.LogArduinoTriggerTime_ms = [];
            % StimJim properties
            obj.LogTrainIndex = [];
            obj.LogChannelNumber = [];
            obj.LogMode = [];
            obj.LogPulseAmplitude = [];
            obj.LogPulseDuration_us = [];
            obj.LogBipolar = [];
            obj.LogNumberOfPulses = [];
            obj.LogTrainFrequency_Hz = [];
            obj.stimjim_cfg = [];



            % Connect to Arduino
            fprintf('Connecting to Arduino on %s...\n', obj.Port);

            obj.SerialObj = serialport(obj.Port, ...
                obj.BaudRate, 'Timeout', timeoutSeconds);

            configureTerminator(obj.SerialObj, "LF");
            pause(2);
            flush(obj.SerialObj);

            % writeline(, 'S');

            fprintf('Serial connection established.\n');

        end


        %% DESTRUCTOR

        function delete(obj)
            % Save any outstanding trigger records
            if obj.LoggingEnabled && ~isempty(obj.LogTimestamps)
                try
                    obj.save_log();
                catch ME
                    warning('Could not save trigger log: %s', ME.message);
                end
            end
            obj.LoggingEnabled = false;

            % Release serial connection
            if ~isempty(obj.SerialObj)
                obj.SerialObj = [];
            end
        end

        function log_stimjim_cfg(obj)
            if obj.LoggingEnabled
                obj.LogTrainIndex(end+1, 1) = ...
                    obj.stimjim_cfg.trainIndex;
                obj.LogChannelNumber(end+1,1) = ...
                    obj.stimjim_cfg.channelNumber ;
                obj.LogMode(end+1,1) = ...
                    obj.stimjim_cfg.mode;
                obj.LogPulseAmplitude(end+1,1) = ...
                    obj.stimjim_cfg.pulseAmplitude;
                obj.LogPulseDuration_us(end+1,1) = ...
                    obj.stimjim_cfg.pulseDuration_us;
                obj.LogBipolar(end+1,1) = ...
                    obj.stimjim_cfg.bipolar;
                obj.LogNumberOfPulses(end+1,1) = ...
                    obj.stimjim_cfg.numberOfPulses;
                obj.LogTrainFrequency_Hz(end+1,1) = ...
                    obj.stimjim_cfg.trainFrequency_Hz;
                % This is an arduino one, but this should be done anyways, so may as well put it here
                % It is another constant that will not change with the trigger
                obj.LogArduinoTriggerTime_ms(end+1, 1) = ...
                    obj.ArduinoTriggerTime_ms;
            end
        end

        %% VERIFY CONNECTION

        function tf = verify_setup(obj)

            writeline(obj.SerialObj, 'S');

            try
                response = strtrim(readline(obj.SerialObj));
                fprintf("\nGot response when verifying...");
                fprintf(response);
                fprintf("\n");
                tf = strcmp(response, ...
                    "This is a custom trigger arduino!");

            catch
                tf = false;
            end

        end


        %% INDIVIDUAL TRIGGER

        function trigger(obj)

            % Record timestamp immediately before sending command
            if obj.LoggingEnabled

                timestamp = string(datetime('now', ...
                    'TimeZone', 'local', ...
                    'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));

                elapsed = toc(obj.LogClock);

            end

            % Send individual trigger command
            obj.sendLine("T");

            % Only record if writeline succeeds
            if obj.LoggingEnabled

                obj.LogTriggerNumbers(end+1,1) = ...
                    numel(obj.LogTriggerNumbers) + 1;

                obj.LogTimestamps(end+1,1) = timestamp;

                obj.LogElapsedSeconds(end+1,1) = elapsed;
                obj.log_stimjim_cfg();

            end

        end


        %% OUTPUT CONTROL

        function turn_on(obj)
            obj.sendLine("O");
        end

        function turn_off(obj)
            obj.sendLine("F");
        end


        %% SET ON TIME

        function set_on_time(obj, ms_time)

            validateattributes(ms_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});

            obj.sendLine("C;" + string(ms_time));

        end


        %% ARDUINO-SIDE LOOP (OPTIONAL)

        function loop(obj, on_time, off_time, loops)

            if nargin < 4 || isempty(loops)
                loops = -1;
            end

            validateattributes(on_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});

            validateattributes(off_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});

            validateattributes(loops, {'numeric'}, ...
                {'scalar','integer','finite'});

            obj.sendLine("L;" + string(on_time) + ";" + ...
                string(off_time) + ";" + string(loops));

        end


        %% START TIMESTAMP LOGGING

        function start_logging(obj, filename)

            if nargin < 2 || isempty(filename)
                filename = "Arduino_Trigger_Log.csv";
            end

            obj.LogFile = string(filename);

            % Reset previous logging data
            obj.LogTimestamps = strings(0,1);
            obj.LogElapsedSeconds = [];
            obj.LogTriggerNumbers = [];
            obj.LogTrainIndex = [];
            obj.LogChannelNumber = [];
            obj.LogMode = [];
            obj.LogPulseAmplitude = [];
            obj.LogPulseDuration_us = [];
            obj.LogBipolar = [];
            obj.LogNumberOfPulses = [];
            obj.LogTrainFrequency_Hz = [];
            obj.LogArduinoTriggerTime_ms = [];

            % Start independent experiment timer
            obj.LogClock = tic;

            obj.LoggingEnabled = true;

            fprintf('Trigger logging enabled.\n');
            fprintf('Output file: %s\n', obj.LogFile);

        end


        %% SAVE TIMESTAMP LOG

        function save_log(obj)

            if isempty(obj.LogTimestamps)
                warning('No triggers have been recorded.');
                return;
            end

        logTable = table( ...
            obj.LogTriggerNumbers, ...
            obj.LogTimestamps, ...
            obj.LogElapsedSeconds, ...
            obj.LogArduinoTriggerTime_ms, ...
            obj.LogTrainIndex, ...
            obj.LogChannelNumber, ...
            obj.LogMode, ...
            obj.LogPulseAmplitude, ...
            obj.LogPulseDuration_us, ...
            obj.LogBipolar, ...
            obj.LogNumberOfPulses, ...
            obj.LogTrainFrequency_Hz, ...
            'VariableNames', { ...
                'TriggerNumber', ...
                'Timestamp', ...
                'ElapsedSeconds', ...
                'ArduinoTriggerTime (ms)', ...
                'TrainIndex', ...
                'ChannelNumber', ...
                'Mode', ...
                'PulseAmplitude', ...
                'PulseDuration_us', ...
                'Bipolar', ...
                'NumberOfPulses', ...
                'TrainFrequency_Hz'});

            writetable(logTable, obj.LogFile);

            fprintf('\nTrigger log saved!\n');
            fprintf('Triggers recorded: %d\n', ...
                numel(obj.LogTriggerNumbers));
            fprintf('File: %s\n', obj.LogFile);

        end

    end


    %% STATIC METHODS

    methods (Static)

        function device = scan_serial_ports()
            % Find Arduino by checking available serial ports.

            device = "";

            ports = serialportlist("available");

            if isempty(ports)
                fprintf('No serial ports found.\n');
                return;
            end

            fprintf('\nFound %d available serial port(s).\n', ...
                numel(ports));

            for k = 1:numel(ports)

                port = ports(k);

                fprintf('\nChecking %s...\n', port);

                try

                    s = serialport(port, 115200, ...
                        'Timeout', 2);

                    configureTerminator(s, "LF");

                    % Allow Arduino reset after connection
                    pause(2);

                    flush(s);

                    writeline(s, 'S');

                    response = strtrim(readline(s));

                    fprintf('Response: %s\n', response);

                    if strcmp(response, ...
                            'This is a custom trigger arduino!')

                        fprintf('\nTrigger Arduino found on %s!\n', ...
                            port);

                        device = string(port);

                        clear s;
                        return;

                    end

                    clear s;

                catch ME

                    fprintf('Could not use %s: %s\n', ...
                        port, ME.message);

                    clear s;

                end

            end

            fprintf('\nTrigger Arduino not found.\n');

        end

    end


    %% PRIVATE METHODS

    methods (Access = private)

        function sendLine(obj, command)

            if isempty(obj.SerialObj)
                error('ArduinoController:Disconnected', ...
                    'Arduino is not connected.');
            end

            writeline(obj.SerialObj, char(command));

        end

    end

end
