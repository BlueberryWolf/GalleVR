#ifdef _WIN32
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef _WIN32
    #define EXPORT __declspec(dllexport)
    #define BSWAP32(x) _byteswap_ulong(x)
#else
    #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
    #include <arpa/inet.h>
    #define BSWAP32(x) ntohl(x)
    #define _stricmp strcasecmp
#endif

char* extract_tag(const char* xml, const char* tag) {
    char start[128], end[128];
    sprintf(start, "<%s>", tag);
    sprintf(end, "</%s>", tag);
    char* s = strstr(xml, start);
    if (!s) return NULL;
    s += strlen(start);
    char* e = strstr(s, end);
    if (!e) return NULL;
    size_t len = e - s;
    char* val = malloc(len + 1);
    if (val) {
        memcpy(val, s, len);
        val[len] = '\0';
    }
    return val;
}

char* duplicate_string(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char* d = malloc(len + 1);
    if (d) strcpy(d, s);
    return d;
}
char* extract_xml_attribute(const char* xml, const char* attr_name) {
    if (!xml || !attr_name) return NULL;
    size_t attr_len = strlen(attr_name);
    const char* ptr = xml;
    while (1) {
        const char* match = strstr(ptr, attr_name);
        if (!match) break;
        int valid_prefix = 0;
        if (match == xml) {
            valid_prefix = 1;
        } else {
            char prev = *(match - 1);
            if (prev == ' ' || prev == '\t' || prev == '\r' || prev == '\n' || prev == ':') {
                valid_prefix = 1;
            }
        }
        if (valid_prefix) {
            const char* eq = match + attr_len;
            while (*eq == ' ' || *eq == '\t') eq++;
            if (*eq == '=') {
                eq++;
                while (*eq == ' ' || *eq == '\t') eq++;
                char quote = *eq;
                if (quote == '"' || quote == '\'') {
                    const char* val_start = eq + 1;
                    const char* val_end = strchr(val_start, quote);
                    if (val_end) {
                        size_t val_len = val_end - val_start;
                        char* val = malloc(val_len + 1);
                        if (val) {
                            memcpy(val, val_start, val_len);
                            val[val_len] = '\0';
                            return val;
                        }
                    }
                }
            }
        }
        ptr = match + 1;
    }
    return NULL;
}
char* extract_sub_attribute(const char* xml, const char* tag_name, const char* attr_name) {
    char search_tag[128];
    sprintf(search_tag, "%s", tag_name);
    char* tag_start = strstr(xml, search_tag);
    if (!tag_start) {
        sprintf(search_tag, "rse:%s", tag_name);
        tag_start = strstr(xml, search_tag);
    }
    if (!tag_start) return NULL;
    char* tag_end = strchr(tag_start, '>');
    if (!tag_end) return NULL;
    size_t tag_len = tag_end - tag_start;
    char* tag_content = malloc(tag_len + 1);
    if (!tag_content) return NULL;
    memcpy(tag_content, tag_start, tag_len);
    tag_content[tag_len] = '\0';
    char* val = extract_xml_attribute(tag_content, attr_name);
    free(tag_content);
    return val;
}

char* decode_xml_entities(const char* src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    char* dest = malloc(len + 1);
    if (!dest) return NULL;
    size_t i = 0, j = 0;
    while (i < len) {
        if (src[i] == '&') {
            if (strncmp(src + i, "&quot;", 6) == 0) {
                dest[j++] = '"';
                i += 6;
            } else if (strncmp(src + i, "&amp;", 5) == 0) {
                dest[j++] = '&';
                i += 5;
            } else if (strncmp(src + i, "&lt;", 4) == 0) {
                dest[j++] = '<';
                i += 4;
            } else if (strncmp(src + i, "&gt;", 4) == 0) {
                dest[j++] = '>';
                i += 4;
            } else if (strncmp(src + i, "&apos;", 6) == 0) {
                dest[j++] = '\'';
                i += 6;
            } else {
                dest[j++] = src[i++];
            }
        } else {
            dest[j++] = src[i++];
        }
    }
    dest[j] = '\0';
    return dest;
}

char* extract_players_json(const char* xml) {
    char* start = strstr(xml, "<rse:UserInfos>");
    if (!start) start = strstr(xml, "UserInfos");
    if (!start) return duplicate_string("[]");
    char* end = strstr(start, "</rse:UserInfos>");
    if (!end) end = strstr(start, "UserInfos>");
    if (!end) return duplicate_string("[]");
    char* ptr = start;
    size_t out_cap = 1024;
    char* out = malloc(out_cap);
    if (!out) return duplicate_string("[]");
    strcpy(out, "[");
    int first = 1;
    while (ptr < end) {
        char* item = strstr(ptr, "UserInfo");
        if (!item || item >= end) break;
        char* item_end = strchr(item, '>');
        if (!item_end || item_end >= end) break;
        size_t len = item_end - item;
        char* item_content = malloc(len + 1);
        if (!item_content) break;
        memcpy(item_content, item, len);
        item_content[len] = '\0';
        char* raw_id = extract_xml_attribute(item_content, "U-Id");
        char* raw_name = extract_xml_attribute(item_content, "U-Name");
        char* raw_head_pos = extract_xml_attribute(item_content, "UI-HeadPosition");
        char* raw_head_ori = extract_xml_attribute(item_content, "UI-HeadOrientation");
        char* raw_head_scale = extract_xml_attribute(item_content, "UI-HeadScale");
        char* raw_is_in_view = extract_xml_attribute(item_content, "UI-IsInView");
        char* id = decode_xml_entities(raw_id);
        char* name = decode_xml_entities(raw_name);
        char* head_pos = decode_xml_entities(raw_head_pos);
        char* head_ori = decode_xml_entities(raw_head_ori);
        char* head_scale = decode_xml_entities(raw_head_scale);
        char* is_in_view = decode_xml_entities(raw_is_in_view);
        if (id && name) {
            char entry[512];
            sprintf(entry, "%s{\"id\":\"%s\",\"displayName\":\"%s\",\"headPosition\":\"%s\",\"headOrientation\":\"%s\",\"headScale\":\"%s\",\"isInView\":\"%s\"}",
                    first ? "" : ",", id, name, head_pos ? head_pos : "", head_ori ? head_ori : "", head_scale ? head_scale : "1.0", is_in_view ? is_in_view : "true");
            first = 0;
            if (strlen(out) + strlen(entry) + 10 >= out_cap) {
                out_cap *= 2;
                char* new_out = realloc(out, out_cap);
                if (!new_out) {
                    if (raw_id) free(raw_id);
                    if (raw_name) free(raw_name);
                    if (raw_head_pos) free(raw_head_pos);
                    if (raw_head_ori) free(raw_head_ori);
                    if (raw_head_scale) free(raw_head_scale);
                    if (raw_is_in_view) free(raw_is_in_view);
                    if (id) free(id);
                    if (name) free(name);
                    if (head_pos) free(head_pos);
                    if (head_ori) free(head_ori);
                    if (head_scale) free(head_scale);
                    if (is_in_view) free(is_in_view);
                    free(item_content);
                    break;
                }
                out = new_out;
            }
            strcat(out, entry);
        }
        if (raw_id) free(raw_id);
        if (raw_name) free(raw_name);
        if (raw_head_pos) free(raw_head_pos);
        if (raw_head_ori) free(raw_head_ori);
        if (raw_head_scale) free(raw_head_scale);
        if (raw_is_in_view) free(raw_is_in_view);
        if (id) free(id);
        if (name) free(name);
        if (head_pos) free(head_pos);
        if (head_ori) free(head_ori);
        if (head_scale) free(head_scale);
        if (is_in_view) free(is_in_view);
        free(item_content);
        ptr = item_end + 1;
    }
    strcat(out, "]");
    return out;
}

static void parse_png(FILE* file, char** vrcx_json, char** vrchat_xml) {
    fseek(file, 8, SEEK_SET);
    uint32_t len_be;
    char type[5] = {0};

    // png chunk format: [length][type][data][crc]
    while (fread(&len_be, 4, 1, file) == 1) {
        uint32_t chunk_length = BSWAP32(len_be);
        if (fread(type, 4, 1, file) != 1) break;

        // VRCX metadata is stored in iTXt chunks
        if (strcmp(type, "iTXt") == 0 || strcmp(type, "tEXt") == 0) {
            char* chunk_data = malloc(chunk_length + 1);
            if (!chunk_data) break;
            
            if (fread(chunk_data, 1, chunk_length, file) != chunk_length) {
                free(chunk_data);
                break;
            }
            chunk_data[chunk_length] = '\0';

            const char* needle = "{\"application\":\"VRCX\"";
            char* json_start = NULL;

            // find start of JSON in chunk
            for (uint32_t i = 0; i <= (chunk_length > 21 ? chunk_length - 21 : 0); i++) {
                if (chunk_data[i] == '{' && memcmp(chunk_data + i, needle, 21) == 0) {
                    json_start = chunk_data + i;
                    break;
                }
            }

            if (json_start && !*vrcx_json) {
                // calculate length from start of JSON to end of chunk
                size_t json_len = chunk_length - (json_start - chunk_data);
                *vrcx_json = malloc(json_len + 1);
                if (*vrcx_json) {
                    memcpy(*vrcx_json, json_start, json_len);
                    (*vrcx_json)[json_len] = '\0';
                }
            }

            if (!*vrchat_xml) {
                char* xml_ptr = chunk_data;
                while (xml_ptr < chunk_data + chunk_length && *xml_ptr != '<') {
                    xml_ptr++;
                }
                if (xml_ptr < chunk_data + chunk_length && (
                    strstr(xml_ptr, "<xmp:CreatorTool>VRChat</xmp:CreatorTool>") || 
                    strstr(xml_ptr, "<vrc:WorldID>") ||
                    strstr(xml_ptr, "http://ns.baru.dev/resonite-ss-ext/")
                )) {
                    size_t xml_len = (chunk_data + chunk_length) - xml_ptr;
                    *vrchat_xml = malloc(xml_len + 1);
                    if (*vrchat_xml) {
                        memcpy(*vrchat_xml, xml_ptr, xml_len);
                        (*vrchat_xml)[xml_len] = '\0';
                    }
                }
            }

            free(chunk_data);
            fseek(file, 4, SEEK_CUR);
        } 
        else if (strcmp(type, "IDAT") == 0 || strcmp(type, "IEND") == 0) {
            // stop at pixel data
            break; 
        } 
        else {
            // jump over other chunks
            fseek(file, chunk_length + 4, SEEK_CUR);
        }
    }
}

static void parse_jpeg(FILE* file, char** vrchat_xml) {
    fseek(file, 2, SEEK_SET);
    while (1) {
        int c1 = fgetc(file);
        if (c1 == EOF) break;
        if (c1 != 0xFF) continue; // Skip non-0xFF padding
        int marker = fgetc(file);
        if (marker == EOF) break;
        if (marker == 0xFF) {
            ungetc(marker, file);
            continue;
        }
        // Stop scanning if we hit SOS (0xDA) or EOI (0xD9)
        if (marker == 0xDA || marker == 0xD9) {
            break;
        }
        
        // Read segment length (2 bytes, big-endian)
        unsigned char len_bytes[2];
        if (fread(len_bytes, 1, 2, file) != 2) break;
        uint16_t segment_length = (len_bytes[0] << 8) | len_bytes[1];
        if (segment_length < 2) break;
        
        uint32_t payload_len = segment_length - 2;
        
        if (marker == 0xE1) { // APP1 marker (XMP is typically here)
            char* payload = malloc(payload_len + 1);
            if (payload) {
                if (fread(payload, 1, payload_len, file) == payload_len) {
                    payload[payload_len] = '\0';
                    const char* ns = "http://ns.adobe.com/xap/1.0/";
                    size_t ns_len = strlen(ns);
                    if (payload_len > ns_len && memcmp(payload, ns, ns_len) == 0) {
                        size_t xml_offset = ns_len;
                        while (xml_offset < payload_len && payload[xml_offset] == '\0') {
                            xml_offset++;
                        }
                        if (xml_offset < payload_len) {
                            size_t xml_len = payload_len - xml_offset;
                            *vrchat_xml = malloc(xml_len + 1);
                            if (*vrchat_xml) {
                                memcpy(*vrchat_xml, payload + xml_offset, xml_len);
                                (*vrchat_xml)[xml_len] = '\0';
                            }
                        }
                    }
                }
                free(payload);
            }
            if (*vrchat_xml) break; // found XMP
        } else {
            fseek(file, payload_len, SEEK_CUR);
        }
    }
}

static void parse_webp(FILE* file, char** vrchat_xml) {
    fseek(file, 12, SEEK_SET);
    while (1) {
        char fcc[5] = {0};
        if (fread(fcc, 1, 4, file) != 4) break;
        
        unsigned char size_bytes[4];
        if (fread(size_bytes, 1, 4, file) != 4) break;
        uint32_t chunk_size = size_bytes[0] | (size_bytes[1] << 8) | (size_bytes[2] << 16) | (size_bytes[3] << 24);
        
        if (strcmp(fcc, "XMP ") == 0) {
            *vrchat_xml = malloc(chunk_size + 1);
            if (*vrchat_xml) {
                if (fread(*vrchat_xml, 1, chunk_size, file) == chunk_size) {
                    (*vrchat_xml)[chunk_size] = '\0';
                } else {
                    free(*vrchat_xml);
                    *vrchat_xml = NULL;
                }
            }
            break;
        } else {
            uint32_t skip = (chunk_size + 1) & ~1;
            fseek(file, skip, SEEK_CUR);
        }
    }
}

EXPORT char* extract_vrc_metadata(const char* file_path, const char* ext) {
    if (strcmp(ext, ".png") != 0 && strcmp(ext, "png") != 0) {
        return NULL;
    }
    FILE* file = fopen(file_path, "rb");
    char* vrcx_json = NULL;
    char* vrchat_xml = NULL;

    if (file) {
        parse_png(file, &vrcx_json, &vrchat_xml);
        fclose(file);
    }

    if (!vrcx_json && !vrchat_xml) {
        return NULL;
    }

    char* world_id = NULL;
    char* world_name = NULL;
    char* author = NULL;
    char* create_date = NULL;

    if (vrchat_xml) {
        world_id = extract_tag(vrchat_xml, "vrc:WorldID");
        world_name = extract_tag(vrchat_xml, "vrc:WorldDisplayName");
        author = extract_tag(vrchat_xml, "xmp:Author");
        create_date = extract_tag(vrchat_xml, "xmp:CreateDate");
    }

    size_t result_len = 1024;
    if (vrcx_json) result_len += strlen(vrcx_json);
    if (world_id) result_len += strlen(world_id);
    if (world_name) result_len += strlen(world_name);
    if (author) result_len += strlen(author);
    if (create_date) result_len += strlen(create_date);

    char* result = malloc(result_len);
    if (result) {
        sprintf(result,
            "{\"vrcx\":%s,\"xmp\":{"
            "\"worldId\":\"%s\","
            "\"worldName\":\"%s\","
            "\"author\":\"%s\","
            "\"createDate\":\"%s\""
            "}}",
            vrcx_json ? vrcx_json : "null",
            world_id ? world_id : "",
            world_name ? world_name : "",
            author ? author : "",
            create_date ? create_date : ""
        );
    }

    if (world_id) free(world_id);
    if (world_name) free(world_name);
    if (author) free(author);
    if (create_date) free(create_date);
    if (vrcx_json) free(vrcx_json);
    if (vrchat_xml) free(vrchat_xml);

    return result;
}

EXPORT char* extract_resonite_metadata(const char* file_path, const char* ext) {
    FILE* file = fopen(file_path, "rb");
    char* vrchat_xml = NULL;

    if (file) {
        if (strcmp(ext, ".png") == 0 || strcmp(ext, "png") == 0) {
            char* dummy_vrcx = NULL;
            parse_png(file, &dummy_vrcx, &vrchat_xml);
            if (dummy_vrcx) free(dummy_vrcx);
        }
        else if (strcmp(ext, ".jpg") == 0 || strcmp(ext, "jpg") == 0 ||
                 strcmp(ext, ".jpeg") == 0 || strcmp(ext, "jpeg") == 0) {
            parse_jpeg(file, &vrchat_xml);
        }
        else if (strcmp(ext, ".webp") == 0 || strcmp(ext, "webp") == 0) {
            parse_webp(file, &vrchat_xml);
        }
        fclose(file);
    }

    if (!vrchat_xml) {
        FILE* fallback_file = fopen(file_path, "rb");
        if (fallback_file) {
            fseek(fallback_file, 0, SEEK_END);
            size_t file_size = ftell(fallback_file);
            
            // Check if WebP file by extension to check tail first
            int is_webp = 0;
            size_t path_len = strlen(file_path);
            if (path_len >= 5) {
                const char* ext_check = file_path + path_len - 5;
                if (_stricmp(ext_check, ".webp") == 0) {
                    is_webp = 1;
                }
            }
            
            char* buf = NULL;
            if (is_webp) {
                // Try reading the end of the file first
                size_t tail_size = file_size > 65536 ? 65536 : file_size;
                fseek(fallback_file, (long)(file_size - tail_size), SEEK_SET);
                buf = malloc(tail_size + 1);
                if (buf) {
                    size_t bytes_read = fread(buf, 1, tail_size, fallback_file);
                    buf[bytes_read] = '\0';
                    
                    char* ns_ptr = NULL;
                    const char* needle = "http://ns.baru.dev/resonite-ss-ext/";
                    size_t needle_len = strlen(needle);
                    if (bytes_read >= needle_len) {
                        for (size_t i = 0; i <= bytes_read - needle_len; i++) {
                            if (memcmp(buf + i, needle, needle_len) == 0) {
                                ns_ptr = buf + i;
                                break;
                            }
                        }
                    }
                    if (ns_ptr) {
                        char* xml_start = ns_ptr;
                        while (xml_start > buf && *xml_start != '<') {
                            xml_start--;
                        }
                        char* xml_end = strstr(ns_ptr, "</rdf:Description>");
                        if (!xml_end) xml_end = strstr(ns_ptr, "/>");
                        
                        if (xml_end) {
                            if (*xml_end == '<') {
                                xml_end += 18;
                            } else {
                                xml_end += 2;
                            }
                            size_t xml_len = xml_end - xml_start;
                            vrchat_xml = malloc(xml_len + 1);
                            if (vrchat_xml) {
                                memcpy(vrchat_xml, xml_start, xml_len);
                                vrchat_xml[xml_len] = '\0';
                            }
                        }
                    }
                    free(buf);
                    buf = NULL;
                }
            }
            
            // Fallback to reading the first 2MB if not found in the tail
            if (!vrchat_xml) {
                fseek(fallback_file, 0, SEEK_SET);
                size_t head_size = file_size > 2 * 1024 * 1024 ? 2 * 1024 * 1024 : file_size;
                buf = malloc(head_size + 1);
                if (buf) {
                    size_t bytes_read = fread(buf, 1, head_size, fallback_file);
                    buf[bytes_read] = '\0';
                    
                    char* ns_ptr = NULL;
                    const char* needle = "http://ns.baru.dev/resonite-ss-ext/";
                    size_t needle_len = strlen(needle);
                    if (bytes_read >= needle_len) {
                        for (size_t i = 0; i <= bytes_read - needle_len; i++) {
                            if (memcmp(buf + i, needle, needle_len) == 0) {
                                ns_ptr = buf + i;
                                break;
                            }
                        }
                    }
                    if (ns_ptr) {
                        char* xml_start = ns_ptr;
                        while (xml_start > buf && *xml_start != '<') {
                            xml_start--;
                        }
                        char* xml_end = strstr(ns_ptr, "</rdf:Description>");
                        if (!xml_end) xml_end = strstr(ns_ptr, "/>");
                        
                        if (xml_end) {
                            if (*xml_end == '<') {
                                xml_end += 18;
                            } else {
                                xml_end += 2;
                            }
                            size_t xml_len = xml_end - xml_start;
                            vrchat_xml = malloc(xml_len + 1);
                            if (vrchat_xml) {
                                memcpy(vrchat_xml, xml_start, xml_len);
                                vrchat_xml[xml_len] = '\0';
                            }
                        }
                    }
                    free(buf);
                    buf = NULL;
                }
            }
            fclose(fallback_file);
        }
    }

    if (!vrchat_xml) {
        return NULL;
    }

    char* raw_loc_name = extract_xml_attribute(vrchat_xml, "LocationName");
    char* raw_loc_url = extract_xml_attribute(vrchat_xml, "LocationURL");
    char* raw_time_taken = extract_xml_attribute(vrchat_xml, "TimeTaken");
    char* raw_host_id = extract_sub_attribute(vrchat_xml, "LocationHost", "U-Id");
    char* raw_host_name = extract_sub_attribute(vrchat_xml, "LocationHost", "U-Name");
    char* raw_taken_by_id = extract_sub_attribute(vrchat_xml, "TakenBy", "U-Id");
    char* raw_taken_by_name = extract_sub_attribute(vrchat_xml, "TakenBy", "U-Name");
    char* raw_pos = extract_xml_attribute(vrchat_xml, "TakenGlobalPosition");
    char* raw_rot = extract_xml_attribute(vrchat_xml, "TakenGlobalRotation");
    char* raw_scale = extract_xml_attribute(vrchat_xml, "TakenGlobalScale");
    char* raw_fov = extract_xml_attribute(vrchat_xml, "CameraFOV");
    char* raw_cam_man = extract_xml_attribute(vrchat_xml, "CameraManufacturer");
    char* players_json = extract_players_json(vrchat_xml);
    char* raw_v1_json = extract_xml_attribute(vrchat_xml, "PhotoMetadataJson");

    char* loc_name = decode_xml_entities(raw_loc_name);
    char* loc_url = decode_xml_entities(raw_loc_url);
    char* time_taken = decode_xml_entities(raw_time_taken);
    char* host_id = decode_xml_entities(raw_host_id);
    char* host_name = decode_xml_entities(raw_host_name);
    char* taken_by_id = decode_xml_entities(raw_taken_by_id);
    char* taken_by_name = decode_xml_entities(raw_taken_by_name);
    char* pos = decode_xml_entities(raw_pos);
    char* rot = decode_xml_entities(raw_rot);
    char* scale = decode_xml_entities(raw_scale);
    char* fov = decode_xml_entities(raw_fov);
    char* cam_man = decode_xml_entities(raw_cam_man);
    char* v1_json = decode_xml_entities(raw_v1_json);

    size_t result_len = 2560;
    if (loc_name) result_len += strlen(loc_name);
    if (loc_url) result_len += strlen(loc_url);
    if (time_taken) result_len += strlen(time_taken);
    if (host_id) result_len += strlen(host_id);
    if (host_name) result_len += strlen(host_name);
    if (taken_by_id) result_len += strlen(taken_by_id);
    if (taken_by_name) result_len += strlen(taken_by_name);
    if (pos) result_len += strlen(pos);
    if (rot) result_len += strlen(rot);
    if (scale) result_len += strlen(scale);
    if (fov) result_len += strlen(fov);
    if (cam_man) result_len += strlen(cam_man);
    if (players_json) result_len += strlen(players_json);
    if (v1_json) result_len += strlen(v1_json);

    char* result = malloc(result_len);
    if (result) {
        sprintf(result,
            "{\"application\":\"Resonite\",\"resonite\":{"
            "\"locationName\":\"%s\","
            "\"locationUrl\":\"%s\","
            "\"timeTaken\":\"%s\","
            "\"hostId\":\"%s\","
            "\"hostName\":\"%s\","
            "\"takenById\":\"%s\","
            "\"takenByName\":\"%s\","
            "\"takenGlobalPosition\":\"%s\","
            "\"takenGlobalRotation\":\"%s\","
            "\"takenGlobalScale\":\"%s\","
            "\"cameraFov\":\"%s\","
            "\"cameraManufacturer\":\"%s\","
            "\"players\":%s,"
            "\"v1Json\":%s"
            "}}",
            loc_name ? loc_name : "",
            loc_url ? loc_url : "",
            time_taken ? time_taken : "",
            host_id ? host_id : "",
            host_name ? host_name : "",
            taken_by_id ? taken_by_id : "",
            taken_by_name ? taken_by_name : "",
            pos ? pos : "",
            rot ? rot : "",
            scale ? scale : "",
            fov ? fov : "",
            cam_man ? cam_man : "",
            players_json ? players_json : "[]",
            v1_json ? v1_json : "null"
        );
    }

    if (raw_loc_name) free(raw_loc_name);
    if (raw_loc_url) free(raw_loc_url);
    if (raw_time_taken) free(raw_time_taken);
    if (raw_host_id) free(raw_host_id);
    if (raw_host_name) free(raw_host_name);
    if (raw_taken_by_id) free(raw_taken_by_id);
    if (raw_taken_by_name) free(raw_taken_by_name);
    if (raw_pos) free(raw_pos);
    if (raw_rot) free(raw_rot);
    if (raw_scale) free(raw_scale);
    if (raw_fov) free(raw_fov);
    if (raw_cam_man) free(raw_cam_man);
    if (raw_v1_json) free(raw_v1_json);

    if (loc_name) free(loc_name);
    if (loc_url) free(loc_url);
    if (time_taken) free(time_taken);
    if (host_id) free(host_id);
    if (host_name) free(host_name);
    if (taken_by_id) free(taken_by_id);
    if (taken_by_name) free(taken_by_name);
    if (pos) free(pos);
    if (rot) free(rot);
    if (scale) free(scale);
    if (fov) free(fov);
    if (v1_json) free(v1_json);
    if (players_json) free(players_json);
    if (vrchat_xml) free(vrchat_xml);

    return result;
}

EXPORT char* extract_vrcx_metadata(const char* file_path) {
    const char* dot = strrchr(file_path, '.');
    const char* ext = dot ? dot : "";
    char* res = extract_vrc_metadata(file_path, ext);
    if (res) return res;
    return extract_resonite_metadata(file_path, ext);
}

EXPORT void free_metadata(char* ptr) {
    if (ptr) free(ptr);
}
