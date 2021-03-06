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

package provide sdrtk::iscale 1.0.0

package require Tk
package require snit

namespace eval ::sdrtk {}

##
## a ttk::scale constrained to integer values
##

snit::widgetadaptor sdrtk::iscale {
    option -command {}
    option -variable -default {} -configuremethod Configure

    delegate option * to hull
    delegate method * to hull

    variable value

    constructor {args} {
	installhull using ttk::scale -command [mymethod Command] -variable [myvar value]
	$self configure {*}$args
    }
    destructor {
	catch {trace remove variable $options(-variable) write [mymethod TraceWrite]}
    }
    method {Configure -variable} {val} {
	if {$options(-variable) ne {}} {
	    trace remove variable $options(-variable) write [mymethod TraceWrite]
	}
	set options(-variable) $val
	if {$options(-variable) ne {}} {
	    trace add variable $options(-variable) write [mymethod TraceWrite]
	    $self TraceWrite
	}
    }
    method TraceWrite {args} {
	set value [set $options(-variable)]
    }

    method Command {val} {
	set val [expr {int(round($val))}]
	set value $val
	if {$options(-variable) ne {}} { set $options(-variable) $val }
	if {$options(-command) ne {}} { {*}$options(-command) $val }
    }
}
