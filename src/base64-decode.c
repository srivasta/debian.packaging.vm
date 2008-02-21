/* public domain */

/* BASE64 on stdin -> converted data on stdout */

#include <stdlib.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#ifndef WIN32
#define WIN32
#endif
#endif

#ifdef WIN32
#include <io.h>
#include <fcntl.h>
#endif

unsigned char alphabet[64] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int
main(void)
{
    static char inalphabet[256], decoder[256];
    int i, bits, char_count, errors = 0;

#ifdef WIN32
	_setmode( _fileno(stdout), _O_BINARY);
#endif

	for (i = (sizeof alphabet) - 1; i >= 0 ; i--) {
	inalphabet[alphabet[i]] = 1;
	decoder[alphabet[i]] = i;
	}

#define BUFLEN 72*500 // must be multiple of 4

    int len;
    char buf[BUFLEN];
    char outbuf[BUFLEN];

    while(!feof(stdin)) {
        unsigned char c;

        int pos=0;
        char *out=outbuf;
        len=fread(buf, sizeof(c), BUFLEN, stdin);
        if(!len) continue;

cont_buffer:
        char_count = 0;
        bits = 0;
        while(pos<len) {
            c=buf[pos++];
            if (c == '=')
                break;
            if (! inalphabet[c])
                continue;
            bits += decoder[c];
            char_count++;
            if (char_count == 4) {
                *out++ = ((bits >> 16));
                *out++ = (((bits >> 8) & 0xff));
                *out++ = ((bits & 0xff));
                bits = 0;
                char_count = 0;
            } else {
                bits <<= 6;
            }
        }
        switch (char_count) {
            case 1:
                fprintf(stderr, "base64-decode: base64 encoding incomplete: at least 2 bits missing");
                errors++;
                break;
            case 2:
                *out++ = ((bits >> 10));
                break;
            case 3:
                *out++ = ((bits >> 16));
                *out++ = (((bits >> 8) & 0xff));
                break;
            case 0:
                break;
            default:
                fprintf(stderr, "base64-decode: base64 encoding incomplete: at least %d bits truncated",
                        ((4 - char_count) * 6));
        }
        if(pos<len) // did not proceed the whole thing, continue
            goto cont_buffer;
        fwrite(outbuf, sizeof(char), (out-outbuf), stdout);
    }
    exit(errors ? 1 : 0);
}
