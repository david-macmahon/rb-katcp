#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'katcp'

OPTS = {
  :verbose => false
}

ARGV.options do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] HOST[:PORT] [CMD [ARGS]]"
  op.separator('')
  op.separator('Runs KATCP command CMD with (optional) arguments ARGS on HOST.')
  op.separator('If CMD is not given, just connect and print inform messages.')
  op.separator('Non-standard port can be given as HOST:PORT.')
  op.separator('')
  op.separator("Example: #{op.program_name} roach2 progdev my_design.bof")
  op.separator('')
  op.separator 'Options:'
  op.on_tail("-v", "--[no-]verbose", "Prints inform messages") do |o|
    OPTS[:verbose] = o
  end
  op.on_tail("-h", "--help", "Show this message") do
    puts op
    exit 1
  end
  op.parse!
end

if ARGV.empty?
  puts ARGV.options
  exit 1
end

host, port = ARGV.shift.split(':')
port ||= ENV['KATCP_PORT'] || '7147'
port = Integer(port) rescue 7147

cmd = ARGV.shift

exit_status = 0

r = KATCP::RoachClient.new(host, port)

if cmd
  puts r.informs(true) if OPTS[:verbose]

  resp = r.respond_to?(cmd) ? r.send(cmd, *ARGV) : r.request(cmd, *ARGV)

  if resp.is_a? KATCP::Response
    puts resp
    exit_status = resp.ok? ? 0 : 1
  else
    puts "got a #{resp.class}: #{resp.inspect}"
  end

  puts r.informs(true) if OPTS[:verbose]
else
  puts r.informs(true)
end

r.close

exit exit_status
