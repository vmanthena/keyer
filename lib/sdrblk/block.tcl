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

package provide sdrblk::block 1.0.0

package require snit

package require sdrblk::comp-stub
package require sdrkit::jack

#
# The block represents a node or a subgraph of computational nodes.
# The nodes may be enabled or disabled. Enabled nodes will participate
# in the computation when activated. The enabled nodes may be activated
# or deactivated. Activated nodes are actively processing samples and
# consuming computational cycles.
#
# The graph is constructed with all the potential computational units
# organized into the structure they would form if enabled and activated.
# The graph has subgraphs which can be sequences, alternate branches,
# parallel paths, fan out, fan in, and terminal nodes.
#
# The units required for the desired computation are enabled, and when
# enabled their parameters can be configured as required.
#
# So, the blocks serve these purposes:
#
# 1 - they organize the structure of the radio or other dsp computation
# 2 - they organize the enablement/disablement of the units
# 3 - they organize the configuration of the units
# 4 - they organize the activation/deactivation of the units
# 5 - they maintain the port connection/disconnection of the activated units
#

namespace eval sdrblx {}

snit::type sdrblk::block {
    ##
    ## this type variable, shared among all instances, enables verbose messages
    ##
    typevariable verbose -array {
	construct 0 configure 0 destroy 0 require 0
	connect 1 enable 0 activate 0
	controls 0 controlget 0 control 0
	inport 0 outport 0
    }

    ##
    ## define the matching port suffixes
    typevariable matches [dict create \
			      capture_1 {in_i playback_1} \
			      capture_2 {in_q playback_2} \
			      out_i {in_i playback_1} \
			      out_q {in_q playback_2} \
			      midi_capture_1 midi_in \
			      midi_out {midi_in midi_playback_1} \
			     ]

    ##
    ## data that is private to the instance
    ##
    variable data -array {
	connect {}
	disconnect {}
	parts {}
	alternates {}
	sequence {}
    }

    ##
    ## common options and methods
    ##

    # send a configuration option to the type's configuration handler
    method dispatch {opt val} {
	if {$verbose(configure)} { puts "block $options(-name) $self configure $opt {$val} dispatched to $options(-type)" }
	$self $options(-type) configure $opt $val
    }

    # -type defines the type of block
    option -type -readonly yes -type {snit::stringtype -regexp {^(jack|sequence|alternate|spectrum|meter|input|output)$}}
    
    # -partof defines the containment hierarchy
    option -partof -readonly yes

    # -server specifies the jack server name, acquired from -partof
    option -server -readonly yes

    # -prefix, -suffix, and -name define the hierarchical naming of components, acquired from -partof, or constructed
    option -prefix -readonly yes
    option -suffix -readonly yes
    option -name -readonly yes

    # -input and -output define the graph structure
    option -input -default {}
    option -output -default {}
    option -super -default {} -readonly yes
    
    # -inport and -outport define the enabled connections
    option -inport -default {} -configuremethod dispatch
    option -outport -default {} -configuremethod dispatch

    # -require defines package required to load
    option -require -default {}

    # -enable make this component enabled or disabled
    option -enable -default no -configuremethod dispatch

    # -activate make this component activated or deactivated
    option -activate -default no -configuremethod dispatch

    # -control is the radio controller
    option -control -readonly yes
    
    # these are the methods the radio controller uses
    # to talk to the computational components
    method controls {} { return [$self control] }
    method control {args} {
	if {$verbose(control)} { puts "block $options(-name) $self control {$args}" }
	return [::sdrblx::$options(-name) configure {*}$args]
    }
    method controlget {opt} {
	if {$verbose(controlget)} { puts "block $options(-name) $self controlget $opt" }
	return [::sdrblx::$options(-name) cget $opt]
    }
    
    # parts management for blocks that contain blocks
    # add a part to this block
    method addpart {block} { lappend data(parts) $block }
    # return the parts of this block
    method parts {} { return $data(parts) }
    # filter the parts of this block
    method filter-parts {pred} {
	set parts {}
	foreach part [$self parts] { if {[{*}$pred $part]} { lappend parts $part } }
	return $parts
    }
    # is this part an input part
    method is-input-part {part} { return [expr {[$part cget -input] eq {}}] }
    # is this part an output part
    method is-output-part {part} { return [expr {[$part cget -output] eq {}}] }
    # return the input parts of this block
    method input-parts {} { return [$self filter-parts [mymethod is-input-part]] }
    # return the output parts of this block
    method output-parts {} { return [$self filter-parts [mymethod is-output-part]] }

    # connection management
    proc match-ins-outs {ins outs} {
	if {[llength $ins] != [llength $outs]} {
	    error "match-ins-outs: ins={$ins} cannot match outs={$outs}"
	}
	foreach x $outs {
	    lassign [split $x :] x0 x1
	    if {[info exists tout($x1)]} {
		error "match-ins-outs: duplicate output suffix $x1: $x $tout($x1)"
	    }
	    set tout($x1) $x
	}
	set nins {}
	set nouts {}
	foreach x $ins {
	    lassign [split $x :] x0 x1
	    if {[info exists tin($x1)]} {
		error "match-ins-outs: duplicate input suffix $x1: $x $tin($x1)"
	    }
	    set tin($x1) $x
	    if { ! [dict exists $matches $x1]} {
		error "match-ins-outs: no matches mapping for input suffix $x1"
	    }
	    set matched 0
	    foreach m [dict get $matches $x1] {
		if {[info exists tout($m)]} {
		    lappend nins $x
		    lappend nouts $tout($m)
		    unset tout($m)
		    set matched 1
		    break
		}
	    }
	    if { ! $matched } {
		error "match-ins-outs: no match for $x in outputs [array get tout]"
	    }
	}
	if {[array size tout]} {
	    error "match-ins-outs: not match for outputs [array get tout]"
	}
	    return [list $nins $nouts]
    }
    proc lremove {listname element} {
	upvar $listname list
	if {[set i [lsearch -exact $list $element]] >= 0} {
	    set list [lreplace $list $i $i]
	}
    }
    method connection {connect ins outs} {
	if {$options(-type) ni {jack output}} {
	    error "$options(-name) doesn't know how to $connect {$ins} and {$outs}: $options(-type) is wrong"
	}
	lassign [match-ins-outs $ins $outs] ins outs
	if {[llength $ins] != [llength $outs]} {
	    error "$options(-name) cannot $connect {$ins} and {$outs}: length mismatch"
	}
	foreach i $ins o $outs {
	    set connection [list sdrkit::jack -server $options(-server) connect $i $o]
	    set disconnection [list sdrkit::jack -server $options(-server) disconnect $i $o]
	    if {$connect eq {connect}} {
		lappend data(connect) $connection
		lappend data(disconnect) $disconnection
		if {$options(-activate)} {
		    {*}$connection
		}
	    } else {
		lremove data(connect) $connection
		lremove data(disconnect) $disconnection
		if {$options(-activate)} {
		    {*}$disconnection
		}
	    }
	}
    }
    method connect {ins outs} { $self connection connect $ins $outs }
    method disconnect {ins outs} { $self connection disconnect $ins $outs }

    # common constructor
    constructor {args} {
	if {$verbose(construct)} { puts "block $self constructor {$args}" }
	array set tmp $args
	set partof $tmp(-partof)
	set options(-server) [$partof cget -server]
	set options(-prefix) [$partof cget -name]
	set options(-control) [$partof cget -control]
	set options(-name) [string trim $options(-prefix)-$tmp(-suffix) -]
	set super $partof
	if {[catch {$super addpart $self} error erropts]} {
	    if {[string match {unknown subcommand "addpart": must be*} $error]} {
		set options(-super) {}
	    } else {
		return -options $erropts $error
	    }
	} else {
	    set options(-super) $super
	}
	#puts "before configure: server=$options(-server) prefix=$options(-prefix) suffix=$options(-suffix) name=$options(-name) control=$options(-control) super=$options(-super)"
	$self configure {*}$args
	$options(-control) add $options(-name) $self
	$self $options(-type) constructor
    }

    # common destructor
    destructor {
	catch {$self $options(-type) destructor}
	catch {$options(-control) remove $options(-name)}
    }
    
    ##
    ## -type jack
    ## blocks which contain a single jack module
    ## and need jack connections to function
    ##
    option -ports -default {} -readonly yes -configuremethod dispatch
    option -factory -readonly yes -configuremethod dispatch
    
    method {jack constructor} {} {
	$options(-factory) ::sdrblx::$options(-name) -server $options(-server)
	set ports [dict create]
	dict for {port desc} [sdrkit::jack -server $options(-server) list-ports] {
	    if {[string first ${options(-name)}: $port] == 0} {
		dict set ports $port $desc
	    }
	}
	set options(-ports) $ports
	::sdrblx::$options(-name) deactivate
    }

    method {jack destructor} {} {
	catch {rename ::sdrblx::$options(-name) {}}
    }

    method {jack configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self jack configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -inport {
		if {$verbose(inport)} { puts "block $options(-name) $self jack configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$options(-enable)} {
		    if {$val ne {}} { $self connect $val [$self jack ports * input] }
		    $self configure -outport [$self jack ports * output]
		    if {$old ne {}} { $self disconnect $old [$self jack ports * input] }
		} else {
		    $self configure -outport $val
		}
	    }
	    -enable {
		if {$verbose(enable)} { puts "block $options(-name) $self jack configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$val && ! $old} { # enable
		    $self connect $options(-inport) [$self jack ports * input]
		    $self configure -outport [$self jack ports * output]
		} elseif {$old && ! $val} { # disable
		    $self disconnect $options(-inport) [$self jack ports * input]
		    $self configure -outport $options(-inport)
		} else {
		    error "$options(name) configure $opt $val when options($opt) is $options($opt)"
		}
	    }
	    -activate {
		if {$verbose(activate)} { puts "block $options(-name) $self jack configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$val && ! $old} { # activate
		    ::sdrblx::$options(-name) activate
		    foreach conn $data(connect) { {*}$conn }
		} elseif {$old && ! $val} { # deactivate
		    # foreach disconn $data(disconnect) { {*}$discon }; # unnecessary?
		    ::sdrblx::$options(-name) deactivate
		} else {
		    error "$options(name) configure $opt $val when options($opt) is $options($opt)"
		}
	    }
	    -outport {
		$self stub configure $opt $val
	    }
	    -factory -
	    -ports { set options($opt) $val }
	    default {
		error "$options(-name) doesn't know how to \"jack configure $opt {$val}\""
	    }
	}
    }

    method {jack ports} {ptype pdirection} {
	if {$options(-type) ne {jack}} { error "$options(-name) is not a jack block" }
	set ports {}
	dict for {port desc} $options(-ports) {
	    if {([dict get $desc type] eq $ptype || $ptype eq {*}) &&
		[dict get $desc direction] eq $pdirection} {
		lappend ports $port
	    }
	}
	return $ports
    }

    ##
    ## -type alternate
    ## these options and method applies to blocks which switch between alternate graphs
    ##
    option -alternates -readonly yes -configuremethod dispatch
    option -alternate -default {} -configuremethod dispatch
    
    method {alternate constructor} {} {
	sdrblk::comp-stub ::sdrblx::$options(-name)
	foreach package $options(-require) {
	    package require $package
	}
	foreach element $options(-alternates) {
	    lappend data(alternates) [$element %AUTO% -partof $self]
	}
    }

    method {alternate destructor} {} {
	catch {
	    for element $data(alternates) {
		catch {$element destroy}
	    }
	}
	catch {rename ::sdrblx::$options(-name) {}}
    }

    method {alternate configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self alternate configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -inport {
		set options($opt) $val
		if {$verbose(inport)} { puts "block $options(-name) $self alternate configure $opt {$val} was {$old}" }
		if {$options(-alternate) ne {}} {
		    $options(-alternate) configure $opt $val
		} else {
		    $self configure -outport $val
		}
	    }
	    -outport {
		if {$verbose(outport)} { puts "block $options(-name) $self alternate configure $opt {$val} was {$old}" }
		$self stub configure $opt $val
	    }
	    -activate {
		if {$verbose(activate)} { puts "block $options(-name) $self alternate configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$options(-alternate) ne {} && [$options(-alternate) cget -enable]} {
		    $options(-alternate) configure $opt $val
		}
	    }
	    -enable {
		if {$verbose(enable)} { puts "block $options(-name) $self alternate configure $opt {$val} was {$old}" }
		if { ! $old && $val} {
		    set options($opt) $val
		} else {
		    error "$options(-name) can only be enabled once"
		}
	    }
	    -alternates {
		set options($opt) $val
	    }
	    -alternate {
		if {$val ne {} && $val ni $data(alternates)} { error "$options(-name) $val is not a valid alternate" }
		set options($opt) $val
		if {$val ne {}} {
		    $val configure -inport $options(-inport) -outport $options(-outport)
		}
		if {$old ne {}} {
		    $old configure -inport {} -outport {}
		}
	    }
	    default {
		error "$options(-name) doesn't know how to \"alternate configure $opt {$val}\""
	    }
	}
    }
    
    ##
    ## -type sequence
    ##  sequences of blocks
    ##
    option -sequence -readonly yes -configuremethod dispatch
    
    method {sequence constructor} {} {
	# make a stub controller
	sdrblk::comp-stub ::sdrblx::$options(-name)
	# build the components of the sequence
	foreach package $options(-require) {
	    package require $package
	}
	foreach element $options(-sequence) {
	    lappend data(sequence) [$element %AUTO% -partof $self]
	}
	# connect the components of the sequence
	foreach \
	    last [concat [list {}] [lrange $data(sequence) 0 end-1]] \
	    element $data(sequence) \
	    next [concat [lrange $data(sequence) 1 end] [list {}]] \
	    {
		if {$last ne {} && $next ne {}} {
		    $element configure -input $last -output $next
		} elseif {$next ne {}} {
		    $element configure -output $next
		} elseif {$last ne {}} {
		    $element configure -input $last
		}
	    }
	# reset the sequence sink and source
	$self configure -source $options(-source) -sink $options(-sink)
    }

    method {sequence destructor} {} {
	catch {rename ::sdrblx::$options(-name) {}}
	catch {
	    foreach element $data(sequence) {
		catch {$element destroy}
	    }
	}
    }
    
    method {sequence configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -inport {
		if {$verbose(inport)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		set options($opt) $val
		foreach part [$self input-parts] {
		    $part configure -inport $val
		}
	    }
	    -outport {
		if {$verbose(outport)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		$self stub configure $opt $val
	    }
	    -activate {
		if {$verbose(activate)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		set options($opt) $val
		foreach part [$self parts] {
		    if {[$part cget -enable]} {
			$part stub configure $opt $val
		    }
		}
	    }
	    -enable {
		if {$verbose(enable)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		if { ! $old && $val} {
		    set options($opt) $val
		} else {
		    error "$options(-name) can only be enabled once"
		}
	    }
	    -sequence { set options($opt) $val }
	    -source {
		if {$verbose(connect)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$val ne {}} {
		    foreach part [$self input-parts] {
			if {[$part cget -type] eq {input}} {
			    $part configure -source $val
			}
		    }
		}
	    }
	    -sink {
		if {$verbose(connect)} { puts "block $options(-name) $self sequence configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$val ne {}} {
		    foreach part [$self output-parts] {
			if {[$part cget -type] eq {output}} {
			    $part configure -sink $options(-sink)
			}
		    }
		}
	    }
	    default {
		error "$options(-name) doesn't know how to \"sequence configure $opt {$val}\""
	    }
	}
    }

    ##
    ## -type input, -type output
    ## blocks which connect directly to hardware
    ##
    option -sink -default {} -configuremethod dispatch

    method {output constructor} {}  { $self stub constructor }
    method {output destructor} {}  { $self stub destructor }
    method {output configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self outport configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -outport {
		if {$verbose(outport)} { puts "block $options(-name) $self configure $opt {$val} was {$old}" }
		set options($opt) $val
	    }
	    -inport {
		if {$verbose(inport)} { puts "block $options(-name) $self configure $opt {$val} was {$old}" }
		$self stub configure $opt $val
	    }
	    -activate { $self stub configure $opt $val }
	    -enable { $self stub configure $opt $val }
	    -sink {
		if {$verbose(connect)} { puts "block $options(-name) $self output configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$options(-outport) ne {}} {
		    if {$options(-outport) ne [$options(-super) cget -inport]} {
			$self connect $options(-outport) $val
		    }
		    if {$old ne {}} {
			$self disconnect $options(-outport) $old
		    }
		}
	    }
	    default {
		error "$options(-name) doesn't know how to \"output configure $opt {$val}\""
	    }
	}
    }

    option -source -default {} -configuremethod dispatch
    
    method {input constructor} {}  { $self stub constructor }
    method {input destructor} {}  { $self stub destructor }
    method {input configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self input configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -inport {
		if {$verbose(inport)} { puts "block $options(-name) $self input configure $opt {$val} was {$old}" }
		set options($opt) $val
		$self configure -outport $val
	    }
	    -outport { $self stub configure $opt $val }
	    -activate { $self stub configure $opt $val }
	    -enable { $self stub configure $opt $val }
	    -source {
		set options($opt) $val
		if {$verbose(connect)} { puts "block $self input configure $opt {$val} was {$old}" }
		$self configure -inport $val
	    }
	    default {
		error "$options(-name) doesn't know how to \"input configure $opt {$val}\""
	    }
	}
    }
    
    ##
    ## -type meter, -type spectrum
    ## blocks which provide placeholders for meter and spectrum taps
    ##
    method {meter constructor} {}  { $self stub constructor }
    method {meter destructor} {}  { $self stub destructor }
    method {meter configure} {opt val} { $self stub configure $opt $val }

    method {spectrum constructor} {} { $self stub constructor }
    method {spectrum destructor} {} { $self stub destructor }
    method {spectrum configure} {opt val} { $self stub configure $opt $val }

    ##
    ## stub methods for common behavior
    ##
    method {stub constructor} {} {
	sdrblk::comp-stub ::sdrblx::$options(-name)
    }
    method {stub destructor} {} {
	catch {rename ::sdrblx::$options(-name) {}}
    }
    method {stub configure} {opt val} {
	set old $options($opt)
	if {$verbose(configure)} { puts "block $options(-name) $self stub configure $opt {$val} was {$old}" }
	switch -- $opt {
	    -inport {
		if {$verbose(inport)} { puts "block $options(-name) $self stub configure $opt {$val} was {$old}" }
		set options($opt) $val
		$self configure -outport $val
	    }
	    -outport {
		if {$verbose(outport)} { puts "block $options(-name) $self stub configure $opt {$val} was {$old}" }
		set options($opt) $val
		if {$options(-output) ne {}} {
		    $options(-output) configure -inport $val
		} elseif {$options(-super) ne {}} {
		    $options(-super) configure -outport $val
		}
	    }
	    -enable {
		if {$verbose(enable)} { puts "block $options(-name) $self stub configure $opt {$val} was {$old}" }
		set options($opt) $val
	    }
	    -activate {
		if {$verbose(activate)} { puts "block $options(-name) $self stub configure $opt {$val} was {$old}" }
		if {$options(-enable)} {
		    set options($opt) $val
		}
		if {$options(-output) ne {}} {
		    $options(-output) configure $opt $val
		}
	    }
	    default {
		error "$options(-name) doesn't know how to \"stub configure $opt {$val}\""
	    }
	}
    }
}

