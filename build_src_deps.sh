#!/usr/bin/env bash

set -ex

BASEDIR="$HOME/src"

function build_nasm {
  cd "$BASEDIR"
  rm -rf "$BASEDIR/nasm"
  git clone -b nasm-2.13.02 http://repo.or.cz/nasm.git "$BASEDIR/nasm"
  cd "$BASEDIR/nasm"
  ./autogen.sh
  ./configure
  make
}

function build_x264 {
  cd "$BASEDIR"
  rm -rf "$BASEDIR/x264"
  git clone http://git.videolan.org/git/x264.git "$BASEDIR/x264"
  cd "$BASEDIR/x264"
  ./configure --enable-pic --enable-static
  make
}

function build_ffmpeg {
  cd "$BASEDIR"
  rm -rf "$BASEDIR/ffmpeg"
  git clone https://git.ffmpeg.org/ffmpeg.git "$BASEDIR/ffmpeg"
  cd "$BASEDIR/ffmpeg"
  ./configure --enable-gpl --enable-libx264
  make
}

if [ -z "$1" ]; then
  build_nasm
  build_x264
  build_ffmpeg
else
  build_"$1"
fi
