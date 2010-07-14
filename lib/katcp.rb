#--
#
# This file includes an RDoc hack so that links can be made to open up into a
# new frame rather then the current frame.
# 
# The "trick" is to append ``"target="_top'' to the URL.
#
#++
#
# = Ruby/KATCP
#
# == Introduction
#
# <b>Ruby/KATCP</b> is a Ruby extension for communicating via the Karoo Array
# Telescope Control Protocol (KATCP).  More information about KATCP can be
# found at the {CASPER
# Wiki}[http://casper.berkeley.edu/wiki/KATCP"target="_top], including the {KATCP
# specification
# }[http://casper.berkeley.edu/wiki/images/1/11/NRF-KAT7-6.0-IFCE-002-Rev4.pdf"target="_top]
# in PDF format.
#
# == Features
#
# * Provides a base KATCP client supporting the functionality described in the
#   KATCP specification.
#
# * Provides an extended KATCP client to support the <tt>tcpborphserver2</tt>
#   KATCP server implementation on {ROACH
#   }[http://casper.berkeley.edu/wiki/ROACH"target="_top] boards.
#
# * Automatically provides support for all current and any future KATCP request
#   types through the use of Ruby's +method_missing+ feature.
#
# * Handles all escaping and unescaping of text transferred over KATCP.
#
# * Provides convenient and flexible ways of converting packed binary data to
#   various numerical formats, including Array and {NArray
#   }[http://narray.rubyforge.org/"target="_top] objects.
#
# * Plays nicely with +irb+, the interactive Ruby shell.
#
# == Examples
#
#   TODO
#
# == Tips and tricks
#
#   TODO
#
# == Current Limitations
#
# * Only the client side is implemented.
# * Only TCP communication is supported (i.e. no RS/232 support).

require 'katcp/client'
