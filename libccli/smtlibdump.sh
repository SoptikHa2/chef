#!/usr/bin/env sh
#
# This script dumps queries from sqlite3 databases in SMT-Lib format.
#
# Maintainer: Tinu Weber <martin.weber@epfl.ch>

DOCKER_VERSION='v0.6'
DOCKER_HOSTPATH='/host'
DOCKER_HOSTPATH_IN='/host-in'
DOCKER_HOSTPATH_OUT='/host-out'
DOCKER_HOSTPATH_BUILD='/host-build'
RUNNAME="$(basename "$0")"
RUNPATH="$(readlink -f "$(dirname "$0")")"
RUNDIR="$(basename "$RUNPATH")"
SRCPATH_ROOT="$(dirname "$RUNPATH")"
if [ -z "$INVOKENAME" ]; then
	INVOKENAME="$RUNNAME"
fi

# DUMP =========================================================================

dump()
{
	case "$RELEASE" in
		'release') RELEASE_NAME='Release+Asserts' ;;
		'debug') RELEASE_NAME='Debug+Asserts' ;;
		*) die_internal 'dump(): Invalid release: %s' "$RELEASE" ;;
	esac

	TOOL_BIN="$BUILD_PATH/$BUILD/klee/$RELEASE_NAME/bin/query-tool"

	if [ ! -e "$TOOL_BIN" ]; then
		die 2 '%s not found' "$TOOL_BIN"
	fi

	"$TOOL_BIN" \
		-end-solver="$SOLVER" \
		-generate-smtlib -smtlib-out-path="$DUMP_PATH" \
		$(test $MONOLITHIC -eq 1 && echo '-smtlib-monolithic') \
		$(test $HUMAN -eq 1 && echo '-smtlib-human-readable') \
		$(test $LIMIT -gt 0 && echo "-smtlib-dump-limit $LIMIT") \
		$(test $COMPACT -eq 1 && echo '-smtlib-compact') \
		"$DB_FILE"
}

# DUMPALL ======================================================================

dumpall()
{
	DB_ROOT="$DB_PATH"
	DUMP_ROOT="$DUMP_PATH"

	die 3 'not implemented'
}

# DOCKER =======================================================================

docker_dump()
{
	docker run \
		--rm \
		-t \
		-i \
		-v "$SRCPATH_ROOT":"$DOCKER_HOSTPATH" \
		-v "$DB_PATH":"$DOCKER_HOSTPATH_IN" \
		-v "$DUMP_PATH":"$DOCKER_HOSTPATH_OUT" \
		-v "$BUILD_PATH":"$DOCKER_HOSTPATH_BUILD" \
		dslab/s2e-chef:"$DOCKER_VERSION" \
		"$DOCKER_HOSTPATH"/"$RUNDIR"/"$RUNNAME" \
			-a "$ARCH" \
			-b "$DOCKER_HOSTPATH_BUILD" \
			$(test $COMPACT -eq 1 && printf "%s" '-c') \
			-l $LIMIT \
			-m "$MODE" \
			$(test $MONOLITHIC -eq 1 && printf "%s" '-M') \
			-o "$DOCKER_HOSTPATH_OUT" \
			-r "$RELEASE" \
			-s "$SOLVER" \
			$(test $HUMAN -eq 1 && printf "%s" '-w') \
			-z \
			"$DOCKER_HOSTPATH_IN/$DB_NAME"
}

# DRY RUN ======================================================================

dryrun()
{
	cat <<- EOF
	ARCH=$ARCH
	MODE=$MODE
	RELEASE=$RELEASE
	SOLVER=$SOLVER
	DUMP_PATH=$DUMP_PATH
	DB_FILE=$DB_FILE
	MONOLITHIC=$(boolean $MONOLITHIC)
	HUMAN=$(boolean $HUMAN)
	LIMIT=$LIMIT
	EOF

	if [ $DIRECT -eq 0 ]; then
		cat <<- EOF
		DOCKER_HOSTPATH=$SRCPATH_ROOT:$DOCKER_HOSTPATH
		DOCKER_HOSTPATH_IN=$DB_PATH:$DOCKER_HOSTPATH_IN
		DOCKER_HOSTPATH_OUT=$DUMP_PATH:$DOCKER_HOSTPATH_OUT
		DOCKER_HOSTPATH_BUILD=$BUILD_PATH:$DOCKER_HOSTPATH_BUILD
		EOF
	fi
}

# UTILITIES ====================================================================

boolean()
{
	case "$1" in
		0) echo 'false' ;;
		*) echo 'true' ;;
	esac
}

# ACL + docker + mkdir -p = issues
mkdirp()
{
	test -e "$1" || mkdir "$1"
}

die()
{
	die_retval=$1
	die_format="$2"
	shift 2
	printf "$die_format\n" "$@" >&2
	exit $die_retval
}

die_help()
{
	die_help_format="$1"
	if [ -n "$die_help_format" ]; then
		shift
		printf "$die_help_format\n" "$@" >&2
	fi
	usage >&2
	die 1 'Run `%s -h` for help.' "$INVOKENAME"
}

die_internal()
{
	printf "Internal error: "
	die "$@"
}

usage()
{
	cat <<- EOF
	Usage: $INVOKENAME [OPTIONS] DB_FILE
	EOF
}

help()
{
	usage

	cat <<- EOF

	Options:
	  -a ARCH        Chef build architecture [default=$ARCH]
	  -b BUILD_PATH  Path to the Chef build directory
	                 [default=$BUILD_PATH]
	  -c             Print compact SMTLIB (experimental!)
	  -h             Display this help
	  -l LIMIT       Limit number of produced queries to LIMIT (0 = no limit) [default=0]
	  -m MODE        Build mode ('normal', 'asan', 'libmemtracer') [default=$MODE]
	  -M             Monolithic dump (no separate files)
	  -o DUMP_PATH   Dump queries from the DB file to DUMP_PATH
	                 [default=$DUMP_PATH]
	  -r RELEASE     Release mode ('release' or 'debug') [default=$RELEASE]
	  -s SOLVER      Use solver SOLVER [default=$SOLVER]
	  -w             Use whitespace to make it human-readable
	  -y             Dry run: print runtime variables and exit
	  -z             Direct mode (do not use docker)
	EOF

	#If DB_PATH denotes a directory, all database files below are searched and dumped.
	#In that case, DUMP_PATH is considered a tree that copies DB_PATH's structure.
	#EOF
}

isnumeric()
{
	case "$1" in
		''|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

# MAIN =========================================================================

get_options()
{
	# Default values:
	ARCH='i386'
	BUILD_PATH="$SRCPATH_ROOT/build"
	COMPACT=0
	DUMP_PATH="$PWD"
	LIMIT=0
	MODE='normal'
	MONOLITHIC=0
	RELEASE='release'
	SOLVER='stp'
	HUMAN=0
	DIRECT=0
	DRYRUN=0

	while getopts a:b:chl:m:Mo:r:s:wyz opt; do
		case "$opt" in
			a) ARCH="$OPTARG" ;;
			b) BUILD_PATH="$OPTARG" ;;
			c) COMPACT=1 ;;
			h) help; exit 1 ;;
			l) LIMIT="$OPTARG" ;;
			m) MODE="$OPTARG" ;;
			M) MONOLITHIC=1 ;;
			o) DUMP_PATH="$OPTARG" ;;
			r) RELEASE="$OPTARG" ;;
			s) SOLVER="$OPTARG" ;;
			w) HUMAN=1 ;;
			y) DRYRUN=1 ;;
			z) DIRECT=1 ;;
			'?') die_help ;;
		esac
	done

	case "$ARCH" in
		i386|x86_64) ;;
		*) die_help 'Illegal architecture: %s' "$ARCH" ;;
	esac
	case "$MODE" in
		normal|asan|libmemtracer) ;;
		*) die_help 'Illegal build mode: %s' "$MODE" ;;
	esac
	case "$RELEASE" in
		release|debug) ;;
		*) die_help 'Illegal release mode: %s' "$MODE" ;;
	esac
	if ! isnumeric "$LIMIT"; then
		die_help 'Non-numeric value passed for -l'
	fi
	DUMP_PATH="$(readlink -f "$DUMP_PATH")"
	BUILD_PATH="$(readlink -f "$BUILD_PATH")"
	BUILD="$ARCH-$RELEASE-$MODE"
	if [ ! -d "$BUILD_PATH/$BUILD" ]; then
		die 2 '%s: build does not exist in %s' "$BUILD" "$BUILD_PATH"
	fi
	ARGSHIFT=$(($OPTIND - 1))
}

get_db_path()
{
	DB_FILE="$1"
	if [ -z "$DB_FILE" ]; then
		die_help 'Missing database path'
	fi
	DB_FILE="$(readlink -f "$DB_FILE")"
	if [ ! -e "$DB_FILE" ]; then
		die 2 '%s: database does not exist' "$DB_FILE"
	fi
	DB_NAME="$(basename "$DB_FILE")"
	DB_PATH="$(dirname "$DB_FILE")"
	DB_DIR="$(basename "$DB_PATH")"
	ARGSHIFT=1
}

main()
{
	get_options "$@"
	shift $ARGSHIFT
	get_db_path "$@"
	shift $ARGSHIFT

	if [ $DRYRUN -eq 1 ]; then
		dryrun
	elif [ $DIRECT -eq 1 ]; then
		if [ -d "$DBPATH" ]; then
			dumpall
		else
			dump
		fi
	else
		docker_dump
	fi
}

set -e
main "$@"
set +e
