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

if { [ catch { package require fileutil } caughtError ] } {
    set missingLib "tcllib"
    puts "ERROR: $caughtError ...\n
	  possibly missing library $missingLib ..."
    showRequiredLibs $missingLib
}
package require cmdline
package require struct::queue
package require log

if { [ catch { package require Thread } caughtError ] } {
    set missingLib "tclthread"
    puts "ERROR: $caughtError ...\n
	  possibly missing library $missingLib ..."
    showRequiredLibs $missingLib 
}

# globals
global listFiles

# get the threadId for this script (main thread), only needed on Winodws
# will not hurt on any platform
set mainThread [thread::id]

# we want to start logging right from the start but we can't log to files until
# after we've set up all the cmdline params... so this variable needs to be set
# after that. until then we shall have the log thread work only with stdout and
# stderr
#
tsv::set sharedLogging isLogReady 0
tsv::set sharedLogging isErrorReady 0

# start the log thread
#debug     => 0
#info      => 1
#notice    => 2
#warning   => 3
#error     => 4
#critical  => 5
#alert     => 6
#emergency => 7
set logThread [thread::create -joinable] {
    
    source thrLogger.tcl
    
}

thread::send $logThread [list set callMainThread $mainThread]
alogAlert "beginning..."

# deal with command line
array set arrCommonDefs [setDefaults]
array set arrCommonUsg [setUsage]

if ([string match $tcl_platform(platform) "windows"]) {
    array set arrPlatformDefs \
      [setDefaults "[file normalize $env(appdata)]/pdfJpegConv/pdfJpegConv" \
		    [file normalize $env(home)] "windows"]
    array set arrPlatformUsg \
	 [setUsage "[file normalize $env(appdata)]/pdfJpegConv/pdfJpegConv" \
		    [file normalize $env(home)] "windows"]
} else {
    array set arrPlatformDefs \
	   [setDefaults "[file normalize $env(home)]/.pdfJpegConv/pdfJpegConv" \
			 [file normalize $env(home)] "unix"]
    array set arrPlatformUsg \
	      [setUsage "[file normalize $env(home)]/.pdfJpegConv/pdfJpegConv" \
			 [file normalize $env(home)] "unix"]    
}

set options [list \
    [list "config.arg"            ""               $arrPlatformUsg(configUsg)] \
    [list "forgetConfig"                       $arrCommonUsg(forgetConfigUsg)] \
    [list "gsBinary.arg"          ""           $arrPlatformUsg(gsBinaryUsage)] \
    [list "logFile.arg"           ""              $arrPlatformUsg(logFileUsg)] \
    [list "errorFile.arg"         ""            $arrPlatformUsg(errorFileUsg)] \
    [list "maxSizeLogs.arg"       ""            $arrCommonUsg(maxSizeLogsUsg)] \
    [list "logLevel.arg"          ""               $arrCommonUsg(logLevelUsg)] \
    [list "excludeConverted.arg"  ""     $arrPlatformUsg(excludeConvertedUsg)] \
    [list "excludeFucked.arg"     ""        $arrPlatformUsg(excludeFuckedUsg)] \
    [list "cleanExcludeConverted"        $arrCommonUsg(cleanExcludeConverted)] \
    [list "cleanExcludeFucked"              $arrCommonUsg(cleanExcludeFucked)] \
    [list "chrSearchProgress.arg" ""      $arrCommonUsg(chrSearchProgressUsg)] \
    [list "chrConvProgress.arg"   ""        $arrCommonUsg(chrConvProgressUsg)] \
    [list "searchRootPaths.arg"   ""      $arrPlatformUsg(searchRootPathsUsg)] \
    [list "minSearchThreads.arg"  ""       $arrCommomUsg(minSearchThreadsUsg)] \
    [list "maxSearchThreads.arg"  ""       $arrCommonUsg(manSearchThreadsUsg)] \
    [list "minConvThreads.arg"    ""         $arrCommonUsg(minConvThreadsUsg)] \
    [list "maxConvThreads.arg"    ""         $arrCommonUsg(maxConvThreadsUsg)] \
]

set usage ": pdfJpegConv.tcl \[options] ...\noptions:"
array set arrCmdLineParms [::cmdline::getKnownOptions argv $options $usage]
alogDebug $logThread "see command line option values below"
# this next command may be iffy, check to see if one can pass the array directly
# to the log::logarray command or if one needs to first copy the array to the 
# thread first
thread::send -async $logThread {log::logarray debug arrCmdLineParms}

# ok, if we populate the defaults directly in the options list, we can't check
# the priority between cmdline, config file, and defaults. so we wated a lot of 
# time with the arrays but we can still  use the defaults array to populate
# post check
# see example
if {[string length $arrCmdLineParms(config)] > 0} {
    propFile fileConfigs $arrCmdLineParms(config) -force 1
} else {
    propFile fileConfigs $arrPlatformDefs(configDef)
}
alogDebug $logThread [fileConfigs getPropFile]

if ([string length $arrCmdLineParms(logFile)] == 0} {
    set logFile [fileConfigs getProperty "logFile"]
    if {[string match $logFile "-1"] || \
	[string match $logFile  "0"] || \
	[string length $logFile] == 0} {
	set logFile $arrPlatformDefs(logFileDef)
    }
} else {
    set logFile $arrCmdLineParms(logFile)
}
alogDebug $logThread "logging to $logFile"

if {[string length $arrCmdLineParms(errorFile)] == 0} {
    set errorFile [fileConfigs getProperty "errorFile"]
    if {[string match $errorFile "-1"] || \
	[string match $errorFile "0"] || \
	[string length $errorFile] == 0} {
	set errorFile $arrPlatformDefs(errorFileDef)
    }
} else {
    set errorFile $arrCmdLineParms(errorFile)
}
alogDebug $logThread "error logging to $errorFile"




# before this next command we should deal with the log and error files, and 
# obviously with the log level suppression
if {[string length $arrCmdLineParms(gsBinary)] == 0} {
    set gsBinary [fileConfigs getProperty "gsBinary"]
    if { [string match $gsBinary "-1"] || \
	 [string match $gsBinary "0"] || \
	 [string length $gsBinary] == 0} {
	set gsBinary $arrPlatformDefs(gsBinaryDef)
    }
} else {
    set gsBinary $arrCmdLineParms(gsBinary)
}
alogDebug $logThread "will try to use $gsBinary for conversion"
# check for gsBinary: put it on a thread and let it spin, wait for that thread
# after you've finished dealing with the other command line parms




# begin

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

if { [ file isfile $fnExcludeFucked ] } {      
    set fExcludeFucked [ open $fnExcludeFucked r ]
    set content [ read -nonewline $fExcludeFucked ]
    set listExcludeFucked [ split $content "\n" ]
    puts "\nINFO: Exclude failed conversion files list in \
    [ file normalize [ file nativename $fnExcludeFucked ] ]:\n\t \
    Some of these files can be unfucked the cutePDF writer..."
    close $fExcludeFucked
}

if { $debug } {
    puts "\nDEBUG: all the [ regsub -all {\*|\.} $ext {} ] files \
    that failed conversion during this session will have their names \
    appended to the \
    [ file normalize [ file nativename $fnExcludeFucked ] ] file. \
    Be sure to remove the ones \
    run through cutePDF for another conversion attempt..."
}

if { $debug } {
    set fDebug [ open "\./[clock format [clock seconds] -format {%y-%m-%d--%H-%M-%S}]-listFiles.log" w ]
    puts $fDebug "--- Excluded from conversion, already converted ---"
    puts $fDebug [ join $listExcludeConverted \n ]
    puts $fDebug "\n--- Excluded from conversion, fucked-up pdf formatting ---"
    puts $fDebug [ join $listExcludeFucked \n ]
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
set fExcludeFucked [ open $fnExcludeFucked a+ ]

foreach myFile $listFiles {
    
    if { [ lsearch -exact -sorted -increasing -dictionary $listExcludeConverted \
	 $myFile ] != -1 } {
	puts "\nDEBUG: skipping $myFile, already converted..."
	puts "INFO: [ incr countSkipped ] files..."
	puts "INFO: [ incr countRemaining -1 ] files to convert..."
	continue
    }
    
    if { [ lsearch -exact -sorted -increasing -dictionary $listExcludeFucked $myFile ] ne -1 } {
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
close $fExcludeFucked

puts "\nINFO: done. converted [ expr { [ llength $listFiles ] - $countErrors -$countSkipped } ] \
	[ regsub -all {\*|\.} $ext {} ] files to jpeg images"
puts "INFO: $countSkipped files skipped..."
puts "INFO: $countErrors [ regsub -all {\*|\.} $ext {} ] file conversions failed..."


# procedures


proc showRequiredLibs { missingLib } {
    puts "This application will not run unless the $missingLib library \n
	  is installed. \n
	  To install $missingLib: \n
	  \t\* On Linux invoke your software management application and \n
	  install the $missingLib package. For example, on a Fedora \n
	  installation execute as root:\n
	  \t \"yum install tcllib\"\n
	  \t\* On Windows make sure you have installed Tcl downloaded from \n
	  http://www.activestate.com."
    exit 1
}

proc searchFilesRecurse { dir ext { debug 0 } { progress "#" } } {
    
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

proc createGsOutput { myFile } {

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

proc execGs { gsBinary myFile { debug 0 } { fDebug } fExcludeFucked } {

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
	    if { $debug } {
		puts $fDebug "[ file normalize [ file nativename $myFile ] ]: gs error caught $catchMe\?"
	    }
	    puts $fExcludeFucked $myFile
	    flush $fExcludeFucked
	
	    return -code ok 0
    } else {
	return -code ok 1
    }
}

proc alogDebug {idThread message} {
    thread::send -async $idThread {log::Puts debug "[timeStamp] $message"}
}

proc alogInfo {idThread message} {
    thread::send -async $idThread {log::Puts info "[timeStamp] $message"}
}

proc alogNote {idThread message} {
    thread::send -async $idThread {log::Puts notice "[timeStamp] $message"}
}

proc alogWarn {idThread message} {
    thread::send -async $idThread {log::Puts warning "[timeStamp] $message"}
}

proc alogErr {idThread message} {
    thread::send -async $idThread {log::Puts error "[timeStamp] $message"}
}

proc alogCrit {idThread message} {
    thread::send -async $idThread {log::Puts critical "[timeStamp] $message"}
}

proc alogAlert {idThread message} {
    thread::send -async $idThread {log::Puts alert "[timeStamp] $message"}
}

proc alogEmergency {idThread message} {
    thread::send -async $idThread {log::Puts emergency "[timeStamp] $message"}
}

proc setDefaults {{confPath ""} {homePath ""} {platform ""}} {
    
    if {[string length $confPath] > 0} {
	set configDef           [list "configDef"           "$confPath\.config"]
	set logFileDef          [list "logFileDef"             "$confPath\.log"]
	set errorFileDef        [list "errorFileDef"         "$confPath\.error"]
	set excludeConvertedDef \
	[list "convertedFileDef" "$confPath\.converted"]
	set excludeFuckedDef    [list "fuckedFileDef"       "$confPath\.fucked"]
	set searchRootPathsDef  [list "searchRootPathsDef"            $homePath]
	if {[string match $platform "windows"]} {
	    set gsBinaryDef \
	    [list "gsBinaryDef" "C:/Program Files/gs/gs8.70/bin/gswin32c.exe"]
	} else {
	    set gsBinaryDef [list "gsBinaryDef"                   "/usr/bin/gs"]
	}
	return -code ok [concat $configDef $logFileDef $errorFileDef \
	 $excludeConvertedDef $excludeFuckedDef \
	 $searchRootPathsDef $gsBinaryDef]
    }
    
    set maxSizeLogsDef       [list "maxSizeLogsDef"                     1048576]
    set logLevelDef          [list "logLevelDef"                              0]
    set chrSearchProgressDef \
    [list "chrSearchProgressDef" "Looking for pdf files..."] 
    set chrConvProgressDef   [list "chrConvProgressDef"         "Converting..."] 
    set searchExtDef         [list "searchExtDef"                     "\*\.pdf"] 
    set minSearchThreadsDef  [list "minSearchThreadsDef"                     10]
    set maxSearchThreadsDef  [list "maxSearchThreadsDef"                     40]
    set minConvThreadsDef    [list "minConvThreadsDef"                        1]
    set maxConvThreadsDef    [list "maxConvThreadsDef"                        8]
    return -code ok [concat $maxSizeLogsDef $logLevelDef $chrSearchProgressDef \
     $chrConvProgressDef $searchExtDef $minSearchThreadsDef \
     $maxSearchThreadsDef $minConvThreadsDef $maxConvThreadsDef]
}

proc setUsage {{confPath ""} {homePath ""} {platform ""}} {
    
    if {[string length $confPath] > 0} {
	set configUsg [list "configUsg" "get options from this configuration \
	 file.\ncommand line options take precedence over config \
	 file options.\nconfig file options take precedence over \
	 defaults.\ndefault value is $confPath\.config."]
	set logFileUsg [list "logFileUsg" "application log file.\ndefault \
	 value is $confPath\.log."]
	set errorFileUsg [list "errorFileUsg" "application error file.\n \
	 default value is $confPath\.error."]
	set excludeConvertedUsg [list "excludeConvertedUsg" "file containing a \
	 list of files to exclude because they have \
	 already been converted.\n \
	 default value is $confPath\.converted."]
	set excludeFuckedUsg [list "excludeFuckedUsg" "file containing a list \
	 of files to exclude because they have failed \
	 conversion at least once.\nupdated while running. \
			     \ndefault value is $confPath\.fucked."]
	set searchRootPathsUsg [list "searchRootPathsUsg" "list of directories \
	 to search.\ndefault value is $homePath"]
	if {[string match $platform "windows"]} {
	    set gsBinaryUsg [list "gsBinaryUsg" "normalized location of the \
	     GhostScript binary.\ndefault value is \
	     C:/Program Files/gs/gs8.70/bin/gswin32c.exe.\n \
	     the application will try to guess this location \
	     if the default location is not correct"]
	} else {
	    set gsBinaryUsg [list "gsBinaryUsg" "normalized location of the \
	     GhostScript binary.\ndefault value is /usr/bin/gs."]
	}
	return -code ok [concat $configUsg $logFileUsg $errorFileUsg \
	 $excludeConvertedUsg $excludeFuckedUsg \
	 $searchRootPathsUsg $gsBinaryUsg]
    }
    
    set forgetConfigUsg [list "forgetConfigUsg" "do not save the current \
     configuration to the default configuration file."]
    set cleanExcludeConvertedUsg [list "cleanExcludeConvertedUsg" "remove \
     information about files already converted."]
    set cleanExcludeFuckedUsg [list "cleanExcludeFuckedUsg" "remove \
     information about files that have failed \
     conversion."]
    set maxSizeLogsUsg [list "maxSizeLogsUsg" "maximum size of any active log \
     or error file in bytes or multiples of bytes (approximate). use M/m to \
     signify MBytes, and k/K to signigy kBytes.\n \
     if a log or error file is larger than this limit, it will be archived and \
     a new file will be written.\ndefault is 1048576 bytes i.e. 1 MByte.\n \
     maximum is 999MBytes."]
    set logLevelUsg [list "logLevelUsg" "log level: 0-7, 0 => debug, \
     info => 1, notice => 2, warning => 3, error => 4, \
     critical => 5, alert => 6, emergency => 7"]
    set chrConvProgressUsg [list "chrConvProgressUsg" "console message while \
     busy converting.\n\default value is \
			   \"Converting...\""]
    set chrSearchProgressUsg [list "chrSearchProgressUsg" "console message \
     while busy searching.\n\default value is \
			     \"Looking for pdf files...\""]
    set searchExtUsg [list "searchExtDef" "file extension to search for.\n \
     default value is \*\.pdf."]
    set minSearchThreadsUsg [list "minSearchThreadsUsg" "minimum number of \
     threads to use when searching for files.\n \
     default value is 10."]
    set maxSearchThreadsUsg [list "maxSearchThreadsUsg" "maximum number of \
     threads to use when searching for files.\n \
     default value is 40."]
    set minConvThreadsUsg [list "minConvThreadsUsg" "minimum number of threads \
     to use when converting.\ndefault value is 1."]
    set maxConvThreadsUsg [list "maxConvThreadsUsg" "maximum number of threads \
     to use when converting.\ndefault is 8."]
    
    return -code ok [concat $forgetConfigUsg $cleanExcludeConvertedUsg \
     $cleanExcludeFuckedUsg $maxSizeLogsUsg $logLevelUsg \
     $chrSearchProgressUsg $chrConvProgressUsg $searchExtUsg \
     $minSearchThreadsUsg $maxSearchThreadsUsg \
     $minConvThreadsUsg $maxConvThreadsUsg]
    
}

 proc multiBytes2bytes {bytesString} {
     # TODO need to check for maxSize 999Mbytes in all cases and only return
     # the value if lte than that, otherwise just return 1Mb
     # DONE
     
     if {[string is integer -strict -failindex idx $bytesString]} {
	 set ret $bytesString
     } else {
	 switch -nocase [string index $toBytes $idx] {
	     "b" {
		 set ret [string range $toBytes 0 [expr {$idx -1 }]]
	     }
	     "k" {
		 set ret [expr {$toByes * 1024}]
	     }
	     "m" {
		 set ret -code ok [expr {$toBytes * 1024 * 1024}]
	     }
	     default {
		 set ret 1048576
	     }
	 }
     }
     if {$ret >= 1047527424} {
	 set ret 1048576
     }
     
     return -code ok $ret
 }

exit 0

