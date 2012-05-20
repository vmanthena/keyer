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
# a composite component that implements a receiver
#
package provide sdrkit::rx 1.0.0

package require snit
package require sdrtk::clabelframe

namespace eval sdrkit {}

snit::type sdrkit::rx {
    option -name rx
    option -title {RX}
    option -in-ports {in_i in_q}
    option -out-ports {out_i out_q}
    option -in-options {}
    option -out-options {}
    option -sub-components {
	rf-g {RF Gain} gain
	rf-iqs {IQ Swap} iq-swap
	rf-iqd {IQ Delay} iq-delay
	rf-sp1 {Spectrum Semi-raw} spectrum-tap
	-rf-nb1 {Noiseblanker} noiseblanker
	-rf-nb2 {SDRom Noiseblanker} sdrom-noiseblanker
	rf-iqc {IQ Correct} iq-correct
	if-sp2 {Spectrum Pre-filter} spectrum-tap
	if-lo {LO Mixer} lo-mixer
	if-bpf {BP Filter} filter-overlap-save
	af-mt1 {Meter Post-filter} meter-tap
	af-sp3 {Spectrum Post-filter} spectrum-tap
	-af-cmp {Compander} compand
	af-agc {AGC} agc
	af-sp4 {Spectrum Post-AGC} spectrum-tap
	af-dem {Demodulation} demod
	-af-sql {Squelch} squelch
	-af-spt {Spot Tone} spot
	-af-geq {Graphic EQ} graphic-eq
	af-g {AF Gain} gain
    }
    option -connections {
	{} in-ports rf-g in-ports
	rf-g out-ports rf-iqs in-ports
	rf-iqs out-ports rf-iqd in-ports
	rf-iqd out-ports rf-sp1 in-ports
	rf-sp1 out-ports rf-nb1 in-ports
	rf-nb1 out-ports rf-nb2 in-ports
	rf-nb2 out-ports rf-iqc in-ports
	rf-iqc out-ports if-sp2 in-ports
	if-sp2 out-ports if-lo in-ports
	if-lo out-ports if-bpf in-ports
	if-bpf out-ports af-mt1 in-ports
	af-mt1 out-ports af-sp3 in-ports
	af-sp3 out-ports af-cmp in-ports
	af-cmp out-ports af-agc in-ports
	af-agc out-ports af-sp4 in-ports
	af-sp4 out-ports af-dem in-ports
	af-dem out-ports af-sql in-ports
	af-sql out-ports af-spt in-ports
	af-spt out-ports af-geq in-ports
	af-geq out-ports af-g in-ports
	af-g out-ports {} out-ports
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
	# puts "$self constructor"
	$self configure {*}$args
    }
    destructor {
	foreach name $data(parts) {
	    $option(-component) name-destroy $options(-name)-$name
	}
    }
    proc match-ports {ports1 ports2} {
	switch "$ports1 to $ports2" {
	    {out_i out_q to out_i out_q midi_out} {
		return {{out_i out_q} {out_i out_q}}
	    }
	    {midi_out to out_i out_q midi_out} {
		return {{midi_out} {midi_out}}
	    }
	    default {
		error "need to match $ports1 to $ports2"
	    }
	}
    }
    method resolve-parts {} {
	# need to match midi vs audio
	foreach {name1 ports1 name2 ports2} $options(-connections) {
	    set name1 [string trim "$options(-name)-$name1" -]
	    set name2 [string trim "$options(-name)-$name2" -]
	    set ports1 [$options(-component) $ports1 $name1]
	    set ports2 [$options(-component) $ports2 $name2]
	    if {[llength $ports1] != [llength $ports2]} {
		lassign [match-ports $ports1 $ports2] ports1 ports2
	    }
	    foreach p1 $ports1 p2 $ports2 {
		$options(-component) connect-ports $name1 $p1 $name2 $p2
	    }
	}
    }
    method build-parts {} {
	if {$options(-window) ne {none}} return
	foreach {name title command} $options(-sub-components) {
	    if {[string match -* $name]} {
		# placeholder component, replace with spectrum tap
		set name [string range $name 1 end]
		set command spectrum-tap
	    }
	    set data($name-enable) 0
	    lappend data(parts) $name
	    package require sdrkit::$command
	    ::sdrkit::component ::sdrkitv::$options(-name)-$name \
		-window none \
		-server $options(-server) \
		-name $options(-name)-$name \
		-subsidiary sdrkit::$command \
		-control [$options(-component) get-controller]
	}
    }
    method build-ui {} {
	if {$options(-window) eq {none}} return
	set w $options(-window)
	if {$w eq {}} { set pw . } else { set pw $w }
	
	foreach {name title command} $options(-sub-components) {
	    if {[string match -* $name]} {
		# placeholder component, replace with spectrum tap
		set name [string range $name 1 end]
		set command spectrum-tap
	    }
	    sdrtk::clabelframe $w.$name -label $title
	    if {$command ni {meter-tap spectrum-tap}} {
		# only display real working components
		grid $w.$name -sticky ew
	    }
	    ttk::checkbutton $w.$name.enable -text {} -variable [myvar data($name-enable)] -command [mymethod Enable $name]
	    set data($name-enable) 0
	    lappend data(parts) $name
	    package require sdrkit::$command
	    frame $w.$name.container
	    ::sdrkit::component ::sdrkitv::$options(-name)-$name \
		-window $w.$name.container \
		-server $options(-server) \
		-name $options(-name)-$name \
		-subsidiary sdrkit::$command \
		-control [$options(-component) get-controller] \
		-minsizes $options(-minsizes) \
		-weights $options(-weights)
	    grid $w.$name.enable $w.$name.container
	    grid columnconfigure $w.$name 1 -weight 1 -minsize [tcl::mathop::+ {*}$options(-minsizes)]
	}
	grid columnconfigure $pw 0 -minsize [tcl::mathop::+ {*}$options(-minsizes)] -weight 1
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
    method Enable {name} { $options(-component) report name-enable $options(-name)-$name $data($name-enable) }
}

