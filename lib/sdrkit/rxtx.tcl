# -*- mode: Tcl; tab-width: 8; -*-
#
# Copyright (C) 2011, 2012 by Roger E Critchlow Jr, Santa Fe, NM, USA.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
# 

#
# a composite component that builds a transceiver
#
package provide sdrkit::rxtx 1.0.0

package require snit
package require sdrtk::clabelframe

namespace eval sdrkit {}

snit::type sdrkit::rxtx {
    option -name sdr-src
    option -title {IQ Source}
    option -in-ports {}
    option -out-ports {out_i out_q}
    option -in-options {}
    option -out-options {}
    option -sub-components {
	rx {Receiver} rx
	tx {Transmitter} tx
	keyer {Keyer} keyer
    }
    option -connections {
    }

    option -server default
    option -component {}

    option -window {}
    option -minsizes {100 200}
    option -weights {1 3}

    variable data -array {
	enabled 0
	active 0
	parts {}
    }

    constructor {args} {
	$self configure {*}$args
    }
    destructor {
	puts "rxtx destructor"
	foreach name $data(parts) {
	    $option(-component) name-destroy $options(-name)-$name
	}
    }
    method resolve-parts {} {
	foreach {name1 ports1 name2 ports2} $options(-connections) {
	    set name1 [string trim "$options(-name)-$name1" -]
	    set name2 [string trim "$options(-name)-$name2" -]
	    foreach p1 [$options(-component) $ports1 $name1] p2 [$options(-component) $ports2 $name2] {
		$options(-component) connect-ports $name1 $p1 $name2 $p2
	    }
	}
    }
    method build-parts {} {
	if {$options(-window) ne {none}} return
	foreach {name title command} $options(-sub-components) {
	    set data($name-enable) 0
	    lappend data(parts) $name
	    set args {}
	    if {[llength $command] > 1} {
		set args [lrange $command 1 end]
		set command [lindex $command 0]
	    }
	    package require sdrkit::$command
	    ::sdrkit::component ::sdrkitv::$options(-name)-$name \
		-window none \
		-server $options(-server) \
		-name $options(-name)-$name \
		-subsidiary sdrkit::$command -subsidiary-opts $args \
		-control [$options(-component) get-controller]
	}
    }
    method build-ui {} {
	if {$options(-window) eq {none}} return
	set w $options(-window)
	if {$w eq {}} { set pw . } else { set pw $w }
	
	ttk::notebook $w.full
	ttk::notebook $w.empty
	foreach {name title command} $options(-sub-components) {
	    ttk::frame $w.full.$name
	    ttk::frame $w.empty.$name
	    lappend data(parts) $name
	    set args {}
	    if {[llength $command] > 1} {
		set args [lrange $command 1 end]
		set command [lindex $command 0]
	    }
	    package require sdrkit::$command
	    ::sdrkit::component ::sdrkitv::$options(-name)-$name \
		-window $w.full.$name \
		-server $options(-server) \
		-name $options(-name)-$name \
		-subsidiary sdrkit::$command -subsidiary-opts $args \
		-control [$options(-component) get-controller] \
		-minsizes $options(-minsizes) \
		-weights $options(-weights)
	    $w.full add $w.full.$name -text $title
	    $w.empty add $w.empty.$name -text $title
	}
	$w.full add [ttk::frame $w.full.collapse] -text Collapse
	$w.empty add [ttk::frame $w.empty.collapse] -text Collapse
	grid $w.full -sticky nsew
	grid columnconfigure $pw 0 -minsize [tcl::mathop::+ {*}$options(-minsizes)] -weight 1
	bind $w.full <<NotebookTabChanged>> [mymethod note-full-select $w]
	bind $w.empty <<NotebookTabChanged>> [mymethod note-empty-select $w]
    }

    method note-full-select {w} {
	#puts "note-full-select [$w.full select]"
	set select [$w.full select]
	if {[string match *collapse* $select]} {
	    # collapse
	    #puts "collapsing"
	    grid remove $w.full
	    grid $w.empty -row 0 -column 0 -sticky ew
	    $w.empty select [regsub {full} $select empty]
	} else {
	    # stay expanded
	}
    }

    method note-empty-select {w} {
	#puts "note-empty-select [$w.empty select]"
	set select [$w.empty select]
	if {[string match *collapse* $select]} {
	    # stay collapsed
	} else {
	    # expand
	    #puts "expanding"
	    grid remove $w.empty
	    grid $w.full -row 0 -column 0 -sticky nsew
	    $w.full select [regsub {empty} $select full]
	}
    }
    method is-active {} { return $data(active) }
    method activate {} {
	set data(active) 1
	foreach part $data(parts) {
	}
    }
    method deactivate {} {
	set data(active) 1
	foreach part $data(parts) {
	}
    }
    method Enable {name} {
	if {$data($name-enable)} {
	    $options(-component) part-enable $options(-name)-$name
	} else {
	    $options(-component) part-disable $options(-name)-$name
	}
    }
}
