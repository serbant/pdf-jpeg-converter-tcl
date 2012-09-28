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

Version 0.0.1
	usage: pdfJpegConv.tcl [RootSearchPath] [SearchExt]
		[RootSearchPath] default is "D:/hentai"
		[SearchExt] default is "*.pdf"
	pdf's converted are logged into converted.log and not converted again on future runs
	pdf's that fail conversion are logged into fucked.log and not processed on future runs