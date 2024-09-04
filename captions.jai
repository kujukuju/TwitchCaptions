
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Windows";
#import "Process";
#import "String";
#import "Curl";
#import "FixedStringJai";
#import "ContiguousJsonJai";
#import "stb_image_write";
#import "KodaMicroHttp";
#import "Thread";
#import "WhisperJai";

GetWindowTextA :: (hwnd: HWND, lpstring: LPSTR, max: s32) -> s32 #foreign user32;
CreateDIBSection :: (hdc: HDC, bmi: *BITMAPINFO, usage: u32, ppvBits: **void, hSection: HANDLE, offset: DWORD) -> HBITMAP #foreign gdi;
IsWindow :: (hwnd: HWND) -> bool #foreign user32;
c_free :: (memory: *void) #foreign crt "free";

user32 :: #system_library "user32";
gdi :: #system_library "Gdi32";
crt :: #system_library "msvcrt";

replacement_line := false;
captured_lines: [..] FixedString(4096);
captured_indices: [..] int;
changed_times: [..] float64;
translated_lines: [..] FixedString(4096);
translated: [..] bool;

next_index := 0;

deepl_secret: string;

mutex: Mutex;

// if you want very instant translations using up a ton of translation tokens you would have like 50, 50
// if you want very instant translations using up a moderate amount of translation tokens you have would have like 200, 50
// if you want very slow translations using up very few tokens you would have like 50, 500
translation_delay :: 50;
translation_stable_delay :: 500;

command_lines: [..] string;
command_mutex: Mutex;

original_language: string;
target_language: string;
model: string;
lines: int;
display_original_language: bool;
use_local_english_translations: bool;
include_notes: bool;
step: string;
length: string;

main :: () {
    init(*mutex);
    init(*command_mutex);

    config_file, config_file_success := read_entire_file("config.txt");
    if !config_file_success {
        print("Could not load config.txt.\n");
        return;
    }

    // remove rn
    config_file_index := 0;
    config_file_replace := 0;
    while config_file_index < config_file.count - 1 {
        if config_file[config_file_index] == #char "\r" && config_file[config_file_index + 1] == #char "\n" {
            config_file_index += 1;
        } else {
            config_file_index += 1;
            config_file_replace += 1;
        }
        config_file[config_file_replace] = config_file[config_file_index];
    }
    config_file.count -= (config_file_index - config_file_replace);

    original_language = "en";
    target_language = "ja";
    model = "ggml-medium";
    lines = 3;
    display_original_language = true;
    use_local_english_translations = false;
    include_notes = false;
    step = "1200";
    length = "10000";

    // get config
    config_lines := split(config_file, "\n");
    for line: config_lines {
        if !line {
            continue;
        }

        part1 := line;
        part2 := line;

        for i: 0..line.count - 1 {
            if line[i] == #char " " {
                part1.count = i;
                break;
            }
        }

        for i: 0..line.count - 1 {
            if line[i] == #char " " {
                part2.data = line.data + i + 1;
                part2.count = line.count - i - 1;
            }
        }

        to_lower_in_place(part2);

        if part1 == {
            case "original_language";
                original_language = part2;
            case "target_language";
                target_language = part2;
            case "model";
                model = part2;
            case "lines";
                lines = parse_int(*part2);
            case "display_original_language";
                display_original_language = part2 == "true";
            case "use_local_english_translations";
                use_local_english_translations = part2 == "true";
            case "include_notes";
                include_notes = part2 == "true";
            case "step";
                step = part2;
            case "length";
                length = part2;
            case;
        }
    }

    if use_local_english_translations && target_language != "en" {
        print("You enabled \"use_local_english_translations\" but \"target_language\" isn't english. You can't do this. Ignoring \"use_local_english_translations\".\n");
        use_local_english_translations = false;
    }
    if use_local_english_translations && display_original_language {
        print("You enabled \"use_local_english_translations\" and \"display_original_language\". You can't do both, because the local translations override the captions. Ignoring \"use_local_english_translations\".\n");
        use_local_english_translations = false;
    }

    if original_language == "en" {
        model = sprint("%.en.bin", model);
    } else {
        model = sprint("%.bin", model);
    }

    if !file_exists(model) {
        print("Could not find model file %.\n", model);
    }

    thread: Thread;
    thread_init(*thread, (thread: *Thread) -> s64 {
        translate := ifx use_local_english_translations then "--translate" else "";

        run_command_continuous("stream.exe", "-m", model, "-l", original_language, translate, "--step", step, "--length", length, lines = *command_lines, mutex = *command_mutex, capture_and_return_output = true);
        return 0;
    });
    thread_start(*thread);

    server := create_server(9000);
    server.extra_headers = .[
        .["Access-Control-Allow-Origin", "*"],
        .["Access-Control-Allow-Methods", "GET, POST, OPTIONS"],
        .["Access-Control-Allow-Headers", "Content-Type"],
    ];
    handle(server, .Get, "*", (request: *HttpRequest, response: *HttpResponse, path: string) -> HttpResult {
        if contains(path, "..") {
            return reply(response, 404);
        }

        file_path: string;
        if path == "" || path == "/" {
            file_path = "server/index.html";
        } else {
            file_path = tprint("server/%", path);
        }
        file, found := read_entire_file(file_path, zero_terminated = true);
        if !found {
            free(file);
            return reply(response, 404);
        }

        content_type: *u8 = "text/plain";
        if ends_with_nocase(file_path, "html") {
            content_type = "text/html";
        } else if ends_with_nocase(file_path, "js") {
            content_type = "text/javascript";
        } else if ends_with_nocase(file_path, "ttf") {
            content_type = "font/ttf";
        } else if ends_with_nocase(file_path, "css") {
            content_type = "text/css";
        }
        
        return reply(response, 200, .[.["Content-Type", content_type]], file.data, .Allocated);
    });

    handle(server, .Get, "/captions", (request: *HttpRequest, response: *HttpResponse) -> HttpResult {
        lock(*mutex);
        defer unlock(*mutex);

        builder: String_Builder;

        append(*builder, "[");
        for *line, index: captured_lines {
            number_string := create_fixed_string(captured_indices[index]);
            append(*builder, "[");
            append(*builder, to_string(*number_string));
            append(*builder, ",");
            if display_original_language {
                append(*builder, "\"");
                append(*builder, to_string(line));
                append(*builder, "\",");
            }
            append(*builder, "\"");
            append(*builder, to_string(*translated_lines[index]));
            append(*builder, "\"");
            append(*builder, "]");

            if index < captured_lines.count - 1  {
                append(*builder, ",");
            }
        }
        append(*builder, "]\0");

        json_string := builder_to_string(*builder);
        
        return reply(response, 200, .[.["Content-Type", "application/json"]], json_string.data, .Allocated);
    });

    server_listen_async(server);
    defer server_stop(server);

    deepl_success: bool;
    deepl_secret, deepl_success = read_entire_file("secrets/deepl.txt");
    if !deepl_success {
        print("Could not read deepl secret!\n");
        return;
    }

    while true {
        reset_temporary_storage();
        
        read_caption_lines();
        translate_text();

        sleep_milliseconds(translation_delay);
    }
}

read_caption_lines :: () {
    lock(*command_mutex);
    defer unlock(*command_mutex);

    lock(*mutex);
    defer unlock(*mutex);

    time := seconds_since_init() * 1000;

    for line: command_lines {
        real_line := line;

        i := 0;
        while i < real_line.count - 4 {
            if real_line[i] == 27 && real_line[i + 1] == 91 && real_line[i + 2] == 50 && real_line[i + 3] == 75 {
                real_line.data += i + 4;
                real_line.count -= i + 4;
                i = 0;
            } else {
                i += 1;
            }
        }

        final_line := real_line.count >= 2 && real_line[real_line.count - 2] == 13 && real_line[real_line.count - 1] == 10;

        while real_line.count >= 1 && (real_line[0] == 10 || real_line[0] == 13 || real_line[0] == 32) {
            real_line.data += 1;
            real_line.count -= 1;
        }

        while real_line.count >= 1 && (real_line[real_line.count - 1] == 10 || real_line[real_line.count - 1] == 13 || real_line[real_line.count - 1] == 32) {
            real_line.count -= 1;
        }

        if real_line.count == 0 {
            continue;
        }

        is_note_char :: (char: int) -> bool {
            return char == #char "(" ||char == #char "[" || char == #char ")" ||char == #char "]" || char == #char "*";
        }

        if !include_notes && is_note_char(real_line[0]) && is_note_char(real_line[real_line.count - 1]) {
            continue;
        }

        replacement := true;
        if !replacement_line {
            replacement = false;
        }
        replacement_line = !final_line;

        // print("% %\n", replacement_line, real_line);
        // for i: 0..line.count - 1 {
        //     print("% ", line[i]);
        // }
        // print("\n\n");

        fixed_line := create_fixed_string(real_line, 4096);

        if replacement && captured_lines.count > 0 {
            exact_match := captured_lines.count > 0 && captured_lines[captured_lines.count - 1] == fixed_line;
            if !exact_match {
                if use_local_english_translations {
                    translated_lines[captured_lines.count - 1] = fixed_line;
                    changed_times[captured_lines.count - 1] = time;
                    translated[captured_lines.count - 1] = true;
                } else {
                    captured_lines[captured_lines.count - 1] = fixed_line;
                    changed_times[captured_lines.count - 1] = time;
                    translated[captured_lines.count - 1] = false;
                }
            }
        } else {
            if use_local_english_translations {
                array_add(*captured_lines, FixedString(4096).{});
                array_add(*captured_indices, next_index);
                array_add(*changed_times, time);
                array_add(*translated_lines, fixed_line);
                array_add(*translated, true);
            } else {
                array_add(*captured_lines, fixed_line);
                array_add(*captured_indices, next_index);
                array_add(*changed_times, time);
                array_add(*translated_lines, FixedString(4096).{});
                array_add(*translated, false);
            }

            next_index += 1;
        }
    }

    for line: command_lines {
        free(line);
    }
    command_lines.count = 0;

    while captured_lines.count > lines {
        array_ordered_remove_by_index(*captured_lines, 0);
        array_ordered_remove_by_index(*captured_indices, 0);
        array_ordered_remove_by_index(*changed_times, 0);
        array_ordered_remove_by_index(*translated_lines, 0);
        array_ordered_remove_by_index(*translated, 0);
    }
}

translate_text :: () {
    time := seconds_since_init() * 1000;

    desired_translations: [..] FixedString(4096);
    desired_translations.allocator = temp;

    desired_indices: [..] int;
    desired_indices.allocator = temp;

    for captured_line, captured_index: captured_lines {
        if !translated[captured_index] && time - changed_times[captured_index] > translation_stable_delay {
            array_add(*desired_translations, captured_lines[captured_index]);
            array_add(*desired_indices, captured_index);
        }
    }

    if desired_translations.count == 0 {
        return;
    }

    deepl_valid, deepl_response := deepl_request_post("https://api-free.deepl.com/v2/translate", tprint("Authorization: DeepL-Auth-Key %\0", deepl_secret).data, desired_translations);
    if !deepl_valid {
        print("Could not request translation!\n");
        return;
    }

    translations := get_translations_from_json(get_unicode(deepl_response));
    defer {
        for translation: translations {
            free(translation);
        }
    }

    if translations.count != desired_translations.count {
        print("Received back incorrect number of translations... % != %\n", desired_translations.count, translations.count);
        print("%\n", deepl_response);
        return;
    }

    lock(*mutex);
    defer unlock(*mutex);

    for translation, index: translations {
        translated[desired_indices[index]] = true;
        translated_lines[desired_indices[index]] = create_fixed_string(get_string(translation), 4096);
    }

    print("Translations:\n---\n");
    for line: captured_lines {
        print("%\n", to_string(*line));
    }

    print("---\n");

    for line: translated_lines {
        print("%\n", to_string(*line));
    }
    print("\n");
}

get_translations_from_json :: (response: Unicode) -> [..] Unicode {
    translations: [..] Unicode;
    translations.allocator = temp;

    found_translations := false;
    inside_translations := false;

    found_text := false;
    inside_text := 0;

    escape := false;

    is_string :: (response: Unicode, index: int, expected: string) -> bool {
        matches := true;
        index_offset := 0;
        while index + index_offset < response.count && index_offset < expected.count && matches {
            matches = matches && response.data[index + index_offset] == expected[index_offset];
            index_offset += 1;
        }
        matches = matches && index_offset == expected.count;
        return matches;
    }

    current_translation: string;

    for character, index: response {
        if !found_translations && !inside_translations && is_string(response, index, "translations") {
            found_translations = true;
        } else if found_translations && !inside_translations && character == #char "[" {
            found_translations = false;
            inside_translations = true;
        } else if inside_translations && !found_text && is_string(response, index, "text") {
            found_text = true;
        } else if found_text && inside_text == 0 && character == #char ":" {
            found_text = false;
            inside_text = 1;
        } else if inside_text == 1 && character == #char "\"" {
            found_text = false;
            inside_text = 2;

            current_translation.data = response.data + index + 1;
            current_translation.count = 0;
        } else if inside_text == 2 && character == #char "\"" && !escape {
            inside_text = 0;

            current_translation.count = index - (current_translation.data - response.data);
            array_add(*translations, get_unicode(current_translation));
        }

        if inside_text == 2 && character == #char "\\" {
            escape = true;
        } else {
            escape = false;
        }
    }

    for unicode, index: translations {
        builder: String_Builder;
        current_line: string;
        for character, index: unicode {
            if !current_line.data {
                current_line.data = unicode.data + index;
            }

            current_line.count = index - (current_line.data - unicode.data);

            if index > 0 && unicode.data[index - 1] == #char "\\" && unicode.data[index] == #char "\"" {
                current_line.count = max(current_line.count - 1, 0);
                if current_line.count > 0 {
                    append(*builder, current_line);
                    current_line = "";
                }
                append(*builder, "\"");
            }
        }

        if current_line.data {
            current_line.count = unicode.count - (current_line.data - unicode.data);
            if current_line.count > 0 {
                append(*builder, current_line);
            }
        }

        translations[index] = get_unicode(builder_to_string(*builder));
    }

    return translations;
}

deepl_request_post :: (url: *u8, header: *u8, lines: [] FixedString(4096)) -> bool, string {
    curl := curl_easy_init();
    defer curl_easy_cleanup(curl);
    assert(!!curl, "Curl could not be initialized.");
    
    list: *curl_slist;
    defer curl_slist_free_all(list);
    list = curl_slist_append(list, header);
    list = curl_slist_append(list, "Content-Type: application/json");
    curl_easy_setopt(curl, .HTTPHEADER, list);

    json_builder: String_Builder;
    append(*json_builder, "{");
    append(*json_builder, "\"text\": [");
    for *line: lines {
        unicode := get_unicode(to_string(line));

        append(*json_builder, "\"");
        current_line: string;
        for character, character_index: unicode {
            if !current_line.data {
                current_line.data = unicode.data + character_index;
            }
            current_line.count = character_index - (current_line.data - unicode.data);

            if character == #char "\"" {
                if current_line.count > 0 {
                    append(*json_builder, current_line);
                    current_line = "";
                }

                append(*json_builder, "\\\"");
            }
        }
        if current_line.data {
            current_line.count = unicode.count - (current_line.data - unicode.data);
            if current_line.count > 0 {
                append(*json_builder, current_line);
            }
        }

        append(*json_builder, "\"");

        if it_index < lines.count - 1 {
            append(*json_builder, ", ");
        }
    }
    append(*json_builder, "], \"target_lang\": \"");
    append(*json_builder, target_language);
    append(*json_builder, "\"}\0");
    
    json_string := builder_to_string(*json_builder);
    defer free(json_string);

    print("Request string:\n%\n", json_string);

    curl_easy_setopt(curl, .POSTFIELDS, json_string.data);
    curl_easy_setopt(curl, .URL, url);

    output_builder: String_Builder;
    curl_easy_setopt(curl, .WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, .WRITEDATA, *output_builder);

    success := curl_easy_perform(curl) == 0;
    return success, builder_to_string(*output_builder);
}

write_callback :: (contents: *u8, count: u64, size: u64, builder: *String_Builder) -> u64 #c_call {
    total_size := count * size;
    new_context: Context;
    push_context new_context {
        // Append to the builder
        append(builder, contents, cast(s64) total_size);
    }
    return total_size;
}

Unicode :: struct {
    data: *u8;
    count: int;
}

free :: (unicode: Unicode) {
    free(unicode.data);
}

get_unicode :: (line: string) -> Unicode {
    return Unicode.{line.data, line.count};
}

get_string :: (line: Unicode) -> string {
    output: string;
    output.data = line.data;
    output.count = line.count;
    return output;
}

copy_unicode :: (line: Unicode) -> Unicode {
    copied: Unicode;
    copied.data = alloc(line.count);
    memcmp(copied.data, line.data, line.count);
    copied.count = line.count;
    return copied;
}

for_expansion :: (unicode: Unicode, body: Code, flags: For_Flags) #expand {
    #assert(!(flags & .REVERSE));
    #assert(!(flags & .POINTER));
    
    i := 0;
    while i < unicode.count {
        value: int;
        index := i;

        if unicode.data[i] >= 240 {
            if i >= unicode.count + 3 {
                break;
            }
            value = ((unicode.data[i] & 0x07) << 18) | ((unicode.data[i + 1] & 0x3F) << 12) | ((unicode.data[i + 2] & 0x3F) << 6) | (unicode.data[i + 3] & 0x3F);

            i += 4;
        } else if unicode.data[i] >= 224 {
            if i >= unicode.count + 2 {
                break;
            }
            value = ((unicode.data[i] & 0x0F) << 12) | ((unicode.data[i + 1] & 0x3F) << 6) | (unicode.data[i + 2] & 0x3F);

            i += 3;
        } else if unicode.data[i] >= 192 {
            if i >= unicode.count + 1 {
                break;
            }
            value = ((unicode.data[i] & 0x1F) << 6) | (unicode.data[i + 1] & 0x3F);

            i += 2;
        } else {
            value = unicode.data[i];

            i += 1;
        }

        `it := value;
        `it_index := index;

        #insert body;
    }
}

split :: (unicode: Unicode) -> [] Unicode, last_newline_index: int {
    lines: [..] Unicode;
    last_newline_index := -1;

    current_line: Unicode;
    for char, index: unicode {
        if char == #char "\r" || char == #char "\n" {
            if current_line.data {
                current_line.count = index - (current_line.data - unicode.data);
                if current_line.count > 0 {
                    array_add(*lines, current_line);
                    current_line = .{};
                }
            }

            last_newline_index = index;
        } else if !current_line.data {
            current_line.data = unicode.data + index;
            current_line.count = 0;
        }
    }

    // if current_line.data && !current_line.count {
    //     current_line.count = unicode.count - (current_line.data - unicode.data);
    //     array_add(*lines, current_line);
    // }

    return lines, last_newline_index;
}


file_open_shared :: (name: string, for_writing := false, keep_existing_content := false, log_errors := false) -> File, bool {
    System :: #import "System";
    #import "Windows_Utf8";

    handle: HANDLE;
    if for_writing {
        mode: u32;
        if keep_existing_content mode = OPEN_ALWAYS;
        else mode = CREATE_ALWAYS;
        handle = CreateFileW(utf8_to_wide_new(name,, allocator=temp), FILE_GENERIC_READ | FILE_GENERIC_WRITE, FILE_SHARE_READ, creation = mode);
    } else {
        handle = CreateFileW(utf8_to_wide_new(name,, allocator=temp), FILE_GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE);
    }

    if handle == INVALID_HANDLE_VALUE {
        if log_errors {
            error_code, error_string := System.get_error_value_and_string();
            log_error("Could not open file \"%\": code %, %", name, error_code, error_string);
        }

        return .{}, false;
    }

    file: File;
    file.handle = handle;

    return file, true;
}

run_command_continuous :: (args: .. string, lines: *[..] string, mutex: *Mutex, working_directory := "", capture_and_return_output := false, print_captured_output := false, timeout_ms := -1, arg_quoting := Process_Argument_Quoting.QUOTE_IF_NEEDED) -> (process_result: Process_Result, output_string := "", error_string := "", timeout_reached := false) {
    System :: #import "System";

    process: Process;
    success := create_process(*process, .. args, working_directory, capture_and_return_output, arg_quoting);
    if !success    return .{type = .FAILED_TO_LAUNCH};

    defer deinit(*process);

    output_string: string;
    error_string : string;
    timeout_reached: bool;

    exit_timeout_ms := timeout_ms;
    
    if capture_and_return_output {
        output_builder: String_Builder;
        init_string_builder(*output_builder);
        error_builder : String_Builder;
        init_string_builder(*error_builder);

        start_time := current_time_monotonic();
        remaining_timeout_ms := timeout_ms;

        while true {
            reset(*output_builder);
            reset(*error_builder);

            output_buffer := ensure_contiguous_space_and_return_available_range(*output_builder);
            error_buffer := ensure_contiguous_space_and_return_available_range(*error_builder);
            success, output_bytes, error_bytes := read_from_process(*process, output_buffer, error_buffer, remaining_timeout_ms);

            {
                lock(mutex);
                defer unlock(mutex);

                out_string: string;
                out_string.data = output_buffer.data;
                out_string.count = output_bytes;
                array_add(lines, copy_string(out_string));
            }

            if output_bytes {
                advance_through_ensured_space(*output_builder, output_bytes);
                if print_captured_output {
                    new_data := to_string(output_buffer.data, output_bytes);
                    write_string(new_data, to_standard_error = false);
                }
            }
            if error_bytes {
                advance_through_ensured_space(*error_builder, error_bytes);
                if print_captured_output {
                    new_data := to_string(error_buffer.data, error_bytes);
                    write_string(new_data, to_standard_error = true);
                }
            }

            if !success {
                log_error("Could not read output of command \"%\"", get_quoted_command_string(args,, temp));
                kill_process(*process);
                break;
            }

            if timeout_ms >= 0 {
                now := current_time_monotonic();
                remaining_timeout_ms = timeout_ms - to_milliseconds(now - start_time);

                if remaining_timeout_ms <= 0 {
                    // We’ve hit a timeout! Time to kill the child. (will be reaped below)
                    timeout_reached = true;
                    success := kill_process(*process);
                    if !success {
                        error_code, error_string := System.get_error_value_and_string();
                        log_error("Could not kill child for command \"%\": % %", get_quoted_command_string(args,, temp), error_code, error_string);
                    }
                    break;
                }
            }

            if process.output.eof && process.error.eof    break;
        }

        output_string = builder_to_string(*output_builder);
        error_string  = builder_to_string(*error_builder);
        exit_timeout_ms = -1;
    }

    process_result: Process_Result;
    exit_code: s32;
    while true {
        success, process_result = get_process_result(*process, exit_timeout_ms);
        if !success {
            error_code, error_string := System.get_error_value_and_string();
            log_error("Could not get process result for command \"%\": % %", get_quoted_command_string(args,, temp), error_code, error_string);
            kill_process(*process);
            process_result = .{type = .EXITED, exit_code = -1};
            break;
        }

        if process_result.type != .STILL_RUNNING     break;

        assert(exit_timeout_ms >= 0);
        exit_timeout_ms = -1;
        timeout_reached = true;
        // Kill process and then try to reap it again
        success = kill_process(*process);
        if !success {
            error_code, error_string := System.get_error_value_and_string();
            log_error("Could not kill child for command \"%\": % %", get_quoted_command_string(args,, temp), error_code, error_string);
            process_result = .{type = .EXITED, exit_code = -1};
            break;
        }
    }

    return process_result, output_string, error_string, timeout_reached;
}