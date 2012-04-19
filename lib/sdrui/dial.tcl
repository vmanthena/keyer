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
# a rotary encoder
#
package provide sdrui::dial 1.0

package require Tk
package require snit

snit::widgetadaptor sdrui::dial {
    # the maximum radius is 1/2 the minimum of width and height
    option -bg {};			# background color of the window containing the dial

    option -radius 80;			# radius of the dial in percent of max
    option -fill \#888;			# color of the dial
    option -outline black;		# color of the dial outline
    option -width 3;			# thickness of the dial outline

    option -thumb-radius 20;		# radius of the thumb in percent of max
    option -thumb-position 50;		# center of thumb in percent of max
    option -thumb-fill \#999;		# color of the thumb
    option -thumb-outline black;	# color of the thumb outline
    option -thumb-width 2;		# thickness of the thumb outline
    option -thumb-activewidth 4;	# thickness of the thumb outline when active

    option -graticule 20;		# number of graticule lines to draw
    option -graticule-radius 95;	# radius of graticule lines in percent of max
    option -graticule-width 3;		# width of graticule lines in pixels
    option -graticule-fill black;	# 

    option -cpr 1000;			# counts per revolution

    option -command {};			# script called to report rotation 
    
    variable data -array {
	partial-turn 0
    }

    constructor {args} {
	installhull using canvas -width 250 -height 250
	$self configure {*}$args
	set data(pi) [expr atan2(0,-1)]
	set data(2pi) [expr {2*$data(pi)}]
	set data(phi) [expr {-$data(pi)/2}]
	if {$options(-bg) eq {}} {
	    set options(-bg) [$hull cget -background]
	}
	$hull configure -background $options(-bg)
	bind $win <Configure> [mymethod window-configure %w %h]
	bind $win <ButtonPress-4> [mymethod tune up]
	bind $win <ButtonPress-5> [mymethod tune down]
    }
    
    method {tune} {dir} { $self rotate $data($dir-step) }

    method thumb-press {x y} { set data(phi) [expr {atan2($y-$data(yc),$x-$data(xc))}] }
    method thumb-motion {x y} {
	set phi0 $data(phi)
	set data(phi) [expr {atan2($y-$data(yc),$x-$data(xc))}]
	$self rotate [expr {$data(phi)-$phi0}]
    }

    method rotate {dphi} {
	## rotate thumb
	$self rotate-thumb $dphi

	## compute rotation in counts 
	set dturn [expr {$options(-cpr) * $dphi / $data(2pi) + $data(partial-turn)}]

	## account for discontinuity at +/-pi
	if {$dturn > $options(-cpr)/2} {
	    set dturn [expr {$dturn-$options(-cpr)}]
	} elseif {$dturn < -$options(-cpr)/2} {
	    set dturn [expr {$dturn+$options(-cpr)}]
	}

	## remember leftover partial turn
	set data(partial-turn) [expr {fmod($dturn,1)}]
	
	## see if there is anything to send
	set dturn [expr {$dturn-$data(partial-turn)}]

	if {abs($dturn) >= 1 && $options(-command) ne {}} {
	    {*}$options(-command) $dturn
	}
    }

    method rotate-thumb {dphi} {
	## get current thumb coordinates
	foreach {x1 y1 x2 y2} [$hull coords thumb] break
	## compute the thumb center
	set x [expr {($x1+$x2)/2.0-$data(xc)}]
	set y [expr {($y1+$y2)/2.0-$data(yc)}]
	## rotate thumb coordinates
	set sindphi [expr {sin($dphi)}]
	set cosdphi [expr {cos($dphi)}]
	foreach {x y} [list [expr {$x*$cosdphi - $y*$sindphi}] [expr {$y*$cosdphi + $x*$sindphi}]] break
	## set current thumb coordinates
	$hull coords thumb [expr {$x-$data(tr)+$data(xc)}] [expr {$y-$data(tr)+$data(yc)}] [expr {$x+$data(tr)+$data(xc)}] [expr {$y+$data(tr)+$data(yc)}]
	$hull coords pointer [expr {$x*$data(tis)+$data(xc)}] [expr {$y*$data(tis)+$data(yc)}] [expr {$x*$data(tos)+$data(xc)}] [expr {$y*$data(tos)+$data(yc)}]
    }

    method window-configure {w h} {
	#puts "ui-dial window-configure $w $h"
	set r  [expr {min($w,$h)/2.0}];				# radius of space available
	set xc [expr {$w/2.0}];					# center of space available
	set yc [expr {$h/2.0}];					# center of space available
	set dr [expr {$options(-radius)*$r/100.0}];		# dial radius
	set tr [expr {$r*$options(-thumb-radius)/100.0}];	# thumb radius
	set tp [expr {$r*$options(-thumb-position)/100.0}];	# thumb position radius scale
	set tis [expr {($tp-$tr)/$tp}];				# thumb inner radius scale
	set tos [expr {($tp+$tr)/$tp}];				# 
	set gr [expr {$r*$options(-graticule-radius)/100.0}];	# graticule radius
	set dial [list [expr {$xc-$dr}] [expr {$yc-$dr}] [expr {$xc+$dr}] [expr {$yc+$dr}]]
	set x [expr {$tp*cos($data(phi))}]
	set y [expr {$tp*sin($data(phi))}]
	set thumb [list [expr {$x-$tr+$xc}] [expr {$y-$tr+$yc}] [expr {$x+$tr+$xc}] [expr {$y+$tr+$yc}]]
	set pointer [list [expr {$x*$tis+$xc}] [expr {$y*$tis+$yc}] [expr {$x*$tos+$xc}] [expr {$y*$tos+$yc}]]

	if {$options(-graticule) <= 0} {
	    set graticule [list $xc $yc $xc $yc]
	    set mask [list $xc $yc $xc $yc]
	} else {
	    set graticule {}
	    set p 0
	    set dp [expr {$data(2pi)/$options(-graticule)}]
	    for {set i 0} {$i < $options(-graticule)} {incr i} {
		set x [expr {$xc+$gr*cos($p)}]
		set y [expr {$yc+$gr*sin($p)}]
		lappend graticule $xc $yc $x $y
		set p [expr {$p+$dp}]
	    }
	    set ir [expr {($dr+$gr)/2.0}]
	    set mask [list [expr {$xc-$ir}] [expr {$yc-$ir}] [expr {$xc+$ir}] [expr {$yc+$ir}]]
	}
	if {[llength [$hull find withtag thumb]] == 0} {
	    $hull create line $graticule -tag graticule -fill $options(-graticule-fill) -width $options(-graticule-width)
	    $hull create oval $mask -tag mask -fill $options(-bg) -outline {} 
	    $hull create oval $dial -tag dial -fill $options(-fill) -outline $options(-outline) -width $options(-width) 
	    $hull create oval $thumb -tag thumb -fill $options(-thumb-fill) -outline $options(-thumb-outline) -activewidth $options(-thumb-activewidth) -width $options(-thumb-width)
	    $hull create line $pointer -tag pointer -fill $options(-thumb-outline) -width $options(-thumb-width)
	    $hull bind thumb <ButtonPress-1> [mymethod thumb-press %x %y]
	    $hull bind thumb <B1-Motion> [mymethod thumb-motion %x %y]
	} else {
	    $hull coords graticule $graticule
	    $hull coords dial $dial
	    $hull coords thumb $thumb
	}
	array set data [list yc $yc xc $xc tr $tr tis $tis tos $tos]
    }
}    