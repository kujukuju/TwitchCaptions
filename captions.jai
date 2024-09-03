
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

tesseract_path :: "Tesseract-OCR/tesseract.exe";

captured_lines: [..] FixedString(4096);
changed_times: [..] float64;
translated_lines: [..] FixedString(4096);
translated: [..] bool;
persisting: [..] bool;

deepl_secret: string;

mutex: Mutex;

// if you want very instant translations using up a ton of translation tokens you would have like 50, 50
// if you want very instant translations using up a moderate amount of translation tokens you have would have like 200, 50
// if you want very slow translations using up very few tokens you would have like 50, 500
translation_delay :: 50;
translation_stable_delay :: 500;

caption_file: File;
caption_file_last_line_start: int;
caption_file_lines: [..] FixedString(4096);

main :: () {
    init(*mutex);

    run_command("stream.exe", "-m", "ggml-medium.en.bin", "-l", "en", "--step", "1200", "--length", "10000", capture_and_return_output = true);

    caption_file_open: bool;
    caption_file, caption_file_open = file_open("captions.txt", for_writing = false, keep_existing_content = true, log_errors = true);
    assert(caption_file_open, "Could not open caption file.\n");

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
            append(*builder, "\"");
            append(*builder, to_string(line));
            append(*builder, "\",\"");
            append(*builder, to_string(*translated_lines[index]));
            append(*builder, "\"");

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
        get_text();
        translate_text();

        sleep_milliseconds(translation_delay);
    }
}

read_caption_lines :: () {
    bytes: [..] u8;
    bytes.allocator = temp;

    file_set_position(caption_file, caption_file_last_line_start);
    read_count := 1;
    while read_count > 0 {
        array_reserve(*bytes, bytes.allocated + 4096);

        read_success: bool;
        read_success, read_count = file_read(caption_file, bytes.data + bytes.count, bytes.allocated - bytes.count);
        if !read_success {
            print("Could not read captions file.\n");
        }

        bytes.count += read_count;
    }

    unicode: Unicode;
    lines, last_newline := split(unicode,, temp);
    
    if last_newline != -1 {
        caption_file_last_line_start += last_newline + 1;
    }

    fixed_lines: [..] FixedString(4096);
    fixed_lines.allocator = temp;
    for line: lines {
        if line.count == 0 {
            continue;
        }

        array_add(*fixed_lines, create_fixed_string(get_string(line), 4096));
    }

    // remove all lines that match the last captured line
    if caption_file_lines.count > 0 {
        i := 0;
        while i < fixed_lines.count {
            if is_similar(fixed_lines[i], caption_file_lines[fixed_lines.count - 1]) {
                array_ordered_remove_by_index(*fixed_lines, i);
            } else {
                i += 1;
            }
        }
    }

    for fixed_line: fixed_lines {
        array_add(*caption_file_lines, fixed_line);
    }

    builder: String_Builder;
    for line: caption_file_lines {
        append(*builder, to_string(*line));
        append(*builder, "\n");
    }

    builder_string := builder_to_string(*builder);
    defer free(builder_string);
    write_entire_file("captured_file_lines.txt", builder_string);
}

get_text :: () {
    lines: [..] FixedString(4096);
    lines.allocator = temp;

    start_i := max(caption_file_lines.count - 4, 0);
    for i: start_i..caption_file_lines.count - 1 {
        array_add(*lines, caption_file_lines[i]);
    }

    process_lines(lines);
}

is_similar :: (line: Unicode, captured: FixedString(4096)) -> bool {
    fixed_line := create_fixed_string(get_string(line), 4096);
    return is_similar(fixed_line, captured);
}

is_similar :: (line1: FixedString(4096), line2: FixedString(4096)) -> bool {
    line1_string := to_string(*line1);
    line2_string := to_string(*line2);
    similar := line1_string == line2_string;

    shorter_line1 := line1_string;
    shorter_line2 := line2_string;
    if shorter_line1.count >= 4 && shorter_line2.count >= 4 {
        shorter_line1.count /= 2;
        shorter_line2.count /= 2;
    }
    similar = similar || begins_with_nocase(line1_string, shorter_line2);
    similar = similar || begins_with_nocase(line2_string, shorter_line1);

    return similar;
}

process_lines :: (lines: [] FixedString(4096)) {
    lock(*mutex);
    defer unlock(*mutex);

    // when you can't find the first captured_line anymore we will push it into the beginning
    // actually... we will always maintain one translated line that's no longer found anywhere

    newly_captured_lines: [..] FixedString(4096);
    newly_changed_times: [..] float64;
    newly_translated_lines: [..] FixedString(4096);
    newly_translated: [..] bool;
    newly_persisting: [..] bool;

    time := seconds_since_init() * 1000;

    first_non_persisting_index := -1;
    for captured_line, index: captured_lines {
        if !persisting[index] {
            first_non_persisting_index = index;
            break;
        }
    }

    first_persisting_index := -1;
    for captured_line, index: captured_lines {
        if persisting[index] {
            first_persisting_index = index;
            break;
        }
    }

    if captured_lines.count > 0 && lines.count > 0 {
        if first_non_persisting_index >= 0 && !is_similar(lines[0], captured_lines[first_non_persisting_index]) {
            array_add(*newly_captured_lines, captured_lines[first_non_persisting_index]);
            array_add(*newly_changed_times, changed_times[first_non_persisting_index]);
            array_add(*newly_translated_lines, translated_lines[first_non_persisting_index]);
            array_add(*newly_translated, translated[first_non_persisting_index]);
            array_add(*newly_persisting, true);
        } else if first_persisting_index >= 0 {
            array_add(*newly_captured_lines, captured_lines[first_persisting_index]);
            array_add(*newly_changed_times, changed_times[first_persisting_index]);
            array_add(*newly_translated_lines, translated_lines[first_persisting_index]);
            array_add(*newly_translated, translated[first_persisting_index]);
            array_add(*newly_persisting, true);
        }
    }

    for *line: lines {
        // this is checking if the exact line already exists and it will copy it
        exists_index := -1;
        for *captured_line, index: captured_lines {
            if to_string(line) == to_string(captured_line) {
                exists_index = index;
                break;
            }
        }

        // this is checking if the line partially existed before, and it will keep the old translation
        partial_index := -1;
        if exists_index == -1 {
            for *captured_line, index: captured_lines {
                if starts_with(to_string(line), to_string(captured_line)) {
                    partial_index = index;
                    break;
                }
            }
        }

        array_add(*newly_captured_lines, line);
        if exists_index >= 0 {
            array_add(*newly_changed_times, changed_times[exists_index]);
            array_add(*newly_translated_lines, translated_lines[exists_index]);
            array_add(*newly_translated, translated[exists_index]);
            array_add(*newly_persisting, false);
        } else if partial_index >= 0 {
            array_add(*newly_changed_times, time);
            array_add(*newly_translated_lines, translated_lines[partial_index]);
            array_add(*newly_translated, false);
            array_add(*newly_persisting, false);
        } else {
            array_add(*newly_changed_times, time);
            array_add(*newly_translated_lines, FixedString(4096).{});
            array_add(*newly_translated, false);
            array_add(*newly_persisting, false);
        }
    }

    array_free(captured_lines);
    array_free(changed_times);
    array_free(translated_lines);
    array_free(translated);
    array_free(persisting);
    captured_lines = newly_captured_lines;
    changed_times = newly_changed_times;
    translated_lines = newly_translated_lines;
    translated = newly_translated;
    persisting = newly_persisting;
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

    JsonTranslation :: struct {
        detected_source_language: string;
        text: string;
    }

    JsonResponse :: struct {
        translations: [..] JsonTranslation;
    }

    result, memory, valid := json_parse(deepl_response, JsonResponse);
    defer free(memory);
    if !valid {
        print("Could not translate text... %\n", desired_translations);
        return;
    }

    if result.translations.count != desired_translations.count {
        print("Received back incorrect number of translations... % != %\n", desired_translations.count, result.translations.count);
        for translation: result.translations {
            print("%\n", translation);
        }
        return;
    }

    lock(*mutex);
    defer unlock(*mutex);

    for translation, index: result.translations {
        translated[desired_indices[index]] = true;
        translated_lines[desired_indices[index]] = create_fixed_string(translation.text, 4096);
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

capture_window :: (hwnd: HWND) {
    bytes, width, height := get_window_bytes(hwnd);
    defer free(bytes);

    for i: 0..width * height {
        bytes[i * 4 + 3] = 255;
    }

    stbi_write_png("captions.png", cast(s32) width, cast(s32) height, 4, bytes, cast(s32) (4 * width));
}

get_window_bytes :: (hwnd: HWND) -> *u8, int, int {
    hdcScreen := GetDC(null);
    hdcMemDC := CreateCompatibleDC(hdcScreen);

    screenWidth := GetSystemMetrics(SM_CXSCREEN);
    screenHeight := GetSystemMetrics(SM_CYSCREEN);

    hbmScreen := CreateCompatibleBitmap(hdcScreen, screenWidth, screenHeight);

    if (!hdcMemDC) {
        print("CreateCompatibleDC failed: %\n", GetLastError());
        return null, 0, 0;
    }

    rcClient: RECT;
    GetWindowRect(hwnd, *rcClient);

    rcClient.left += 8;
    rcClient.right -= 98;
    rcClient.top += 8;
    rcClient.bottom -= 8;

    width := rcClient.right - rcClient.left;
    height := rcClient.bottom - rcClient.top;

    SelectObject(hdcMemDC, hbmScreen);

    BitBlt(hdcMemDC, 0, 0, width, height, hdcScreen, rcClient.left, rcClient.top, ROP.SRCCOPY);

    bmpScreen: BITMAP;
    GetObjectA(hbmScreen, size_of(BITMAP), *bmpScreen);

    bi: BITMAPINFOHEADER;
    bi.biSize = size_of(BITMAPINFOHEADER);
    bi.biWidth = width;
    bi.biHeight = height * -1;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;
    bi.biSizeImage = 0;
    bi.biXPelsPerMeter = 0;
    bi.biYPelsPerMeter = 0;
    bi.biClrUsed = 0;
    bi.biClrImportant = 0;

    pPixels := alloc(4 * width * height);

    GetDIBits(hdcMemDC, hbmScreen, 0, cast(u32) height, pPixels, cast(*BITMAPINFO) *bi, DIB_RGB_COLORS);

    DeleteObject(hbmScreen);
    DeleteDC(hdcMemDC);
    ReleaseDC(hwnd, hdcScreen);

    return pPixels, cast(int) width, cast(int) height;
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
        append(*json_builder, "\"");
        append(*json_builder, to_string(line));
        append(*json_builder, "\"");

        if it_index < lines.count - 1 {
            append(*json_builder, ", ");
        }
    }
    append(*json_builder, "], \"target_lang\": \"JA\"}\0");
    
    json_string := builder_to_string(*json_builder);

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