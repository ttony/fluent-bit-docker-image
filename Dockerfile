FROM registry.access.redhat.com/ubi8/ubi:8.4-211

# Fluent Bit version
ENV FLB_MAJOR 1
ENV FLB_MINOR 7
ENV FLB_PATCH 3
ENV FLB_VERSION 1.7.3

ARG FLB_TARBALL=https://github.com/fluent/fluent-bit/archive/v$FLB_VERSION.tar.gz
ENV FLB_SOURCE $FLB_TARBALL
RUN mkdir -p /fluent-bit/bin /fluent-bit/etc /fluent-bit/log /tmp/fluent-bit-master/

RUN dnf update -y && dnf install -y cmake diffutils gcc gcc-c++ libpq-devel m4 make openssl-devel systemd-devel tar unzip && dnf clean all

# We require flex & bison which are not available for UBI to build record accessor and this is also used in some other output plugins
# We could build 1.6.10 as the 1.7 series will not build without RA: https://github.com/fluent/fluent-bit/issues/3097
# We must disable http input as well because this triggers another RA failure in 1.6.10: https://github.com/fluent/fluent-bit/issues/2930
#RUN cmake -DFLB_RECORD_ACCESSOR=Off -DFLB_STREAM_PROCESSOR=Off -DFLB_IN_HTTP=Off -DFLB_OUT_LOKI=Off -DFLB_TLS=On ../ && make && install bin/fluent-bit /fluent-bit/bin/
ARG BISON_VER=3.7
ARG BUSON_URL=http://ftp.gnu.org/gnu/bison
ARG FLEX_VER=2.6.4
ARG FLEX_URL=https://github.com/westes/flex/files/981163
ADD ${BUSON_URL}/bison-${BISON_VER}.tar.gz /bison/
ADD ${FLEX_URL}/flex-${FLEX_VER}.tar.gz /flex/
RUN tar -xzvf /bison/bison-${BISON_VER}.tar.gz -C /bison/ && tar -xzvf /flex/flex-${FLEX_VER}.tar.gz -C /flex/
# Flex needs Bison so do first
WORKDIR /bison/bison-${BISON_VER}/
RUN ./configure && make && make install && rm -rf /bison
WORKDIR /flex/flex-${FLEX_VER}/
RUN ./configure && make && make install && rm -rf /flex

RUN curl -L -o "/tmp/fluent-bit.tar.gz" ${FLB_SOURCE} \
    && cd /tmp/ && mkdir fluent-bit \
    && tar zxfv fluent-bit.tar.gz -C ./fluent-bit --strip-components=1 \
    && cd fluent-bit/build/ \
    && rm -rf /tmp/fluent-bit/build/*

WORKDIR /tmp/fluent-bit/build/
RUN cmake -DFLB_RELEASE=On \
          -DFLB_TRACE=Off \
          -DFLB_JEMALLOC=On \
          -DFLB_TLS=On \
          -DFLB_SHARED_LIB=Off \
          -DFLB_EXAMPLES=Off \
          -DFLB_HTTP_SERVER=On \
          -DFLB_IN_SYSTEMD=On \
          -DFLB_OUT_KAFKA=On \
          -DFLB_OUT_PGSQL=On ..

RUN make -j $(getconf _NPROCESSORS_ONLN)
RUN install bin/fluent-bit /fluent-bit/bin/

# Configuration files
COPY conf/fluent-bit.conf \
     conf/parsers.conf \
     conf/parsers_ambassador.conf \
     conf/parsers_java.conf \
     conf/parsers_extra.conf \
     conf/parsers_openstack.conf \
     conf/parsers_cinder.conf \
     conf/plugins.conf \
     /fluent-bit/etc/


#
EXPOSE 2020

#
ENV USER=1001 \
    USERGROUP=2001

RUN groupadd -g ${USERGROUP} app && useradd -u ${USER} -g app -s /bin/sh app

#
USER ${USER}

# Entry point
CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf"]
