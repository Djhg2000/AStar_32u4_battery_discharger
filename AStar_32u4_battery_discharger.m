function AStar_32u4_battery_discharger(SERIAL_DEVICE = "/dev/ttyACM0")
% Process data from discharger circuit

pkg load instrument-control

% Defines
SERIAL_BAUDRATE = 9600;
SERIAL_TIMEOUT = -1;
PRETTY_OUTPUT = false;



% Arduino board voltage
v_cc = 4.98;
% Resistive load in Ohms
resistance = 1/((1/99.7) + (1/99.7) + (1/99.4));
% Battery cutoff voltage
v_cutoff = 3;

% Display the testing parameters
fwrite(stdout, ["Test parameters:\nSystem voltage: ", num2str(v_cc), "V, Resistance: ", num2str(resistance) " Ohm, Cutoff voltage: ", num2str(v_cutoff), "V\n\n"]);

time_unit = 1;
capacity = double(0);
error_count = 0;
warning_count = 0;
warning_count_old = 0;
serial_port = serial(SERIAL_DEVICE, SERIAL_BAUDRATE, SERIAL_TIMEOUT);

% Initial values
%serial_line = srl_fgetl_firstchar(serial_port, 'N');
%positive_raw = (serial_line(7) - '0')*1000 + (serial_line(8) - '0')*100 + (serial_line(9) - '0')*10 + (serial_line(10) - '0');
fwrite(stdout, ["Detecting battery...\n"]);
fflush(stdout);
set_mosfet(serial_port, '+');
voltage = get_voltage(serial_port, v_cc);
set_mosfet(serial_port, '-');

% Set up the plot and handles
%handle_plot = plot(1:time_unit, voltage, "xdatasource", "time_unit", "ydatasource", "voltage");
%handle_figure = get(handle_plot, "children");

%% Set up the datasources
%set(handle_plot, "xdatasource", "1:time_unit");
%set(handle_plot, "ydatasource", "voltage");

if ((voltage <= (v_cutoff + 0.1)) || (voltage > 4.5))
	fwrite(stdout, ["/!\\ Battery discharged or not connected /!\\\n"]);
	fwrite(stdout, ["Please connect a charged battery and press any key "]);
	fflush(stdout);
	kbhit();
	fwrite(stdout, ["\n"]);

	%serial_line = srl_fgetl_firstchar(serial_port, 'N');
	%positive_raw = (serial_line(7) - '0')*1000 + (serial_line(8) - '0')*100 + (serial_line(9) - '0')*10 + (serial_line(10) - '0');
	set_mosfet(serial_port, '+');
	voltage = get_voltage(serial_port, v_cc);
	set_mosfet(serial_port, '+');
end
fwrite(stdout, ["Battery detected.\n"]);
fwrite(stdout, ["Press any key to start: "]);
fflush(stdout);
kbhit();
fwrite(stdout, ["\n"]);

% Send MOSFET enable character and verify transmission
if (set_mosfet(serial_port, '+') ~= 0)
	fwrite(stdout, ["Fatal error: writing to ", SERIAL_DEVICE, " failed, will now exit!\n"]);
	fflush(stdout);
	exit(1);
end

% Wait for voltages to settle
while (get_voltage(serial_port, v_cc) < 0.5) end

timer = tic();

while (true)
	%serial_line = srl_fgetl_firstchar(serial_port, 'N');
	%save("-append", "-binary", ["raw_serial-", date(), ".txt"], "serial_line");
	%fwrite(stdout, ["Raw input: ", serial_line, "\n"]);
	%fflush(stdout);

	% Raw ADC values
	%negative_raw = (serial_line(2) - '0')*1000 + (serial_line(3) - '0')*100 + (serial_line(4) - '0')*10 + (serial_line(5) - '0')
	%positive_raw = (serial_line(7) - '0')*1000 + (serial_line(8) - '0')*100 + (serial_line(9) - '0')*10 + (serial_line(10) - '0')

	% Calculate voltage levels from the ADC values (10-bit ADC), save the values from the positive lead for plotting
	voltage(time_unit) = get_voltage(serial_port, v_cc);

	% Sanity checks
	if ((voltage(time_unit) > v_cc) || (voltage(time_unit) < 0))
		error_count++;
		fwrite(stdout, ["Error: Sanity check failed for iteration ", num2str(time_unit), " at ", num2str(voltage(time_unit)), "V\n"]);
		if (time_unit > 1)
			voltage(time_unit) = voltage(time_unit - 1);
			fwrite(stdout, ["       Value replaced with previous value ", num2str(voltage(time_unit)), "V\n"]);
		else
			voltage(time_unit) = v_cc;
			fwrite(stdout, ["       Value replaced with Vcc value ", num2str(voltage(time_unit)), "V\n"]);
		end
	elseif ((time_unit > 1) && ((voltage(time_unit) > (voltage(time_unit - 1) + 0.1)) || (voltage(time_unit) < (voltage(time_unit - 1) - 0.1))))
		warning_count++;
		fwrite(stdout, ["Warning: Suspicious input for iteration ", num2str(time_unit), " at ", num2str(voltage(time_unit)), "V\n"]);
	end

	% Calculate current from the voltage drop
	% Ohm's law states that U=I*R
	% The current will then be I=U/R, or in our case, current = voltage drop / resistance
	current(time_unit) = ((voltage(time_unit)) / resistance);
	% Capacity is the integral of our load, which means we can get a good approximation by simply summing the load values
	% This would not be in Ah however, we will have to divide it down from As and multiply it by 1000 to get mAh
	% Put simply, we divide by 3.6
	capacity += (current(time_unit) / 3.6);

	%refreshdata(handle_figure, "caller");
	%refresh(handle_figure);
	%drawnow();

	fwrite(stdout, ["Voltage: ", num2str(voltage(time_unit), "%1.4f"), "V, Current: ", num2str(current(time_unit)*1000, "%5f") "mA, Capacity: ", num2str(capacity), "mAh"]);
	if (PRETTY_OUTPUT)
		fwrite(stdout, ["    \r"]);
	else
		fwrite(stdout, ["\n"]);
	end
	fflush(stdout);

	% Don't break on suspicious values
	if ((warning_count == warning_count_old) && (voltage(time_unit) < 3))
		break;
	else
		warning_count_old = warning_count;
		time_unit++;
	end
end

time_actual = toc(timer);

fwrite(stdout, ["\nDischarge complete, disconnecting battery...\n"]);
fflush(stdout);
% Send MOSFET disable character and verify transmission
if (set_mosfet(serial_port, '-') ~= 0)
	fwrite(stdout, ["Error: writing to ", SERIAL_DEVICE, " failed!\n\n"]);
	fwrite(stdout, ["          / \\\n"]);
	fwrite(stdout, ["         /   \\\n"]);
	fwrite(stdout, ["        / ||| \\\n"]);
	fwrite(stdout, ["       /  |||  \\\n"]);
	fwrite(stdout, ["      /   |||   \\\n"]);
	fwrite(stdout, ["     /    |||    \\\n"]);
	fwrite(stdout, ["    /             \\\n"]);
	fwrite(stdout, ["   /      ***      \\\n"]);
	fwrite(stdout, ["  /       ***       \\\n"]);
	fwrite(stdout, [" /___________________\\\n"]);
	fwrite(stdout, ["DISCONNECT BATTERY MANUALLY!\n\n"]);
else
	fwrite(stdout, ["Battery successfully disconnected!\n\n"]);
end
fflush(stdout);

% We're done with the actual discharger, close the serial port
srl_close(serial_port);

% We will need to account for the microcontroller clock drift when testing larger batteries
% This will tell us how long a microcontroller second is with respect to the computer clock
time_unit_size = (time_actual)/time_unit;

% Simply summing up our current readings leave us with A per time unit, which is almost what we want.
% If we multiply the sum with the size of out time units, we get As
% Then we simply divide by (60*60) to get Ah and multiply by 1000 to get mAh
% In order to preserve percision, we simplify 1000/3600 to 1/3.6
capacity = (sum(current)*time_unit_size)/3.6;

fwrite(stdout, ["=== Final battery statistics ===\n"]);
fwrite(stdout, ["Voltage:       ", num2str(voltage(1)), " V to ", num2str(voltage(time_unit)), " V\n"]);
fwrite(stdout, ["Capacity:      ", num2str(capacity), " mAh\n"]);
fwrite(stdout, ["Duration:      ", num2str(time_actual), " seconds\n\n"]);
fwrite(stdout, ["Clock drift:   ", num2str(time_unit_size - 1), " actual seconds per clock second\n"]);
fwrite(stdout, ["Error count:   ", num2str(error_count), " serial errors\n"]);
fwrite(stdout, ["Warning count: ", num2str(warning_count), " ADC warnings\n"]);
fwrite(stdout, ["Reliability:   ", num2str(((time_unit - (warning_count + error_count)) / time_unit) * 100), " %\n"]);

plot(1:time_unit, voltage);

filename = ["run-", date()];
fwrite(stdout, ["Saving data to file...\n"]);
fflush(stdout);
save([filename, ".log"], "voltage", "current", "capacity", "time_actual");
fwrite(stdout, ["Saving plot to file...\n"]);
fflush(stdout);
print([filename, ".svg"], "-dsvg");
fwrite(stdout, ["Data and plot saved to files ", filename, ".log and ", filename, ".svg respectively\n"]);
fflush(stdout);

fwrite(stdout, ["=== Test completed, have a nice day ===\n"]);

% === End of main function ===
end



% --- Local functions -----

% Reimplementation of fgetl for serial
function srl_fgetl_line = srl_fgetl(srl_fgetl_device)

	srl_fgetl_line = [];
	while ((srl_fgetl_char = char(srl_read(srl_fgetl_device, 1))) ~= "\n") end
	while ((srl_fgetl_char = char(srl_read(srl_fgetl_device, 1))) ~= "\n")
		srl_fgetl_line = [srl_fgetl_line, srl_fgetl_char];
	end
end

% Modified reimplementation of fgetl for serial
function srl_fgetl_line = srl_fgetl_firstchar(srl_fgetl_device, srl_fgetl_firstchar)

	srl_fgetl_line = srl_fgetl_firstchar;
	while ((srl_fgetl_char = char(srl_read(srl_fgetl_device, 1))) ~= srl_fgetl_firstchar)
		% Don't fflush() in here, we don't want to risk missing a byte
		fwrite(stdout, ["srl_fgetl_firstchar(): wanted \"", srl_fgetl_firstchar, "\" got \"", srl_fgetl_char, "\"\n"]);
	end

	while ((srl_fgetl_char = char(srl_read(srl_fgetl_device, 1))) ~= "\n")
		srl_fgetl_line = [srl_fgetl_line, srl_fgetl_char];
	end
end

function get_voltage_voltage = get_voltage(get_voltage_device, get_voltage_v_cc)

	get_voltage_serial_line = srl_fgetl_firstchar(get_voltage_device, 'N');
	save("-append", "-binary", ["raw_serial-", date(), ".txt"], "get_voltage_serial_line");

	% Convert string into raw ADC values
	get_voltage_negative_raw = (get_voltage_serial_line(2) - '0')*1000 + (get_voltage_serial_line(3) - '0')*100 + (get_voltage_serial_line(4) - '0')*10 + (get_voltage_serial_line(5) - '0');
	get_voltage_positive_raw = (get_voltage_serial_line(7) - '0')*1000 + (get_voltage_serial_line(8) - '0')*100 + (get_voltage_serial_line(9) - '0')*10 + (get_voltage_serial_line(10) - '0');

	% Scale to real voltage value
	get_voltage_voltage = (get_voltage_positive_raw - get_voltage_negative_raw)*get_voltage_v_cc/2^10;
end

function set_mosfet_error = set_mosfet(set_mosfet_device, set_mosfet_state)

	set_mosfet_error = 0;

	% Translate numerical values if any, otherwise just pass it through
	if (set_mosfet_state == 1)
		set_mosfet_state = '+';
	elseif (set_mosfet_state == 0)
		set_mosfet_state = '-';
	end

	% Send MOSFET state character and verify transmission
	if ((srl_write(set_mosfet_device, set_mosfet_state) ~= 1))
		set_mosfet_error = 1;
	end
end

