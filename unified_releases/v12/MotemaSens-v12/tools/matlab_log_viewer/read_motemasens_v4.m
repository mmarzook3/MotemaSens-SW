function [T, info] = read_motemasens_v4(fid, headerSize, fileBytes)
%READ_MOTEMASENS_V4 Decode and verify independent v4 acquisition streams.
% Invalid acquisition values and missing samples remain NaN. No interpolation,
% repeated values, display filtering or timeline compression is performed.

    trailerSize = 152;
    dataEnd = fileBytes;
    trailerPresent = false;
    trailer = struct();
    if fileBytes >= headerSize + trailerSize
        fseek(fid, -trailerSize, 'eof');
        magic = fread_exact(fid, 8, '*char')';
        if numel(magic) >= 7 && strcmp(magic(1:7), 'MSENDV4')
            sizeValue = double(fread_exact(fid, 1, 'uint16'));
            version = double(fread_exact(fid, 1, 'uint16'));
            if sizeValue == trailerSize && version == 4
                trailerPresent = true;
                dataEnd = fileBytes - trailerSize;
                trailer = read_trailer(fid);
            end
        end
    end

    rows = repmat(new_row('', 0, 0, false), 0, 1);
    gaps = [0 0 0];
    diagnostics = struct();
    parsedChunks = 0;
    trailingBytes = 0;
    fseek(fid, headerSize, 'bof');
    while ftell(fid) < dataEnd
        chunkStart = ftell(fid);
        if chunkStart + 16 > dataEnd
            trailingBytes = dataEnd - chunkStart;
            break;
        end
        chunkType = double(fread_exact(fid, 1, 'uint8'));
        flags = double(fread_exact(fid, 1, 'uint8'));
        payloadSize = double(fread_exact(fid, 1, 'uint16'));
        sequence = double(fread_exact(fid, 1, 'uint32'));
        sessionUs = double(fread_exact(fid, 1, 'uint64'));
        expectedSizes = [28 20 16 20 144];
        if chunkType < 1 || chunkType > 5 || payloadSize ~= expectedSizes(chunkType) || ...
                ftell(fid) + payloadSize > dataEnd
            trailingBytes = dataEnd - chunkStart;
            break;
        end
        payload = fread_exact(fid, payloadSize, 'uint8');
        parsedChunks = parsedChunks + 1;

        if chunkType == 1
            row = decode_ecg(payload, flags, sessionUs, sequence);
            rows(end+1,1) = row; %#ok<AGROW>
        elseif chunkType == 2
            count = min(double(u16(payload, 1)), 8);
            samples = typecast(uint8(payload(5:20)), 'int16');
            valid = bitand(flags, 1) ~= 0;
            for index = 0:count-1
                row = new_row('MIC', sessionUs + index * 500, ...
                    mod(sequence + index, 2^32), valid);
                row.mic_block_sample_count = count;
                row.mic_block_sample_index = index;
                if valid; row.mic_sample = double(samples(index + 1)); end
                rows(end+1,1) = row; %#ok<AGROW>
            end
        elseif chunkType == 3
            values = typecast(uint8(payload(1:12)), 'int16');
            valid = bitand(flags, 1) ~= 0;
            row = new_row('IMU', sessionUs, sequence, valid);
            row.imu_diag_flags = double(payload(13));
            if valid
                row.imu_x_g = double(values(1)) / 1000;
                row.imu_y_g = double(values(2)) / 1000;
                row.imu_z_g = double(values(3)) / 1000;
                row.raw_x = double(values(4)); row.raw_y = double(values(5));
                row.raw_z = double(values(6));
            end
            rows(end+1,1) = row; %#ok<AGROW>
        elseif chunkType == 4
            streamId = double(payload(1));
            reason = double(payload(2));
            missing = double(u64(payload, 5));
            expected = double(u32(payload, 13));
            next = double(u32(payload, 17));
            streamName = stream_name(streamId);
            row = gap_row('GAP', streamName, reason, missing, expected, next, ...
                sessionUs, sequence, NaN);
            rows(end+1,1) = row; %#ok<AGROW>
            if streamId >= 1 && streamId <= 3
                gaps(streamId) = gaps(streamId) + missing;
                periods = [2000 500 8000];
                for index = 0:missing-1
                    row = gap_row([streamName '_MISSING'], streamName, reason, ...
                        missing, expected, next, sessionUs + index * periods(streamId), ...
                        mod(expected + index, 2^32), index);
                    rows(end+1,1) = row; %#ok<AGROW>
                end
            end
        else
            diagnostics = decode_diagnostics(payload);
            row = new_row('SESSION_DIAGNOSTICS', sessionUs, sequence, true);
            names = fieldnames(diagnostics);
            for index = 1:numel(names)
                name = names{index};
                if isfield(row, name); row.(name) = diagnostics.(name); end
            end
            rows(end+1,1) = row; %#ok<AGROW>
        end
    end

    crcValid = false;
    if trailerPresent
        crcValid = crc32_region(fid, headerSize, dataEnd - headerSize) == trailer.payloadCrc32;
    end
    complete = trailerPresent && trailingBytes == 0 && crcValid && ...
        parsedChunks == trailer.chunkCount;
    quality = classify_quality(complete, trailerPresent, trailer, gaps, diagnostics);
    for index = 1:numel(rows); rows(index).session_quality = quality; end
    T = struct2table(rows);
    timingReady = strcmp(quality, 'complete');
    if timingReady
        status = 'V4 COMPLETE: CRC32, chunk count and stream accounting verified.';
    else
        status = sprintf('V4 %s: review diagnostics and explicit gaps before analysis.', upper(quality));
    end
    info = struct('formatVersion', 4, 'recordSize', 0, 'complete', complete, ...
        'trailerPresent', trailerPresent, 'trailingBytes', trailingBytes, ...
        'crcValid', crcValid, 'parsedChunks', parsedChunks, 'trailer', trailer, ...
        'gapSamples', gaps, 'sessionDiagnostics', diagnostics, 'quality', quality, ...
        'timingReady', timingReady, 'status', status);
end

function trailer = read_trailer(fid)
    trailer.chunkCount = double(fread_exact(fid, 1, 'uint32'));
    trailer.elapsedUs = double(fread_exact(fid, 1, 'uint64'));
    trailer.payloadCrc32 = double(fread_exact(fid, 1, 'uint32'));
    trailer.ecgConfigFlags = double(fread_exact(fid, 1, 'uint32'));
    counters = double(fread_exact(fid, 15, 'uint64'));
    names = {'ecgFramesReceived','ecgInvalidFrames','ecgAcquisitionOverruns', ...
        'ecgLateFrames','ecgSaturationEvents','ecgLeadOffEvents', ...
        'ecgRegisterReadbackMismatches','micSamplesAcquired','micSamplesPersisted', ...
        'micExplicitGapSamples','micFrameQueueDrops','imuSamples','imuMissedUpdates', ...
        'imuPollFailures','sdDroppedChunks'};
    for index = 1:numel(names); trailer.(names{index}) = counters(index); end
end

function row = decode_ecg(payload, flags, sessionUs, sequence)
    status = double(u32(payload, 1));
    channels = typecast(uint8(payload(5:20)), 'int32');
    diagnostics = double(u16(payload, 21));
    valid = bitand(flags, 1) ~= 0 && ...
        bitand(uint32(status), uint32(hex2dec('F00000'))) == uint32(hex2dec('C00000')) && ...
        bitand(uint16(diagnostics), uint16(hex2dec('0040'))) == 0;
    row = new_row('ECG', sessionUs, sequence, valid);
    row.ecg_status = status; row.diag_flags = diagnostics;
    row.frame_read_delay_us = double(u16(payload, 23));
    row.lead_off_p = double(payload(25)); row.lead_off_n = double(payload(26));
    row.sat_mask = double(payload(27));
    if valid
        row.ecg_ch1_raw = double(channels(1)); row.ecg_ch2_raw = double(channels(2));
        row.ecg_ch3_raw = double(channels(3)); row.ecg_ch4_raw = double(channels(4));
        row.lead_i = row.ecg_ch1_raw; row.lead_ii = row.ecg_ch2_raw;
        row.lead_iii_derived = row.ecg_ch2_raw - row.ecg_ch1_raw;
    end
end

function row = gap_row(kind, stream, reason, missing, expected, next, sessionUs, sequence, index)
    row = new_row(kind, sessionUs, sequence, false);
    row.gap_stream = stream; row.gap_reason = reason; row.gap_missing_samples = missing;
    row.gap_expected_sequence = expected; row.gap_next_sequence = next; row.missing_index = index;
end

function row = new_row(stream, sessionUs, sequence, valid)
    row = struct('stream', stream, 'session_us', sessionUs, 'sequence', sequence, ...
        'valid', logical(valid), 'ecg_status', NaN, 'ecg_ch1_raw', NaN, ...
        'ecg_ch2_raw', NaN, 'ecg_ch3_raw', NaN, 'ecg_ch4_raw', NaN, ...
        'lead_i', NaN, 'lead_ii', NaN, 'lead_iii_derived', NaN, ...
        'lead_off_p', NaN, 'lead_off_n', NaN, 'sat_mask', NaN, ...
        'diag_flags', NaN, 'frame_read_delay_us', NaN, ...
        'mic_block_sample_count', NaN, 'mic_block_sample_index', NaN, ...
        'mic_sample', NaN, 'imu_x_g', NaN, 'imu_y_g', NaN, 'imu_z_g', NaN, ...
        'raw_x', NaN, 'raw_y', NaN, 'raw_z', NaN, 'imu_diag_flags', NaN, ...
        'gap_stream', '', 'gap_reason', NaN, 'gap_missing_samples', NaN, ...
        'gap_expected_sequence', NaN, 'gap_next_sequence', NaN, 'missing_index', NaN, ...
        'session_quality', '', 'diagnostics_schema', NaN, 'core1_max_stall_us', NaN, ...
        'core1_max_busy_us', NaN, 'sd_max_write_us', NaN, 'ecg_queue_high_water', NaN, ...
        'mic_queue_high_water', NaN, 'imu_queue_high_water', NaN, ...
        'storage_operations_rejected', NaN, 'start_ack_us', NaN, 'stop_ack_us', NaN, ...
        'discarded_pre_session_ecg', NaN, 'discarded_pre_session_mic', NaN, ...
        'discarded_pre_session_imu', NaN, 'ecg_queue_dropped', NaN, ...
        'mic_queue_dropped', NaN, 'imu_queue_dropped', NaN, 'sd_write_failures', NaN, ...
        'ecg_first_sequence', NaN, 'ecg_last_sequence', NaN, 'ecg_first_us', NaN, ...
        'ecg_last_us', NaN, 'mic_first_sequence', NaN, 'mic_last_sequence', NaN, ...
        'mic_first_us', NaN, 'mic_last_us', NaN, 'imu_first_sequence', NaN, ...
        'imu_last_sequence', NaN, 'imu_first_us', NaN, 'imu_last_us', NaN, ...
        'log_format_version', 4);
end

function diagnostics = decode_diagnostics(payload)
    qualityNames = {'unverified','complete','minor_loss','failed'};
    qualityIndex = min(max(double(payload(5)) + 1, 1), numel(qualityNames));
    diagnostics = struct('diagnostics_schema', double(u16(payload, 1)), ...
        'quality', qualityNames{qualityIndex}, 'core1_max_stall_us', double(u32(payload, 9)), ...
        'core1_max_busy_us', double(u32(payload, 13)), 'sd_max_write_us', double(u32(payload, 17)), ...
        'ecg_queue_high_water', double(u16(payload, 21)), 'mic_queue_high_water', double(u16(payload, 23)), ...
        'imu_queue_high_water', double(u16(payload, 25)), 'storage_operations_rejected', double(u32(payload, 29)), ...
        'start_ack_us', double(u32(payload, 33)), 'stop_ack_us', double(u32(payload, 37)), ...
        'discarded_pre_session_ecg', double(u32(payload, 41)), ...
        'discarded_pre_session_mic', double(u32(payload, 45)), ...
        'discarded_pre_session_imu', double(u32(payload, 49)), ...
        'ecg_queue_dropped', double(u32(payload, 53)), 'mic_queue_dropped', double(u32(payload, 57)), ...
        'imu_queue_dropped', double(u32(payload, 61)), 'sd_write_failures', double(u32(payload, 65)), ...
        'ecg_first_sequence', double(u32(payload, 73)), 'ecg_last_sequence', double(u32(payload, 77)), ...
        'ecg_first_us', double(u64(payload, 81)), 'ecg_last_us', double(u64(payload, 89)), ...
        'mic_first_sequence', double(u32(payload, 97)), 'mic_last_sequence', double(u32(payload, 101)), ...
        'mic_first_us', double(u64(payload, 105)), 'mic_last_us', double(u64(payload, 113)), ...
        'imu_first_sequence', double(u32(payload, 121)), 'imu_last_sequence', double(u32(payload, 125)), ...
        'imu_first_us', double(u64(payload, 129)), 'imu_last_us', double(u64(payload, 137)));
end

function quality = classify_quality(complete, trailerPresent, trailer, gaps, diagnostics)
    if ~complete
        if trailerPresent; quality = 'failed'; else; quality = 'unverified'; end
        return;
    end
    micMismatch = trailer.micSamplesAcquired ~= ...
        trailer.micSamplesPersisted + trailer.micExplicitGapSamples;
    excessiveLoss = loss_ppm(gaps(1), trailer.ecgFramesReceived) >= 10000 || ...
        loss_ppm(gaps(2), trailer.micSamplesPersisted) >= 10000 || ...
        loss_ppm(gaps(3), trailer.imuSamples) >= 10000;
    diagnosticFailure = ~isempty(fieldnames(diagnostics)) && ...
        (strcmp(diagnostics.quality, 'failed') || diagnostics.sd_write_failures ~= 0);
    if trailer.sdDroppedChunks ~= 0 || micMismatch || excessiveLoss || diagnosticFailure
        quality = 'failed'; return;
    end
    warning = any(gaps ~= 0) || trailer.ecgInvalidFrames ~= 0 || ...
        trailer.ecgAcquisitionOverruns ~= 0 || ...
        trailer.ecgSaturationEvents ~= 0 || trailer.ecgLeadOffEvents ~= 0 || ...
        trailer.ecgRegisterReadbackMismatches ~= 0 || trailer.micFrameQueueDrops ~= 0 || ...
        trailer.imuMissedUpdates ~= 0 || trailer.imuPollFailures ~= 0;
    if ~isempty(fieldnames(diagnostics))
        warning = warning || strcmp(diagnostics.quality, 'minor_loss') || ...
            diagnostics.ecg_queue_dropped ~= 0 || diagnostics.mic_queue_dropped ~= 0 || ...
            diagnostics.imu_queue_dropped ~= 0;
    end
    if warning; quality = 'minor_loss'; else; quality = 'complete'; end
end

function ppm = loss_ppm(missing, persisted)
    total = missing + persisted;
    if missing == 0 || total == 0; ppm = 0; else; ppm = min(1000000, floor(missing * 1000000 / total)); end
end

function name = stream_name(streamId)
    names = {'ECG','MIC','IMU'};
    if streamId >= 1 && streamId <= 3
        name = names{streamId};
    else
        name = sprintf('UNKNOWN_%d', streamId);
    end
end

function value = u16(payload, offset)
    value = typecast(uint8(payload(offset:offset+1)), 'uint16');
end

function value = u32(payload, offset)
    value = typecast(uint8(payload(offset:offset+3)), 'uint32');
end

function value = u64(payload, offset)
    value = typecast(uint8(payload(offset:offset+7)), 'uint64');
end

function crc = crc32_region(fid, offset, count)
    persistent lookupTable
    if isempty(lookupTable)
        lookupTable = zeros(256, 1, 'uint32');
        polynomial = uint32(hex2dec('EDB88320'));
        for index = 0:255
            value = uint32(index);
            for bit = 1:8
                if bitand(value, uint32(1))
                    value = bitxor(bitshift(value, -1), polynomial);
                else
                    value = bitshift(value, -1);
                end
            end
            lookupTable(index + 1) = value;
        end
    end
    original = ftell(fid); fseek(fid, offset, 'bof');
    value = uint32(hex2dec('FFFFFFFF')); remaining = count;
    while remaining > 0
        block = fread(fid, min(65536, remaining), 'uint8=>uint8');
        if isempty(block); break; end
        for index = 1:numel(block)
            key = bitand(bitxor(value, uint32(block(index))), uint32(255));
            value = bitxor(bitshift(value, -8), lookupTable(double(key) + 1));
        end
        remaining = remaining - numel(block);
    end
    crc = double(bitcmp(value)); fseek(fid, original, 'bof');
end

function value = fread_exact(fid, count, precision)
    value = fread(fid, count, precision);
    if numel(value) ~= count; error('Unexpected end of v4 binary log.'); end
end
