classdef ArduinoController < handle
    %ARDUINOCONTROLLER Control the custom trigger Arduino over serial.
    %
    % Commands sent to the Arduino:
    %   S                 Verify identity; expected response is a text line
    %   T                 Trigger
    %   O                 Turn output on
    %   F                 Turn output off
    %   C;<milliseconds>  Set on-time
    %   L;<on_ms>;<off_ms>;<loops>  Repeat on/off sequence
    %
    % A loop count of -1 requests indefinite repetition, matching Python.
    % Confirm the firmware's behavior and use appropriate hardware safeguards.

    properties (SetAccess = private)
        Port
        BaudRate
    end

    properties (Access = private)
        SerialObj
    end

    methods
        function obj = ArduinoController(port, baudRate, timeoutSeconds)
            if nargin < 2 || isempty(baudRate), baudRate = 115200; end
            if nargin < 3 || isempty(timeoutSeconds), timeoutSeconds = 2; end
            validateattributes(port, {'char','string'}, {'scalartext'});
            validateattributes(baudRate, {'numeric'}, {'scalar','integer','positive'});
            validateattributes(timeoutSeconds, {'numeric'}, {'scalar','positive'});

            obj.Port = char(port);
            obj.BaudRate = baudRate;
            obj.SerialObj = serialport(obj.Port, obj.BaudRate, ...
                'Timeout', timeoutSeconds);
            configureTerminator(obj.SerialObj, "LF");
            flush(obj.SerialObj);
        end

        function delete(obj)
            % Releasing the serialport object closes the connection.
            if ~isempty(obj.SerialObj)
                obj.SerialObj = [];
            end
        end

        function tf = verify_setup(obj)
            obj.sendLine("S");
            try
                response = strtrim(readline(obj.SerialObj));
                tf = strcmp(response, "This is a custom trigger arduino!");
            catch
                tf = false;
            end
        end

        function trigger(obj)
            obj.sendLine("T");
        end

        function turn_on(obj)
            obj.sendLine("O");
        end

        function turn_off(obj)
            obj.sendLine("F");
        end

        function set_on_time(obj, ms_time)
            validateattributes(ms_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            obj.sendLine("C;" + string(ms_time));
        end

        function loop(obj, on_time, off_time, loops)
            if nargin < 4 || isempty(loops), loops = -1; end
            validateattributes(on_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(off_time, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(loops, {'numeric'}, ...
                {'scalar','integer','finite'});
            obj.sendLine("L;" + string(on_time) + ";" + ...
                string(off_time) + ";" + string(loops));
        end
    end

    methods (Access = private)
        function sendLine(obj, command)
            writeline(obj.SerialObj, char(command));
        end
    end
end

function device = scan_serial_ports()
%SCAN_SERIAL_PORTS Find a serial port that identifies as the trigger Arduino.
% Returns the port name (e.g., "COM4" or "/dev/ttyACM0"), or "" if not found.
    device = "";
    ports = serialportlist("available");
    if isempty(ports)
        fprintf('No serial ports found.\n');
        return;
    end

    fprintf('Found %d available serial port(s):\n', numel(ports));
    for k = 1:numel(ports)
        port = ports(k);
        fprintf('\nChecking %s\n', port);
        try
            s = serialport(port, 115200, 'Timeout', 2);
            configureTerminator(s, "LF");
            cleanup = onCleanup(@() clearSerial(s)); %#ok<NASGU>
            pause(2); % Allow time for a possible Arduino reset.
            flush(s);
            writeline(s, 'S');
            t0 = tic;
            response = strtrim(readline(s));
            elapsed = toc(t0);
            fprintf('Response: %s\n', response);
            fprintf('Read time: %.3f seconds\n', elapsed);
            if strcmp(response, 'This is a custom trigger arduino!')
                fprintf('Found the trigger Arduino on %s\n', port);
                device = string(port);
                return;
            end
        catch ME
            fprintf('Could not use %s: %s\n', port, ME.message);
        end
        clear cleanup;
    end
    fprintf('Trigger Arduino not found.\n');
end

function clearSerial(s)
%CLEARSERIAL Release a serial connection created during scanning.
    clear s;
end
