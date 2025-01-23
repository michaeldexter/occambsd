#!/usr/bin/awk -f
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2025 Jared Jennings
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

function usage() {
    print "\n\
Usage: awk -f FreeBSD-pkgbase-dep-graph.awk                \\\n\
              -v pkg=\"pkg --my-switches\"                   \\\n\
              -v repository=myrepo                         \\\n\
              -v base_pkg_exclusions=\"zfs|csh|-lib32\\$\"    \\\n\
         > my-cool-graph.g \n\
\n\
Constructs and emits a directed graph from pkg-rquery(8) data, wherein\n\
nodes represent packages, and edges are drawn from a package toward\n\
packages it depends on (by requiring shared libraries they provide).\n\
All packages are 'selected', except for those whose names match the\n\
base_pkg_exclusions extended regular expression (see re_format(7)).\n\
The node for each selected package is highlighted, along with any\n\
surprising direct dependencies (packages excluded by\n\
base_pkg_exclusions, but depended upon by selected packages.) Second-\n\
degree surprising dependencies are not highlighted. Hack and improve!\n\
\n\
The graph file is made for use with Graphviz; after installing the port\n\
or package, see dot(1), and try: fdp -Tpng -o cool.png my-cool-graph.g\n\
" > "/dev/stderr";
}


# All the base package names start with "FreeBSD-". Elide that for the
# graph, to make it less busy.
function mod_pkg_name(pn) {
    sub("FreeBSD-", "", pn)
    return pn
}

# Skip drawing some packages.
function skip_node_p(pn) {
    # On amd64, there are a lot of -lib32 packages, and if we draw
    # those in the graph, it doubles the number of nodes and edges per
    # node and makes the graph illegible.
    if(pn ~ /-lib32$/) return 1
    if(pn ~ /-man$/) return 1        # Man pages
    if(pn ~ /-dbg$/) return 1        # Debug symbols
    if(pn ~ /-dev$/) return 1        # Development files
    return 0
}

# Skip drawing some dependencies.
function skip_edge_p(p1, p2) {
    # Loooots of things in 14.2 depend on clibs and runtime. Not
    # everything, so you *might* want to draw them. But if you don't,
    # the graph really clears up.
    if(p2 ~ /clibs$/) return 1
    if(p2 ~ /runtime$/) return 1
    return 0
}

# Show, in the graph, some indication of what we didn't draw.
function emit_skipped() {
    print "  \"-lib32 packages\\n(not shown)\";"
    print "  \"-man packages\\n(not shown)\";"
    print "  \"-dbg packages\\n(not shown)\";"
    print "  \"-dev packages\\n(not shown)\";"
    print "  \"many of these packages\\n(arrows not shown)\" -> \"clibs\";"
    print "  \"many of these packages\\n(arrows not shown)\" -> \"runtime\";"
}

# Write the main structure of the graph, delegating details.
function emit_graph() {
    print "digraph g {"
    print "  rankdir=LR;"
    print "  overlap=false;"

    emit_contents()
    emit_skipped()

    print "}"
}

# Write nodes and edges computed from package and dependency data. In
# particular, this is where we follow the shared-library dependency.
#
# It appears in early 2025 that dependencies among base packages are
# all arbitrated via shared libraries required and provided, not
# direct package dependencies.
function emit_contents() {
    for(package in existing_packages) {
        draw_node_for_package(package)
        split(requires_shlibs[package], required_shlibs)
        for(rshli in required_shlibs) {
            required_shlib = required_shlibs[rshli]
            split(provides_shlibs[required_shlib], providing_packages)
            for(ppi in providing_packages) {
                providing_package = providing_packages[ppi]
                draw_edge_for_dependency(package, providing_package)
            }
        }
    }
}

# Write a node corresponding to a package, with the right style.
function draw_node_for_package(package) {
    if(!(package in already_nodes)) {
        if(!skip_node_p(package)) {
            if(package in specified_packages) {
                printf "  \"%s\" [color=green, fillcolor=lightgreen, style=filled];\n", package
            } else {
                printf "  \"%s\" [color=gray];\n", package
            }
            already_nodes[package] = 1
        }
    }
}

# Write an edge corresponding to a dependency, with the right style.
function draw_edge_for_dependency(package, providing_package) {
    if((!skip_node_p(package)) &&
       (!skip_node_p(providing_package)) &&
       (!skip_edge_p(package, providing_package))) {
        if(!((package " " providing_package) in already_edges)) {
            if(package in specified_packages) {
                if(providing_package in specified_packages) {
                    printf "  \"%s\" -> \"%s\" [color=gray];\n",
                        package, providing_package
                } else {
                    # This is the case where a package we want depends
                    # on a package we excluded. The latter will be
                    # installed despite the exclusion, perhaps
                    # surprisingly.
                    printf "  \"%s\" -> \"%s\" [color=blue];\n",
                        package, providing_package
                }
            } else {
                printf "  \"%s\" -> \"%s\" [color=gray];\n",
                    package, providing_package
            }
            already_edges[package " " providing_package] = 1
        }
    }
}


function obtain_dependency_data() {
    rquery = pkg " rquery -r " repository " "
    while ((rquery "'%n'" | getline) > 0) {
        existing_packages[mod_pkg_name($0)] = 1
    }
    while ((rquery "'%n' | grep -vE '('"                \
            base_pkg_exclusions "')'" | getline) > 0) {
        specified_packages[mod_pkg_name($0)] = 1
    }
    while ((rquery "'%n %B'" | getline) > 0) {
        if(mod_pkg_name($1) in requires_shlibs) {
            requires_shlibs[mod_pkg_name($1)] =                 \
                requires_shlibs[mod_pkg_name($1)] " " $2
        } else {
            requires_shlibs[mod_pkg_name($1)] = $2
        }
    }
    while ((rquery "'%b %n'" | getline) > 0) {
        if($1 in provides_shlibs) {
            provides_shlibs[$1] =                               \
                provides_shlibs[$1] " " mod_pkg_name($2)
        } else {
            provides_shlibs[$1] = mod_pkg_name($2)
        }
    }
}

BEGIN {
    if((!pkg) && (!base_pkg_exclusions) && (!repository)) {
        # no settings given
        usage()
        exit 1
    }
    if(!pkg) pkg = "pkg "
    if(!base_pkg_exclusions) {
        print "WARNING: base_pkg_exclusions empty; all base pkgs selected\n\n"\
            > "/dev/stderr";
    }
    if(!repository) {
        print "ERROR: you must specify a repository for pkg rquery to use\n\n"\
            > "/dev/stderr";
        usage()
        exit 1
    }
    # Slightly tricky quoting here. We are going to pass
    # base_pkg_exclusions to a subshell as a parameter for grep. If
    # there are any double-quotes in base_pkg_exclusions, we don't
    # want to allow a command injection, and if there are any
    # backslashy things, we want to send them to grep, not to the
    # shell.
    #
    # So we put this whole thing in single quotes - and if it contains
    # any single quotes, escape them by exiting the single quotes,
    # writing \', and then reentering single quotes. (When two strings
    # directly abut each other, like 'Fr'x'ank', sh concatenates them
    # into one word, Frxank. We just make the x a single quote, \'.
    gsub(/'/, "'\\''", base_pkg_exclusions)
    base_pkg_exclusions = "'" base_pkg_exclusions "'"

    # After we've absorbed those bits of knowledge, we can use them to
    # go get the dependency data and make the graph.
    obtain_dependency_data()
    emit_graph()
}
