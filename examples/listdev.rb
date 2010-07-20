#!/usr/bin/env ruby

# listdev.rb - list devices on a ROACH
#
#   $ listdev.rb roach030111
#   XAUI0
#   acc_len
#   ant_levels
#   ctrl
#   gbe0
#   gbe_ip0
#   gbe_port
#   [...]

require 'rubygems'
require 'katcp'

# Abort if no hostname is given
raise "\nusage: #{$0} HOSTNAME" unless ARGV[0]

# Create RoachClient object
roach = KATCP::RoachClient.new(ARGV[0])

# Get list of devices via "?listdev" KATCP request.
# Save returned KATCP::Response object in "resp".
resp = roach.listdev

# Extract first "word" of each line except the last
# one, which will be a "!listdev ok" reply line.
devices = resp.lines[0..-2].map {|l| l[1]}

# Output device list
puts devices
