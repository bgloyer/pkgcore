# Copyright 2005-2010 Brian Harring <ferringb@gmail.com>: BSD/GPL2
# this functionality is all related to saving/loading environmental dumps for ebuilds

filter_env_func_filter() {
	while [ -n "$1" ]; do
		echo -n "$1"
		[ "$#" != 1 ] && echo -n ','
		shift
	done
}

filter_env_var_filter() {
	local _internal_var
	while [ -n "$1" ]; do
		echo -n "$1"
		[ "$#" != 1 ] && echo -n ','
		shift
	done
}

regex_filter_input() {
	local l
	local regex="${1}"
	shift
	while [ -n "$1" ]; do
		regex="${regex}|${1}"
		shift
	done
	regex="^(${regex})$"
	# use egrep if possible... tis faster.
	l=$(type -P egrep)
	if [[ -n $l ]]; then
		# use type -p; qa_interceptors may be be active.
		"$l" -v "${regex}"
	else
		while read l; do
			[[ $l =~ $regex ]] || echo "${l}"
		done
	fi
}

invoke_filter_env() {
	local opts
	[[ $PKGCORE_DEBUG -ge 3 ]] && opts="$opts --debug"
	PYTHONPATH="${PKGCORE_PYTHONPATH}" "${PKGCORE_PYTHON_BINARY}" \
		"${PKGCORE_BIN_PATH}/filter-env" "$@"
}

# selectively saves  the environ- specifically removes things that have been marked to not be exported.
# dump the environ to stdout.
dump_environ() {
	local x

	# dump funcs.
	declare -F | cut -d ' ' -f 3- | regex_filter_input ${DONT_EXPORT_FUNCS} | sort -g | while read x; do
		declare -f "${x}" || die "failed outputting func ${x}" >&2
	done

	declare | invoke_filter_env --print-vars | regex_filter_input ${DONT_EXPORT_VARS} | sort -g | while read x; do
		declare -p "${x}" || die "failed outputting variable ${x}" >&2
	done
}

# dump environ to $1, optionally piping it through $2 and redirecting $2's output to $1.
export_environ() {
	local temp_umask
	if [ "${1:-unset}" == "unset" ]; then
		die "export_environ requires at least one arguement"
	fi

	#the spaces on both sides are important- otherwise, the later ${DONT_EXPORT_VARS/ temp_umask /} won't match.
	#we use spaces on both sides, to ensure we don't remove part of a variable w/ the same name-
	# ex: temp_umask_for_some_app == _for_some_app.
	#Do it with spaces on both sides.

	DONT_EXPORT_VARS="${DONT_EXPORT_VARS} temp_umask "
	temp_umask=`umask`
	umask 0002

	if [ "${2:-unset}" == "unset" ]; then
		dump_environ > "$1"
	else
		dump_environ | $2 > "$1"
	fi
	chown portage:portage "$1" &>/dev/null
	chmod 0664 "$1" &>/dev/null

	DONT_EXPORT_VARS="${DONT_EXPORT_VARS/ temp_umask /}"

	umask $temp_umask
}

# reload a saved env, applying usual filters to the env prior to eval'ing it.
scrub_environ() {
	local src e ret EXISTING_PATH
	# localize these so the reload doesn't have the ability to change them

	[ ! -f "$1" ] && die "scrub_environ called with a nonexist env: $1"

	if [ -z "$1" ]; then
		die "load_environ called with no args, need args"
	fi
	src="$1"

	# here's how this goes; we do an eval'd loadup of the target env w/in a subshell..
	# declares and such will slide past filter-env (so it goes).  we then use our own
	# dump_environ from within to get a clean dump from that env, and load it into
	# the parent eval.
	(

		# protect the core vars and functions needed to do a dump_environ
		# some of these are already readonly- we still are forcing it to be safe.
		declare -r PKGCORE_PYTHONPATH="${PKGCORE_PYTHONPATH}" &> /dev/null
		declare -r PKGCORE_PYTHON_BINARY="${PKGCORE_PYTHON_BINARY}" &> /dev/null
		declare -r DONT_EXPORT_VARS="${DONT_EXPORT_VARS}" &> /dev/null
		declare -r DONT_EXPORT_FUNCS="${DONT_EXPORT_FUNCS}" &> /dev/null
		declare -r SANDBOX_ON="${SANDBOX_ON}" &> /dev/null
#		declare -rx PATH="${PATH}" &> /dev/null

		readonly -f invoke_filter_env &> /dev/null
		readonly -f dump_environ &> /dev/null
		readonly -f regex_filter_input &> /dev/null

		rm -f "${T}/.pre-scrubbed-env" || die "failed rm'ing"
		# run the filtered env.
		invoke_filter_env \
			-f "$(filter_env_func_filter ${DONT_EXPORT_FUNCS} )" \
			-v "$(filter_env_var_filter ${DONT_EXPORT_VARS} src x EXISTING_PATH)" -i "$src" \
			> "${T}/.pre-scrubbed-env" || die "failed first step of scrubbing the env to load"

		source "${src}" || die "failed sourcing scrubbed env"


		# if reinstate_loaded_env_attributes exists, run it to add to the vars.
		# old pkgcore env saving approach, long before portage/paludis were around...
		type reinstate_loaded_env_attributes &> /dev/null && \
			reinstate_loaded_env_attributes
		unset -f reinstate_loaded_env_attributes

		# ok. it's loaded into this subshell... now we use our dump mechanism (which we trust)
		# to output it- this mechanism is far more bulletproof then the load filtering (since
		# declare and friends can set vars via many, many different ways), thus we use it
		# as the final filtering.

		unset -v EXISTING_PATH old_phase

		rm -f "${T}/.scrubbed-env"
		dump_environ > ${T}/.scrubbed-env || die "dumping environment failed"
	) || exit 1 # note no die usage here... exit instead, since we don't want another tb thrown
}
