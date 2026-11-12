classdef StimJimController < handle
    % STIMJIMCONTROLLER MATLAB serial interface for stimjimPulser firmware.
    %
    % Firmware protocol implemented here:
    %   D                         Print calibration offsets
    %   S<idx>,<m0>,<m1>,<period_us>,<train_duration_us>; <a0>,<a1>,<stage_us>;...
    %   T<idx>                    Start pulse train on timer T
    %   U<idx>                    Start pulse train on timer U
    %
    % Firmware baud rate in the supplied sketch: 112500 baud.
    %
    % IMPORTANT:
    % - The supplied firmware has no analog threshold parameter.
    % - The firmware supports two output channels and up to 10 stages.
    % - This class configures trains but does not start them automatically.
    % - Amplitude values are mV in voltage mode and uA in current mode.
    %
    % MATLAB Instrument Control Toolbox / serialport support is required.

    properties (SetAccess = private)
        Port
        BaudRate
        LastResponse
    end

    properties (Access = private)
        SerialObj
    end

    methods
        function obj = StimJimController(port, baudRate, timeoutSeconds)
            if nargin < 1
                port = "";
            end
            if nargin < 2 || isempty(baudRate)
                baudRate = 112500;
            end
            if nargin < 3 || isempty(timeoutSeconds)
                timeoutSeconds = 0.25;
            end

            validateattributes(baudRate, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(timeoutSeconds, {'numeric'}, ...
                {'scalar','positive','finite'});

            if isempty(port)
                port = StimJimController.findStimJimPort(baudRate);
            end
            if isempty(port)
                error('StimJim:NotFound', ...
                    ['No StimJim response was detected. Check the USB ', ...
                     'connection, firmware, and serial port.']);
            end

            obj.Port = char(port);
            obj.BaudRate = baudRate;
            obj.LastResponse = "";

            fprintf('Opening StimJim on %s at %d baud...\n', ...
                obj.Port, obj.BaudRate);

            obj.SerialObj = serialport(obj.Port, obj.BaudRate, ...
                'Timeout', timeoutSeconds);
            configureTerminator(obj.SerialObj, "LF");
            pause(1.5);  % Teensy may reset when the serial port opens.
            flush(obj.SerialObj);

            % D is a non-stimulation query supported by the supplied sketch.
            obj.sendRaw("D");
            obj.LastResponse = obj.readResponse(1.5, false);

            fprintf('StimJim connection opened.\n');
            if strlength(obj.LastResponse) > 0
                fprintf('%s\n', obj.LastResponse);
            else
                fprintf(['No startup/query text was received. The serial ', ...
                    'port is open, but device identity was not confirmed.\n']);
            end
        end

        function delete(obj)
            if ~isempty(obj.SerialObj)
                try
                    flush(obj.SerialObj);
                catch
                end
                obj.SerialObj = [];
            end
        end

        function response = configurePulseTrain(obj, cfg)
            % Build and send an S command using a configuration structure.
            %
            % Required fields:
            %   trainIndex       0..99
            %   channelNumber    0 or 1
            %   mode             0=voltage, 1=current
            %   pulseAmplitude  mV or uA according to mode
            %   pulseDuration_us total pulse duration; bipolar splits it
            %   into two approximately equal phases
            %   bipolar          true/false
            %   numberOfPulses   positive integer
            %   trainFrequency_Hz positive frequency
            %   threshold        must be [] because firmware has no threshold
            %
            % Bipolar encoding: two sequential stages, +amplitude then
            % -amplitude, each on the selected channel. The other channel
            % is set to mode 3 (grounded) and zero amplitude.

            required = {'trainIndex','channelNumber','mode', ...
                'pulseAmplitude','pulseDuration_us','bipolar', ...
                'numberOfPulses','trainFrequency_Hz'};
            for k = 1:numel(required)
                if ~isfield(cfg, required{k})
                    error('StimJim:MissingParameter', ...
                        'Missing cfg.%s.', required{k});
                end
            end

            if isfield(cfg, 'threshold') && ~isempty(cfg.threshold)
                error('StimJim:UnsupportedThreshold', ...
                    ['The supplied stimjimPulser firmware does not ', ...
                     'implement an analog threshold parameter. ', ...
                     'Its R command configures a digital rising-edge input.']);
            end

            validateattributes(cfg.trainIndex, {'numeric'}, ...
                {'scalar','integer','>=',0,'<=',99});
            validateattributes(cfg.channelNumber, {'numeric'}, ...
                {'scalar','integer','>=',0,'<=',1});
            validateattributes(cfg.mode, {'numeric'}, ...
                {'scalar','integer','>=',0,'<=',1});
            validateattributes(cfg.pulseAmplitude, {'numeric'}, ...
                {'scalar','integer','finite'});
            validateattributes(cfg.pulseDuration_us, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(cfg.bipolar, {'logical','numeric'}, ...
                {'scalar'});
            validateattributes(cfg.numberOfPulses, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(cfg.trainFrequency_Hz, {'numeric'}, ...
                {'scalar','positive','finite'});

            % Firmware uses unsigned long for period and train duration.
            period_us = round(1e6 / cfg.trainFrequency_Hz);
            if period_us < 1 || period_us > 4294967295
                error('StimJim:PeriodRange', ...
                    'Requested frequency produces an invalid period.');
            end

            trainDuration_us = double(cfg.numberOfPulses) * period_us;
            if trainDuration_us > 4294967295
                error('StimJim:TrainDurationRange', ...
                    'Train duration exceeds the firmware unsigned-long range.');
            end

            % Construct the two-channel mode and stage amplitudes.
            modes = [3 3];  % Default both channels grounded.
            modes(cfg.channelNumber + 1) = cfg.mode;

            amp0 = 0;
            amp1 = 0;

            if logical(cfg.bipolar)
                if cfg.pulseDuration_us < 2
                    error('StimJim:BiphasicDuration', ...
                        'Bipolar pulse duration must be at least 2 us.');
                end
                phase1_us = floor(cfg.pulseDuration_us / 2);
                phase2_us = cfg.pulseDuration_us - phase1_us;

                % The firmware subtracts its measured DAC/ADC overhead
                % from each stage duration. Reject very short stages to
                % avoid unsigned underflow in delayMicroseconds().
                if min(phase1_us, phase2_us) <= 20
                    error('StimJim:StageTooShort', ...
                        ['Each bipolar stage must exceed 20 us for this ', ...
                         'firmware implementation.']);
                end

                stageDurations = [phase1_us phase2_us];
                stageAmplitudes = [cfg.pulseAmplitude, ...
                                  -cfg.pulseAmplitude];
            else
                if cfg.pulseDuration_us <= 20
                    error('StimJim:StageTooShort', ...
                        ['Pulse stage must exceed 20 us for this firmware ', ...
                         'implementation.']);
                end
                stageDurations = cfg.pulseDuration_us;
                stageAmplitudes = cfg.pulseAmplitude;
            end

            % On the Teensy 3.5 target, unsigned int is 32-bit.
            if any(stageDurations > 4294967295)
                error('StimJim:StageDurationRange', ...
                    'A stage duration exceeds the firmware unsigned-int range.');
            end

            totalPulseDuration = sum(stageDurations);
            if totalPulseDuration >= period_us
                error('StimJim:PulsePeriod', ...
                    ['Total pulse duration must be shorter than the ', ...
                     'inter-pulse period.']);
            end

            if numel(stageDurations) > 10
                error('StimJim:TooManyStages', ...
                    'Firmware supports a maximum of 10 stages.');
            end

            for k = 1:numel(stageDurations)
                if cfg.channelNumber == 0
                    stageAmps0 = stageAmplitudes(k);
                    stageAmps1 = 0;
                else
                    stageAmps0 = 0;
                    stageAmps1 = stageAmplitudes(k);
                end

                if k == 1
                    stageText = sprintf('%d,%d,%d', ...
                        stageAmps0, stageAmps1, stageDurations(k));
                else
                    stageText = [stageText, sprintf('; %d,%d,%d', ...
                        stageAmps0, stageAmps1, stageDurations(k))]; %#ok<AGROW>
                end
            end

            command = sprintf('S%d,%d,%d,%.0f,%.0f; %s', ...
                cfg.trainIndex, modes(1), modes(2), ...
                period_us, trainDuration_us, stageText);

            fprintf('\nSending configuration command:\n%s\n\n', command);
            obj.sendRaw(command);

            response = obj.readResponse(2.0, false);
            obj.LastResponse = response;

            if strlength(response) == 0
                fprintf('No response received after configuration.\n');
            else
                fprintf('StimJim response:\n%s\n', response);
            end
        end

        function response = startTrain(obj, trainIndex, timerSelect)
            % Explicitly start a previously configured train.
            % timerSelect is 'T' or 'U'. This method is intentionally
            % separate from configurePulseTrain().
            if nargin < 3 || isempty(timerSelect)
                timerSelect = 'T';
            end
            validateattributes(trainIndex, {'numeric'}, ...
                {'scalar','integer','>=',0,'<=',99});

            timerSelect = upper(char(timerSelect));
            if ~ismember(timerSelect, {'T','U'})
                error('StimJim:InvalidTimer', ...
                    'timerSelect must be T or U.');
            end

            command = sprintf('%s%d', timerSelect, trainIndex);
            fprintf('Sending start command: %s\n', command);
            obj.sendRaw(command);
            response = obj.readResponse(1.0, false);
            obj.LastResponse = response;

            if strlength(response) > 0
                fprintf('StimJim response:\n%s\n', response);
            end
        end

        function response = sendQuery(obj, command, waitSeconds)
            % Send a supported non-stimulation/query command and print reply.
            if nargin < 3 || isempty(waitSeconds)
                waitSeconds = 1.0;
            end
            if ~(ischar(command) || (isstring(command) && isscalar(command)))
                error('StimJim:InvalidCommand', 'Command must be text.');
            end
            obj.sendRaw(string(command));
            response = obj.readResponse(waitSeconds, false);
            obj.LastResponse = response;
            if strlength(response) > 0
                fprintf('%s\n', response);
            end
        end

        function disconnect(obj)
            if ~isempty(obj.SerialObj)
                obj.SerialObj = [];
                fprintf('StimJim serial connection released.\n');
            end
        end
    end

    methods (Access = private)
        function sendRaw(obj, command)
            if isempty(obj.SerialObj)
                error('StimJim:Disconnected', 'StimJim is not connected.');
            end
            writeline(obj.SerialObj, char(command));
        end

        function response = readResponse(obj, waitSeconds, printLines)
            if nargin < 3
                printLines = false;
            end
            response = "";
            t0 = tic;

            while toc(t0) < waitSeconds
                if isempty(obj.SerialObj)
                    break;
                end

                if obj.SerialObj.NumBytesAvailable > 0
                    try
                        line = strtrim(string(readline(obj.SerialObj)));
                        if strlength(line) > 0
                            if strlength(response) == 0
                                response = line;
                            else
                                response = response + newline + line;
                            end
                            if printLines
                                fprintf('%s\n', line);
                            end
                        end
                    catch
                        % A partial line may time out; continue until deadline.
                    end
                else
                    pause(0.01);
                end
            end
        end
    end

    methods (Static)
        function port = findStimJimPort(baudRate)
            % Scan available ports. D is a non-stimulation command that
            % prints calibration offsets in the supplied firmware.
            if nargin < 1
                baudRate = 112500;
            end

            port = "";
            ports = serialportlist("available");

            if isempty(ports)
                fprintf('No available serial ports found.\n');
                return;
            end

            fprintf('Scanning %d serial port(s) for StimJim...\n', numel(ports));

            for k = 1:numel(ports)
                candidate = ports(k);
                fprintf('Checking %s ...\n', candidate);
                s = [];

                try
                    s = serialport(candidate, baudRate, 'Timeout', 0.2);
                    configureTerminator(s, "LF");
                    pause(1.5);
                    flush(s);

                    writeline(s, 'D');

                    t0 = tic;
                    received = "";
                    while toc(t0) < 2.0
                        if s.NumBytesAvailable > 0
                            try
                                line = strtrim(string(readline(s)));
                                if strlength(line) > 0
                                    received = received + " " + line;
                                end
                            catch
                            end
                        else
                            pause(0.01);
                        end
                    end

                    if contains(received, "ADC offsets") || ...
                       contains(received, "current offsets")
                        fprintf('StimJim detected on %s.\n', candidate);
                        port = string(candidate);
                        clear s;
                        return;
                    end
                catch ME
                    fprintf('Could not query %s: %s\n', candidate, ME.message);
                end

                if ~isempty(s)
                    clear s;
                end
            end

            fprintf('No StimJim identity response detected.\n');
        end
    end
end
