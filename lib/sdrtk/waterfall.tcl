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
package provide sdrtk::waterfall 1.0.0

package require Tk
package require snit
package require hotiron

snit::widgetadaptor sdrtk::waterfall {
    
    option -atten 0
    option -pal 0
    option -min -125.0
    option -max -60.0
    option -min-f -1e6
    option -max-f 1e6
    
    option -height 200
    option -width 1024
    option -zoom -default 1 -type sdrtype::zoom
    option -pan -default 0 -type sdrtype::pan
    option -scale -default 1.0 -configuremethod handle-option
    option -offset -default  0.0 -configuremethod handle-option
    option -sample-rate -default 48000 -configuremethod handle-option

    option -reverse 0
    option -direction s

    option -command -default {}

    delegate option * to hull
    delegate method * to hull

    variable data -array {
	line-number 0
	freq 0
    }

    constructor {args} {
	installhull using canvas
	$self configure {*}$args
	$hull configure -width $options(-width) -height $options(-height) -bg black
	bind $win <Configure> [mymethod DrawAll]
	bind $win <ButtonPress-1> [mymethod Press %W %x %y]
	bind $win <ButtonRelease-1> [mymethod Release %W %x %y]
	bind $win <B1-Motion> [mymethod Motion %W %x %y]
    }

    ##
    ## cleanup your mess
    ##
    destructor {
	foreach img [array names data img-*] { rename $data($img) {} }
	array unset data
    }

    method DrawAll {} {
    }
    method Press {w x y} {
	set data(freq) [expr {($x-$data(xoffset))/$data(xscale)}]
	# puts "Press $w $b $x $y -> $f $data(xscale) $data(xoffset)"
    }
    method Release {w x y} {
	set df [expr {($x-$data(xoffset))/$data(xscale) - $data(freq)}]
	#puts "Release $w $b $x $y -> $f"
	if {$options(-command) ne {}} { {*}$options(-command) $w $x $y $df }
    }
    method Motion {w x y} {
	set df [expr {($x-$data(xoffset))/$data(xscale) - $data(freq)}]
	set data(freq) [expr {$data(freq)+$df}]
	# puts "Motion $w $x $y"
	if {$options(-command) ne {}} { {*}$options(-command) $w $x $y $df }
    }

    ##
    ## compute a pixel value for the specified level using the configured palette
    ##
    method pixel {level} {
	# clamp to percentage of range
	set level [expr {min(1,max(0,($level-$options(-min))/($options(-max)-$options(-min))))}]
	# use 100 levels
	set i color-$options(-pal)-[expr {int(100*$level)}]
	if { ! [info exists data($i)]} {
	    set data($i) [::hotiron $level $options(-pal)]
	}
	return $data($i)
    }

    ##
    ## make a scan line row or column of pixel values
    ##
    method scan {xy} {
	set data(xscale) [expr {[winfo width $win]/double($options(-sample-rate))}]
	set data(xoffset) [expr {[winfo width $win]/2.0}]
	set ymin 1e6
	set ymax -1e6
	set xmin 1e6
	set xmax -1e6
	foreach {x y} $xy {
	    set x [expr {$x*$data(xscale)+$data(xoffset)}]
	    set xmin [expr {min($xmin,$x)}]
	    set xmax [expr {max($xmax,$x)}]
	    set y [expr {$y+$options(-atten)}]
	    set ymin [expr {min($ymin,$y)}]
	    set ymax [expr {max($ymax,$y)}]
	    lappend f([expr {round($x)}]) $y
	}
	set n [winfo width $win]
	for {set x 0} {$x < $n} {incr x} {
	    if {[info exists f($x)]} {
		set y [expr {[tcl::mathop::+ {*}$f($x)]/double([llength $f($x)])}]
	    } else {
		set y $ymin
	    }
	    lappend freq $x
	    if {$options(-direction) in {n s}} {
		lappend scan [$self pixel $y]
	    } else {
		lappend scan [list [$self pixel $y]]
	    }
	}
	if {$options(-reverse)} {
	    set freq [lreverse $freq]
	    set scan [lreverse $scan]
	}
	if {$options(-direction) in {n s}} {
	    return [list $freq [list $scan]]
	} else {
	    return [list $freq $scan]
	}
    }

    ##
    ## draw a new scan line
    ##
    method update {xy} {
	# compute the scan line of pixels
	# this needs to scale x to window width
	lassign [$self scan $xy] freq scan
	set x0 [lindex $freq 0]
	
	# scroll all the canvas images up/down/left/right by 1
	switch $options(-direction) {
	    n { $hull move all 0 -1 }
	    s { $hull move all 0 1 }
	    e { $hull move all 1 0 }
	    w { $hull move all -1 0 }
	}

	# create a new canvas image
	set i $data(line-number)
	set data(img-$i) [image create photo]
	$data(img-$i) put $scan
	switch $options(-direction) {
	    default {
		set data(item-$i) [$hull create image $x0 0 -anchor nw -image $data(img-$i)]
		#$hull scale $data(item-$i) 0 0 $options(-scale) 1
		#$hull move $data(item-$i) $options(-offset) 0
	    }
	}
	# increment our scanline index
	incr data(line-number)
    }

    method adjust {savename} {
	upvar $savename save
	$hull move all [expr {-$save(-offset)}] 0
	$hull scale all 0 0 [expr {$options(-scale)/$save(-scale)}] 1
	$hull move all $options(-offset) 0
	# puts "waterfall::configure -scale $data(-scale) -offset $data(-offset) bbox [$w bbox all]"
    }

    method handle-option {option value} {
	array set save [array get options]
	set options($option) $value
	$self adjust save
    }

}

