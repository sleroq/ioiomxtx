#!/usr/bin/env sh
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-
# $ mxtx-cp.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#       Copyright (c) 2017 Tomi Ollila
#           All rights reserved
#
# Created: Tue 24 Oct 2017 19:45:43 EEST too
# Last modified: Tue 05 Jul 2022 16:37:24 +0300 too

case ~ in '~') echo "'~' does not expand. old /bin/sh?" >&2; exit 1; esac

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf

LANG=C LC_ALL=C; export LANG LC_ALL; unset LANGUAGE

saved_IFS=$IFS; readonly saved_IFS

warn () { printf '%s\n' "$*"; } >&2
die () { printf '%s\n' "$*"; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_env () { printf '+ %s\n' "$*" >&2; env "$@"; }
x_eval () { printf '+ %s\n' "$*" >&2; eval "$*"; }
x_exec () { printf '+ %s\n' "$*" >&2; exec "$@"; die "exec '$*' failed"; }

if test $# = 0
then printf >&2 %s\\n ''\
  "Usage: ${0##*/} [options] [link:]src... [link:]dest" ''\
  '  -[arpcsrtunxzCSHL]: as in rsync(1)'\
  "  -v's and -q's: one -v (with --progress) is default"\
  '  --exclude=, --rsync-path=, --max-size=, --min-size=, --inplace,'\
  '         --existing, --ignore-existing and '\'--\'': as in rsync(1)'\
  '  --tar: use tar instead or rsync (workaround where rsync not available)'\
  '' hints: \
  "   read rsync(1) manual page for all these options (and caveats)"\
  "   use '-L' to copy symlink referent (default is to skip symbolic links)"\
  "   use '-H' (with -a) to copy hardlinks (default is to copy file contents)"\
  "   use '-x' to restrict source (per entry) to one file system"\
  "   use '--inplace' (and retries) if copying does not complete in one go"\
  "   use '/' or '/.' at the end of source directory to shorten target path"\
  "   option '-C' (with -a/-r) is useful to filter out many vcs related files"\
  "   add extra quotes when spaces in filenames, like 'path/to/\"file name\"'"\
  "   use rsync -e mxtx-io ... for 'raw' rsync interface" ''
  exit
fi

sopts= lopts=

addsopt () { case $sopts in *$1*) ;; *) sopts=$sopts$1 ;; esac; }
addlopt () { case $lopts in *$1*) ;; *) lopts=$lopts\ $1${2+=$2} ;; esac; }

q=0 excl= rspath= tar=false
while getopts ':arpcsrtunzCSHLxqv' opt
do case $opt
   in '?')
	test "$OPTARG" = - || die "'-$OPTARG': unknown ${0##*/} short option"
	OPTIND=2
	case $1
	in --tar) tar=true
	# one exclude, use 'raw' interface where more needed...
	;; --exclude) excl=$2; OPTIND=3
	;; --exclude=*) excl=${1#*=}
	;; --rsync-path) rspath=$2; OPTIND=3
	;; --rsync-path=*) rspath=${1#*=}
	;; --max-size | --min-size) addlopt $1 $2; OPTIND=3
	;; --max-size=* | --min-size=*) addlopt ${1%%=*} ${1#*=}
	;; --existing | --ignore-existing) addlopt $1
	;; --partial | --inplace) addlopt $1  # partial kept for backw. compat.
	;; --one-file-system) addsopt x
	;; --dry-run) addsopt n
	;; --) break
	;; *) die "'$1': unknown ${0##*/} long option"
	esac
   ;; a|r|p|c|s|r|t|u|n|z|C|S|H|L) addsopt $opt
   ;; x) sopts=$sopts$opt
   ;; q) q=$((q + 1))
   ;; v) q=$((q - 1))
   ;; *) die "'-$opt': unknown ${0##*/} short option"
   esac
   test $OPTIND = 1 || { shift $((OPTIND - 1)); OPTIND=1; }
done

case $q in -*) addsopt vv; addlopt --progress
	;; 0) addsopt v; addlopt --progress
	;; 1)
	;; *) addsopt q
esac

$tar || {
	if test $# = 1
	then die "${0##*/}: missing destination operand after '$1'"
	fi
	case $0 in */*) c=$0 ;; *) c=./$0 ;; esac
	case $sopts in *v*) exec=x_exec ;; *) exec=exec ;; esac
	#exec=echo
	$exec rsync -e mxtx-rsh ${rspath:+--rsync-path="$rspath"} \
		${excl:+--exclude="$excl"} ${sopts:+-$sopts} $lopts "$@"
	exit not reached
}

test $# = 3 && test "$3" = '!' || {
 printf >&2 ' %s\n' '' 'With --tar:'\
 "   there may be one source and destination, and last argument must be '!'"\
 "   both source and destination may be 'remote'"\
 "   destination is always considered as directory (which must exist)"\
 "   operation will always be recursive if source is a directory"\
 "   in 'remote' source, extra shell whitespace/wildcard handling is done"\
 "   options 'p', 'z', 'q', 'n', 'x' and' '--exclude=' may work as with rsync"\
 ''
 exit
}

case $sopts in *[ap]*) p=p ;; *) p= ;; esac
case $sopts in *z*) z=z ;; *) z= ;; esac
case $sopts in *v*) v=vv;; *) v= ;; esac
case $sopts in *n*) x=t ;; *) x=x ;; esac
case $sopts in *x*) ofs=--one-file-system ;; *) ofs= ;; esac

case $1 in *:*) star="mxtx-rsh ${1%%:*} tar" s=${1#*:}
	;; *) star=tar s=$1
esac
# remove '.' before 'tar' when porting for e.g. ssh use
case $2 in *:*) dtar="mxtx-rsh ${2%%:*} . tar" d=${2#*:}
	;; *) dtar=tar d=$2
esac

# cleanup trailing slashes (if any) -- and empty $s -> '.'
sd=
while :; do
	case $s in /) break
		;; */) sd=/. # and to do-block
		;; */.) sd=/. s=${s%.} # and to do-block
		;; '') s=.; break
		;; *) break
	esac
	s=${s%/}
done
# there is a bit of evolution here. just trailing '/' support added last...
s=$s$sd
case $s in *?/*) sd=${s##*/} s=${s%/*} ;; *) sd=$s s= ;; esac

# trailing slashes (if any) -- and also trailing '/.'s
while :; do
	case $d in /) break
		;; */) # to do-block
		;; */.) d=${d%.} # and to do-block
		;; .) d=; break
		;; *) break
	esac
	d=${d%/}
done

# note: long lines -- for easier comparison
echo >&2 + \
$star ${s:+-C "$s"} $ofs ${excl:+--exclude="$excl"} -$z''cf - $sd '|' $dtar ${d:+-C "$d"} -"$z$x$v$p"f -
#exit
$star ${s:+-C "$s"} $ofs ${excl:+--exclude="$excl"} -$z''cf - $sd  |  $dtar ${d:+-C "$d"} -"$z$x$v$p"f -
