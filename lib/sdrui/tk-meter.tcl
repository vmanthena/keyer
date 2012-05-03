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

##
## s-meter
## horizontal bar
##

##
## http://en.wikipedia.org/wiki/S_meter
## IARU Region 1 Technical Recommendation R.1
##
## S-reading	HF		Signal Generator emf
##		μV (50Ω)	dBm	dB above 1uV
## S9+60dB			-13
## S9+40dB			-33
## S9+20dB			-53
## S9+10dB	160.0		-63	44
## S9		50.2		-73	34
## S8		25.1		-79	28
## S7		12.6		-85	22
## S6		6.3		-91	16
## S5		3.2		-97	10
## S4		1.6		-103	4
## S3		0.8		-109	-2
## S2		0.4		-115	-8
## S1		0.2		-121	-14
## S0				-127
##

package provide sdrui::tk-meter 1.0.0

package require Tk
package require snit

snit::widgetadaptor sdrui::tk-meter {
    option -max -default -13.0 -configuremethod opt-handler
    option -min -default -127.0 -configuremethod opt-handler

    variable data -array {
	width 1
    }
    
    constructor {args} {
	installhull using canvas -height 5
	$self configure {*}$args
	$hull configure -bg white
	$hull create line 0 2.5 0 2.5 -width 5 -fill red -tag meter
	bind $win <Configure> [mymethod rescale %w %h]
	#$self rescale [winfo width $win] [winfo height $hull]
    }
    
    method rescale {wd ht} {
	#puts "rescale $wd $ht"
	set data(width) $wd
    }

    method update {dB} {
	set x [expr {($dB-$options(-min))*$data(width)/($options(-max)-$options(-min))}]
	puts "tk-meter $x"
	$hull coords meter 0 2.5 $x 2.5
    }

    method {opt-handler -max} {value} { set options(-max) $value }
    method {opt-handler -min} {value} { set options(-min) $value }
}
