/* version.h - in place of the one upstream's Makefile generates
 * (scripts/gen-version-h.sh): the release and the commit this core builds. */
#ifndef VJAG_VERSION_H
#define VJAG_VERSION_H
#define CORE_BASE_VERSION "v3.9.0"
#define GIT_VERSION " 6bf3574"
#define CORE_VERSION CORE_BASE_VERSION GIT_VERSION
#endif
