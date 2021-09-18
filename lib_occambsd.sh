# f_occam_options Function Usage:

# f_occam_options < Source Directory > "< Optional Build Options To Keep >" i.e.

# f_occam_options /usr/src "WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR"

# keepers="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR"
# f_occam_options /usr/src "$keepers" (Must be in quotation marks)

f_occam_options()
{
	[ -f ${1}/Makefile ] || \
		{ echo f_occam_options: Invalid source directory ; exit 1 ; }

	opts=$( make -C $1 showconfig __MAKE_CONF=/dev/null SRCCONF=/dev/null \
		| sort \
		| sed '
			s/^MK_//
			s/=//
		' \
		| awk '
		$2 == "yes" { printf "WITHOUT_%s=YES\n", $1 }
		'
	)

	if [ "$2" ] ; then
		IFS=" "

		for keeper in $2 ; do
		opts=$( echo $opts | grep -v $keeper )
	done
	fi

	echo $opts
} # End f_occam_options

# Example Tests

#f_occam_options /usr/src "WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB WITHOUT_BOOT WITHOUT_LOADER_LUA WITHOUT_LOCALES WITHOUT_ZONEINFO WITHOUT_VI WITHOUT_EFI"

#keepers="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB WITHOUT_BOOT WITHOUT_LOADER_LUA WITHOUT_LOCALES WITHOUT_ZONEINFO WITHOUT_VI WITHOUT_EFI"

#f_occam_options /usr/src "$keepers"

#f_occam_options /usr/src

#f_occam_options
