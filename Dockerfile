ARG AWS_ACCOUNT_ID
FROM ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/hls-base:latest
ENV PREFIX=/usr/local \
    SRC_DIR=/usr/local/src \
    GCTPLIB=/usr/local/lib \
    HDFLIB=/usr/local/lib \
    ZLIB=/usr/local/lib \
    SZLIB=/usr/local/lib \
    JPGLIB=/usr/local/lib \
    PROJLIB=/usr/local/lib \
    HDFINC=/usr/local/include \
    GCTPINC=/usr/local/include \
    GCTPLINK="-lGctp -lm" \
    HDFLINK=" -lmfhdf -ldf -lm" \
		L8_AUX_DIR=/usr/local/src \
    ECS_ENABLE_TASK_IAM_ROLE=true \
    PYTHONPATH="${PREFIX}/lib/python2.7/site-packages" \
    ACCODE=LaSRCL8V3.5.5

# Move common files to source directory
COPY ./hls_libs/common $SRC_DIR

# Move and compile tiling
COPY ./hls_libs/tiling ${SRC_DIR}/tiling
RUN cd ${SRC_DIR}/tiling \
    && make \
    && make clean \
    && make install \
    && cd $SRC_DIR \
    && rm -rf tiling


# Move and compile nbar
COPY ./hls_libs/nbar ${SRC_DIR}/nbar
RUN cd ${SRC_DIR}/nbar \
    && make \
    && make clean \
    && make install \
    && cd $SRC_DIR \
    && rm -rf nbar

COPY ./scripts/* ${PREFIX}/bin/

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["landsat-tile.sh"]
