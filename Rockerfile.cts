#
# This prepares an image to be ready for CTS testing
#
# ~~~
#  rocker build -f Rockerfile.cts [--attach]                                \
#    [--var TAG=master]   # master, pre-release-17.0, pre-release-13.0, ... \
#    --var RELEASE=master # master, pre-release/17.0, pre-release/13.0, ...
# ~~~
#
# Environment variables that are used in the build:
#  - DOCKER_IMAGE: name of the final image to be tagged (default: igalia/mesa)
#

{{ $image := (or .Env.DOCKER_IMAGE "igalia/mesa") }}

FROM {{ $image }}:{{ .RELEASE }}

LABEL maintainer "Andres Gomez <agomez@igalia.com>"

USER root

RUN apt-get update                                                  \
  && apt-get -y --no-install-recommends install ssh less nano       \
  && rm -fr /var/lib/apt/lists/*

USER local

RUN git clone http://github.com/Igalia/piglit.git /home/local/piglit.git

ENV vblank_mode=0

{{ if .TAG }}
TAG {{ $image }}:{{ .TAG }}
{{ end }}
