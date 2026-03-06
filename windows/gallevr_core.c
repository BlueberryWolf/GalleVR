#ifdef _WIN32
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// Fast PNG chunk scanner to find VRCX metadata in Description field
// Returns a pointer to a heap-allocated string (C-string). Caller must free it.
EXPORT char* extract_vrcx_metadata(const char* file_path) {
    FILE* file = fopen(file_path, "rb");
    if (!file) return NULL;

    // Check PNG signature
    unsigned char signature[8];
    if (fread(signature, 1, 8, file) != 8) {
        fclose(file);
        return NULL;
    }
    if (signature[0] != 0x89 || signature[1] != 0x50 || signature[2] != 0x4E || signature[3] != 0x47 ||
        signature[4] != 0x0D || signature[5] != 0x0A || signature[6] != 0x1A || signature[7] != 0x0A) {
        fclose(file);
        return NULL;
    }

    // Scan chunks
    while (true) {
        uint32_t length_be = 0;
        if (fread(&length_be, 1, 4, file) != 4) break;
        
        // Convert from big-endian
        uint32_t length = ((length_be & 0xFF) << 24) | ((length_be & 0xFF00) << 8) | 
                          ((length_be & 0xFF0000) >> 8) | ((length_be & 0xFF000000) >> 24);

        char type[5] = {0};
        if (fread(type, 1, 4, file) != 4) break;

        // We are looking for tEXt or iTXt
        bool is_text = (strcmp(type, "tEXt") == 0);
        bool is_itxt = (strcmp(type, "iTXt") == 0);

        if (is_text || is_itxt) {
            char* data = (char*)malloc((size_t)length + 1);
            if (data) {
                if (fread(data, 1, length, file) == length) {
                    data[length] = '\0';
                    
                    char* null_pos = (char*)memchr(data, '\0', length);
                    if (null_pos != NULL) {
                        size_t keyword_len = null_pos - data;
                        if (keyword_len == 11 && memcmp(data, "Description", 11) == 0) {
                            char* value = NULL;
                            if (is_text) {
                                value = null_pos + 1;
                            } else {
                                size_t offset_after_null = (null_pos - data) + 3;
                                if (length > offset_after_null) {
                                    char* lang_null = (char*)memchr(null_pos + 3, '\0', length - offset_after_null);
                                    if (lang_null != NULL) {
                                        size_t lang_offset = lang_null - data + 1;
                                        if (length > lang_offset) {
                                            char* trans_null = (char*)memchr(lang_null + 1, '\0', length - lang_offset);
                                            if (trans_null != NULL) {
                                                value = trans_null + 1;
                                            }
                                        }
                                    }
                                }
                            }

                            if (value != NULL) {
                                if (strstr(value, "VRCX") != NULL) {
                                    char* result = (char*)malloc(strlen(value) + 1);
                                    if (result) {
                                        strcpy(result, value);
                                        free(data);
                                        fclose(file);
                                        return result;
                                    }
                                }
                            }
                        }
                    }
                }
                free(data);
            }
            // Skip CRC
            fseek(file, 4, SEEK_CUR);
        } else {
            // Skip data and CRC
            fseek(file, length + 4, SEEK_CUR);
        }

        // Stop if we hit IDAT
        if (strcmp(type, "IDAT") == 0) break;
    }

    fclose(file);
    return NULL;
}

EXPORT void free_metadata(char* ptr) {
    if (ptr) free(ptr);
}
