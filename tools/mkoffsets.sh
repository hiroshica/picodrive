# automatically compute structure offsets for gcc targets in ELF format
# (C) 2018 Kai-Uwe Bloem. This work is placed in the public domain.
#
# usage: mkoffsets <output dir>

CC=${CC:-gcc}

# endianess of target (automagically determined below)
ENDIAN=

# check which object format to dissect
READELF=
OBJDUMP=
check_obj ()
{
	# prepare an object file; as side effect dtermine the endianess
	CROSS=$(echo $CC | sed 's/gcc.*//')
	echo '#include <stdint.h>' >/tmp/getoffs.c
	echo "const int32_t val = 1;" >>/tmp/getoffs.c
	$CC $CFLAGS -I .. -c /tmp/getoffs.c -o /tmp/getoffs.o || exit 1

	# check for readelf; readelf is the only toolchain tool not using bfd,
	# hence it works with ELF files for every target
	if file /tmp/getoffs.o | grep -q ELF; then
		if command -v readelf >/dev/null; then
			READELF=readelf
		elif command -v ${CROSS}readelf >/dev/null; then
			READELF=${CROSS}readelf
		fi
	fi
	if [ -n "$READELF" ]; then
		# find the the .rodata section (in case -fdata-sections is used)
		rosect=$($READELF -S /tmp/getoffs.o | grep '\.rodata\|\.sdata' |
						sed 's/^[^.]*././;s/ .*//')
		# read .rodata section as hex string (should be only 4 bytes)
		ro=$($READELF -x $rosect /tmp/getoffs.o | grep '0x' | cut -c14-48 |
						tr -d ' \n' | cut -c1-8)
		# if no output could be read readelf isn't working
		if [ -z "$ro" ]; then
			READELF=
		fi
	fi
	# if there is no working readelf try using objdump
	if [ -z "$READELF" ]; then
		# objdump is using bfd; try using the toolchain objdump first
		# since this is likely working with the toolchain objects
		if command -v ${CROSS}objdump >/dev/null; then
			OBJDUMP=${CROSS}objdump
		elif command -v objdump >/dev/null; then
			OBJDUMP=objdump
		fi
		# find the start line of the .rodata section; read the next line
		ro=$($OBJDUMP -s /tmp/getoffs.o | awk '\
		  /Contents of section.*(__const|.ro?data|.sdata)/ {o=1; next} \
		  {if(o) { gsub(/  .*/,""); $1=""; gsub(/ /,""); print; exit}}')
		# no working tool for extracting the ro data; stop here
		if [ -z "$ro" ]; then
			echo "/* mkoffset.sh: no readelf or not ELF, offset table not created */" >$fn
			echo "WARNING: no readelf or not ELF, offset table not created"
			exit
		fi
	fi
	# extract decimal value from ro
	rodata=$(printf "%d" 0x$ro)
	ENDIAN=$(if [ "$rodata" -eq 1 ]; then echo be; else echo le; fi)
}

# compile with target C compiler and extract value from .rodata section
compile_rodata ()
{
	$CC $CFLAGS -I .. -c /tmp/getoffs.c -o /tmp/getoffs.o || exit 1
	if [ -n "$READELF" ]; then
		# find the .rodata section (in case -fdata-sections is used)
		rosect=$(readelf -S /tmp/getoffs.o | grep '\.rodata\|\.sdata' |
						sed 's/^[^.]*././;s/ .*//')
		# read .rodata section as hex string (should be only 4 bytes)
		ro=$(readelf -x $rosect /tmp/getoffs.o | grep '0x' | cut -c14-48 |
						tr -d ' \n' | cut -c1-8)
	elif [ -n "$OBJDUMP" ]; then
		# find the start line of the .rodata section; read the next line
		ro=$($OBJDUMP -s /tmp/getoffs.o | awk '\
		  /Contents of section.*(__const|.ro?data|.sdata)/ {o=1; next} \
		  {if(o) { gsub(/  .*/,""); $1=""; gsub(/ /,""); print; exit}}')
	fi
	if [ "$ENDIAN" = "le" ]; then
		# swap needed for le target
		hex=""
		for b in $(echo $ro | sed 's/\([0-9a-f]\{2\}\)/\1 /g'); do
			hex=$b$hex;
		done
	else
		hex=$ro
	fi
	# extract decimal value from hex string
	rodata=$(printf "%d" 0x$hex)
}

# determine member offset and create #define
get_define () # prefix struct member member...
{
	prefix=$1; shift
	struct=$1; shift
	field=$(echo $* | sed 's/ /./g')
	name=$(echo $* | sed 's/ /_/g')
	echo '#include <stdint.h>' > /tmp/getoffs.c
	echo '#include "pico/pico_int.h"' >> /tmp/getoffs.c
	echo "static struct $struct p;" >> /tmp/getoffs.c
	echo "const int32_t val = (char *)&p.$field - (char*)&p;" >>/tmp/getoffs.c
	compile_rodata
	line=$(printf "#define %-20s 0x%04x" $prefix$name $rodata)
}

fn="${1:-.}/pico_int_offs.h"
if echo $CFLAGS | grep -qe -flto; then CFLAGS="$CFLAGS -fno-lto"; fi

check_obj
# output header
echo "/* autogenerated by mkoffset.sh, do not edit */" >$fn
echo "/* target endianess: $ENDIAN, compiled with: $CC $CFLAGS */" >>$fn
# output offsets
get_define OFS_Pico_ Pico video reg		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m rotate		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m z80Run		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m dirtyPal		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m hardware		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m z80_reset		; echo "$line" >>$fn
get_define OFS_Pico_ Pico m sram_reg		; echo "$line" >>$fn
get_define OFS_Pico_ Pico sv			; echo "$line" >>$fn
get_define OFS_Pico_ Pico sv data		; echo "$line" >>$fn
get_define OFS_Pico_ Pico sv start		; echo "$line" >>$fn
get_define OFS_Pico_ Pico sv end		; echo "$line" >>$fn
get_define OFS_Pico_ Pico sv flags		; echo "$line" >>$fn
get_define OFS_Pico_ Pico rom			; echo "$line" >>$fn
get_define OFS_Pico_ Pico romsize		; echo "$line" >>$fn
get_define OFS_Pico_ Pico est			; echo "$line" >>$fn

get_define OFS_EST_ PicoEState DrawScanline	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState rendstatus	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState DrawLineDest	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState HighCol		; echo "$line" >>$fn
get_define OFS_EST_ PicoEState HighPreSpr	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState Pico		; echo "$line" >>$fn
get_define OFS_EST_ PicoEState PicoMem_vram	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState PicoMem_cram	; echo "$line" >>$fn
get_define OFS_EST_ PicoEState PicoOpt		; echo "$line" >>$fn
get_define OFS_EST_ PicoEState Draw2FB		; echo "$line" >>$fn
get_define OFS_EST_ PicoEState HighPal		; echo "$line" >>$fn

get_define OFS_PMEM_ PicoMem vram		; echo "$line" >>$fn
get_define OFS_PMEM_ PicoMem vsram		; echo "$line" >>$fn
get_define OFS_PMEM32x_ Pico32xMem pal_native	; echo "$line" >>$fn

get_define OFS_SH2_ SH2_ is_slave		; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_bios			; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_da			; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_sdram		; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_rom			; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_dram			; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_drcblk_da		; echo "$line" >>$fn
get_define OFS_SH2_ SH2_ p_drcblk_ram		; echo "$line" >>$fn
