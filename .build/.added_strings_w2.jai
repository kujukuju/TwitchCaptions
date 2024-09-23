// Workspace: Target Program

//
// #insert text. Generated from C:/Users/Kuju/Projects/ContiguousJsonJai/reader.jai:41.
//
 

//
// #insert text. Generated from C:/Users/Kuju/Projects/ContiguousJsonJai/reader.jai:290.
//
if name == "character_count" {
InnerType :: #run type_of(result.character_count);
index, success = json_parse_into(content, index, cast(*InnerType) ((cast(*u8) result) + 0), memory, relative, contiguous_memory, keep_strings_in_place);
if !success {
return index, false;
}
} else if name == "character_limit" {
InnerType :: #run type_of(result.character_limit);
index, success = json_parse_into(content, index, cast(*InnerType) ((cast(*u8) result) + 8), memory, relative, contiguous_memory, keep_strings_in_place);
if !success {
return index, false;
}
} else {
index, success = skip_unknown_type(content, index);
if !success {
return index, false;
}
}
