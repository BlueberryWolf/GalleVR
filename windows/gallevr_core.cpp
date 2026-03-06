#ifdef _WIN32
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <algorithm>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C" {

// Fast PNG chunk scanner to find VRCX metadata in Description field
// Returns a pointer to a heap-allocated string (C-string). Caller must free it.
EXPORT char* extract_vrcx_metadata(const char* file_path) {
    std::ifstream file(file_path, std::ios::binary);
    if (!file) return nullptr;

    // Check PNG signature
    unsigned char signature[8];
    if (!file.read((char*)signature, 8)) return nullptr;
    if (signature[0] != 0x89 || signature[1] != 0x50 || signature[2] != 0x4E || signature[3] != 0x47 ||
        signature[4] != 0x0D || signature[5] != 0x0A || signature[6] != 0x1A || signature[7] != 0x0A) {
        return nullptr;
    }

    // Scan chunks
    while (file) {
        uint32_t length_be = 0;
        if (!file.read((char*)&length_be, 4)) break;
        
        // Convert from big-endian
        uint32_t length = ((length_be & 0xFF) << 24) | ((length_be & 0xFF00) << 8) | 
                          ((length_be & 0xFF0000) >> 8) | ((length_be & 0xFF000000) >> 24);

        char type[5] = {0};
        if (!file.read(type, 4)) break;

        // We are looking for tEXt or iTXt
        bool is_text = (strcmp(type, "tEXt") == 0);
        bool is_itxt = (strcmp(type, "iTXt") == 0);

        if (is_text || is_itxt) {
            std::vector<char> data(length);
            if (file.read(data.data(), length)) {
                std::string data_str(data.data(), length);
                
                size_t null_pos = data_str.find('\0');
                if (null_pos != std::string::npos) {
                    std::string keyword = data_str.substr(0, null_pos);
                    
                    if (keyword == "Description") {
                        std::string value;
                        if (is_text) {
                            value = data_str.substr(null_pos + 1);
                        } else {
                            size_t lang_null = data_str.find('\0', null_pos + 3);
                            if (lang_null != std::string::npos) {
                                size_t trans_null = data_str.find('\0', lang_null + 1);
                                if (trans_null != std::string::npos) {
                                    value = data_str.substr(trans_null + 1);
                                }
                            }
                        }

                        // Check if it's VRCX
                        if (value.find("VRCX") != std::string::npos) {
                            char* result = (char*)malloc(value.length() + 1);
                            if (result) {
                                strcpy(result, value.c_str());
                                return result;
                            }
                        }
                    }
                }
            }
            // Skip CRC
            file.seekg(4, std::ios::cur);
        } else {
            // Skip data and CRC
            file.seekg(length + 4, std::ios::cur);
        }

        // Stop if we hit IDAT
        if (strcmp(type, "IDAT") == 0) break;
    }

    return nullptr;
}

EXPORT void free_metadata(char* ptr) {
    if (ptr) free(ptr);
}

}
