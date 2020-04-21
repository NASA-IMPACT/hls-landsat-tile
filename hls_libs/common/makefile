# Note: before run make, do in the shell:
# source $HOME/code/share/makeenv/makeenv.sh

TGT = L8inS2tile
OBJ = 	L8inS2tile.o \
	hls_projection.o \
	lsat.o \
	lsatmeta.o \
	util.o \
	hdfutility.o \
	read_arop_output.o \
	resample_lsat.o \
	cubic_conv.o 

	
$(TGT): $(OBJ)
	$(CC) $(CFLAGS) -o $(TGT) $(OBJ)  -L$(GCTPLIB) -L$(HDFLIB) -L$(ZLIB) -L$(SZLIB) -L$(JPGLIB) -L$(PROJLIB) $(GCTPLINK) $(HDFLINK) 

L8inS2tile.o: L8inS2tile.c 
	$(CC) $(CFLAGS) -c L8inS2tile.c -I$(HDFINC) -I$(GCTPINC)

hls_projection.o: hls_projection.c
	$(CC) $(CFLAGS) -c hls_projection.c -I$(GCTPINC) -I$(HDFINC)

lsat.o: lsat.c
	$(CC) $(CFLAGS) -c lsat.c -I$(HDFINC)

lsatmeta.o: lsatmeta.c
	$(CC) $(CFLAGS) -c lsatmeta.c -I$(HDFINC)

util.o: util.c
	$(CC) $(CFLAGS) -c  util.c -I$(HDFINC)

hdfutility.o: hdfutility.c
	$(CC) $(CFLAGS) -c  hdfutility.c -I$(HDFINC)

read_arop_output.o: read_arop_output.c
	$(CC) $(CFLAGS) -c read_arop_output.c -I$(HDFINC)

resample_lsat.o: resample_lsat.c
	$(CC) $(CFLAGS) -c resample_lsat.c -I$(HDFINC)

cubic_conv.o: cubic_conv.c
	$(CC) $(CFLAGS) -c cubic_conv.c -I$(HDFINC)

link:
	ln -sf ../../common/lsat.h
	ln -sf ../../common/lsat.c
	ln -sf ../../common/lsatmeta.h
	ln -sf ../../common/lsatmeta.c

	ln -sf ../../../share/common/hls_commondef.h
	ln -sf ../../../share/common/fillval.h
	ln -sf ../../../share/common/hdfutility.h
	ln -sf ../../../share/common/hdfutility.c
	ln -sf ../../../share/common/read_arop_output.h
	ln -sf ../../../share/common/read_arop_output.c
	

	ln -sf ../../../share/common/hls_projection.h
	ln -sf ../../../share/common/hls_projection.c
	ln -sf ../../../share/common/cubic_conv.h
	ln -sf ../../../share/common/cubic_conv.c
	ln -sf ../../../share/common/util.h
	ln -sf ../../../share/common/util.c

clean:
	rm -f *.o


