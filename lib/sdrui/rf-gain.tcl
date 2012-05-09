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
## rf-gain - rf-gain control
##
package provide sdrui::rf-gain 1.0.0

package require Tk
package require snit
package require sdrtype::types
package require sdrtk::lspinbox

namespace eval ::sdrui {}
    
snit::widgetadaptor sdrui::rf-gain {

    option -gain -default 0 -type sdrtype::gain

    option -options {-gain}

    option -command {}
    option -opt-connect-to {}
    option -opt-connect-from {}

    delegate option -label to hull as -text
    delegate option -labelanchor to hull
    delegate option * to hull
    delegate method * to hull

    constructor {args} {
	installhull using sdrtk::lspinbox -label {RF Gain} -labelanchor n \
	    -width 4 -textvar [myvar options(-gain)] -command [mymethod Set -gain] \
	    -from [sdrtype::gain cget -min] -to [sdrtype::gain cget -max] -increment 1
	$self configure {*}$args
    }

    method resolve {} {
	foreach tf {to from} {
	    lappend options(-opt-connect-$tf) {*}[sdrui::common::connect $tf $win $options(-options)]
	}
    }

    method Set {opt} { {*}$options(-command) report $opt $options($opt) }

}


