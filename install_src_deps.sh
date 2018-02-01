#!/usr/bin/env bash

set -ex

BASEDIR="$HOME/src"

if [ ! -e "$BASEDIR/nasm/nasm" ]; then
    ~/.build_src_deps.sh nasm
fi
cd $BASEDIR/nasm
sudo make install || echo "Installing docs fails but should be OK otherwise"

if [ ! -e "$BASEDIR/x264/x264" ]; then
    ~/.build_src_deps.sh x264
fi
cd $BASEDIR/x264
sudo make install

if [ ! -e "$BASEDIR/ffmpeg/ffmpeg" ]; then
    ~/.build_src_deps.sh ffmpeg
fi
cd $BASEDIR/ffmpeg
sudo make install
