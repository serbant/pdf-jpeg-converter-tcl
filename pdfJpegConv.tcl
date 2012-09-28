#!/bin/sh
# the next line restarts using wish \
exec tclsh86 "$0" ${1+"$@"}

###############################################################################
#Batch convert pdf files to jpg images
#Copyright (C) 2010  Serban Teodorescu
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################
    
    
# globals
global gsBinary
if {[string match $tcl_platform(platform) "unix"]} {
    set gsBinary "/usr/bin/gs"
}
if {[string match $tcl_platform(platform) "windows"]} {
    set gsBinary "C:/Program Files/gs/gs8.70/bin/gswin32c.exe"
}

# globals that should not be globals but need to be available in execGs
# the ghostscript interpreter tends to fail in ways that cannot be handled
# via catch and we use these globals to log such failures
global fDebug
global fExcludeBusted
global debug
global progress
global listFiles

# procedures
proc searchFilesRecurse { dir ext } {
    global debug
    global progress
    global listFiles
    
    if { $debug eq 0 } {
	    puts -nonewline $progress
    }
    
    set listLocalFiles [ lsort -dictionary [ glob -nocomplain -directory $dir $ext ] ] 
    if { [llength $listLocalFiles ] && $debug} {
	puts "\nINFO: found [ llength $listLocalFiles ] \
	      [ regsub -all {\*|\.} $ext {} ] files in directory $dir"
    }
	    
	foreach file [ glob -nocomplain $dir/* ] {
	
	if { [ file isdirectory $file ] } {
	    if { $debug } {
		puts "DEBUG: searching [file normalize [file nativename $file]]..."
	    }
	    
	    searchFilesRecurse $file $ext
	    continue
	}
	
	if { [ string equal -nocase [ regsub -all {\*} $ext {} ] [ file extension $file ] ] } {
	    lappend listFiles [ file normalize $file ]
	    continue
	}
    }
}

proc inputChecks { dir } {

    if { [ file isdirectory $dir ] } {
	puts "\nINFO: Using search path starting from $dir ..."
	return -code ok 1
    } else {
	puts "\nINFO: Invalid command line parameter(s) detected.\n\
	      $dir is not a valid directory or does not exist..."
	
	return -code ok 0
    }
}

proc Usage {} {

    puts "Usage:\n\
	  [info script] \[Directoy where to start searching\] \[Extension of the files to search for\]\n\
	  where\n\
	  \[Directory where to start searching\] is a valid file system directory; \
	  use forward slashes only.\n\
	  and\n\
	  \[Extension of the files to search for\] is a valid Windows style file extension; \
	  formats like \"*.ext\", \".ext\", \"ext\" are acceptable and the length of the \
	  extension is not limited to 3 characters.\n"
}

proc createGsOutput myFile {

    if { [ file isdir [ file normalize [ file rootname [ file normalize \
	 [ file nativename $myFile ] ] ] ] ] } {
	return -code ok 1
    }
	
    if { ![file exists [file normalize [file rootname [file normalize [file nativename $myFile]]]]] || \
       { [file exists [file normalize [file rootname [file normalize [file nativename $myFile]]]]] && \
	 [file isfile [file normalize [file rootname [file normalize [file nativename $myFile]]]]] \
       } } {
       
	if {[catch {file mkdir [file normalize [file rootname [file normalize [file nativename $myFile]]]]} catchMe]} {
	    return -code error \
		   -errorInfo "[file nativename $myFile]: can't create output directory, $catchMe" \
		   0
	} else {
	    return -code ok 1
	}
    }
}

proc execGs myFile {

    global gsBinary
    global fDebug
    global fExcludeBusted
    
    if { [ catch \
	 { exec -ignorestderr -- $gsBinary \
		-dBATCH \
		-dNOPAUSE \
		-sDEVICE=jpeg \
		-dJPEGQ=100 \
		-sOutputFile=[ file normalize [ file rootname [ file normalize \
			     [ file nativename $myFile ] ] ] ]\\page\-\%03d.jpg \
		[ file normalize [ file nativename $myFile ] ] \
		>& "[ file normalize [ file rootname [ file normalize \
		    [ file nativename $myFile ] ] ] ]\\conversion.log" \
	 } catchMe ] \
	} {
	puts $fDebug "[ file normalize [ file nativename $myFile ] ]: gs error caught $catchMe\?"
	puts $fExcludeBusted $myFile
	flush $fExcludeBusted
	
	return -code ok 0
    } else {
	return -code ok 1
    }
}

# Start main
set searchRootPath "D:/hentai"
set ext "\*\.pdf"

set fnExcludeConverted "\./converted.log"
set fnExcludeBusted "\./fucked.log"

# Verify and process input
switch -exact $argc {
    0 {
	puts "\nNo command line parameters detected.\n\
	      Using default search path starting from $searchRootPath ...\n\
	      Using default search extension $ext ..."
    }
    
    1 {
	if { ![ inputChecks [ lindex $argv 0 ] ] } {
	    Usage
	    exit
	}
	
	set searchRootPath [ lindex $argv 0 ]
	puts "\nUsing default search extension $ext ..."
    }
    
    default {
	if { ![ inputChecks [ lindex $argv 0 ] ] } {
	    Usage
	    exit
	}
	
	set searchRootPath [ lindex $argv 0 ]
	set ext "\*\.[ regsub -all {\*|\.|\?} [ lindex $argv 1 ] {} ]"
	puts "\nUsing search extension $ext ..."
    }
}
	    

# begin
set progress "\."
set debug 1
set listFiles [ list ]
set listExcludeConverted ""
set listExcludeBusted ""
set countErrors 0

searchFilesRecurse $searchRootPath $ext

if { [ file isfile $fnExcludeConverted ] } {
    set fExcludeConverted [ open $fnExcludeConverted r ]
    set content [ read -nonewline $fExcludeConverted ]
    set listExcludeConverted [ split $content \n ]
    puts "\nINFO: Exclude converted files listed in \
	  [ file normalize [ file nativename $fnExcludeConverted ] ]..."
    close $fExcludeConverted
}
      
if { $debug } {
    puts "\nDEBUG: all the [ regsub -all {\*|\.} $ext {} ] files \
	  successfully converted during this session will have their names \
	  appended to the \
	  [ file normalize [ file nativename $fnExcludeConverted ] ] file..."
}

if { [ file isfile $fnExcludeBusted ] } {      
    set fExcludeBusted [ open $fnExcludeBusted r ]
    set content [ read -nonewline $fExcludeBusted ]
    set listExcludeBusted [ split $content "\n" ]
    puts "\nINFO: Exclude failed conversion files list in \
	      [ file normalize [ file nativename $fnExcludeBusted ] ]:\n\t \
	      Some of these files can be unfucked the cutePDF writer..."
    close $fExcludeBusted
}

if { $debug } {
    puts "\nDEBUG: all the [ regsub -all {\*|\.} $ext {} ] files \
	  that failed conversion during this session will have their names \
	  appended to the \
	  [ file normalize [ file nativename $fnExcludeBusted ] ] file. \
	  Be sure to remove the ones \
	  run through cutePDF for another conversion attempt..."
}
      
if { $debug } {
    set fDebug [ open "\./[clock format [clock seconds] -format {%y-%m-%d--%H-%M-%S}]-listFiles.log" w ]
    puts $fDebug "--- Excluded from conversion, already converted ---"
    puts $fDebug [ join $listExcludeConverted \n ]
    puts $fDebug "\n--- Excluded from conversion, fucked-up pdf formatting ---"
    puts $fDebug [ join $listExcludeBusted \n ]
    puts $fDebug "\--- Attempt conversion during this session ---"
    puts $fDebug [ join $listFiles \n ]
    puts $fDebug "\n--- Failures ---"
    flush $fDebug
    # close $fDebug
    puts "\nDEBUG: List of files to convert available in the \
	    [ file normalize [ file rootname [ file normalize [ file nativename \
	    [ info script ] ] ] ] ]\/debug\.log file..."
}

if { ![ llength $listFiles ] } {
    puts "\nINFO: 0 [ regsub -all {\*\.} $ext {} ] files \
	  under directory $searchRootPath and its subdirectories"
    exit 0
} else {
    puts "\nINFO: [ llength $listFiles ] \
	  [ regsub -all {\*\.} $ext {} ] files..."
    set countSkipped 0
    set countRemaining [ llength $listFiles ]
}    

set fExcludeConverted [ open $fnExcludeConverted a+ ]
set fExcludeBusted [ open $fnExcludeBusted a+ ]
		   
foreach myFile $listFiles {

    if { [ lsearch -exact -sorted -increasing -dictionary $listExcludeConverted \
	 $myFile ] != -1 } {
	puts "\nDEBUG: skipping $myFile, already converted..."
	puts "INFO: [ incr countSkipped ] files..."
	puts "INFO: [ incr countRemaining -1 ] files to convert..."
	continue
    }
    
    if { [ lsearch -exact -sorted -increasing -dictionary $listExcludeBusted $myFile ] ne -1 } {
	puts "\nDEBUG: skipping $myFile, conversion failed once already..."
	puts "INFO: [ incr countSkipped ] files..."
	puts "INFO: [ incr countRemaining -1 ] files to convert..."
	continue
    }
    
    puts "\nINFO: [ file nativename $myFile ]: Now converting..."
	    
    if { ![createGsOutput $myFile ] } {
	puts "INFO: [ file nativename $myFile ]: $errorInfo. aborting conversion..."
	puts "\nINFO: [ incr countErrors ] conversion errors..."
	puts "INFO: [ incr countRemaining -1 ] files to convert..."
	if { $debug } {
	    puts $fDebug "[ file nativename $myFile ]: $errorInfo. aborting conversion..."
	    flush $fDebug
	}
	continue
    }
    
    if { ![ execGs $myFile ] } {
	puts "\nINFO: [ file nativename $myFile ]: $errorInfo. aborting conversion..."
	puts "\nINFO: [ incr countErrors ] conversion errors..."
	puts "INFO: [ incr countRemaining -1 ] files still to convert..."
	if { $debug } {
	    puts $fDebug "[ file nativename $myFile ]: $errorInfo. aborting conversion..."
	    flush $fDebug
	}
	continue
    }
    
    puts "\nINFO: [ file nativename $myFile ]: converted to JPEG images in \
	  [ file nativename [ file rootname $myFile ] ]..."
	  
    puts $fExcludeConverted $myFile
    flush $fExcludeConverted
	  
    puts "\nINFO: [ expr { [ llength $listFiles ] - [ incr countRemaining -1 ] } ] files processed..."
    puts "INFO: [ expr { [ llength $listFiles ] - $countRemaining - $countErrors } ] files converted..."
    puts "INFO: $countErrors files failed conversions so far..."
    puts "INFO: $countSkipped files skipped..."
    puts "INFO: $countRemaining files to convert..."
    
}

if { $debug } {
    close $fDebug
}

close $fExcludeConverted
close $fExcludeBusted

puts "\nINFO: done. converted [ expr { [ llength $listFiles ] - $countErrors -$countSkipped } ] \
	[ regsub -all {\*|\.} $ext {} ] files to jpeg images"
puts "INFO: $countSkipped files skipped..."
puts "INFO: $countErrors [ regsub -all {\*|\.} $ext {} ] file conversions failed..."

exit 0

