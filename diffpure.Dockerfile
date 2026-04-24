FROM nvidia/cuda:11.0.3-devel-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive

# Install package dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        ca-certificates \
        wget \
        git \
        curl \
        ca-certificates \
        libjpeg-dev \
        libpng-dev \
        python \
        python3-dev \
        python3-pip \
        python3-setuptools \
        zlib1g-dev \
        swig \
        cmake \
        vim \
        locales \
        locales-all \
        screen \
        zip \
        unzip
RUN apt-get clean

ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

RUN cd /usr/local/bin && \
    ln -s /usr/bin/python3 python && \
    ln -s /usr/bin/pip3 pip && \
    pip install --upgrade pip setuptools

COPY requirements.txt .
RUN pip install -r requirements.txt