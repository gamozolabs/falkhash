[bits 64]

section .code

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
;
; xmm0 through xmm5 are smashed. This is fine for windows x64, system V x64,
; and falkos ABIs.
falkhash:
	push rax
	push rcx
	push rdi
	push rsi
	push rbp
	sub  rsp, CHUNK_SIZE

	; Add the seed to the length
	mov rbp, rsi
	add rbp, rdx

	; Place the length+seed for both the low and high 64-bits into xmm5,
	; our hash output.
	pinsrq xmm5, rbp, 0
	pinsrq xmm5, rbp, 1

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

	; Mix all pieces into xmm0
	aesenc xmm0, xmm1
	aesenc xmm0, xmm2
	aesenc xmm0, xmm3
	aesenc xmm0, xmm4

	; Finalize xmm0 by mixing with itself
	aesenc xmm0, xmm0

	; Mix in xmm0 to the hash
	aesenc xmm5, xmm0

	; Go to the next chunk, fall through if we're done.
	add rdi, CHUNK_SIZE
	sub rsi, CHUNK_SIZE
	jnz short .lewp
	jmp short .done

.pad_last_chunk:
	; Fill the stack with 0xff's, this is our padding
	push rdi
	lea  rdi, [rsp + 8]
	mov  rax, -1
	mov  ecx, (CHUNK_SIZE / 8)
	rep  stosq
	pop  rdi

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
	; Maybe we should actually use the seed better? Nah, more finalizing!
	aesenc xmm5, xmm5
	aesenc xmm5, xmm5
	aesenc xmm5, xmm5
	aesenc xmm5, xmm5

	add rsp, CHUNK_SIZE
	pop rbp
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
;
; xmm0 through xmm5 are smashed. This is fine for windows x64, system V x64,
; and falkos ABIs.
global falkhash_test
falkhash_test:
	push rcx
	push rdx
	push rsi
	push rdi

%ifdef WIN
	; Translate from windows to linux calling convention
	mov rdi, rcx
	mov rsi, rdx
	mov rdx, r8
	mov rcx, r9
%endif

	call falkhash

	; Store the hash into the hash destination
	movdqa [rcx], xmm5

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

