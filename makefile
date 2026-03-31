ASM=nasm

CC=gcc

SRC_DIR=.
TOOLS_DIR=tools

BUILD_DIR=build

.PHONY:all floppy_image kernel bootloader clean always tools_fat

all:floppy_image tools_fat

#floppy image
floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: Bootloader Kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "NBOS" $(BUILD_DIR)/main_floppy.img
	dd if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main_floppy.img conv=notrunc
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"
# 	mcopy -i $(BUILD_DIR)/main_floppy.img test.txt "::test.txt"
#
#Bootloader
#
Bootloader:$(BUILD_DIR)/bootloader.bin
$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/Bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

#Kernel
Kernel:$(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/main.asm -f bin -o $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/main.bin:$(SRC_DIR)/main.asm
	$(ASM) $(SRC_DIR)/main.asm -f bin -o $(BUILD_DIR)/main.bin


#
#Tools
#
tools_fat:$(BUILD_DIR)/tools/fat
$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools
	$(CC) -g -o $(BUILD_DIR)/tools/fat $(TOOLS_DIR)/fat/fat.c


#Always
always:
	mkdir -p $(BUILD_DIR)

#clean:
	rm -rf $(BUILD_DIR)/*

#qemu
run_boot:
	qemu-system-i386 -fda boot.bin
	
#main_floppy
run:
	qemu-system-i386 -fda build/main_floppy.img