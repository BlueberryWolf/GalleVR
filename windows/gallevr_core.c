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

    // png chunk format: [length][type][data][crc]
    while (fread(&len_be, 4, 1, file) == 1) {
        uint32_t chunk_length = BSWAP32(len_be);
        if (fread(type, 4, 1, file) != 1) break;

        // VRCX metadata is stored in iTXt chunks
        if (strcmp(type, "iTXt") == 0 || strcmp(type, "tEXt") == 0) {
            char* chunk_data = (char*)malloc(chunk_length);
            if (!chunk_data) break;
            
            if (fread(chunk_data, 1, chunk_length, file) != chunk_length) {
                free(chunk_data);
                break;
            }

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
                
                char* result = (char*)malloc(json_len + 1);
                if (result) {
                    memcpy(result, json_start, json_len);
                    result[json_len] = '\0';
                }

                free(chunk_data);
                fclose(file);
                return result;
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
    return NULL;
}

EXPORT void free_metadata(char* ptr) {
    if (ptr) free(ptr);
}
