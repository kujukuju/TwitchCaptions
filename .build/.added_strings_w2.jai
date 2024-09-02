// Workspace: Target Program

//
// #insert text. Generated from C:/Users/Kuju/Projects/ContiguousJsonJai/reader.jai:41.
//
if result.translations.data {
result.translations.data = xx ((cast(*u8) result.translations.data) + pointer_offset);
for result_translations_iterator: 0..result.translations.count - 1 {
if result.translations.data[result_translations_iterator].detected_source_language.data {
result.translations.data[result_translations_iterator].detected_source_language.data = xx ((cast(*u8) result.translations.data[result_translations_iterator].detected_source_language.data) + pointer_offset);
}
if result.translations.data[result_translations_iterator].text.data {
result.translations.data[result_translations_iterator].text.data = xx ((cast(*u8) result.translations.data[result_translations_iterator].text.data) + pointer_offset);
}
}
}

//
// #insert text. Generated from C:/Users/Kuju/Projects/ContiguousJsonJai/reader.jai:290.
//
if name == "translations" {
InnerType :: #run type_of(result.translations);
index, success = json_parse_into(content, index, cast(*InnerType) ((cast(*u8) result) + 0), memory, relative, contiguous_memory, keep_strings_in_place);
if !success {
return index, false;
}
} else {
index, success = skip_unknown_type(content, index);
if !success {
return index, false;
}
}

//
// #insert text. Generated from C:/Users/Kuju/Projects/ContiguousJsonJai/reader.jai:290.
//
if name == "detected_source_language" {
InnerType :: #run type_of(result.detected_source_language);
index, success = json_parse_into(content, index, cast(*InnerType) ((cast(*u8) result) + 0), memory, relative, contiguous_memory, keep_strings_in_place);
if !success {
return index, false;
}
} else if name == "text" {
InnerType :: #run type_of(result.text);
index, success = json_parse_into(content, index, cast(*InnerType) ((cast(*u8) result) + 16), memory, relative, contiguous_memory, keep_strings_in_place);
if !success {
return index, false;
}
} else {
index, success = skip_unknown_type(content, index);
if !success {
return index, false;
}
}

//
// #insert text. Generated from C:/Users/Kuju/Projects/KodaMicroHttp/module.jai:159.
//
internal_handler :: (request: *HttpRequest, response: *HttpResponse, optionals: [] string) -> HttpResult {
optional0 := optionals[0];
return inline handler(request, response, optional0);
}
