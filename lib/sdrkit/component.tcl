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
# a component encapsulates an sdrtcl::dsp computation
# registers as a sdrkit::control component for external control
# and optionally provides a default tk user interface.
#
# the user interface can be packed into the root window,
# packed into a window supplied by a parent component,
# or left unrealized.
#
# the controlling component can be remote and accessed by tk send,
# or local and accessed by procedure call.
#
package provide sdrkit::component 1.0.0

package require snit

package require sdrkit::control
package require sdrkit::comm

namespace eval sdrkit {}
namespace eval sdrkitw {}

snit::type sdrkit::component {
    component subsidiary
    component control

    # the tk appname, jack client name, and sdrkit::control name
    # used to "send" commands to this component
    # used as the jack client name or as the root jack
    #   client name if more than one client is active
    # used as the sdrkit::control name
    option -name sdrkit-component

    # the jack server name to create clients
    option -server default

    # root window for ui options
    # should be {} for .
    # should be a window name for window name
    # should be {none} for no window
    option -window -default {}
    option -parent-window {.}

    # the tk appname / sdrkit::control name
    # of the control application
    # used to "send" commands to the control component 
    option -control {}

    # the tk grid parameters for the standard ui stack
    # which displays a stack of windows in a single toplevel
    # frame.
    # these are the minimum sizes and weights
    # for columns 0 and 1 in a grid display
    # column 0 displays the option value with units
    # column 1 displays the scale for adjusting the value
    # other options are generally centered in a column
    # spanning these two.
    option -minsizes {100 200}
    option -weights {1 3}

    # enable or activate this component
    option -enable -default false -configuremethod Configure
    option -activate -default false -configuremethod Configure
    
    # the factory for the subsidiary which we're wrapping
    option -subsidiary {}
    option -subsidiary-opts {}

    # delegate unknown options to the subsidiary
    delegate option * to subsidiary

    # delegate unknown methods to the controller
    # won't work, have a special method call to reach controller
    # delegate method * to control

    variable data -array {
    }

    constructor {args} {
	$self configure {*}$args
	install subsidiary using $options(-subsidiary) ::sdrkitw::$options(-name) \
	    -server $options(-server) -name $options(-name) \
	    -component $self {*}$options(-subsidiary-opts)

	# determine window setup
	if {$options(-window) ne {none}} {
	    # configure for some windows
	    package require Tk
	    if {$options(-window) eq {}} {
		# configure for root window
		wm title . $options(-name)
	    } elseif {[winfo exists $options(-window)]} {
		# configure for another window
	    } else {
		error "invalid window: $options(-window)"
	    }
	    $subsidiary configure -window $options(-window) -minsizes $options(-minsizes) -weights $options(-weights)
	}

	# determine control setup
	if {$options(-control) ne {}} {
	    set control $options(-control)
	} else {
	    # look for controller
	    if {[info commands ::sdrkit-control] eq {}} {
		# make one
		::sdrkit::control ::sdrkit-control -server $options(-server)
	    }
	    set control [::sdrkit-control get-controller]
	}

	# build the subsidiary parts
	$subsidiary build-parts

	# enable or disable depending on the controller
	if {$options(-control) ne {}} {
	    set options(-enable) 0
	    set options(-activate) 0
	    if {[$subsidiary is-active]} { $subsidiary deactivate }
	} else {
	    set options(-enable) 1
	    set options(-activate) 1
	    if { ! [$subsidiary is-active]} { $subsidiary activate }
	}

	# double check controls and ports against dps component
	#puts "info commands ::sdrkitx::$options(-name)* is [info commands ::sdrkitx::$options(-name)*]"
	if {[info commands sdrkitx::$options(-name)*] ne {}} {
	    puts "testing ports and options for $options(-name)"
	    set ports1 [::sdrkitx::$options(-name) info ports]
	    set ports2 [concat [$subsidiary cget -in-ports] [$subsidiary cget -out-ports]]
	    set opts1 [::sdrkitx::$options(-name) info options]
	    set opts2 [concat [$subsidiary cget -in-options] [$subsidiary cget -out-options]]
	    foreach port $port1 { if {$port ni $ports2} { error "$options(-name) has real port $port not in $ports2" } }
	    foreach port $port2 { if {$port ni $ports1} { error "$options(-name) names port $port not in $ports1" } }
	    foreach opt $opt1 { if {$opt ni $opts2} { error "$options(-name) has real option $opt not in $opts2" } }
	    foreach opt $opt2 { if {$opt ni $opts1} { error "$options(-name) names option $opt not in $opts1" } }
	} else {
	    #puts "info commands ::sdrkitx::* is [info commands ::sdrkitx::*]"
	}

	# set up control
	$self control part-add $options(-name) [sdrkit::comm::wrap $self]

	# build the ui if any
	if {$options(-window) ne {none}} {
	    $subsidiary build-ui
	    if {$options(-window) eq {}} {
		bind . <Destroy> [mymethod destroy]
	    }
	}
	
	# resolve the parts
	if {{resolve-parts} in [$subsidiary info methods]} {
	    $subsidiary resolve-parts
	}
    }
    destructor {
	catch {$subsidiary destroy}
    }
    #
    # callback from subsidiary reporting option changes
    #
    method report {args} { $self control part-report $options(-name) {*}$args }
    #
    # callback from subsidiary requesting controller method
    #
    method get-controller {} { return $options(-control) }
    #
    # call to the controller
    #
    method control {args} { return [sdrkit::comm::send $control {*}$args] }
    method name-report {args} { return [$self control part-report {*}$args] }
    method name-enable {args} { return [$self control part-enable {*}$args] }
    method name-destroy {args} { return [$self control part-destroy {*}$args] }
    # double listing
    method connect-ports {n1 p1 n2 p2} { return [$self control port-connect [list [list $n1 $p1]] [list [list $n2 $p2]]] }
    method connect-options {n1 o1 n2 o2} { return [$self control opt-connect [list [list $n1 $o1]] [list [list $n2 $o2]]] }
    method out-ports {args} { return [$self control part-out-ports {*}$args] }	
    method in-ports {args} { return [$self control part-in-ports {*}$args] }	
}
