/*
  Copyright (C) 2011, 2012 by Roger E Critchlow Jr, Santa Fe, NM, USA.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
*/
#ifndef FRAMEWORK_OPTIONS_VARS_H
#define FRAMEWORK_OPTIONS_VARS_H
#if FRAMEWORK_OPTIONS_MIDI
// midi options
int chan, note;
#endif
#if FRAMEWORK_OPTIONS_KEYER_TONE
// tone options    
float freq, gain, rise, fall;
int window, window2;
#endif
#if FRAMEWORK_OPTIONS_KEYER_SPEED
// speed options
float wpm; int word;
#endif
// element timing options
#if FRAMEWORK_OPTIONS_KEYER_TIMING_DAH
float  dah;
#endif
#if FRAMEWORK_OPTIONS_KEYER_TIMING_IES
float  ies;
#endif
#if FRAMEWORK_OPTIONS_KEYER_TIMING_ILS
float  ils;
#endif
#if FRAMEWORK_OPTIONS_KEYER_TIMING_IWS
float  iws;
#endif
#if FRAMEWORK_OPTIONS_KEYER_OPTIONS_SWAP
int swap;
#endif
#if FRAMEWORK_OPTIONS_KEYER_OPTIONS_ALSP
int alsp;
#endif
#if FRAMEWORK_OPTIONS_KEYER_OPTIONS_AWSP
int awsp;
#endif
#if FRAMEWORK_OPTIONS_KEYER_OPTIONS_MODE
int mode;
#endif
#endif
