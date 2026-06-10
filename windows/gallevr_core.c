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

EXPORT char* extract_vrcx_metadata(const char* file_path) {
    FILE* file = fopen(file_path, "rb");
    if (!file) return NULL;

    // skip png signature
    if (fseek(file, 8, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }

    uint32_t len_be;
    char type[5] = {0};
    char* vrchat_xml = NULL;

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

            if (json_start) {
                // calculate length from start of JSON to end of chunk
                size_t json_len = chunk_length - (json_start - chunk_data);
                char* result = malloc(json_len + 1);
                if (result) {
                    memcpy(result, json_start, json_len);
                    result[json_len] = '\0';
                }
                free(chunk_data);
                if (vrchat_xml) free(vrchat_xml);
                fclose(file);
                return result;
            }

            if (!vrchat_xml) {
                char* xml_ptr = chunk_data;
                while (xml_ptr < chunk_data + chunk_length && *xml_ptr != '<') {
                    xml_ptr++;
                }
                if (xml_ptr < chunk_data + chunk_length && (strstr(xml_ptr, "<xmp:CreatorTool>VRChat</xmp:CreatorTool>") || strstr(xml_ptr, "<vrc:WorldID>"))) {
                    size_t xml_len = (chunk_data + chunk_length) - xml_ptr;
                    vrchat_xml = malloc(xml_len + 1);
                    if (vrchat_xml) {
                        memcpy(vrchat_xml, xml_ptr, xml_len);
                        vrchat_xml[xml_len] = '\0';
                    }
                }
            }

            free(chunk_data);
            fseek(file, 4, SEEK_CUR); // skip CRC
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

    fclose(file);

    if (vrchat_xml) {
        char* world_id = extract_tag(vrchat_xml, "vrc:WorldID");
        char* world_name = extract_tag(vrchat_xml, "vrc:WorldDisplayName");
        char* author = extract_tag(vrchat_xml, "xmp:Author");
        char* create_date = extract_tag(vrchat_xml, "xmp:CreateDate");

        char* result = malloc(1024 + (world_id ? strlen(world_id) : 0) + (world_name ? strlen(world_name) : 0) + (author ? strlen(author) : 0));
        if (result) {
            sprintf(result, 
                "{\"application\":\"VRChat\",\"version\":\"1.0\","
                "\"world\":{\"id\":\"%s\",\"name\":\"%s\"},"
                "\"authorName\":\"%s\",\"createDate\":\"%s\"}",
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
        free(vrchat_xml);
        return result;
    }

    return NULL;
}

EXPORT void free_metadata(char* ptr) {
    if (ptr) free(ptr);
}
