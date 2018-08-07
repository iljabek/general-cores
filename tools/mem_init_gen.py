#!/usr/bin/env python
##-------------------------------------------------------------------------------
## CERN BE-CO-HT
## General Cores
## https://www.ohwr.org/projects/general-cores
##-------------------------------------------------------------------------------
##
## Python script to generate an init file for block rams. Input file should be
## raw binary, such as the one generated by GNU binutils "objcopy -O binary".
##
## Loosely based on the various init generation tools found in wrpc-sw.
##
## Usage:
##   python mem_init_gen.py -of output_format input_file > output_file
##
## Supported output formats:
##
##   bram: custom ascii-encoded binary, one 32-bit value per line, for Xilinx,
##         to be used with the functions in the memory_loader_pkg
##
##   mif : Altera Memory Initialization File
##
##   vhd : constant VHDL array of type t_meminit_array, as defined in genram_pkg.
##
##-------------------------------------------------------------------------------
## Copyright CERN 2018
##-------------------------------------------------------------------------------
## This Source Code Form is subject to the terms of the Mozilla Public License,
## version 2.0. If a copy of the MPL was not distributed with this file, You can
## obtain one at https://mozilla.org/MPL/2.0/.
##-------------------------------------------------------------------------------

from __future__ import print_function

import argparse
import binascii
import datetime

today = datetime.date.today()

parser = argparse.ArgumentParser (
    description='script to generate an init file for block rams' )

parser.add_argument ( 'in_file' )
parser.add_argument ( '-i', '--invert', action='store_true', dest='invert',
                      help = 'Invert endianess of input file' )
parser.add_argument ( '-of', '--oformat', choices = ['BRAM', 'MIF', 'VHD'], type = str.upper,
                      required = False, dest='oformat', default = 'BRAM',
                      help = 'output format (default is BRAM)' )
parser.add_argument ( '-d', '--depth', type = int, default = 0,
                      required = False, dest='depth',
                      help = 'depth of memory in bytes (default is equal to the '
                      'size of the input file)' )
parser.add_argument ( '-w', '--width', type = int,
                      required = False, dest='width', default = 4,
                      help = 'width of memory in bytes (default is 4)' )
parser.add_argument ( '-p', '--pad', type = int,
                      required = False, dest='pad', default = 0,
                      help = 'byte padding value to use if size argument is larger '
                      'than input file size (default is 0, max is 255)' )
parser.add_argument ( '-n', '--name', type = str.lower,
                      required = False, dest='name', default = 'mem_init',
                      help = 'name to use for this block (default is "mem_init")' )

args = parser.parse_args ( )

# check for proper padding value
if args.pad not in range ( 0, 256 ):
    parser.error ( 'Padding value must be between 0 and 255' )

# read binary file
with open ( args.in_file, 'rb' ) as fin:
    contents = fin.read ( )

# byte value to use for padding
pad_val = chr ( args.pad & 0xff )

# pad/trim if necessary to get to args.depth
if args.depth:
    byte_count = args.depth * args.width
    if byte_count > len ( contents ):
        contents += pad_val * ( byte_count - len ( contents ) )
    else:
        contents = contents[:byte_count]

# pad if necessary to get to args.width boundary
contents += pad_val * ( len ( contents ) % args.width )

# convert to 2D list of WIDTH-sized ASCII-encoded (hex format) elements
# with optional endianess inversion
if args.invert == True and args.width > 1:
    words = [ int ( binascii.hexlify ( contents[i:i+args.width][::-1] ), 16 )
              for i in range ( 0, len ( contents ), args.width ) ]
else:
    words = [ int ( binascii.hexlify ( contents[i:i+args.width] ), 16 )
              for i in range ( 0, len ( contents ), args.width ) ]

# BRAM output
if args.oformat == 'BRAM':
    fwidth = args.width * 8
    for word in words:
        print ( '{:0{fwidth}b}'.format ( word, fwidth = fwidth ) )

# MIF output
if args.oformat == 'MIF':
    print ( 'DEPTH = {};'.format ( len ( words ) ) )
    print ( 'WIDTH = {};'.format ( args.width ) )
    print ( 'ADDRESS_RADIX = HEX;' )
    print ( 'DATA_RADIX = HEX;' )
    print ( 'CONTENT' )
    print ( 'BEGIN' )
    fwidth = args.width * 2
    for i, word in enumerate ( words ):
        print ( '{:x} : {:0{fwidth}x};'.format ( i, word, fwidth = fwidth ) )
    print ( 'END;' )

# VHD output
if args.oformat == 'VHD':
    print ( '-' * 80 )
    print ( '-- Memory initialization file for {}'.format ( args.in_file ) )
    print ( '--' )
    print ( '-- This file was automatically generated on {}'.format (
        today.strftime ( '%A, %B %d %Y') ) )
    print ( '-- by {} using the following arguments:'.format ( parser.prog ) )
    print ( '--  {}'.format ( vars(args) ) )
    print ( '--' )
    print ( '-- {} is part of OHWR general-cores:'.format ( parser.prog ) )
    print ( '-- https://www.ohwr.org/projects/general-cores/wiki' )
    print ( '-' * 80 )
    print ( )
    print ( 'library ieee;' )
    print ( 'use ieee.std_logic_1164.all;' )
    print ( 'use ieee.numeric_std.all;' )
    print ( )
    print ( 'library work;' )
    print ( 'use work.memory_loader_pkg.all;' )
    print ( )
    print ( 'package {}_pkg is'.format ( args.name ) )
    print ( )
    print ( '  constant {} : t_meminit_array('.format ( args.name ),
            '{} downto 0, {} downto 0) := ('.format ( len ( words ) - 1, args.width * 8 - 1 ) )
    iwidth  = len ( str ( len ( words ) ) )
    fwidth  = args.width * 2
    numcol  = 80 / (12 + iwidth + fwidth)
    for i, word in enumerate ( words ):
        print ( '    {:{iwidth}d} => x"{:0{fwidth}x}"'.format (
            i, word, iwidth = iwidth, fwidth = fwidth ), end = '' )
        if i == len ( words ) - 1:
            print ( ');' );
        else:
            print ( ',', end = '' );
            if i % numcol == numcol - 1:
                print ( )
    print ( )
    print ( 'end package {}_pkg;'.format ( args.name ) )
