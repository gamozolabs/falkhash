[bits 64]

section .code

%macro XMMPUSH 1
	sub rsp, 16
	movdqu [rsp], %1
%endmacro

%macro XMMPOP 1
	movdqu %1, [rsp]
	add rsp, 16
%endmacro

; A chunk_size of 0x50 is ideal for AMD fam 15h platforms, which is what this
; was optimized and designed for. If you change this value, you have to
; manually add/remove movdqus and aesencs from the core loop. This must be
; divisible by 16.
%define CHUNK_SIZE 0x50

; rdi  -> data
; rsi  -> len
; edx  -> seed
; xmm5 <- 128-bit hash
;
; All non-output GP registers are preserved, conforming to the falkos ABI.
; All non-output XMM registers are also preserved.
falkhash:
	push rax
	push rcx
	push rdi
	push rsi

	XMMPUSH xmm0
	XMMPUSH xmm1
	XMMPUSH xmm2
	XMMPUSH xmm3
	XMMPUSH xmm4
	XMMPUSH xmm6

	sub rsp, CHUNK_SIZE

	; Clear stack memory for tail chunk
	pxor xmm5, xmm5
	movdqu [rsp], xmm5
	movdqu [rsp + 0x10], xmm5
	movdqu [rsp + 0x20], xmm5
	movdqu [rsp + 0x30], xmm5
	movdqu [rsp + 0x40], xmm5

	; Add the seed to the length
	mov rax, rsi
	add rax, rdx

	; Place the seed to low 64bits and length+seed to high 64-bits of xmm6
	pinsrq xmm6, rsi, 0
	pinsrq xmm6, rax, 1
	movdqa xmm5, xmm6

.lewp:
	; If we have less than a chunk, copy the partial chunk to the stack.
	cmp rsi, CHUNK_SIZE
	jb  short .pad_last_chunk

.continue:
	; Read 5 pieces from memory into xmms
	movdqu xmm0, [rdi + 0x00]
	movdqu xmm1, [rdi + 0x10]
	movdqu xmm2, [rdi + 0x20]
	movdqu xmm3, [rdi + 0x30]
	movdqu xmm4, [rdi + 0x40]

	; Seed and mix all pieces into xmm0
	pxor   xmm0, xmm6
	pxor   xmm1, xmm6
	pxor   xmm2, xmm6
	pxor   xmm3, xmm6
	pxor   xmm4, xmm6
	aesenc xmm0, xmm1
	aesenc xmm0, xmm2
	aesenc xmm0, xmm3
	aesenc xmm0, xmm4

	; Finalize xmm0
	aesenc xmm0, xmm6

	; Mix hash and xor xmm0 into the hash
	aesenc xmm5, xmm0

	; Go to the next chunk, fall through if we're done.
	add rdi, CHUNK_SIZE
	sub rsi, CHUNK_SIZE
	jnz short .lewp
	jmp short .done

.pad_last_chunk:
	; Copy the remainder of data to the stack
	mov rcx, rsi
	mov rsi, rdi
	mov rdi, rsp
	rep movsb

	; Make our data now come from the stack, and set the size to one chunk.
	mov rdi, rsp
	mov rsi, CHUNK_SIZE

	jmp short .continue

.done:
	; Finalize the hash. This is required at least once to pass
	; Combination 0x8000000 and Combination 0x0000001. Need more than 1 to
	; pass the Seed tests. We do 4 because they're pretty much free.
	aesenc xmm5, xmm6
	aesenc xmm5, xmm6
	aesenc xmm5, xmm6
	aesenc xmm5, xmm6

	add rsp, CHUNK_SIZE

	XMMPOP xmm6
	XMMPOP xmm4
	XMMPOP xmm3
	XMMPOP xmm2
	XMMPOP xmm1
	XMMPOP xmm0

	pop rsi
	pop rdi
	pop rcx
	pop rax
	ret

; rdi -> pointer to data
; rsi -> len
; edx -> 32-bit seed
; rcx <> pointer to caller allocated 128-bit hash destination
;
; All non-output GP registers are preserved, conforming to the falkos ABI.
; All XMM registers are preserved.
global falkhash_test
falkhash_test:
	push rcx
	push rdx
	push rsi
	push rdi

	XMMPUSH xmm5

%ifdef WIN
	; Translate from windows to linux calling convention
	mov rdi, rcx
	mov rsi, rdx
	mov rdx, r8
	mov rcx, r9
%endif

	call falkhash

	; Store the hash into the hash destination
	movdqu [rcx], xmm5

	XMMPOP xmm5

	pop rdi
	pop rsi
	pop rdx
	pop rcx
	ret

; rax <- 64-bit rdtsc value
global rdtsc64
rdtsc64:
	push rdx

	rdtsc
	shl rdx, 32
	or  rax, rdx
	
	pop rdx
	ret

