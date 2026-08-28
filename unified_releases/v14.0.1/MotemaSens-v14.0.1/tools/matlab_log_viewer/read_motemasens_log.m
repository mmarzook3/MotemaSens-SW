function [T, info] = read_motemasens_log(fullFileName)
%READ_MOTEMASENS_LOG Read MotemaSens CSV or binary SD recordings.
% Supports binary formats v1 (64 bytes), v2 (80 bytes), v3 (92 bytes) and
% v4 typed independent ECG/MIC/IMU/GAP chunks.

    [~, ~, extension] = fileparts(fullFileName);
    if ~strcmpi(extension, '.bin')
        T = readtable(fullFileName, 'VariableNamingRule', 'preserve');
        info = struct('formatVersion', NaN, 'complete', NaN, ...
            'status', 'CSV input; binary session trailer is not applicable.');
        return;
    end

    fid = fopen(fullFileName, 'rb', 'ieee-le');
    if fid < 0
        error('Could not open file: %s', fullFileName);
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    magic = fread_required(fid, 8, '*char')';
    if numel(magic) < 7 || ~strcmp(magic(1:7), 'MSLOGB1')
        error('This is not a recognised MotemaSens binary log.');
    end

    headerSize = double(fread_required(fid, 1, 'uint16'));
    recordSize = double(fread_required(fid, 1, 'uint16'));
    formatVersion = double(fread_required(fid, 1, 'uint32'));
    startMs = double(fread_required(fid, 1, 'uint32')); %#ok<NASGU>
    channelMask = double(fread_required(fid, 1, 'uint8')); %#ok<NASGU>
    rateMetadata = fread_required(fid, 3, 'uint8');
    firmwareVersion = fread_required(fid, 40, '*char')'; %#ok<NASGU>

    fileInfo = dir(fullFileName);
    if formatVersion == 4
        if recordSize ~= 0
            error('Unsupported MotemaSens v4 header: recordSize must be zero.');
        end
        [T, info] = read_motemasens_v4(fid, headerSize, double(fileInfo.bytes), rateMetadata);
        return;
    end

    expectedSizes = [64, 80, 92];
    if formatVersion < 1 || formatVersion > numel(expectedSizes) || ...
            recordSize ~= expectedSizes(formatVersion)
        error('Unsupported MotemaSens format/version-size pair: v%d, %d bytes.', ...
            formatVersion, recordSize);
    end

    payloadBytes = double(fileInfo.bytes) - headerSize;
    dataBytes = payloadBytes;
    info = struct('formatVersion', formatVersion, 'recordSize', recordSize, ...
        'complete', false, 'trailerPresent', false, 'trailingBytes', 0, ...
        'status', 'Incomplete: clean-stop trailer missing.', 'trailer', struct());

    if formatVersion == 3 && payloadBytes >= 96
        fseek(fid, -96, 'eof');
        trailerMagic = fread_required(fid, 8, '*char')';
        if numel(trailerMagic) >= 7 && strcmp(trailerMagic(1:7), 'MSENDV3')
            trailerSize = double(fread_required(fid, 1, 'uint16'));
            trailerVersion = double(fread_required(fid, 1, 'uint16'));
            trailerValues = fread_required(fid, 11, 'uint32');
            trailerReserved = fread_required(fid, 40, 'uint8');
            if trailerSize == 96 && trailerVersion == 3
                dataBytes = payloadBytes - 96;
                info.trailerPresent = true;
                info.trailer = struct( ...
                    'recordCount', double(trailerValues(1)), ...
                    'elapsedMs', double(trailerValues(2)), ...
                    'payloadCrc32', double(trailerValues(3)), ...
                    'ecgInvalidFrames', double(trailerValues(4)), ...
                    'ecgAcquisitionOverruns', double(trailerValues(5)), ...
                    'micSamplesAcquired', double(trailerValues(6)), ...
                    'micFrameQueueDrops', double(trailerValues(7)), ...
                    'micLogUnderflows', double(trailerValues(8)), ...
                    'micLogRingDrops', double(trailerValues(9)), ...
                    'imuSamples', double(trailerValues(10)), ...
                    'sdDroppedRecords', double(trailerValues(11)), ...
                    'micSourceGapSamples', double(typecast(uint8(trailerReserved(1:4)), 'uint32')), ...
                    'ecgFramesReceived', double(typecast(uint8(trailerReserved(5:8)), 'uint32')), ...
                    'ecgSaturationEvents', double(typecast(uint8(trailerReserved(9:12)), 'uint32')), ...
                    'ecgLeadOffEvents', double(typecast(uint8(trailerReserved(13:16)), 'uint32')), ...
                    'ecgCableNoiseEvents', double(typecast(uint8(trailerReserved(17:20)), 'uint32')), ...
                    'ecgRldUnstableEvents', double(typecast(uint8(trailerReserved(21:24)), 'uint32')), ...
                    'ecgRegisterReadbackMismatches', double(typecast(uint8(trailerReserved(25:28)), 'uint32')), ...
                    'ecgConfigFlags', double(typecast(uint8(trailerReserved(29:32)), 'uint32')), ...
                    'imuMissedUpdates', double(typecast(uint8(trailerReserved(33:36)), 'uint32')), ...
                    'imuPollFailures', double(typecast(uint8(trailerReserved(37:40)), 'uint32')));
            else
                info.status = 'Incomplete: invalid v3 trailer header.';
            end
        end
    end

    recordCount = floor(dataBytes / recordSize);
    info.trailingBytes = mod(dataBytes, recordSize);
    if info.trailerPresent && info.trailingBytes == 0 && ...
            info.trailer.recordCount == recordCount
        info.complete = true;
        info.status = 'Complete: clean-stop trailer found. Use the Python converter to verify CRC32.';
    elseif info.trailerPresent && info.trailingBytes == 0
        info.status = 'Incomplete: trailer record count mismatch.';
    end
    if recordCount <= 0
        error('No records found in binary log.');
    end

    fseek(fid, headerSize, 'bof');
    ms = zeros(recordCount, 1); ecg_us = zeros(recordCount, 1);
    ecg_seq8 = zeros(recordCount, 1); ecg_seq = zeros(recordCount, 1);
    ecg_status = zeros(recordCount, 1); ecg_ch1_raw = zeros(recordCount, 1);
    ecg_ch2_raw = zeros(recordCount, 1); ecg_ch3_raw = zeros(recordCount, 1);
    ecg_ch4_raw = nan(recordCount, 1);
    lead_off_p = zeros(recordCount, 1); lead_off_n = zeros(recordCount, 1);
    sat_mask = zeros(recordCount, 1); diag_flags = zeros(recordCount, 1);
    mic_ms = zeros(recordCount, 1); mic_seq8 = zeros(recordCount, 1);
    mic_trace = zeros(recordCount, 1); mic_level = zeros(recordCount, 1);
    mic_first_us = nan(recordCount, 1); mic_sample_seq = nan(recordCount, 1);
    mic_raw_0 = nan(recordCount, 1); mic_raw_1 = nan(recordCount, 1);
    mic_raw_2 = nan(recordCount, 1); mic_raw_3 = nan(recordCount, 1);
    acc_ms = zeros(recordCount, 1); acc_seq8 = zeros(recordCount, 1);
    acc_x_g = zeros(recordCount, 1); acc_y_g = zeros(recordCount, 1);
    acc_z_g = zeros(recordCount, 1); raw_x = zeros(recordCount, 1);
    raw_y = zeros(recordCount, 1); raw_z = zeros(recordCount, 1);
    acc_diag_flags = zeros(recordCount, 1);
    mic_block_valid_mask = nan(recordCount, 1); mic_missing_count = nan(recordCount, 1);
    mic_block_reason = repmat({''}, recordCount, 1); imu_valid = nan(recordCount, 1);
    imu_age_us = nan(recordCount, 1); imu_sample_seq = nan(recordCount, 1);
    log_format_version = repmat(formatVersion, recordCount, 1);

    for row = 1:recordCount
        ms(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_us(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_seq(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_status(row) = double(fread_required(fid, 1, 'uint32'));
        ecg_ch1_raw(row) = double(fread_required(fid, 1, 'int32'));
        ecg_ch2_raw(row) = double(fread_required(fid, 1, 'int32'));
        ecg_ch3_raw(row) = double(fread_required(fid, 1, 'int32'));
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

        if formatVersion >= 2
            mic_first_us(row) = double(fread_required(fid, 1, 'uint32'));
            mic_sample_seq(row) = double(fread_required(fid, 1, 'uint32'));
            mic_raw_0(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
            mic_raw_1(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
            mic_raw_2(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
            mic_raw_3(row) = double(fread_required(fid, 1, 'int16')) / 32767.0;
        end
        if formatVersion == 3
            mic_block_valid_mask(row) = double(fread_required(fid, 1, 'uint8'));
            mic_missing_count(row) = double(fread_required(fid, 1, 'uint8'));
            mic_block_reason{row} = mic_reason(double(fread_required(fid, 1, 'uint8')));
            imu_valid(row) = double(fread_required(fid, 1, 'uint8'));
            imu_age_us(row) = double(fread_required(fid, 1, 'uint32'));
            imu_sample_seq(row) = double(fread_required(fid, 1, 'uint32'));
        end
    end

    ecg_valid = bitand(uint32(ecg_status), uint32(hex2dec('F00000'))) == ...
        uint32(hex2dec('C00000')) & bitand(uint16(diag_flags), uint16(hex2dec('0040'))) == 0;
    ecg_ch1_raw(~ecg_valid) = NaN;
    ecg_ch2_raw(~ecg_valid) = NaN;
    ecg_ch3_raw(~ecg_valid) = NaN;
    lead_i = ecg_ch1_raw;
    lead_ii = ecg_ch2_raw;
    lead_iii_derived = ecg_ch2_raw - ecg_ch1_raw;

    LOG_HEADER = repmat({'LOG'}, recordCount, 1);
    T = table(LOG_HEADER, ms, ecg_us, ecg_seq8, ecg_seq, ecg_status, ...
        ecg_valid, ecg_ch1_raw, ecg_ch2_raw, ecg_ch3_raw, ecg_ch4_raw, ...
        lead_i, lead_ii, lead_iii_derived, lead_off_p, lead_off_n, sat_mask, ...
        diag_flags, mic_ms, mic_seq8, mic_trace, mic_level, mic_first_us, ...
        mic_sample_seq, mic_raw_0, mic_raw_1, mic_raw_2, mic_raw_3, acc_ms, ...
        acc_seq8, acc_x_g, acc_y_g, acc_z_g, raw_x, raw_y, raw_z, acc_diag_flags, ...
        mic_block_valid_mask, mic_missing_count, mic_block_reason, imu_valid, ...
        imu_age_us, imu_sample_seq, log_format_version);
end

function value = fread_required(fid, count, precision)
    value = fread(fid, count, precision);
    if numel(value) ~= count
        error('Unexpected end of binary log while reading %s.', precision);
    end
end

function label = mic_reason(value)
    labels = {'complete', 'disabled', 'startup_sync', 'queue_underflow', 'queue_drop', 'ring_drop', 'source_gap'};
    if value >= 0 && value < numel(labels)
        label = labels{value + 1};
    else
        label = sprintf('unknown_%d', value);
    end
end
