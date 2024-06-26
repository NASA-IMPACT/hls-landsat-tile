FROM 018923174646.dkr.ecr.us-west-2.amazonaws.com/espa/external-c2
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
    ECS_ENABLE_TASK_IAM_ROLE=true \
    PYTHONPATH="${PYTHONPATH}:${PREFIX}/lib/python3.6/site-packages" \
    ACCODE=LaSRCL8V3.5.1 \
    LC_ALL=en_US.utf-8 \
    LANG=en_US.utf-8

# Python base dependencies
RUN pip3 install scipy awscli gdal~=2.4
RUN ln -fs /usr/bin/python3 /usr/bin/python

# The Python click library requires a set locale
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

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


# Move and compile angle_tiling
COPY ./hls_libs/angle_tiling ${SRC_DIR}/angle_tiling
RUN cd ${SRC_DIR}/angle_tiling \
    && make \
    && make clean \
    && make install \
    && cd $SRC_DIR \
    && rm -rf angle_tiling

RUN pip3 install click==7.1.2
RUN pip3 install rio-cogeo==1.1.10 --no-binary rasterio --user
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-thumbnails@v1.3
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-metadata@v2.5
RUN pip3 install wheel
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-browse_imagery@v1.7
RUN pip3 install libxml2-python3
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-hdf_to_cog@v2.1
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-manifest@v2.0
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-cmr_stac@v1.7
RUN pip3 install git+https://github.com/NASA-IMPACT/hls-utilities@v1.6

COPY ./python_scripts/* ${PREFIX}/bin/
COPY ./scripts/* ${PREFIX}/bin/


ENTRYPOINT ["/bin/sh", "-c"]
CMD ["landsat-tile.sh"]
