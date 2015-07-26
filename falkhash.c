#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

uint64_t
falkhash_test(uint8_t *data, uint64_t len, uint32_t seed, void *out);

uint64_t
rdtsc64(void);

#define SIZE (1024 * 1024)

int
main(void)
{
	uint8_t  *str;
	uint64_t  tests, it, bytes = 0;

	str = malloc(SIZE);
	if(!str){
		perror("malloc() error ");
		return -1;
	}
	memset(str, 0x41, SIZE);

	it = rdtsc64();
	for(tests = 0; tests < 100000; tests++){
		uint64_t hash[2];

		falkhash_test(str, SIZE, 0, hash);
		bytes += SIZE;
	}
	printf("Cycles per byte %f\n", (double)(rdtsc64() - it) / bytes);

	return 0;
}

