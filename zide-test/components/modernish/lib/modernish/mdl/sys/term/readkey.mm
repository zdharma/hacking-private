#! /module/for/moderni/sh
\command unalias readkey _Msh_readkey_getBufChar _Msh_readkey_restoreTerminalState _Msh_readkey_setTerminalState 2>/dev/null

# readkey: read a single character from the keyboard without echoing back to
# the terminal. Buffering is done so that multiple waiting characters are
# read one at a time.
#
# Usage: readkey [ -E REGEX ] [ -t TIMEOUT ] [ -r ] VARNAME
#
# -E: Only accept characters that match the extended regular expression REGEX.
#
# -t: Specify a TIMEOUT in seconds (one significant digit after the
#     decimal point). After the timeout expires, no character is read and
#     readkey returns status 1.
#	http://pubs.opengroup.org/onlinepubs/9699919799/utilities/stty.html#tag_20_123_05_05
#	http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap11.html#tag_11_01_07_03
#
# -r: Raw mode. Disables Ctrl+C and Ctrl+Z processing as well as
#     translation of carriage return (13) to linefeed (10).
#
# The character read is stored into the variable referenced by VARNAME,
# which defaults to `REPLY` if not specified.
#
# Exit status:
# 0: A character was read successfully.
# 1: There were no characters to read (timeout).
# 2: Standard input is not on a terminal.
#
# --- begin license ---
# Copyright (c) 2018 Martijn Dekker <martijn@inlv.org>, Groningen, Netherlands
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# --- end license ---

use var/stack/trap   # to restore terminal state, we need to push traps

unset -v _Msh_rK_buf
readkey() {
	# ____ begin option parser ____
	# This parser was generated by: generateoptionparser -o -f readkey -v _Msh_rKo_ -n r -a tE
	unset -v _Msh_rKo_r _Msh_rKo_t _Msh_rKo_E
	while	case ${1-} in
		( -[!-]?* ) # split a set of combined options
			_Msh_rKo__o=$1
			shift
			while _Msh_rKo__o=${_Msh_rKo__o#?} && not str empty "${_Msh_rKo__o}"; do
				_Msh_rKo__a=-${_Msh_rKo__o%"${_Msh_rKo__o#?}"} # "
				push _Msh_rKo__a
				case ${_Msh_rKo__o} in
				( [tE]* ) # split optarg
					_Msh_rKo__a=${_Msh_rKo__o#?}
					not str empty "${_Msh_rKo__a}" && push _Msh_rKo__a && break ;;
				esac
			done
			while pop _Msh_rKo__a; do
				set -- "${_Msh_rKo__a}" "$@"
			done
			unset -v _Msh_rKo__o _Msh_rKo__a
			continue ;;
		( -[r] )
			eval "_Msh_rKo_${1#-}=''" ;;
		( -[tE] )
			let "$# > 1" || die "readkey: $1: option requires argument"
			eval "_Msh_rKo_${1#-}=\$2"
			shift ;;
		( -- )	shift; break ;;
		( -* )	die "readkey: invalid option: $1" ;;
		( * )	break ;;
		esac
	do
		shift
	done
	# ^^^^ end option parser ^^^^

	# timeout: convert seconds to tenths of seconds
	if isset _Msh_rKo_t; then
		case ${_Msh_rKo_t} in
		( '' | *[!0123456789.]* | *. | *.*.* )
			die "readkey: -t: invalid timeout value: ${_Msh_rKo_t}" ;;
		( *.* )
			# have just 1 digit after decimal point, then remove the point
			str match "${_Msh_rKo_t}" "*.??*" && _Msh_rKo_t=${_Msh_rKo_t%${_Msh_rKo_t##*.?}}
			_Msh_rKo_t=${_Msh_rKo_t%.?}${_Msh_rKo_t##*.} ;;
		( * )
			_Msh_rKo_t=${_Msh_rKo_t}0 ;;
		esac
	fi

	case $# in
	( 0 )	set REPLY ;;
	( 1 )	str isvarname "$1" || die "readkey: invalid variable name: $1" ;;
	( * )	die "readkey: excess arguments (expected 1)" ;;
	esac

	# If we still have characters left in the buffer, process those first.
	while not str empty "${_Msh_rK_buf-}"; do
		_Msh_readkey_getBufChar
		if not isset _Msh_rKo_E || str ematch "${_Msh_rK_c}" "${_Msh_rKo_E}"; then
			eval "$1=\${_Msh_rK_c}"
			unset -v _Msh_rKo_r _Msh_rKo_t _Msh_rKo_E_Msh_rK_s _Msh_rK_c
			return
		fi
	done

	# If the buffer variable is empty, fill it with up to 512 bytes from the keyboard buffer.
	is onterminal stdin || return 2
	_Msh_rK_s=$(unset -f stty; PATH=$DEFPATH exec stty -g) || die "readkey: save terminal state: stty failed"
	if not isset -i; then
		pushtrap '_Msh_readkey_setTerminalState' CONT
		pushtrap '_Msh_readkey_restoreTerminalState' DIE
	fi
	pushtrap '_Msh_readkey_restoreTerminalState' INT
	_Msh_readkey_setTerminalState
	forever do
		forever do  # extra loop to re-execute 'dd' after SIGTSTP/SIGCONT
			_Msh_rK_buf=$(PATH=$DEFPATH command dd count=1 2>/dev/null && put X) \
				&& _Msh_rK_buf=${_Msh_rK_buf%X} && break
			let "$? <= 125" || die "readkey: 'dd' failed"
		done
		_Msh_readkey_getBufChar
		if not isset _Msh_rKo_E || str empty "${_Msh_rK_c}" || str ematch "${_Msh_rK_c}" "${_Msh_rKo_E}"; then
			break
		fi
	done
	_Msh_readkey_restoreTerminalState
	if not isset -i; then
		poptrap CONT DIE
	fi
	poptrap INT

	# Store the result into the given variable and return successfully if it's not empty.
	eval "$1=\${_Msh_rK_c}"
	unset -v _Msh_rKo_r _Msh_rKo_t _Msh_rKo_E_Msh_rK_s _Msh_rK_c
	eval "not str empty \"\${$1}\""
}

_Msh_readkey_setTerminalState() {
	set -- -icanon -echo -echonl -istrip -ixon -ixoff -iexten
	if isset _Msh_rKo_r; then
		set -- "$@" -isig nl
	fi
	if isset _Msh_rKo_t; then
		set -- "$@" min 0 time "${_Msh_rKo_t}"
	else
		set -- "$@" min 1	# Solaris defaults to 'min 4', so must set 'min 1' to read 1 keystroke at a time
	fi
	PATH=$DEFPATH command stty "$@" || die "readkey: set terminal state: stty failed"
}

_Msh_readkey_restoreTerminalState() {
	PATH=$DEFPATH command stty "${_Msh_rK_s}" || die "readkey: restore terminal state: stty failed"
}

if thisshellhas WRN_MULTIBYTE; then
	# This shell can't parse multibyte UTF-8 characters, so if the buffer's first
	# character is non-ASCII, fall back on 'sed' to identify it.
	_Msh_readkey_getBufChar() {
		if str match "${_Msh_rK_buf}" "[!$ASCIICHARS]*"; then
			_Msh_rK_c=$(unset -f sed; putln "${_Msh_rK_buf}X" | PATH=$DEFPATH exec sed '1 s/.//; ') \
			|| die "readkey: internal error: 'sed' failed"
			_Msh_rK_c=${_Msh_rK_c%X}
			_Msh_rK_c=${_Msh_rK_buf%"${_Msh_rK_c}"}		# "
			_Msh_rK_buf=${_Msh_rK_buf#"${_Msh_rK_c}"}	# "
		else
			_Msh_rK_c=${_Msh_rK_buf%"${_Msh_rK_buf#?}"}	# "
			_Msh_rK_buf=${_Msh_rK_buf#?}
		fi
	}
else
	# We can always use nice and fast parameter substitutions.
	_Msh_readkey_getBufChar() {
		_Msh_rK_c=${_Msh_rK_buf%"${_Msh_rK_buf#?}"}	# "
		_Msh_rK_buf=${_Msh_rK_buf#?}
	}
fi

if thisshellhas ROFUNC; then
	readonly -f readkey \
		_Msh_readkey_setTerminalState \
		_Msh_readkey_restoreTerminalState \
		_Msh_readkey_getBufChar
fi
