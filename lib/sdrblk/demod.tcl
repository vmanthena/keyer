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

package provide sdrblk::demod 1.0.0

package require snit
package require sdrblk::validate
package require sdrblk::block

package require sdrkit::demod-am
package require sdrkit::demod-sam
package require sdrkit::demod-fm

::snit::type ::sdrblk::demod {
    component block -public block
    component demod

    option -partof -readonly yes
    option -server -readonly yes -default {} -cgetmethod Cget
    option -control -readonly yes -default {} -cgetmethod Cget
    option -prefix -readonly yes -default {} -cgetmethod Prefix

    option -implemented -readonly yes -default yes
    option -suffix -readonly yes -default demod

    option -enable -default no

    constructor {args} {
	puts "demod $self constructor $args"
        $self configure {*}$args
	set options(-name) [string trim [$self cget -prefix]-$options(-suffix) -]
	install block using ::sdrblk::block %AUTO% -partof $self
	[$self cget -control] add $options(-name) $self

    }

    destructor {
        catch {$block destroy}
	catch {rename $options(-name) {}}
    }

    method controls {} {
	return { -mode {demodulation, one of cw, cwu, cwl, ssb, usb, lsb, am, sam, or fm} }
    }

    method control {opt val} { $options(-name) configure $opt $val }

    method controlget {opt} { return [$options(-name) cget $opt] }

    method Validate {opt val} {
	#puts "demod $self Validate $opt $val"
	switch -- $opt {
	    -enable { ::sdrblk::validate::boolean $opt $val }
	    default { error "unknown validate option \"$opt\"" }
	}
    }

    method Configure {opt val} {
	#puts "demod $self Configure $opt $val"
	switch -- $opt {
	    -mode {
		$block configure -internal {}
		catch {rename $demod {}}
		switch $val {
		    cw - cwu - cwl - ssb - usb - lsb {
			# (blms_adapt(rx[k]->banr.gen) || blms_adapt(rx[k]->banf.gen) || nil ) ||
			# ((blms_adapt(rx[k]->banr.gen) || lmsr_adapt(rx[k]->anr.gen) || nil) &&
			# ((blms_adapt(rx[k]->banf.gen) || lmsr_adapt(rx[k]->anf.gen) || nil) here
		    }
		    am {
			install demod using ::sdrkit::demod-am $options(-name) -server [$self cget -server]
			$block configure -internal $demod
			# lmsr_adapt(rx[k]->anf.gen) || blms_adapt(rx[k]->banf.gen) || nil here
		    }
		    sam {
			install demod using ::sdrkit::demod-sam $options(-name) -server [$self cget -server]
			$block configure -internal $demod
			# lmsr_adapt(rx[k]->anf.gen) || blms_adapt(rx[k]->banf.gen) || nil here
		    }
		    fm {
			install demod using ::sdrkit::demod-fm $options(-name) -server [$self cget -server]
			$block configure -internal $demod
		    }
		}
	    }
	    default { error "unknown configure option \"$opt\"" }
	}
	set options($opt) $val
    }

    method Cget {opt} {
	if {[info exists options($opt)] && $options($opt) ne {}} {
	    return $options($opt)
	} else {
	    return [$options(-partof) cget $opt]
	}
    }
    
    method Prefix {opt} {
	if {[info exists options($opt)] && $options($opt) ne {}} {
	    return $options($opt)
	} else {
	    return [$options(-partof) cget -name]
	}
    }
}
