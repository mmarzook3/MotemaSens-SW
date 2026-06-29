clc;
clear;
close all;

%% MotemaSens clean ECG / MIC / IMU viewer
%  This can open either:
%  1. MotemaSens .bin log files from the SD card.
%  2. Converted MotemaSens .csv files.
%
%  What this script does:
%  1. Reads the selected BIN or CSV file.
%  2. Builds proper time axes.
%  3. Checks ECG contact/noise/saturation status columns when available.
%  4. Filters ECG only for display, while keeping raw data visible.
%  5. Uses robust scaling so one large spike does not hide the useful signal.
%  6. Prints a simple quality report.

%% Select log file

[fileName, filePath] = uigetfile( ...
    {'*.bin;*.csv;*.txt;*.tsv;*.log;*.xlsx', 'MotemaSens/data files (*.bin, *.csv, *.txt, *.tsv, *.log, *.xlsx)'; ...
     '*.bin', 'MotemaSens binary logs (*.bin)'; ...
     '*.csv', 'CSV files (*.csv)'; ...
     '*.*', 'All files (*.*)'}, ...
    'Select MotemaSens log file');

if isequal(fileName, 0)
    disp('No file selected.');
    return;
end

fullFileName = fullfile(filePath, fileName);

%% Read log file

T = read_motemasens_file(fullFileName);

T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);

fprintf('\nLoaded file: %s\n', fullFileName);
fprintf('Rows found : %d\n', height(T));
disp('Columns found:');
disp(T.Properties.VariableNames');

%% Time axes

[tEcg, ecgTimeLabel, ecgFs] = make_time_axis(T, {'ecg_us', 'ecg_ms', 'ms'});
[tOther, otherTimeLabel, ~] = make_time_axis(T, {'mic_ms', 'acc_ms', 'ms'});

if isnan(ecgFs) || ecgFs <= 0
    ecgFs = 500;
    warning('Could not estimate ECG sample rate. Assuming 500 Hz.');
end

fprintf('\nEstimated ECG sample rate: %.2f Hz\n', ecgFs);

%% Read ECG leads

[leadI, hasLeadI] = read_ecg_column(T, {'lead_i_raw', 'ecg_lead_i', 'ecg_ch1'});
[leadII, hasLeadII] = read_ecg_column(T, {'lead_ii_raw', 'ecg_lead_ii', 'ecg_ch2'});
[leadIII, hasLeadIII] = read_ecg_column(T, {'lead_iii_raw', 'ecg_lead_iii', 'ecg_ch3'});

if ~hasLeadI && ~hasLeadII && ~hasLeadIII
    error('No ECG columns found. Expected lead_i_raw / lead_ii_raw / lead_iii_raw, or ecg_ch1 / ecg_ch2 / ecg_ch3.');
end

%% Read quality/status columns

leadOffP = read_hex_or_number_column(T, {'lead_off_p', 'ecg_lead_off_p'});
leadOffN = read_hex_or_number_column(T, {'lead_off_n', 'ecg_lead_off_n'});
satMask = read_hex_or_number_column(T, {'sat_mask', 'ecg_sat_mask'});
diagFlags = read_hex_or_number_column(T, {'diag_flags', 'ecg_diag_flags'});

badLeadOff = false(height(T), 1);
badSaturation = false(height(T), 1);
badNoise = false(height(T), 1);

if ~isempty(leadOffP)
    badLeadOff = badLeadOff | (leadOffP ~= 0);
end

if ~isempty(leadOffN)
    badLeadOff = badLeadOff | (leadOffN ~= 0);
end

if ~isempty(satMask)
    badSaturation = badSaturation | (satMask ~= 0);
end

% diag_flags bit definitions used by the MotemaSens CSV:
% bit 1 = lead/contact problem
% bit 2 = saturation
% bit 4 = cable/contact noise
if ~isempty(diagFlags)
    badLeadOff = badLeadOff | bit_is_set(diagFlags, 1);
    badSaturation = badSaturation | bit_is_set(diagFlags, 2);
    badNoise = badNoise | bit_is_set(diagFlags, 4);
end

badAny = badLeadOff | badSaturation | badNoise;
goodSamples = ~badAny;

%% Read MIC and IMU if present

[micTrace, hasMic] = read_numeric_column(T, {'mic_trace'});
[micLevel, hasMicLevel] = read_numeric_column(T, {'mic_level'});
[accX, hasAccX] = read_numeric_column(T, {'acc_x_g'});
[accY, hasAccY] = read_numeric_column(T, {'acc_y_g'});
[accZ, hasAccZ] = read_numeric_column(T, {'acc_z_g'});

%% Clean ECG for display

cleanLeadI = [];
cleanLeadII = [];
cleanLeadIII = [];

if hasLeadI
    cleanLeadI = clean_ecg_for_viewing(leadI, ecgFs);
end

if hasLeadII
    cleanLeadII = clean_ecg_for_viewing(leadII, ecgFs);
end

if hasLeadIII
    cleanLeadIII = clean_ecg_for_viewing(leadIII, ecgFs);
end

%% Quality report

fprintf('\n================ ECG QUALITY REPORT ================\n');
fprintf('Total samples          : %d\n', height(T));
fprintf('Good samples           : %d (%.1f%%)\n', sum(goodSamples), percent(sum(goodSamples), height(T)));
fprintf('Contact/lead warnings  : %d (%.1f%%)\n', sum(badLeadOff), percent(sum(badLeadOff), height(T)));
fprintf('Saturation warnings    : %d (%.1f%%)\n', sum(badSaturation), percent(sum(badSaturation), height(T)));
fprintf('Noise warnings         : %d (%.1f%%)\n', sum(badNoise), percent(sum(badNoise), height(T)));

if hasLeadI
    print_lead_stats('Lead I', leadI);
end

if hasLeadII
    print_lead_stats('Lead II', leadII);
end

if hasLeadIII
    print_lead_stats('Lead III', leadIII);
end

fprintf('====================================================\n\n');

%% Figure 1: ECG raw vs cleaned

figure('Name', 'MotemaSens ECG - Raw and Cleaned View', 'NumberTitle', 'off');
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

if hasLeadI
    nexttile;
    plot_ecg_raw_and_clean(tEcg, leadI, cleanLeadI, goodSamples, 'Lead I');
end

if hasLeadII
    nexttile;
    plot_ecg_raw_and_clean(tEcg, leadII, cleanLeadII, goodSamples, 'Lead II');
end

if hasLeadIII
    nexttile;
    plot_ecg_raw_and_clean(tEcg, leadIII, cleanLeadIII, goodSamples, 'Lead III');
    xlabel(ecgTimeLabel);
end

%% Figure 2: Clean ECG leads, robust scaled

figure('Name', 'MotemaSens ECG - Clean View', 'NumberTitle', 'off');
hold on;
grid on;

offset = 0;
spacing = 2.5;

if hasLeadI
    plot(tEcg, robust_normalise(mask_bad(cleanLeadI, goodSamples)) + offset, 'DisplayName', 'Lead I');
    offset = offset - spacing;
end

if hasLeadII
    plot(tEcg, robust_normalise(mask_bad(cleanLeadII, goodSamples)) + offset, 'DisplayName', 'Lead II');
    offset = offset - spacing;
end

if hasLeadIII
    plot(tEcg, robust_normalise(mask_bad(cleanLeadIII, goodSamples)) + offset, 'DisplayName', 'Lead III');
end

title('Clean ECG View - bad samples are blanked');
xlabel(ecgTimeLabel);
ylabel('Robust scaled ECG');
legend('show');

%% Figure 3: ECG quality flags

figure('Name', 'MotemaSens ECG - Quality Flags', 'NumberTitle', 'off');
hold on;
grid on;

plot(tEcg, double(badLeadOff), 'DisplayName', 'Contact / lead warning');
plot(tEcg, double(badSaturation) + 1.2, 'DisplayName', 'Saturation warning');
plot(tEcg, double(badNoise) + 2.4, 'DisplayName', 'Noise warning');

ylim([-0.2 3.8]);
yticks([0 1.2 2.4]);
yticklabels({'Contact', 'Saturation', 'Noise'});
xlabel(ecgTimeLabel);
title('ECG quality flags from the recording');
legend('show');

%% Figure 4: MIC and IMU view if available

if hasMic || hasAccX || hasAccY || hasAccZ
    figure('Name', 'MotemaSens MIC and IMU', 'NumberTitle', 'off');
    hold on;
    grid on;

    if hasMic
        plot(tOther, robust_normalise(micTrace), 'DisplayName', 'MIC trace');
    end

    if hasMicLevel
        plot(tOther, robust_normalise(micLevel) - 1.5, 'DisplayName', 'MIC level');
    end

    if hasAccX
        plot(tOther, robust_normalise(accX) - 3.0, 'DisplayName', 'IMU X');
    end

    if hasAccY
        plot(tOther, robust_normalise(accY) - 4.5, 'DisplayName', 'IMU Y');
    end

    if hasAccZ
        plot(tOther, robust_normalise(accZ) - 6.0, 'DisplayName', 'IMU Z');
    end

    xlabel(otherTimeLabel);
    ylabel('Robust scaled traces');
    title('MIC and IMU overview');
    legend('show');
end

%% Local functions

function T = read_motemasens_file(fullFileName)
    [~, ~, ext] = fileparts(fullFileName);

    if strcmpi(ext, '.bin')
        T = read_motemasens_bin(fullFileName);
        return;
    end

    if strcmpi(ext, '.xlsx')
        T = readtable(fullFileName, 'VariableNamingRule', 'preserve');
    else
        opts = detectImportOptions(fullFileName, ...
            'FileType', 'text', ...
            'Delimiter', {'\t', ',', ';'});
        opts.VariableNamingRule = 'preserve';
        T = readtable(fullFileName, opts);
    end
end

function T = read_motemasens_bin(fullFileName)
    fid = fopen(fullFileName, 'rb', 'ieee-le');
    if fid < 0
        error('Could not open file: %s', fullFileName);
    end

    cleanupObj = onCleanup(@() fclose(fid));

    magic = fread(fid, 8, '*char')';
    if numel(magic) < 7 || ~strcmp(magic(1:7), 'MSLOGB1')
        error('This is not a recognised MotemaSens binary log.');
    end

    headerSize = fread(fid, 1, 'uint16');
    recordSize = fread(fid, 1, 'uint16');
    formatVersion = fread(fid, 1, 'uint32');
    startMs = fread(fid, 1, 'uint32'); %#ok<NASGU>
    channelMask = fread(fid, 1, 'uint8'); %#ok<NASGU>
    fread(fid, 3, 'uint8');
    firmwareVersionRaw = fread(fid, 40, '*char')'; %#ok<NASGU>

    if isempty(headerSize) || isempty(recordSize) || isempty(formatVersion)
        error('Binary log header is incomplete.');
    end

    if recordSize ~= 64
        error('Unsupported binary log record size: %d bytes.', recordSize);
    end

    if formatVersion ~= 1
        error('Unsupported binary log format version: %d.', formatVersion);
    end

    fileInfo = dir(fullFileName);
    recordCount = floor((fileInfo.bytes - double(headerSize)) / double(recordSize));
    if recordCount <= 0
        error('No records found in binary log.');
    end

    fseek(fid, double(headerSize), 'bof');

    LOG_HEADER = repmat({'LOG'}, recordCount, 1);
    ms = zeros(recordCount, 1);
    ecg_us = zeros(recordCount, 1);
    ecg_seq8 = zeros(recordCount, 1);
    ecg_seq = zeros(recordCount, 1);
    ecg_status = zeros(recordCount, 1);
    lead_i_raw = zeros(recordCount, 1);
    lead_ii_raw = zeros(recordCount, 1);
    lead_iii_raw = zeros(recordCount, 1);
    lead_off_p = zeros(recordCount, 1);
    lead_off_n = zeros(recordCount, 1);
    sat_mask = zeros(recordCount, 1);
    diag_flags = zeros(recordCount, 1);
    mic_ms = zeros(recordCount, 1);
    mic_seq8 = zeros(recordCount, 1);
    mic_trace = zeros(recordCount, 1);
    mic_level = zeros(recordCount, 1);
    acc_ms = zeros(recordCount, 1);
    acc_seq8 = zeros(recordCount, 1);
    acc_x_g = zeros(recordCount, 1);
    acc_y_g = zeros(recordCount, 1);
    acc_z_g = zeros(recordCount, 1);
    raw_x = zeros(recordCount, 1);
    raw_y = zeros(recordCount, 1);
    raw_z = zeros(recordCount, 1);
    acc_diag_flags = zeros(recordCount, 1);

    for row = 1:recordCount
        ms(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_us(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_seq(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_status(row) = double(fread_required(fid, 1, 'uint32'));
        lead_i_raw(row) = double(fread_required(fid, 1, 'int32'));
        lead_ii_raw(row) = double(fread_required(fid, 1, 'int32'));
        lead_iii_raw(row) = double(fread_required(fid, 1, 'int32'));
        mic_ms(row) = double(fread_required(fid, 1, 'uint32'));
        acc_ms(row) = double(fread_required(fid, 1, 'uint32'));
        mic_trace(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
        mic_level(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
        acc_x_g(row) = double(fread_required(fid, 1, 'int16')) / 1000.0;
        acc_y_g(row) = double(fread_required(fid, 1, 'int16')) / 1000.0;
        acc_z_g(row) = double(fread_required(fid, 1, 'int16')) / 1000.0;
        raw_x(row) = double(fread_required(fid, 1, 'int16'));
        raw_y(row) = double(fread_required(fid, 1, 'int16'));
        raw_z(row) = double(fread_required(fid, 1, 'int16'));
        diag_flags(row) = double(fread_required(fid, 1, 'uint16'));
        ecg_seq8(row) = double(fread_required(fid, 1, 'uint8'));
        lead_off_p(row) = double(fread_required(fid, 1, 'uint8'));
        lead_off_n(row) = double(fread_required(fid, 1, 'uint8'));
        sat_mask(row) = double(fread_required(fid, 1, 'uint8'));
        mic_seq8(row) = double(fread_required(fid, 1, 'uint8'));
        acc_seq8(row) = double(fread_required(fid, 1, 'uint8'));
        acc_diag_flags(row) = double(fread_required(fid, 1, 'uint8'));
        fread_required(fid, 3, 'uint8');
    end

    T = table(LOG_HEADER, ms, ecg_us, ecg_seq8, ecg_seq, ecg_status, ...
        lead_i_raw, lead_ii_raw, lead_iii_raw, lead_off_p, lead_off_n, ...
        sat_mask, diag_flags, mic_ms, mic_seq8, mic_trace, mic_level, ...
        acc_ms, acc_seq8, acc_x_g, acc_y_g, acc_z_g, raw_x, raw_y, raw_z, ...
        acc_diag_flags);
end

function value = fread_required(fid, count, precision)
    value = fread(fid, count, precision);
    if numel(value) ~= count
        error('Unexpected end of binary log while reading %s.', precision);
    end
end

function [t, labelText, fs] = make_time_axis(T, preferredNames)
    t = [];
    labelText = 'Sample number';
    fs = NaN;

    for i = 1:numel(preferredNames)
        name = preferredNames{i};
        if ismember(name, T.Properties.VariableNames)
            value = double(T.(name));
            if strcmpi(name, 'ecg_us')
                t = (value - value(1)) / 1e6;
                labelText = 'Time (s)';
            else
                t = (value - value(1)) / 1000;
                labelText = 'Time (s)';
            end
            break;
        end
    end

    if isempty(t)
        t = (0:height(T)-1)';
    end

    if numel(t) > 2
        dt = diff(t);
        dt = dt(isfinite(dt) & dt > 0);
        if ~isempty(dt)
            fs = 1 / median(dt);
        end
    end
end

function [x, found] = read_ecg_column(T, names)
    [x, found] = read_numeric_column(T, names);
    if found
        x = convert_ecg_24bit(x);
    end
end

function [x, found] = read_numeric_column(T, names)
    x = [];
    found = false;
    for i = 1:numel(names)
        name = names{i};
        if ismember(name, T.Properties.VariableNames)
            x = double(T.(name));
            found = true;
            return;
        end
    end
end

function values = read_hex_or_number_column(T, names)
    values = [];
    for i = 1:numel(names)
        name = names{i};
        if ismember(name, T.Properties.VariableNames)
            raw = T.(name);
            values = parse_hex_or_number(raw);
            return;
        end
    end
end

function y = parse_hex_or_number(raw)
    if isnumeric(raw)
        y = double(raw);
        return;
    end

    y = zeros(numel(raw), 1);
    for i = 1:numel(raw)
        if iscell(raw)
            txt = string(raw{i});
        else
            txt = string(raw(i));
        end
        txt = strtrim(txt);
        if startsWith(lower(txt), "0x")
            y(i) = hex2dec(extractAfter(txt, 2));
        elseif all(isstrprop(char(txt), 'xdigit')) && strlength(txt) <= 8
            y(i) = hex2dec(char(txt));
        else
            y(i) = str2double(txt);
        end
    end
end

function tf = bit_is_set(values, bitValue)
    tf = bitand(uint32(values), uint32(bitValue)) ~= 0;
end

function ecgSigned = convert_ecg_24bit(raw)
    raw = double(raw);

    if any(raw < 0)
        ecgSigned = raw;
        return;
    end

    rawU32 = uint32(raw);
    signBitSet = bitget(rawU32, 24) == 1;
    ecgSigned = int32(rawU32);
    ecgSigned(signBitSet) = ecgSigned(signBitSet) - int32(2^24);
    ecgSigned = double(ecgSigned);
end

function y = clean_ecg_for_viewing(x, fs)
    x = double(x);
    x = fillmissing(x, 'linear', 'EndValues', 'nearest');

    baselineWindow = max(3, round(0.7 * fs));
    if mod(baselineWindow, 2) == 0
        baselineWindow = baselineWindow + 1;
    end

    if exist('movmedian', 'file')
        baseline = movmedian(x, baselineWindow, 'omitnan');
    else
        baseline = movmean(x, baselineWindow, 'omitnan');
    end

    y = x - baseline;

    smoothWindow = max(1, round(0.015 * fs));
    y = movmean(y, smoothWindow, 'omitnan');

    y = apply_notch_50hz(y, fs);
end

function y = apply_notch_50hz(x, fs)
    f0 = 50;
    if fs <= (2 * f0)
        y = x;
        return;
    end

    q = 25;
    w0 = 2 * pi * f0 / fs;
    alpha = sin(w0) / (2 * q);

    b0 = 1;
    b1 = -2 * cos(w0);
    b2 = 1;
    a0 = 1 + alpha;
    a1 = -2 * cos(w0);
    a2 = 1 - alpha;

    b0 = b0 / a0;
    b1 = b1 / a0;
    b2 = b2 / a0;
    a1 = a1 / a0;
    a2 = a2 / a0;

    y = filter([b0 b1 b2], [1 a1 a2], x);
end

function y = robust_normalise(x)
    x = double(x);
    x = x - median(x, 'omitnan');
    absX = abs(x(isfinite(x)));

    if isempty(absX)
        y = x;
        return;
    end

    scale = robust_percentile(absX, 98);
    if scale == 0 || isnan(scale)
        scale = max(absX);
    end

    if scale == 0 || isnan(scale)
        y = x;
    else
        y = x / scale;
    end
end

function y = mask_bad(x, goodSamples)
    y = x;
    if numel(y) == numel(goodSamples)
        y(~goodSamples) = NaN;
    end
end

function plot_ecg_raw_and_clean(t, raw, clean, goodSamples, leadName)
    rawView = robust_normalise(raw);
    cleanView = robust_normalise(mask_bad(clean, goodSamples));

    plot(t, rawView, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Raw');
    hold on;
    plot(t, cleanView, 'b', 'LineWidth', 1.1, 'DisplayName', 'Clean display');
    grid on;
    ylabel(leadName);
    title([leadName ' - raw grey, cleaned blue']);
    legend('show');
end

function print_lead_stats(name, x)
    x = double(x);
    fprintf('%s raw range          : %.0f to %.0f\n', name, min(x), max(x));
    fprintf('%s robust amplitude   : %.0f\n', name, robust_percentile(abs(x - median(x, 'omitnan')), 98));
end

function p = percent(value, total)
    if total == 0
        p = 0;
    else
        p = 100 * value / total;
    end
end

function value = robust_percentile(x, percentileValue)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
        return;
    end

    x = sort(x(:));
    percentileValue = max(0, min(100, percentileValue));
    index = 1 + (numel(x) - 1) * percentileValue / 100;
    lowerIndex = floor(index);
    upperIndex = ceil(index);

    if lowerIndex == upperIndex
        value = x(lowerIndex);
    else
        fraction = index - lowerIndex;
        value = x(lowerIndex) * (1 - fraction) + x(upperIndex) * fraction;
    end
end
